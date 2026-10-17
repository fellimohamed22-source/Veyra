import 'core/widgets/profile_dialog.dart';
import 'dart:async';
import 'core/active_booking.dart';
import 'core/maps/tracking_eta.dart';
import 'core/widgets/booking_financial_summary.dart';
import 'core/notifications/notification_launch.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'app_locale.dart';
import 'chat_socket.dart';
import 'app/theme.dart';
import 'core/formatters/error_messages.dart';
import 'core/formatters/date_formatter.dart';
import 'core/formatters/money_formatter.dart';
import 'core/formatters/status_labels.dart';
import 'core/widgets/veyra_button.dart';
import 'core/widgets/signup_consents.dart';
import 'core/widgets/saved_cards_screen.dart';
import 'core/widgets/phone_verification_screen.dart';
import 'core/widgets/veyra_ui.dart';
import 'core/widgets/state_views.dart';
import 'core/widgets/password_dialog.dart';
import 'core/widgets/status_badge.dart';
import 'core/widgets/pin_display.dart';
import 'core/widgets/pagination_bar.dart';
part 'favorites.dart';

/// Short alias used throughout this file -- AppLocale.t() everywhere
/// would be far noisier across ~100 call sites.
String t(String french) => AppLocale.t(french);

bool pushHandlersConfigured=false;

/// Real, confirmed gap fixed here while investigating "push
/// notifications don't work": FirebasePushProvider (backend) correctly
/// sends a combined notification+data message, which Android's system
/// tray auto-displays in background/terminated state -- but a message
/// with BOTH a notification and a data payload is delivered ONLY to
/// FirebaseMessaging.onMessage while the app is in the FOREGROUND, and
/// nothing was ever listening to that stream. The result: with the app
/// open (the most common state while actively testing), a push arrived
/// completely silently -- no banner, no sound, nothing. This plugin
/// shows a real system notification for exactly that case, so
/// foreground behavior matches background/terminated behavior.
final FlutterLocalNotificationsPlugin _localNotifications=FlutterLocalNotificationsPlugin();
bool _localNotificationsInitialized=false;

Future<void> _ensureLocalNotifications(void Function(String payload) onTap)async{
  if(_localNotificationsInitialized)return;
  const androidInit=AndroidInitializationSettings('@mipmap/ic_launcher');
  await _localNotifications.initialize(
    const InitializationSettings(android:androidInit),
    onDidReceiveNotificationResponse:(response){
      final payload=response.payload;
      if(payload!=null)onTap(payload);
    },
  );
  const channel=AndroidNotificationChannel(
    'veyra_default','Veyra',
    description:'Notifications Veyra',
    importance:Importance.high,
  );
  await _localNotifications
    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
    ?.createNotificationChannel(channel);
  _localNotificationsInitialized=true;
  await resumeNotificationLaunch(_localNotifications,onTap);
}

Future<void> _showForegroundPush(RemoteMessage message)async{
  final notification=message.notification;
  if(notification==null)return;
  await _localNotifications.show(
    message.hashCode,
    notification.title,
    notification.body,
    const NotificationDetails(android:AndroidNotificationDetails(
      'veyra_default','Veyra',
      channelDescription:'Notifications Veyra',
      importance:Importance.high,
      priority:Priority.high,
    )),
    payload:jsonEncode(message.data),
  );
}

String clientNotificationRoute(String bookingId,String? template,Map<String,dynamic> data){
  if(template=='NEW_OFFER')return '/offers/$bookingId';
  final event=data['event']?.toString();
  final status=(data['bookingStatus']??(event!=null&&event.startsWith('booking.status.')?event.substring('booking.status.'.length).toUpperCase():data['status'])??'').toString();
  if({'DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'}.contains(status))return '/live/$bookingId';
  if(template=='PAYMENT_REQUIRED'||status=='PAYMENT_PENDING')return '/payment/$bookingId';
  return '/booking/$bookingId';
}
Future<void> resumeActiveBooking()async{
  try{
    final id=activeBookingId(await api.bookings());
    if(id!=null&&router.routeInformationProvider.value.uri.path=='/home')router.go('/booking/'+Uri.encodeComponent(id));
  }catch(_){
    // Keep the usable home screen when the server cannot confirm an active ride.
  }
}

void openPush(RemoteMessage message){
  final bookingId=message.data['bookingId']?.toString();
  if(bookingId==null||bookingId.isEmpty)return;
  router.go(clientNotificationRoute(bookingId,message.data['templateCode']?.toString(),Map<String,dynamic>.from(message.data)));
}

/// Section 19 (mission UX/fonctionnelle) : "Do not rely on RouteObserver
/// if it is unreliable with the nested Navigator. Use the simplest
/// explicit refresh/invalidation mechanism consistent with the current
/// architecture." Un simple compteur global, incrémenté par tout écran
/// qui vient de terminer une mutation, et écouté par tout écran de liste
/// qui doit se rafraîchir en réponse -- ne dépend d'aucune particularité
/// de Navigator/Observer, fonctionne identiquement quel que soit
/// l'endroit de l'arbre de widgets où se trouvent l'un et l'autre.
/// Vient s'ajouter à didPopNext (pas le remplacer) : si RouteObserver se
/// révèle en fait fiable ici, les deux mécanismes se contentent de
/// rafraîchir deux fois sans effet secondaire ; s'il ne l'est pas,
/// celui-ci garantit que le rafraîchissement a bien lieu.
class RefreshBus {
  RefreshBus._();
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static void bump() => tick.value++;
}

/// DEC-07 Firebase Phone Auth. Token obtained when Android verifies the
/// number without a typed code (auto-retrieval).
String? _autoVerifiedPhoneToken;

/// Sends the OTP by SMS; returns the verification id, or null when the
/// device verified the number by itself.
Future<String?> firebaseSendSmsCode(String e164) async {
  if(Firebase.apps.isEmpty)await Firebase.initializeApp();
  _autoVerifiedPhoneToken=null;
  final done=Completer<String?>();
  await FirebaseAuth.instance.verifyPhoneNumber(
    phoneNumber:e164,
    verificationCompleted:(credential)async{
      try{
        final user=await FirebaseAuth.instance.signInWithCredential(credential);
        _autoVerifiedPhoneToken=await user.user?.getIdToken();
        if(!done.isCompleted)done.complete(null);
      }catch(e){
        if(!done.isCompleted)done.completeError(e);
      }
    },
    verificationFailed:(e){if(!done.isCompleted)done.completeError(e);},
    codeSent:(verificationId,_){if(!done.isCompleted)done.complete(verificationId);},
    codeAutoRetrievalTimeout:(_){},
  );
  return done.future;
}

/// Confirms the SMS code with Firebase and returns its ID token (provider
/// "phone"), then signs out of Firebase: the VEYRA session is unaffected.
Future<String> firebaseConfirmSmsCode(String? verificationId,String smsCode) async {
  String? token;
  if(verificationId==null){
    token=_autoVerifiedPhoneToken;
  }else{
    final credential=PhoneAuthProvider.credential(verificationId:verificationId,smsCode:smsCode);
    final user=await FirebaseAuth.instance.signInWithCredential(credential);
    token=await user.user?.getIdToken();
  }
  await FirebaseAuth.instance.signOut();
  if(token==null)throw StateError('PHONE_TOKEN_MISSING');
  return token;
}

Future<void> configurePush() async {
  try{
    if(Firebase.apps.isEmpty)await Firebase.initializeApp();
    if(!pushHandlersConfigured){
      pushHandlersConfigured=true;
      FirebaseMessaging.onMessageOpenedApp.listen(openPush);
      FirebaseMessaging.instance.onTokenRefresh.listen((token)async{try{await api.registerDevice(token,platform:'android');}catch(e){debugPrint('PUSH_TOKEN_REFRESH_FAILED: $e');}});
      final initial=await FirebaseMessaging.instance.getInitialMessage();
      if(initial!=null)WidgetsBinding.instance.addPostFrameCallback((_){openPush(initial);});
      await _ensureLocalNotifications((payload){
        try{
          final data=Map<String,dynamic>.from(jsonDecode(payload) as Map);
          final bookingId=data['bookingId']?.toString();
          if(bookingId!=null&&bookingId.isNotEmpty){
            router.go(clientNotificationRoute(bookingId,data['templateCode']?.toString(),data));
          }
        }catch(_){}
      });
      FirebaseMessaging.onMessage.listen((message){RefreshBus.bump();_showForegroundPush(message);});
    }
    await FirebaseMessaging.instance.requestPermission();
    final token=await FirebaseMessaging.instance.getToken();
    if(token!=null)await api.registerDevice(token,platform:'android');
  }catch(e){
    // Real bug fixed here while investigating "push notifications don't
    // work": this used to be catch(_){}, silently discarding every
    // failure -- a missing/mismatched google-services.json, a denied
    // notification permission, a getToken() failure, or the
    // registerDevice() API call itself failing were all completely
    // invisible, with no way to tell which one without instrumenting
    // the code by hand. debugPrint (not print) since it's the
    // Flutter-idiomatic diagnostic channel, visible in `flutter logs`/
    // device logs without shipping a full logging framework for what
    // is, for now, a single diagnostic line.
    debugPrint('PUSH_CONFIGURE_FAILED: $e');
  }
}

final api=Api(const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080'));

final lastCrash=ValueNotifier<String?>(null);

String _truncatedStack(String stack){
  final lines=stack.split('\n').where((l)=>l.trim().isNotEmpty).take(8).toList();
  return lines.join('\n');
}

void main() {
  runZonedGuarded(() {
    _mainBody();
  },(error,stack){
    // Gap found the hard way: a real device's logcat captured
    // "UNCAUGHT_FLUTTER_ERROR: Null check operator used on a null
    // value" for the actual reported blank-screen bug, but with no
    // stack trace anywhere nearby -- this debugPrint only ever logged
    // exceptionAsString()/error.toString(), never the stack, so there
    // was no way to know which line actually threw. Logging the full
    // stack now, and truncating what the on-screen banner shows (a
    // full Dart stack trace can be dozens of lines) to keep it
    // readable while debugPrint still gets everything via adb logcat.
    debugPrint('UNCAUGHT_ZONE_ERROR: '+error.toString());
    debugPrint('UNCAUGHT_ZONE_STACK:\n'+stack.toString());
    lastCrash.value='ZONE: '+error.toString()+'\n'+_truncatedStack(stack.toString());
  });
}

Future<void> _mainBody() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError=(details){
    FlutterError.presentError(details);
    debugPrint('UNCAUGHT_FLUTTER_ERROR: '+details.exceptionAsString());
    debugPrint('UNCAUGHT_FLUTTER_STACK:\n'+(details.stack?.toString()??'(pas de stack)'));
    lastCrash.value='FLUTTER: '+details.exceptionAsString()+'\n'+_truncatedStack(details.stack?.toString()??'');
  };
  PlatformDispatcher.instance.onError=(error,stack){
    debugPrint('UNCAUGHT_PLATFORM_ERROR: '+error.toString());
    debugPrint('UNCAUGHT_PLATFORM_STACK:\n'+stack.toString());
    lastCrash.value='PLATFORM: '+error.toString()+'\n'+_truncatedStack(stack.toString());
    return true;
  };
  // Loaded in the background, same principle as the Stripe fix just
  // above: a secure-storage read is normally fast and reliable, but
  // nothing async should ever gate the very first frame after the
  // lesson just learned from applySettings() hanging on some devices.
  // French remains correct as the default until this resolves.
  unawaited(AppLocale.load());
  const publishableKey=String.fromEnvironment('STRIPE_PUBLISHABLE_KEY',defaultValue:'');
  if(publishableKey.isNotEmpty){
    Stripe.publishableKey=publishableKey;
    // Real, confirmed bug (flutter-stripe/flutter_stripe#1892): on some
    // Android devices, applySettings() hangs indefinitely with no error
    // at all -- awaiting it here before runApp() means the very first
    // frame never renders on those devices, which looks exactly like a
    // stuck splash screen (the native launch screen never gets
    // dismissed, since Flutter never gets to draw anything). Payment is
    // only ever needed much later in the actual user journey (after
    // login, after booking) by which point this background call has had
    // plenty of time to finish -- there is no real reason for it to gate
    // the app's very first screen.
    unawaited(Stripe.instance.applySettings());
  }
  // Diagnostic aid, re-added: the blank AddressScreen was reported as
  // STILL happening after the confirmed, real FlutterFragmentActivity
  // fix (a2c3919) -- meaning there is a second, separate bug, and this
  // banner is needed again to see it. Learned from prematurely removing
  // it last time before the user had fully confirmed the fix worked
  // end to end: keeping this in place until they explicitly confirm
  // success this time, not removing it speculatively again.
  ErrorWidget.builder=(details){
    lastCrash.value='BUILD: '+details.exceptionAsString();
    return Material(child:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('ERREUR DE RENDU (diagnostic temporaire)',style:TextStyle(color:Colors.red,fontWeight:FontWeight.bold,fontSize:16)),
      const SizedBox(height:12),
      SelectableText(details.exceptionAsString(),style:const TextStyle(fontSize:13)),
      const SizedBox(height:12),
      SelectableText(details.stack?.toString()??'',style:const TextStyle(fontSize:10,color:Colors.black54)),
    ]))));
  };
  runApp(const App());
}

/// Reusable language switcher -- a simple cycling toggle (FR<->EN) rather
/// than a full menu, since only two languages are supported; a menu with
/// two items for a binary choice adds a tap without adding real clarity.
class LanguageSwitch extends StatelessWidget{
  final ButtonStyle? style;
  const LanguageSwitch({super.key,this.style});
  @override Widget build(BuildContext context)=>ValueListenableBuilder<String>(
    valueListenable:AppLocale.code,
    builder:(context,code,_)=>TextButton(
      style:style,
      onPressed:()=>AppLocale.set(code=='fr'?'en':'fr'),
      child:Text(code=='fr'?'FR':'EN',style:const TextStyle(fontWeight:FontWeight.bold)),
    ),
  );
}

// Diagnostic aid, same investigation as ErrorWidget.builder below --
// a global holder so the error banner in App's builder: can show
// whatever runZonedGuarded or FlutterError.onError last caught,
// regardless of which specific screen was active when it happened.
// ErrorWidget.builder alone only replaces the one crashing widget's
// spot in the tree; if a failure happens somewhere runZonedGuarded
// catches but the normal widget-build error path does not reach
// (e.g. inside a route transition callback), this is the fallback that
// still surfaces it visibly.
class App extends StatelessWidget{
  const App({super.key});
  @override Widget build(BuildContext context)=>ValueListenableBuilder<String>(
    valueListenable:AppLocale.code,
    builder:(context,localeCode,_)=>MaterialApp.router(
      title:'Veyra',
      theme:veyraTheme(),
      locale:Locale(localeCode),
      supportedLocales:const [Locale('fr'),Locale('en')],
      localizationsDelegates:const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig:router,
      builder:(context,child)=>ValueListenableBuilder<String?>(
        valueListenable:lastCrash,
        builder:(context,crash,_)=>Stack(children:[
          if(child!=null)child,
          if(crash!=null)Positioned(top:0,left:0,right:0,child:Material(color:Colors.red.shade900,child:SafeArea(bottom:false,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
            const Text('ERREUR CAPTURÉE (diagnostic temporaire)',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold)),
            const SizedBox(height:6),
            SelectableText(crash,style:const TextStyle(color:Colors.white,fontSize:12)),
          ]))))),
        ]),
      ),
    ),
  );
}

/// Lets a screen refresh itself when the user navigates back to it from
/// a pushed screen -- fixes pages not refreshing when returning to them
/// without leaving and reopening the whole app.
final routeObserver=RouteObserver<PageRoute>();

final router=GoRouter(
  initialLocation:'/login',
  routes:[
  GoRoute(path:'/login',builder:(c,s)=>const LoginScreen()),
  GoRoute(path:'/register',builder:(c,s)=>const RegisterScreen()),
  GoRoute(path:'/verify-phone',builder:(c,s)=>PhoneVerificationScreen(
    initialPhone:(s.extra as String?)??'',
    sendCode:firebaseSendSmsCode,
    confirm:firebaseConfirmSmsCode,
    submit:api.verifyPhone,
    onDone:()=>c.go('/home'),
    onLater:()=>c.go('/home'),
  )),
  GoRoute(path:'/forgot',builder:(c,s)=>const ForgotPasswordScreen()),
  GoRoute(path:'/reset-password',builder:(c,s)=>const ResetPasswordScreen()),
  // Coquille de navigation persistante (bottom nav), conforme aux
  // maquettes C02+ ("BottomNavigation" listé comme composant UI dans
  // chaque fiche écran principale). Les écrans de flux (adresses,
  // offres, détail réservation, chat, tracking) restent des routes
  // racine ci-dessous, poussées PAR-DESSUS la coquille entière -- la
  // bottom nav disparaît naturellement pendant ces parcours, comme
  // attendu.
  StatefulShellRoute.indexedStack(
    builder:(c,s,navigationShell)=>AppShell(navigationShell:navigationShell),
    branches:[
      StatefulShellBranch(routes:[GoRoute(path:'/home',builder:(c,s)=>const AccueilScreen())]),
      StatefulShellBranch(routes:[GoRoute(path:'/bookings',builder:(c,s)=>const HomeScreen())]),
      StatefulShellBranch(routes:[GoRoute(path:'/notifications',builder:(c,s)=>const NotificationsScreen())]),
      StatefulShellBranch(routes:[GoRoute(path:'/account',builder:(c,s)=>const AccountScreen())]),
    ],
  ),
  GoRoute(path:'/addresses',builder:(c,s)=>AddressScreen(initialBooking:s.extra is Map?Map<String,dynamic>.from(s.extra as Map):null)),
  GoRoute(path:'/offers/:id',builder:(c,s)=>OffersScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/payment/:id',builder:(c,s)=>PaymentScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/booking/:id',builder:(c,s)=>BookingDetailScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/chat/:id',builder:(c,s)=>ChatScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/live/:id',builder:(c,s)=>LiveLocationScreen(bookingId:s.pathParameters['id']!)),
],
  observers:[routeObserver],
  // Section 64/protocole anti-erreurs : "éviter les écrans morts".
  // Sans errorBuilder, une route inconnue (lien profond mal formé,
  // typo) affichait l'écran d'erreur générique GoRouter, hors charte
  // Veyra. Bouton "Retour à l'accueil" plutôt qu'un cul-de-sac.
  errorBuilder:(c,s)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.error_outline,size:48,color:Color(0xFFDC2626)),
      const SizedBox(height:16),
      Text(t('Page introuvable'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
      const SizedBox(height:16),
      FilledButton(onPressed:()=>c.go('/home'),child:Text(t("Retour à l'accueil"))),
    ])),
  ),
);

/// Consistent, mockup-matching field styling (filled white, rounded,
/// optional leading icon) -- reused across every form in the app rather
/// than repeating the same InputDecoration verbosely at each call site.
InputDecoration appFieldDecoration(String label,{IconData? icon,String? helperText}){
  return InputDecoration(
    labelText:label,
    helperText:helperText,
    prefixIcon:icon==null?null:Icon(icon),
    filled:true,
    fillColor:Colors.white,
    border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none),
  );
}

// statusBadge(String) a été retiré ici : il affichait le code backend
// brut avec les underscores remplacés par des espaces (ex: "DRIVER EN
// ROUTE"), pas une vraie traduction humanisée -- une violation directe
// de "ces codes ne sont jamais rendus tels quels dans l'interface".
// Remplacé par VeyraStatusBadge (core/widgets/status_badge.dart), qui
// utilise le vrai mapping BACKEND_ENUM_UI_MAPPING.md.

class LoginScreen extends StatefulWidget{
  const LoginScreen({super.key});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen>{
  final email=TextEditingController();
  final password=TextEditingController();
  bool loading=false; String? error; bool offline=false;

  @override void initState(){
    super.initState();
    // Real gap fixed here: tokens were already correctly persisted via
    // flutter_secure_storage (survives closing the app), but nothing
    // ever checked for one at startup -- the app always opened on this
    // screen regardless, forcing a fresh login every time even with a
    // perfectly valid stored session. Checked after the first frame
    // (post-frame callback) rather than via GoRouter's own redirect --
    // an async redirect blocking the very first route resolution
    // proved genuinely unreliable to settle correctly in widget tests,
    // and checking here means this screen's own content is always
    // available synchronously on first render regardless.
    WidgetsBinding.instance.addPostFrameCallback((_)async{
      String? token;
      String? refreshToken;
      try{
        token=await api.storage.read(key:'accessToken');
        refreshToken=await api.storage.read(key:'refreshToken');
      }catch(_){
        return;
      }
      if(((token?.isNotEmpty??false)||(refreshToken?.isNotEmpty??false))&&mounted){
        context.go('/home');
        await resumeActiveBooking();
        await configurePush();
      }
    });
  }

  Future<void> submit()async{
    setState((){loading=true;error=null;offline=false;});
    try{
      await api.login(email.text,password.text);
      if(!mounted)return;
      context.go('/home');
      await configurePush();
    }catch(e){
      if(!mounted)return;
      // Distingue OFFLINE (pas de réponse serveur) de ERROR (le serveur
      // a répondu avec un code métier réel, ex: INVALID_CREDENTIALS,
      // ACCOUNT_LOCKED, ACCOUNT_NOT_ACTIVE) -- deux états UX obligatoires
      // distincts selon la fiche C01, auparavant fondus dans un seul
      // texte générique quelle que soit la cause réelle.
      final isOffline=e is DioException&&(
        e.type==DioExceptionType.connectionError||
        e.type==DioExceptionType.connectionTimeout||
        e.type==DioExceptionType.receiveTimeout||
        e.type==DioExceptionType.sendTimeout);
      setState((){
        offline=isOffline;
        error=isOffline?null:VeyraErrorMessages.forException(e);
      });
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  // Real gap fixed here: Google sign-in existed and already worked
  // end-to-end on the driver app (same backend /api/v1/auth/firebase
  // endpoint, already correctly verifying Firebase ID tokens), but was
  // entirely absent on the client -- no button, no SDK call, nothing.
  Future<void> _googleLogin() async {
    setState((){loading=true;error=null;offline=false;});
    try{
      if(Firebase.apps.isEmpty)await Firebase.initializeApp();
      final account=await GoogleSignIn().signIn();
      if(account==null)return;
      final auth=await account.authentication;
      final credential=GoogleAuthProvider.credential(
        accessToken:auth.accessToken,
        idToken:auth.idToken,
      );
      final userCredential=await FirebaseAuth.instance.signInWithCredential(credential);
      final token=await userCredential.user?.getIdToken();
      if(token==null||token.isEmpty)throw StateError('FIREBASE_ID_TOKEN_MISSING');
      await api.loginWithFirebase(token);
      if(!mounted)return;
      context.go('/home');
      await configurePush();
    }catch(e){
      debugPrint('GOOGLE_LOGIN_FAILED: $e');
      if(mounted)setState(()=>error=e is DioException?VeyraErrorMessages.forException(e):t('Connexion Google impossible. Vérifiez la configuration Firebase et réessayez.'));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    body:SafeArea(child:Column(children:[
      Container(
        width:double.infinity,
        padding:const EdgeInsets.fromLTRB(24,32,24,40),
        decoration:const BoxDecoration(
          gradient:LinearGradient(
            begin:Alignment.topCenter,end:Alignment.bottomCenter,
            colors:[Color(0xFF123A66),Color(0xFF1565C0)],
          ),
        ),
        child:Column(children:[
          Align(alignment:Alignment.topRight,child:LanguageSwitch(style:TextButton.styleFrom(foregroundColor:Colors.white))),
          const Icon(Icons.location_on,color:Colors.white,size:40),
          const SizedBox(height:8),
          const Text('Veyra',style:TextStyle(color:Colors.white,fontSize:32,fontWeight:FontWeight.bold)),
          const SizedBox(height:4),
          Text(t('Plus qu\'un trajet, votre confiance'),style:const TextStyle(color:Colors.white70,fontSize:14)),
        ]),
      ),
      Expanded(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(t('Bienvenue'),style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
        const SizedBox(height:20),
        TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:appFieldDecoration(t('Email'),icon:Icons.mail_outline)),
        const SizedBox(height:12),
        TextField(controller:password,obscureText:true,decoration:appFieldDecoration(t('Mot de passe'),icon:Icons.lock_outline)),
        if(offline)Padding(padding:const EdgeInsets.only(top:12),child:VeyraOfflineBanner(onRetry:submit)),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
        const SizedBox(height:20),
        VeyraPrimaryButton(label:t('Se connecter'),loading:loading,onPressed:submit),
        const SizedBox(height:20),
        Row(children:[
          const Expanded(child:Divider()),
          Padding(
            padding:const EdgeInsets.symmetric(horizontal:12),
            child:Text(t('ou'),style:const TextStyle(color:Color(0xFF6B7280))),
          ),
          const Expanded(child:Divider()),
        ]),
        const SizedBox(height:14),
        OutlinedButton.icon(
          onPressed:loading?null:_googleLogin,
          icon:const Icon(Icons.g_mobiledata_rounded,size:28),
          label:Text(t('Continuer avec Google')),
          style:OutlinedButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:14)),
        ),
      TextButton(onPressed:()=>context.push('/forgot'),child:Text(t('Mot de passe oublié ?'))),
      TextButton(onPressed:()=>context.push('/register'),child:Text(t('Créer un compte'))),
      ]))),
    ])));
}

class HomeScreen extends StatefulWidget{
  const HomeScreen({super.key});
  @override State<HomeScreen> createState()=>_HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> with RouteAware{
  late Future<List<dynamic>> future;
  String statusFilter='ALL'; String dateSort='desc'; int page=0; bool hasNext=false;
  int loadRevision=0;
  Future<List<dynamic>> load()async{
    final revision=++loadRevision;
    final rows=await api.bookings(status:statusFilter=='ALL'?null:statusFilter,sort:dateSort,page:page);
    if(revision==loadRevision)hasNext=rows.length==10;
    return rows;
  }
  void resetFilters(){setState((){statusFilter='ALL';dateSort='desc';page=0;future=load();});}
  @override void initState(){
    super.initState();
    future=load();
    RefreshBus.tick.addListener(retry);
  }
  void retry()=>setState((){future=load();});

  // This screen lives inside a StatefulShellRoute, same as AccueilScreen
  // (see the identical fix there, 137f30f "prevent blank booking
  // navigation screen"): subscribing its ModalRoute to the root
  // RouteObserver is unsafe on a real device, where the shell's nested
  // navigator can expose a route type/lifecycle that is not the root
  // PageRoute -- the `as PageRoute` cast throws a synchronous exception
  // that leaves the branch with a blank body, even though
  // flutter analyze/tests stay green throughout (mocked navigation in
  // widget tests never exercises the real shell's nested Navigator).
  // RefreshBus (already wired above) is the explicit cross-navigator
  // refresh mechanism used after a booking mutation, so keep this
  // screen's lifecycle independent from the root observer, same as
  // AccueilScreen.
  @override void dispose(){
    RefreshBus.tick.removeListener(retry);
    super.dispose();
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(
      backgroundColor:const Color(0xFFF2F6FB),elevation:0,
      title:Text(t('Mes trajets planifiés'),style:const TextStyle(color:Color(0xFF123A66),fontWeight:FontWeight.bold)),
    ),
    body:RefreshIndicator(
      onRefresh:()async{retry();try{await future;}catch(_){/* FutureBuilder displays the load error. */}},
      child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(20),children:[
        DropdownButtonFormField<String>(key:ValueKey(statusFilter),initialValue:statusFilter,isExpanded:true,decoration:InputDecoration(labelText:t('État')),
          items:[DropdownMenuItem(value:'ALL',child:Text(t('Tous les états'))),for(final v in ['OPEN_FOR_OFFERS','OFFERS_RECEIVED','CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS','COMPLETED','CLOSED','CANCELLED','DRIVER_CANCELLED','CUSTOMER_NO_SHOW','EXPIRED','NO_OFFER'])DropdownMenuItem(value:v,child:Text(VeyraStatusLabels.bookingStatus(v)))],
          onChanged:(v){if(v!=null)setState((){statusFilter=v;page=0;future=load();});}),
        DropdownButtonFormField<String>(key:ValueKey(dateSort),initialValue:dateSort,isExpanded:true,decoration:InputDecoration(labelText:t('Date')),
          items:[DropdownMenuItem(value:'desc',child:Text(t('Plus récentes'))),DropdownMenuItem(value:'asc',child:Text(t('Plus anciennes')))],
          onChanged:(v){if(v!=null)setState((){dateSort=v;page=0;future=load();});}),
        if(statusFilter!='ALL'||dateSort!='desc')ListTile(title:Text(t('Filtres actifs')),trailing:TextButton(onPressed:resetFilters,child:Text(t('Réinitialiser')))),
        Container(
          padding:const EdgeInsets.all(14),
          decoration:BoxDecoration(color:VeyraColors.infoBackground,borderRadius:BorderRadius.circular(VeyraRadius.md)),
          child:Row(children:[
            const Icon(Icons.schedule_rounded,color:VeyraColors.primary),
            const SizedBox(width:10),
            Expanded(child:Text(t('Veyra MVP fonctionne uniquement sur réservation planifiée, au minimum 2 h avant le départ.'),style:const TextStyle(color:VeyraColors.primaryDark,fontWeight:FontWeight.w600,height:1.3))),
          ]),
        ),
        const SizedBox(height:16),
        FutureBuilder<List<dynamic>>(
          future:future,
          builder:(context,s){
            if(s.connectionState!=ConnectionState.done){
              return const Padding(padding:EdgeInsets.symmetric(vertical:48),child:VeyraLoadingView());
            }
            if(s.hasError){
              final offline=VeyraErrorMessages.isOffline(s.error!);
              return offline
                ? VeyraOfflineBanner(onRetry:retry)
                : VeyraErrorView(errorCode:null,customMessage:VeyraErrorMessages.forException(s.error!),onRetry:retry);
            }
            final items=s.data??[];
            if(items.isEmpty){
              if(page>0)return TextButton(onPressed:()=>setState((){page--;future=load();}),child:Text(t('Page précédente')));
              return Card(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),child:ListTile(
                leading:const Icon(Icons.event_available,color:Color(0xFF1565C0)),
                title:Text(statusFilter=='ALL'?t('Aucune réservation'):t('Aucune réservation ne correspond aux filtres.')),
                onTap:resetFilters,
                subtitle:Text(t('Votre prochain trajet apparaîtra ici.')),
              ));
            }
            return Column(children:[...items.map((raw){
              final x=Map<String,dynamic>.from(raw as Map);
              final title=(x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString();
              final scheduled=VeyraDateFormatter.relativeDay(x['scheduled_at']);
              final status=(x['status']??'').toString();
              final offerPhase={'OPEN_FOR_OFFERS','OFFERS_RECEIVED'}.contains(status);
              return Card(
                margin:const EdgeInsets.only(bottom:12),
                child:InkWell(
                  borderRadius:BorderRadius.circular(VeyraRadius.card),
                  onTap:(){
                    final id=x['id']?.toString();
                    if(id==null)return;
                    context.push(offerPhase?'/offers/$id':'/booking/$id');
                  },
                  child:Padding(
                    padding:const EdgeInsets.all(18),
                    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Container(width:42,height:42,decoration:BoxDecoration(color:VeyraColors.infoBackground,borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.route_outlined,color:VeyraColors.primary)),
                        const SizedBox(width:12),
                        Expanded(child:Text(title,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16,height:1.25,color:VeyraColors.textPrimary))),
                      ]),
                      const SizedBox(height:14),
                      // Même défaut que l'en-tête de OffersScreen (badge non flexible
                      // dans un Row) sur l'écran le plus fréquenté de l'app.
                      SizedBox(width:double.infinity,child:Wrap(
                        alignment:WrapAlignment.spaceBetween,
                        crossAxisAlignment:WrapCrossAlignment.center,
                        spacing:8,runSpacing:6,
                        children:[
                          Row(mainAxisSize:MainAxisSize.min,children:[
                            const Icon(Icons.schedule,size:17,color:VeyraColors.textSecondary),
                            const SizedBox(width:6),
                            Flexible(child:Text(scheduled,style:const TextStyle(color:VeyraColors.textSecondary,fontWeight:FontWeight.w600))),
                          ]),
                          VeyraStatusBadge(status:status),
                        ],
                      )),
                      if(x['selected_driver_id']!=null)Text((x['driver_name']??'Chauffeur confirmé').toString()),
                      if(x['customer_total_amount_minor']!=null)Text(t('Total client')+' : '+VeyraMoneyFormatter.fromMinor(x['customer_total_amount_minor'])),
                      Text((x['category_name']??'').toString()+' • '+(x['passenger_count']??1).toString()+' passager(s) • '+(x['baggage_count']??0).toString()+' bagage(s)'),
                      if(offerPhase)Text((x['offer_count']??0).toString()+' '+t('offres reçues')),
                      const SizedBox(height:14),
                      Row(mainAxisAlignment:MainAxisAlignment.end,children:[
                        Text(offerPhase?t('Voir les offres'):t('Voir la réservation'),style:const TextStyle(color:VeyraColors.primary,fontWeight:FontWeight.w800)),
                        const SizedBox(width:4),const Icon(Icons.arrow_forward_rounded,size:18,color:VeyraColors.primary),
                      ]),
                    ]),
                  ),
                ),
              );
            }),VeyraPaginationBar(page:page,hasNext:hasNext,onPrevious:(){setState((){page--;future=load();});},onNext:(){setState((){page++;future=load();});})]);
          },
        ),
      ]),
    ),
  );
}

/// C02 -- écran d'accueil léger : salutation, raccourci de création de
/// réservation, et aperçu de la SEULE prochaine réservation (la liste
/// complète vit dans l'onglet Réservations/HomeScreen). Conforme à la
/// fiche C02 : "Route entry card" + "Next booking card" (singulier),
/// la liste complète étant une transition séparée ("Réservations →
/// liste historique").
class AccueilScreen extends StatefulWidget{
  const AccueilScreen({super.key});
  @override State<AccueilScreen> createState()=>_AccueilScreenState();
}
class _AccueilScreenState extends State<AccueilScreen> with RouteAware{
  late Future<Map<String,dynamic>> me;
  late Future<List<dynamic>> bookings;

  @override void initState(){
    super.initState();
    _load();
    RefreshBus.tick.addListener(_refresh);
  }

  void _refresh()=>setState(_load);

  void _load(){
    me=api.me();
    bookings=api.bookings();
  }

  // ATTENTION -- non vérifié sur appareil réel (pas de SDK Flutter dans
  // cet environnement) : ce mécanisme didPopNext/RouteObserver
  // fonctionnait correctement avant l'introduction du shell de
  // navigation (StatefulShellRoute), quand cet écran vivait directement
  // sur le Navigator racine. Depuis ce lot, cet écran vit dans le
  // Navigator imbriqué propre à sa branche du shell -- le
  // ModalRoute.of(context) résolu ici pourrait donc être celui de la
  // branche, pas celui du Navigator racine sur lequel /addresses,
  // /booking/:id etc. sont réellement poussés/dépilés, ce qui
  // empêcherait ce callback de se déclencher au retour de ces écrans.
  // Le RefreshIndicator (pull-to-refresh) ci-dessous reste disponible en
  // filet de sécurité manuel dans tous les cas. À vérifier/durcir sur un
  // vrai appareil avant mise en production.
  // This screen lives inside a StatefulShellRoute. Subscribing its
  // ModalRoute to the root RouteObserver is unsafe: on a real device the
  // shell can expose a route type/lifecycle that is not the root
  // PageRoute, and a synchronous exception here leaves the branch with a
  // blank body even though flutter analyze/tests are green. RefreshBus is
  // already the explicit cross-navigator refresh mechanism used after a
  // booking mutation, so keep the home lifecycle independent from the
  // root observer.
  @override void dispose(){
    RefreshBus.tick.removeListener(_refresh);
    super.dispose();
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(
      backgroundColor:const Color(0xFFF2F6FB),elevation:0,
      title:Row(mainAxisSize:MainAxisSize.min,children:const [Icon(Icons.location_on,color:Color(0xFF1565C0)),SizedBox(width:6),Text('Veyra',style:TextStyle(color:Color(0xFF123A66),fontWeight:FontWeight.bold))]),
      actions:const [LanguageSwitch()],
    ),
    body:RefreshIndicator(
      onRefresh:()async{setState(_load);try{await Future.wait([me,bookings]);}catch(_){/* FutureBuilders display the load error. */}},
      child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(20),children:[
        FutureBuilder<Map<String,dynamic>>(
          future:me,
          builder:(context,s){
            final firstName=(s.data?['first_name']??'').toString();
            return Text(
              firstName.isEmpty?t('Bonjour !'):t('Bonjour')+' '+firstName+' !',
              style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold,color:Color(0xFF123A66)),
            );
          },
        ),
        const SizedBox(height:4),
        Text(t('Vos trajets VTC, réservés à l’avance.'),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:15)),
        const SizedBox(height:18),
        Container(
          decoration:BoxDecoration(
            gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[VeyraColors.primaryDark,VeyraColors.primary]),
            borderRadius:BorderRadius.circular(VeyraRadius.card),
          ),
          child:Material(color:Colors.transparent,child:InkWell(
            borderRadius:BorderRadius.circular(VeyraRadius.card),
            onTap:()=>context.push('/addresses'),
            child:Padding(padding:const EdgeInsets.all(22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Container(
                padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
                decoration:BoxDecoration(color:Colors.white.withValues(alpha:.14),borderRadius:BorderRadius.circular(VeyraRadius.pill)),
                child:Row(mainAxisSize:MainAxisSize.min,children:[
                  const Icon(Icons.event_available_outlined,color:Colors.white,size:16),
                  const SizedBox(width:6),
                  Text(t('Réservation planifiée'),style:const TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w800)),
                ]),
              ),
              const SizedBox(height:18),
              Text(t('Planifiez votre prochain trajet'),style:const TextStyle(color:Colors.white,fontSize:23,fontWeight:FontWeight.w900,height:1.15,letterSpacing:-.3)),
              const SizedBox(height:8),
              Text(t('Choisissez le trajet, la date et l’heure. Départ au minimum 2 h à l’avance.'),style:const TextStyle(color:Colors.white70,height:1.35)),
              const SizedBox(height:20),
              Container(
                padding:const EdgeInsets.symmetric(horizontal:16,vertical:13),
                decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(VeyraRadius.md)),
                child:Row(children:[
                  const Icon(Icons.add_road_rounded,color:VeyraColors.primary),
                  const SizedBox(width:10),
                  Expanded(child:Text(t('Planifier une réservation'),style:const TextStyle(color:VeyraColors.primaryDark,fontWeight:FontWeight.w800))),
                  const Icon(Icons.arrow_forward_rounded,color:VeyraColors.primary),
                ]),
              ),
            ])),
          )),
        ),
        const SizedBox(height:28),
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Text(t('Prochaine réservation'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
          TextButton(
            onPressed:()=>context.go('/bookings'),
            child:Text(t('Voir tout')),
          ),
        ]),
        const SizedBox(height:8),
        FutureBuilder<List<dynamic>>(
          future:bookings,
          builder:(context,s){
            if(s.connectionState!=ConnectionState.done){
              return const VeyraLoadingView();
            }
            if(s.hasError){
              return VeyraErrorMessages.isOffline(s.error!)
                ? VeyraOfflineBanner(onRetry:()=>setState(_load))
                : VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState(_load));
            }
            final items=s.data??[];
            // Bug réel trouvé pendant l'étude UX/navigation : le endpoint
            // GET /scheduled-bookings trie "order by scheduled_at desc"
            // (le plus tardif en premier, pensé pour l'onglet
            // Réservations/historique) -- prendre naïvement items.first
            // ici affichait donc la réservation la PLUS ÉLOIGNÉE dans le
            // temps comme "prochaine réservation", pas la plus proche.
            // Sélectionne explicitement, parmi les statuts actifs
            // (non terminaux -- mêmes valeurs que le mapping couleur de
            // VeyraStatusBadge), celle dont scheduled_at est la plus
            // proche, sans dépendre de l'ordre renvoyé par le serveur.
            const terminalStatuses={
              'COMPLETED','CLOSED','CANCELLED','CANCELLED_BY_CLIENT',
              'CANCELLED_BY_DRIVER','DRIVER_CANCELLED','CUSTOMER_NO_SHOW','EXPIRED','NO_OFFER','NO_DRIVER',
            };
            Map<String,dynamic>? next;
            DateTime? nextAt;
            for(final raw in items){
              final candidate=Map<String,dynamic>.from(raw as Map);
              if(terminalStatuses.contains(candidate['status']))continue;
              final at=DateTime.tryParse(candidate['scheduled_at']?.toString()??'');
              if(at==null)continue;
              if(nextAt==null||at.isBefore(nextAt)){
                next=candidate;
                nextAt=at;
              }
            }
            if(next==null){
              return VeyraEmptyView(
                icon:Icons.event_available,
                message:t('Aucune réservation à venir. Votre prochain trajet apparaîtra ici.'),
              );
            }
            final x=next;
            final title=(x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString();
            final status=(x['status']??'').toString();
            final offerPhase={'OPEN_FOR_OFFERS','OFFERS_RECEIVED'}.contains(status);
            return Card(child:InkWell(
              borderRadius:BorderRadius.circular(VeyraRadius.card),
              onTap:(){
                final id=x['id']?.toString();
                if(id==null)return;
                context.push(offerPhase?'/offers/$id':'/booking/$id');
              },
              child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Row(children:[
                  Container(width:48,height:48,decoration:BoxDecoration(color:VeyraColors.infoBackground,borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.calendar_month_rounded,color:VeyraColors.primary)),
                  const SizedBox(width:12),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(VeyraDateFormatter.relativeDay(x['scheduled_at']),style:const TextStyle(color:VeyraColors.primaryDark,fontSize:17,fontWeight:FontWeight.w900)),
                    const SizedBox(height:4),
                    VeyraStatusBadge(status:status),
                  ])),
                ]),
                const SizedBox(height:16),
                Text(title,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800,height:1.3)),
                const SizedBox(height:14),
                Row(children:[
                  Text(offerPhase?t('Comparer les offres'):t('Voir les détails'),style:const TextStyle(color:VeyraColors.primary,fontWeight:FontWeight.w800)),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_rounded,color:VeyraColors.primary),
                ]),
              ])),
            ));
          },
        ),
      ]),
    ),
  );
}

/// Écran Compte minimal : identité, langue, déconnexion. Aucune fiche du
/// kit ne le détaille finement (composant implicite de navigation dans
/// les maquettes C02/etc via la bottom nav), volontairement sobre.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<Map<String, dynamic>> future;
  Uint8List? avatar;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    future = api.me();
    api.avatarBytes().then((value) {
      if (mounted) setState(() => avatar = value);
    });
  }

  Future<void> photo() async {
    if(busy)return;
    setState(()=>busy=true);
    try {
      final result=await FilePicker.platform.pickFiles(type:FileType.image);
      if(result==null||!mounted)return;
      final path=result.files.isEmpty?null:result.files.single.path;
      if(path==null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Impossible de lire cette image.'))));return;}
      final profile=await api.uploadAvatar(path);
      final bytes=await api.avatarBytes();
      if(bytes==null||bytes.isEmpty)throw StateError('AVATAR_RELOAD_EMPTY');
      if(!mounted)return;
      setState((){future=Future.value(profile);avatar=bytes;});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Photo de profil mise à jour.'))));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e is DioException?VeyraErrorMessages.forException(e):t('Impossible d’enregistrer la photo de profil.'))));
    }finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> edit(Map<String,dynamic> profile)async{
    if(busy)return;
    final change=await showDialog<(String,String,String)>(context:context,builder:(_)=>VeyraProfileDialog(profile:profile));
    if(change==null||!mounted||busy)return;
    setState(()=>busy=true);
    try{
      final updated=await api.updateProfile(firstName:change.$1,lastName:change.$2,phone:change.$3);
      if(mounted)setState((){future=Future.value(updated);});
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> password()async{
  if(busy)return;
  final change=await showDialog<(String,String)>(context:context,builder:(_)=>const VeyraPasswordDialog());
  if(change==null||!mounted)return;
  setState(()=>busy=true);
  try{await api.changePassword(change.$1,change.$2);await api.logout();if(mounted)context.go('/login');}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));}
  finally{if(mounted)setState(()=>busy=false);}
}
Future<void> logout() async {
    await api.logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Mon compte'))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const VeyraLoadingView();
          }
          if (snapshot.hasError) {
            return VeyraErrorView(customMessage: VeyraErrorMessages.forException(snapshot.error!),onRetry:()=>setState((){future=api.me();}));
          }
          final profile = snapshot.data ?? <String, dynamic>{};
          final name = ('${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}').trim();
          final rating = double.tryParse((profile['rating_average'] ?? 0).toString()) ?? 0;
          final count = profile['rating_count'] ?? 0;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: avatar == null ? null : MemoryImage(avatar!),
                      child: avatar == null ? const Icon(Icons.person, size: 42) : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton.filled(
                        onPressed: busy ? null : photo,
                        icon: const Icon(Icons.camera_alt_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text(name.isEmpty ? t('Client Veyra') : name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              Center(child: Text((profile['email'] ?? '').toString())),
              Center(child: Text((profile['phone'] ?? '').toString())),
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.amber),
                    Text(' ${rating.toStringAsFixed(1)} ($count ${t('avis')})'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(leading: const Icon(Icons.edit), title: Text(t('Informations personnelles')), onTap: () => edit(profile)),
                    ListTile(leading: const Icon(Icons.lock), title: Text(t('Modifier mon mot de passe')), onTap: password),
                    ListTile(leading:const Icon(Icons.place),title:Text(t('Mes adresses')),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const SavedAddressesScreen()))),
                    ListTile(leading:const Icon(Icons.favorite),title:Text(t('Mes chauffeurs favoris')),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const FavoriteDriversScreen()))),
                    ListTile(leading:const Icon(Icons.credit_card),title:Text(t('Mes moyens de paiement')),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SavedCardsScreen(load:api.savedCards,remove:api.removeSavedCard)))),
                  ],
                ),
              ),
              const LanguageSwitch(),
              const SizedBox(height: 20),
              VeyraSecondaryButton(label: t('Se déconnecter'), icon: Icons.logout, onPressed: logout),
            ],
          );
        },
      ),
    );
  }
}

/// Coquille de navigation persistante (bottom nav 4 onglets), conforme
/// aux maquettes C02 et suivantes ("BottomNavigation" listé comme
/// composant UI). Utilise StatefulShellRoute.indexedStack : chaque
/// onglet garde sa propre pile de navigation indépendante (évite les
/// "routes orphelines"/"double page après push" mentionnés dans le
/// protocole anti-erreurs), et les écrans de flux (adresses, offres,
/// détail réservation, chat, tracking) restent des routes de niveau
/// racine poussées PAR-DESSUS la coquille entière, masquant
/// naturellement la bottom nav pendant ces parcours.
class AppShell extends StatelessWidget{
  final StatefulNavigationShell navigationShell;
  const AppShell({required this.navigationShell,super.key});

  @override Widget build(BuildContext context)=>Scaffold(
    body:navigationShell,
    bottomNavigationBar:NavigationBar(
      selectedIndex:navigationShell.currentIndex,
      onDestinationSelected:(i)=>navigationShell.goBranch(i,initialLocation:i==navigationShell.currentIndex),
      destinations:[
        NavigationDestination(icon:const Icon(Icons.home_outlined),selectedIcon:const Icon(Icons.home),label:t('Accueil')),
        NavigationDestination(icon:const Icon(Icons.event_note_outlined),selectedIcon:const Icon(Icons.event_note),label:t('Réservations')),
        NavigationDestination(icon:const Icon(Icons.notifications_outlined),selectedIcon:const Icon(Icons.notifications),label:t('Notifications')),
        NavigationDestination(icon:const Icon(Icons.person_outline),selectedIcon:const Icon(Icons.person),label:t('Compte')),
      ],
    ),
  );
}

/// Parcours de réservation client en 7 étapes, conforme à la planche 09
/// (et à ses variantes 01, 11, 17) : départ, destination, type de
/// véhicule, détails, commentaire, récapitulatif, demande envoyée.
/// Toute la logique métier précédente est conservée (recherche anti-course
/// et anti-rafale, position, adresses enregistrées, contrôle capacité et
/// délai, publication idempotente, réservation à refaire).
class AddressScreen extends StatefulWidget{
  final Map<String,dynamic>? initialBooking;
  const AddressScreen({this.initialBooking,super.key});
  @override State<AddressScreen> createState()=>_AddressScreenState();
}
class _AddressScreenState extends State<AddressScreen>{
  static const _steps=7;
  int step=0;
  final pickup=TextEditingController();
  final notes=TextEditingController();
  int categoryCapacity=9;
  bool categoriesReady=false;
  final dropoff=TextEditingController();
  List<dynamic> pickupResults=[];
  List<dynamic> dropoffResults=[];
  Map<String,dynamic>? pickupPlace;
  Map<String,dynamic>? dropoffPlace;
  DateTime? scheduledAt;
  String paymentMethod='CASH';
  int passengerCount=1;
  int baggageCount=0;
  String? categoryId;
  String? categoryName;
  late Future<List<dynamic>> categories;
  late Future<List<dynamic>> saved;
  List<Map<String,dynamic>> recents=[];
  Map<String,dynamic>? route;
  String? newBookingId;
  bool pickOnMap=false;

  bool loadingPickup=false;
  bool loadingDropoff=false;
  bool locating=false;
  bool submitting=false;
  String? error;
  Timer? _searchDebounce;
  int pickupSearchRevision=0,dropoffSearchRevision=0;
  static const _recentKey='recentPlaces';

  @override void initState(){
    super.initState();
    categories=loadCategories();
    saved=api.savedAddresses().catchError((_)=><dynamic>[]);
    loadRecents();
    final initial=widget.initialBooking;
    if(initial!=null){
      final pickupLabel=initial['pickup_address']?.toString()??'';
      final dropoffLabel=initial['dropoff_address']?.toString()??'';
      final pickupLat=(initial['pickup_lat'] as num?)?.toDouble();
      final pickupLng=(initial['pickup_lng'] as num?)?.toDouble();
      final dropoffLat=(initial['dropoff_lat'] as num?)?.toDouble();
      final dropoffLng=(initial['dropoff_lng'] as num?)?.toDouble();
      pickup.text=pickupLabel; dropoff.text=dropoffLabel;
      notes.text=(initial['customer_notes']??'').toString();
      if(pickupLat!=null&&pickupLng!=null)pickupPlace={'label':pickupLabel,'lat':pickupLat,'lng':pickupLng};
      if(dropoffLat!=null&&dropoffLng!=null)dropoffPlace={'label':dropoffLabel,'lat':dropoffLat,'lng':dropoffLng};
      categoryId=initial['vehicle_category_id']?.toString()??initial['category_id']?.toString();
      categoryName=initial['vehicle_category_name']?.toString()??initial['category_name']?.toString();
      paymentMethod=initial['payment_method']?.toString()??'CASH';
      passengerCount=(initial['passenger_count'] as num?)?.toInt()??1;
      baggageCount=(initial['baggage_count'] as num?)?.toInt()??0;
      scheduledAt=DateTime.now().add(const Duration(hours:3));
    }
  }

  Future<List<dynamic>> loadCategories()async{
    final items=await api.vehicleCategories();
    if(mounted)setState((){
      categoriesReady=true;
      final matches=items.whereType<Map>().where((x)=>x['id'].toString()==categoryId);
      if(categoryId!=null){
        if(matches.isEmpty){categoryId=null;categoryName=null;}
        else{final selected=matches.first;categoryCapacity=(selected['capacity'] as num).toInt();categoryName=(selected['display_name']??selected['code']).toString();}
      }
    });
    return items;
  }

  Future<void> loadRecents()async{
    try{
      final raw=await api.storage.read(key:_recentKey);
      if(raw==null)return;
      final list=(jsonDecode(raw) as List).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).toList();
      if(mounted)setState(()=>recents=list);
    }catch(_){}
  }

  /// Keeps the last 5 chosen places on the device only (never sent).
  Future<void> rememberPlace(Map<String,dynamic> place)async{
    if(place['lat']==null||place['lng']==null)return;
    final next=[{'label':place['label'],'lat':place['lat'],'lng':place['lng']},...recents.where((p)=>p['label']!=place['label'])].take(5).toList();
    recents=next;
    try{await api.storage.write(key:_recentKey,value:jsonEncode(next));}catch(_){}
  }

  @override void dispose(){
    _searchDebounce?.cancel();
    pickup.dispose();dropoff.dispose();notes.dispose();
    super.dispose();
  }

  Future<void> search(bool isPickup,String q)async{
    final revision=isPickup?++pickupSearchRevision:++dropoffSearchRevision;
    bool current()=>mounted&&revision==(isPickup?pickupSearchRevision:dropoffSearchRevision)&&(isPickup?pickup:dropoff).text.trim()==q.trim();
    if(q.trim().length<3){
      setState((){if(isPickup)pickupResults=[];else dropoffResults=[];});
      return;
    }
    setState((){if(isPickup)loadingPickup=true;else loadingDropoff=true;});
    try{
      final r=await api.autocomplete(q);
      if(current())setState((){if(isPickup)pickupResults=r;else dropoffResults=r;});
    }catch(_){
      if(current())setState(()=>error=t('Recherche d’adresse indisponible.'));
    }finally{
      if(current())setState((){if(isPickup)loadingPickup=false;else loadingDropoff=false;});
    }
  }

  Future<void> useMyLocation()async{
    if(!await Geolocator.isLocationServiceEnabled()){
      if(mounted)setState(()=>error=t('Activez la localisation du téléphone.'));
      return;
    }
    var permission=await Geolocator.checkPermission();
    if(permission==LocationPermission.denied){
      permission=await Geolocator.requestPermission();
    }
    if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever){
      if(mounted)setState(()=>error=t('La localisation est nécessaire pour utiliser votre position actuelle.'));
      return;
    }
    setState(()=>locating=true);
    try{
      final p=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high));
      final place=await api.reverseGeocode(p.latitude,p.longitude);
      if(place==null){
        if(mounted)setState(()=>error=t('Aucune adresse trouvée pour votre position actuelle.'));
        return;
      }
      if(mounted)selectPlace(true,place);
    }catch(_){
      if(mounted)setState(()=>error=t('Impossible d’obtenir votre position actuelle.'));
    }finally{
      if(mounted)setState(()=>locating=false);
    }
  }

  Future<void> pickDestinationOnMap(LatLng point)async{
    try{
      final place=await api.reverseGeocode(point.latitude,point.longitude);
      if(!mounted)return;
      if(place==null){setState(()=>error=t('Aucune adresse trouvée à cet endroit.'));return;}
      selectPlace(false,place);
      setState(()=>pickOnMap=false);
    }catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }
  }

  void selectPlace(bool isPickup,Map<String,dynamic> place){
    final selected=Map<String,dynamic>.from(place);
    setState((){
      error=null;
      if(isPickup){pickupPlace=selected;pickup.text=selected['label']?.toString()??'';pickupResults=[];}
      else{dropoffPlace=selected;dropoff.text=selected['label']?.toString()??'';dropoffResults=[];}
      route=null;
    });
    rememberPlace(selected);
  }

  Future<void> selectSavedAddress(bool isPickup)async{
    final value=await Navigator.push<Map<String,dynamic>>(context,MaterialPageRoute(builder:(_)=>const SavedAddressesScreen(select:true)));
    if(value!=null&&mounted)selectPlace(isPickup,value);
  }

  Future<void> chooseDate()async{
    final now=DateTime.now();
    final latest=now.add(const Duration(days:365));
    final base=scheduledAt??now.add(const Duration(hours:3));
    final initial=base.isBefore(now)?now:(base.isAfter(latest)?latest:base);
    final date=await showDatePicker(context:context,firstDate:now,lastDate:latest,initialDate:initial);
    if(date==null||!mounted)return;
    final time=TimeOfDay.fromDateTime(scheduledAt??now.add(const Duration(hours:3)));
    setDateTime(DateTime(date.year,date.month,date.day,time.hour,time.minute));
  }

  Future<void> chooseTime()async{
    final base=scheduledAt??DateTime.now().add(const Duration(hours:3));
    final time=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(base));
    if(time==null||!mounted)return;
    setDateTime(DateTime(base.year,base.month,base.day,time.hour,time.minute));
  }

  void setDateTime(DateTime selected){
    setState((){
      scheduledAt=selected;
      error=selected.difference(DateTime.now())<const Duration(hours:2)?t('Le départ doit être planifié au moins 2 heures à l’avance.'):null;
    });
  }

  bool get leadTimeOk=>scheduledAt!=null&&scheduledAt!.difference(DateTime.now())>=const Duration(hours:2);
  bool get capacityOk=>passengerCount<=categoryCapacity;

  bool canContinue(){
    switch(step){
      case 0:return pickupPlace!=null;
      case 1:return dropoffPlace!=null;
      case 2:return categoryId!=null&&categoriesReady;
      case 3:return leadTimeOk&&capacityOk;
      default:return true;
    }
  }

  void goTo(int target){
    setState((){step=target;error=null;pickOnMap=false;});
    if(target==5)loadRoute();
  }

  void back(){
    if(step==0){
      if(Navigator.canPop(context))Navigator.pop(context);else context.go('/home');
      return;
    }
    goTo(step-1);
  }

  Future<void> loadRoute()async{
    final a=pickupPlace,b=dropoffPlace;
    if(a==null||b==null||route!=null)return;
    try{
      final r=await api.routeEstimate(fromLat:(a['lat'] as num).toDouble(),fromLng:(a['lng'] as num).toDouble(),toLat:(b['lat'] as num).toDouble(),toLng:(b['lng'] as num).toDouble());
      if(mounted)setState(()=>route=r);
    }catch(_){}
  }

  Future<void> publish()async{
    if(submitting)return;
    if(!categoriesReady){setState(()=>error=t('Rechargez les catégories avant de publier.'));return;}
    if(!capacityOk){setState(()=>error=t('Le nombre de passagers dépasse la capacité de cette catégorie.'));return;}
    if(pickupPlace==null||dropoffPlace==null||scheduledAt==null||categoryId==null){
      setState(()=>error=t('Complétez le trajet, la date et la catégorie.'));
      return;
    }
    if(!leadTimeOk){
      setState(()=>error=t('Le départ doit être planifié au moins 2 heures à l’avance.'));
      return;
    }
    setState((){submitting=true;error=null;});
    try{
      final created=await api.createBooking({
        'pickup':{'lat':pickupPlace!['lat'],'lng':pickupPlace!['lng'],'address':pickupPlace!['label']},
        'dropoff':{'lat':dropoffPlace!['lat'],'lng':dropoffPlace!['lng'],'address':dropoffPlace!['label']},
        'scheduledAt':scheduledAt!.toUtc().toIso8601String(),
        'categoryId':categoryId,
        'paymentMethod':paymentMethod,
        'payerType':'CLIENT',
        'passengerCount':passengerCount,
        'baggageCount':baggageCount,
        'customerNotes':notes.text.trim(),
        'preferredDriverId':widget.initialBooking?['preferred_driver_id'],
      });
      if(!mounted)return;
      RefreshBus.bump();
      // A published request is not a confirmed driver: the success step
      // speaks about the request being sent, never about a ride booked.
      setState((){newBookingId=created['id']?.toString();step=6;});
    }on DioException catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }catch(_){
      if(mounted)setState(()=>error=t('La réservation n’a pas pu être publiée. Vérifiez les informations puis réessayez.'));
    }finally{
      if(mounted)setState(()=>submitting=false);
    }
  }

  // ---------- présentation ----------

  static String shortDate(DateTime d){
    final en=AppLocale.code.value=='en';
    final days=en?['Mon','Tue','Wed','Thu','Fri','Sat','Sun']:['Lun.','Mar.','Mer.','Jeu.','Ven.','Sam.','Dim.'];
    final months=en?['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']:['janv.','févr.','mars','avr.','mai','juin','juil.','août','sept.','oct.','nov.','déc.'];
    return '${days[d.weekday-1]} ${d.day} ${months[d.month-1]} ${d.year}';
  }

  static String hhmm(DateTime d)=>'${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';

  /// "Rue de la Paix, 75008 Paris" -> ("Rue de la Paix", "75008 Paris").
  static (String,String?) splitLabel(String label){
    final i=label.indexOf(',');
    if(i<0)return (label,null);
    return (label.substring(0,i).trim(),label.substring(i+1).trim());
  }

  LatLng? point(Map<String,dynamic>? p)=>p==null||p['lat']==null||p['lng']==null?null:LatLng((p['lat'] as num).toDouble(),(p['lng'] as num).toDouble());

  IconData savedIcon(String name){
    final n=name.toLowerCase();
    if(n.contains('maison')||n.contains('domicile')||n.contains('home'))return Icons.home;
    if(n.contains('travail')||n.contains('bureau')||n.contains('work'))return Icons.work_outline;
    return Icons.bookmark_outline;
  }

  Widget searchField(bool isPickup){
    final controller=isPickup?pickup:dropoff;
    final loading=isPickup?loadingPickup:loadingDropoff;
    return TextField(
      controller:controller,
      onChanged:(q){
        // Setting the text programmatically also fires onChanged: only a
        // real edit (text differs from the chosen place) clears the choice.
        final current=isPickup?pickupPlace:dropoffPlace;
        if(current!=null&&current['label']==q)return;
        setState((){
          if(isPickup){pickupPlace=null;pickupResults=[];loadingPickup=false;pickupSearchRevision++;}
          else{dropoffPlace=null;dropoffResults=[];loadingDropoff=false;dropoffSearchRevision++;}
          route=null;
        });
        // 400 ms debounce: one geocoding call per pause, not per keystroke.
        _searchDebounce?.cancel();
        _searchDebounce=Timer(const Duration(milliseconds:400),()=>search(isPickup,q));
      },
      style:const TextStyle(fontSize:15,fontWeight:FontWeight.w500),
      decoration:InputDecoration(
        hintText:isPickup?t('Adresse de départ'):t('Destination'),
        prefixIcon:Icon(Icons.location_on,color:isPickup?VeyraColors.accent:VeyraColors.pinRed),
        suffixIcon:loading
          ?const Padding(padding:EdgeInsets.all(14),child:SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)))
          :controller.text.isEmpty?null:IconButton(
            tooltip:t('Effacer'),
            icon:const Icon(Icons.cancel,color:VeyraColors.textTertiary,size:20),
            onPressed:(){setState((){controller.clear();if(isPickup){pickupPlace=null;pickupResults=[];}else{dropoffPlace=null;dropoffResults=[];}route=null;});},
          ),
      ),
    );
  }

  List<Widget> suggestions(bool isPickup){
    final results=isPickup?pickupResults:dropoffResults;
    final selected=isPickup?pickupPlace:dropoffPlace;
    if(results.isNotEmpty){
      return [
        VeyraSectionLabel(t('Suggestions')),
        const SizedBox(height:6),
        for(final raw in results.take(6))Builder(builder:(_){
          final item=Map<String,dynamic>.from(raw as Map);
          final (title,sub)=splitLabel(item['label']?.toString()??'');
          return VeyraPlaceTile(icon:Icons.location_on_outlined,title:title,subtitle:sub,onTap:()=>selectPlace(isPickup,item));
        }),
      ];
    }
    return [
      VeyraSectionLabel(isPickup?t('Adresses récentes'):t('Suggestions')),
      const SizedBox(height:6),
      if(selected!=null)Builder(builder:(_){
        final (title,sub)=splitLabel(selected['label']?.toString()??'');
        return VeyraPlaceTile(icon:Icons.location_on,title:title,subtitle:sub,highlighted:true,onTap:(){});
      }),
      for(final p in recents.where((p)=>p['label']!=selected?['label']))Builder(builder:(_){
        final (title,sub)=splitLabel(p['label']?.toString()??'');
        return VeyraPlaceTile(icon:Icons.history,title:title,subtitle:sub,onTap:()=>selectPlace(isPickup,p));
      }),
      FutureBuilder<List<dynamic>>(future:saved,builder:(context,s){
        final items=(s.data??[]).whereType<Map>().toList();
        return Column(children:[
          for(final a in items)VeyraPlaceTile(
            icon:savedIcon(a['label']?.toString()??''),
            title:a['label']?.toString()??'',
            subtitle:a['address']?.toString(),
            onTap:()=>selectPlace(isPickup,{'label':a['address'],'lat':a['lat'],'lng':a['lng']}),
          ),
          VeyraPlaceTile(icon:Icons.bookmark_add_outlined,title:t('Mes adresses enregistrées'),onTap:()=>selectSavedAddress(isPickup)),
        ]);
      }),
    ];
  }

  Widget stepPickup()=>ListView(padding:const EdgeInsets.fromLTRB(20,8,20,20),children:[
    VeyraStepTitle(t('Où partez-vous ?')),
    const SizedBox(height:16),
    searchField(true),
    const SizedBox(height:10),
    VeyraTapRow(
      icon:Icons.my_location,
      label:t('Utiliser ma position actuelle'),
      muted:true,
      onTap:locating?null:useMyLocation,
      trailing:locating?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):null,
    ),
    const SizedBox(height:14),
    VeyraRouteMap(pickup:point(pickupPlace),height:190),
    const SizedBox(height:18),
    ...suggestions(true),
  ]);

  Widget stepDropoff()=>ListView(padding:const EdgeInsets.fromLTRB(20,8,20,20),children:[
    VeyraStepTitle(t('Où allez-vous ?')),
    const SizedBox(height:16),
    searchField(false),
    const SizedBox(height:10),
    VeyraTapRow(icon:Icons.map_outlined,label:pickOnMap?t('Touchez la carte pour placer la destination'):t('Choisir sur la carte'),muted:true,onTap:()=>setState(()=>pickOnMap=!pickOnMap)),
    const SizedBox(height:14),
    // Board 09 step 2 shows the destination pin only.
    VeyraRouteMap(
      dropoff:point(dropoffPlace),
      height:pickOnMap?320:190,
      interactive:pickOnMap,
      onTap:pickOnMap?pickDestinationOnMap:null,
    ),
    const SizedBox(height:18),
    ...suggestions(false),
  ]);

  Widget stepCategory()=>FutureBuilder<List<dynamic>>(
    future:categories,
    builder:(context,s){
      final header=[VeyraStepTitle(t('Quel type de véhicule ?'),subtitle:t('Choisissez la catégorie qui correspond à vos besoins.')),const SizedBox(height:16)];
      if(s.connectionState!=ConnectionState.done)return ListView(padding:const EdgeInsets.all(20),children:[...header,const LinearProgressIndicator()]);
      if(s.hasError)return ListView(padding:const EdgeInsets.all(20),children:[...header,VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState((){categories=loadCategories();}))]);
      final items=(s.data??[]).whereType<Map>().toList();
      return ListView(padding:const EdgeInsets.fromLTRB(20,8,20,20),children:[
        ...header,
        for(final x in items)Padding(
          padding:const EdgeInsets.only(bottom:12),
          child:VeyraSelectableCard(
            selected:x['id'].toString()==categoryId,
            onTap:()=>setState((){
              categoryId=x['id'].toString();
              categoryCapacity=(x['capacity'] as num).toInt();
              categoryName=(x['display_name']??x['code']).toString();
              error=null;
            }),
            child:Row(children:[
              VeyraVehicleThumb(van:(x['capacity'] as num)>4),
              const SizedBox(width:14),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text((x['display_name']??x['code']).toString(),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700)),
                const SizedBox(height:4),
                Row(children:[
                  const Icon(Icons.person_outline,size:18,color:VeyraColors.textSecondary),
                  const SizedBox(width:4),
                  Text('${x['capacity']}',style:const TextStyle(fontWeight:FontWeight.w600)),
                ]),
              ])),
            ]),
          ),
        ),
      ]);
    },
  );

  Widget stepDetails()=>ListView(padding:const EdgeInsets.fromLTRB(20,8,20,20),children:[
    VeyraStepTitle(t('Détails du trajet')),
    const SizedBox(height:18),
    VeyraSectionLabel(t('Date et heure')),
    const SizedBox(height:10),
    VeyraTapRow(icon:Icons.calendar_today_outlined,label:t('Date'),value:scheduledAt==null?t('Choisir'):shortDate(scheduledAt!),chevron:true,onTap:chooseDate),
    const SizedBox(height:10),
    VeyraTapRow(icon:Icons.schedule,label:t('Heure de départ'),value:scheduledAt==null?t('Choisir'):hhmm(scheduledAt!),chevron:true,onTap:chooseTime),
    if(scheduledAt!=null&&!leadTimeOk)...[const SizedBox(height:10),VeyraBanner(tone:VeyraTone.danger,text:t('Le départ doit être planifié au moins 2 heures à l’avance.'))],
    const SizedBox(height:22),
    VeyraSectionLabel(t('Nombre de passagers')),
    const SizedBox(height:10),
    VeyraCounterRow(icon:Icons.person_outline,value:passengerCount,min:1,max:9,semanticLabel:t('Passagers'),onChanged:(v)=>setState(()=>passengerCount=v)),
    if(!capacityOk)...[
      const SizedBox(height:10),
      VeyraBanner(tone:VeyraTone.danger,title:t('Le nombre de passagers dépasse la capacité du véhicule sélectionné.'),text:t('Le véhicule')+' ${categoryName??''} '+t('peut accueillir jusqu’à')+' $categoryCapacity '+t('passagers.')),
    ],
    const SizedBox(height:22),
    VeyraSectionLabel(t('Nombre de bagages')),
    const SizedBox(height:10),
    VeyraCounterRow(icon:Icons.luggage_outlined,value:baggageCount,min:0,max:12,semanticLabel:t('Bagages'),onChanged:(v)=>setState(()=>baggageCount=v)),
    const SizedBox(height:12),
    VeyraBanner(text:t('1 bagage = 1 valise standard. Veuillez indiquer le nombre total de bagages.')),
  ]);

  Widget stepComment()=>ListView(padding:const EdgeInsets.fromLTRB(20,8,20,20),children:[
    VeyraStepTitle(t('Un commentaire ?'),suffix:t('(facultatif)')),
    const SizedBox(height:18),
    Container(
      decoration:BoxDecoration(borderRadius:BorderRadius.circular(VeyraRadius.md),border:Border.all(color:VeyraColors.border)),
      padding:const EdgeInsets.fromLTRB(14,12,14,8),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Icon(Icons.chat_outlined,color:VeyraColors.textPrimary),
        TextField(
          controller:notes,
          maxLength:500,
          minLines:5,
          maxLines:8,
          onChanged:(_)=>setState((){}),
          decoration:InputDecoration(
            hintText:t('Indications pour le chauffeur (lieu exact, bagages, siège enfant…)'),
            border:InputBorder.none,enabledBorder:InputBorder.none,focusedBorder:InputBorder.none,filled:false,
            contentPadding:const EdgeInsets.only(top:10),
          ),
        ),
      ]),
    ),
    const SizedBox(height:14),
    VeyraBanner(text:t('Ce commentaire sera visible par les chauffeurs afin de mieux comprendre votre demande.')),
  ]);

  Widget recapCard({required Widget child})=>Container(
    padding:const EdgeInsets.symmetric(vertical:12),
    decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:VeyraColors.border))),
    child:child,
  );

  Widget recapLine(IconData icon,String label,String value)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:6),
    child:Row(children:[
      Icon(icon,size:24,color:VeyraColors.textPrimary),
      const SizedBox(width:14),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:const TextStyle(fontSize:13,color:VeyraColors.textSecondary)),
        Text(value,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w600)),
      ])),
    ]),
  );

  Widget paymentOption(String value,IconData icon,String title,String subtitle)=>Padding(
    padding:const EdgeInsets.only(bottom:10),
    child:VeyraSelectableCard(
      selected:paymentMethod==value,
      onTap:()=>setState(()=>paymentMethod=value),
      child:Row(children:[
        Icon(icon,color:VeyraColors.primary),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),
          Text(subtitle,style:const TextStyle(fontSize:12,color:VeyraColors.textSecondary)),
        ])),
      ]),
    ),
  );

  Widget stepRecap(){
    final (pTitle,pSub)=splitLabel(pickupPlace?['label']?.toString()??'');
    final (dTitle,dSub)=splitLabel(dropoffPlace?['label']?.toString()??'');
    final points=((route?['points'] as List?)??[]).whereType<Map>().map((m)=>LatLng((m['lat'] as num).toDouble(),(m['lng'] as num).toDouble())).toList();
    final km=route?['distanceMeters'] is num?((route!['distanceMeters'] as num)/1000).round():null;
    final min=route?['durationSeconds'] is num?((route!['durationSeconds'] as num)/60).round():null;
    return ListView(padding:const EdgeInsets.fromLTRB(20,8,20,20),children:[
      VeyraStepTitle(t('Récapitulatif de votre demande')),
      const SizedBox(height:8),
      recapCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        VeyraSectionLabel(t('Trajet'),action:VeyraEditLink(onTap:()=>goTo(0))),
        const SizedBox(height:8),
        VeyraRoutePoints(pickupTitle:pTitle,pickupSubtitle:pSub,dropoffTitle:dTitle,dropoffSubtitle:dSub),
      ])),
      recapCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        VeyraSectionLabel(t('Type de véhicule'),action:VeyraEditLink(onTap:()=>goTo(2))),
        const SizedBox(height:8),
        Row(children:[
          VeyraVehicleThumb(width:84,van:categoryCapacity>4),
          const SizedBox(width:14),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(categoryName??'',style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700)),
            Row(children:[const Icon(Icons.person_outline,size:18,color:VeyraColors.textSecondary),const SizedBox(width:4),Text('$categoryCapacity')]),
          ])),
        ]),
      ])),
      recapCard(child:Column(children:[
        Row(children:[const Spacer(),VeyraEditLink(onTap:()=>goTo(3))]),
        recapLine(Icons.calendar_today_outlined,t('Date et heure'),scheduledAt==null?'':'${shortDate(scheduledAt!)} · ${hhmm(scheduledAt!)}'),
        recapLine(Icons.person_outline,t('Passagers'),'$passengerCount'),
        recapLine(Icons.luggage_outlined,t('Bagages'),'$baggageCount'),
      ])),
      recapCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Expanded(child:Text.rich(TextSpan(children:[
            TextSpan(text:t('Commentaire'),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700)),
            TextSpan(text:' '+t('(facultatif)'),style:const TextStyle(fontSize:13,color:VeyraColors.textSecondary)),
          ]))),
          VeyraEditLink(onTap:()=>goTo(4)),
        ]),
        const SizedBox(height:4),
        Text(notes.text.trim().isEmpty?t('Aucun commentaire'):notes.text.trim(),style:const TextStyle(color:VeyraColors.textSecondary)),
      ])),
      const SizedBox(height:14),
      VeyraSectionLabel(t('Mode de paiement')),
      const SizedBox(height:10),
      paymentOption('ONLINE',Icons.credit_card,t('Payer en ligne par carte'),t('Paiement sécurisé à la confirmation du chauffeur')),
      paymentOption('CASH',Icons.payments_outlined,t('Payer en cash au chauffeur'),t('Vous payez directement le chauffeur')),
      if(widget.initialBooking?['preferred_driver_id']!=null)...[
        const SizedBox(height:4),
        VeyraBanner(tone:VeyraTone.warning,text:t('Votre chauffeur favori sera indiqué comme préférence. Son attribution dépend de sa disponibilité et de votre choix parmi les offres.')),
      ],
      const SizedBox(height:12),
      VeyraRouteMap(pickup:point(pickupPlace),dropoff:point(dropoffPlace),route:points,height:150),
      if(km!=null&&min!=null)...[
        const SizedBox(height:10),
        Row(children:[
          const Icon(Icons.directions_car_outlined,color:VeyraColors.textPrimary),
          const SizedBox(width:10),
          Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(t('Estimation du trajet'),style:const TextStyle(fontWeight:FontWeight.w700)),
            Text('$km km · $min min',style:const TextStyle(color:VeyraColors.textSecondary)),
          ]),
        ]),
      ],
    ]);
  }

  Widget stepSent()=>ListView(padding:const EdgeInsets.fromLTRB(24,24,24,24),children:[
    const SizedBox(height:20),
    Center(child:Container(
      width:120,height:120,
      decoration:const BoxDecoration(shape:BoxShape.circle,color:VeyraColors.successBackground),
      child:const Icon(Icons.send_rounded,size:56,color:VeyraColors.success),
    )),
    const SizedBox(height:28),
    Text(t('Votre demande a été envoyée !'),textAlign:TextAlign.center,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
    const SizedBox(height:12),
    Text(t('Nous recherchons des chauffeurs disponibles pour votre trajet. Vous recevrez leurs offres dans quelques instants.'),textAlign:TextAlign.center,style:const TextStyle(color:VeyraColors.textSecondary,height:1.45)),
    const SizedBox(height:28),
    FilledButton.icon(onPressed:()=>context.go('/home'),icon:const Icon(Icons.home_outlined),label:Text(t('Retour à l’accueil'))),
    const SizedBox(height:12),
    if(newBookingId!=null)FilledButton.icon(
      style:FilledButton.styleFrom(backgroundColor:VeyraColors.surfaceMuted,foregroundColor:VeyraColors.textPrimary),
      onPressed:(){context.go('/home');context.push('/booking/'+newBookingId!);},
      icon:const Icon(Icons.list),
      label:Text(t('Voir ma demande')),
    ),
    const SizedBox(height:20),
    VeyraBanner(text:t('Vous serez notifié dès qu’une nouvelle offre est disponible.')),
  ]);

  @override Widget build(BuildContext context){
    final pages=[stepPickup,stepDropoff,stepCategory,stepDetails,stepComment,stepRecap,stepSent];
    final sent=step==6;
    return PopScope(
      canPop:step==0||sent,
      onPopInvokedWithResult:(didPop,_){if(!didPop)back();},
      child:Scaffold(
        appBar:VeyraFlowHeader(onBack:sent?()=>context.go('/home'):back),
        body:Column(children:[
          // No visible progress bar on the boards; the step stays announced.
          Semantics(liveRegion:true,label:t('Étape')+' ${step+1}/$_steps',child:const SizedBox(height:12,width:double.infinity)),
          Expanded(child:pages[step]()),
          if(error!=null)Padding(padding:const EdgeInsets.fromLTRB(20,0,20,4),child:VeyraBanner(tone:VeyraTone.danger,text:error!)),
        ]),
        bottomNavigationBar:sent?null:VeyraFlowFooter(
          onBack:step==0?null:back,
          onNext:step==5?publish:(canContinue()?()=>goTo(step+1):null),
          nextLabel:step==5?t('Rechercher des offres'):t('Suivant'),
          trailingArrow:step!=5,
          loading:submitting,
        ),
      ),
    );
  }
}

class OffersScreen extends StatefulWidget{
  final String bookingId;
  const OffersScreen({required this.bookingId,super.key});
  @override State<OffersScreen> createState()=>_OffersScreenState();
}
class _OffersScreenState extends State<OffersScreen>{
  late Future<List<dynamic>> future;
  late Future<Map<String,dynamic>> bookingFuture;
  String? error;
  String? acceptingOfferId;
  Timer? refreshTimer;
  bool refreshing=false;
  @override void initState(){
    super.initState();
    refreshTimer=Timer.periodic(const Duration(seconds:10),(_)=>refreshOffers());
    RefreshBus.tick.addListener(refreshOffers);
    future=api.offers(widget.bookingId);
    // Real gap fixed here: this screen only ever fetched the offers
    // list, never the booking's own details -- someone landing here
    // before any offer exists (the normal, expected state right after
    // publishing) had no way to see their own trip's pickup, dropoff,
    // date, or status anywhere, on this screen or otherwise, since this
    // is the only screen a not-yet-assigned booking actually routes to.
    bookingFuture=api.bookingDetail(widget.bookingId);
  }

  Future<void> refreshOffers()async{
    if(refreshing||acceptingOfferId!=null)return;refreshing=true;
    try{final b=await api.bookingDetail(widget.bookingId);final values=await api.offers(widget.bookingId);if(mounted)setState((){future=Future.value(values);bookingFuture=Future.value(b);error=null;});}
    catch(e){if(mounted)setState(()=>error=t('Actualisation interrompue. Vérifiez votre connexion.'));}
    finally{refreshing=false;}
  }
  @override void dispose(){RefreshBus.tick.removeListener(refreshOffers);refreshTimer?.cancel();super.dispose();}
  Future<void> confirmOffer(Map<String,dynamic> offer)async{
    if(acceptingOfferId!=null)return;
    final yes=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:Text(t('Choisir ce chauffeur ?')),content:Text([offer['driverFirstName'],offer['driverLastName'],offer['vehicleBrand'],offer['vehicleModel'],offer['vehicleColor'],offer['vehicleYear'],t('Total à payer')+' : '+VeyraMoneyFormatter.fromMinor(offer['totalMinor'])].where((v)=>v!=null).join(' • ')),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:Text(t('Comparer encore'))),FilledButton(style:FilledButton.styleFrom(minimumSize:const Size(0,52)),onPressed:()=>Navigator.pop(d,true),child:Text(t('Confirmer mon choix')))]));
    if(yes==true&&mounted)await chooseOffer(offer['offerId'].toString());
  }
  Future<void> chooseOffer(String offerId)async{
    if(acceptingOfferId!=null)return;
    setState((){acceptingOfferId=offerId;error=null;});
    try{
      await api.accept(widget.bookingId,offerId);
      final booking=await api.bookingDetail(widget.bookingId);
      if(!mounted)return;
      RefreshBus.bump();
      if(booking['payment_method']=='ONLINE'){
        context.push('/payment/'+widget.bookingId);
      }else{
        context.push('/booking/'+widget.bookingId);
      }
    }on DioException catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }catch(_){
      if(mounted)setState(()=>error=t('Impossible de choisir cette offre pour le moment.'));
    }finally{
      if(mounted)setState(()=>acceptingOfferId=null);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(actions:[IconButton(onPressed:refreshOffers,icon:const Icon(Icons.refresh),tooltip:t('Actualiser'))],title:Text(t('Choisir votre chauffeur')),backgroundColor:const Color(0xFFF2F6FB),elevation:0),
    body:RefreshIndicator(onRefresh:refreshOffers,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(16),children:[
      FutureBuilder<Map<String,dynamic>>(
        future:bookingFuture,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done||s.hasError)return const SizedBox.shrink();
          final b=s.data??{};
          return Card(
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
            child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(
                (b['pickup_address']??'').toString()+' → '+(b['dropoff_address']??'').toString(),
                style:const TextStyle(fontWeight:FontWeight.w600),
              ),
              const SizedBox(height:6),
              // Défaut d'accessibilité réel (test offers_accessibility_test, texte
              // x1,5 sur 320 px) : le badge de statut était un enfant NON flexible
              // d'un Row -- dès que son libellé ("OFFRES REÇUES") est plus large que
              // la ligne, RenderFlex déborde. Wrap + spaceBetween garde le badge à
              // droite en taille normale et le fait passer à la ligne sinon.
              SizedBox(width:double.infinity,child:Wrap(
                alignment:WrapAlignment.spaceBetween,
                crossAxisAlignment:WrapCrossAlignment.center,
                spacing:8,runSpacing:6,
                children:[
                  Text(VeyraDateFormatter.dateTime(b['scheduled_at']),style:const TextStyle(color:Colors.black54,fontSize:13)),
                  VeyraStatusBadge(status:(b['status']??'').toString()),
                ],
              )),
            ])),
          );
        },
      ),
      const SizedBox(height:16),
      if(error!=null)Padding(padding:const EdgeInsets.only(bottom:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
          if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
            ?VeyraOfflineBanner(onRetry:()=>setState((){future=api.offers(widget.bookingId);}))
            :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState((){future=api.offers(widget.bookingId);}));
          final items=s.data??[];
          if(items.isEmpty)return Padding(padding:const EdgeInsets.all(24),child:Text(t('Aucune offre pour le moment. Vous serez notifié dès qu’un chauffeur propose un prix.')));
          return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(items.length==1?t('1 offre reçue'):items.length.toString()+' '+t('offres reçues'),style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:VeyraColors.primaryDark)),
            const SizedBox(height:5),
            Text(t('Comparez librement le prix, le véhicule et le chauffeur.'),style:const TextStyle(color:VeyraColors.textSecondary,height:1.35)),

            const SizedBox(height:14),
            for(final raw in items)Builder(builder:(context){
              final x=Map<String,dynamic>.from(raw as Map);
              final driverName=(x['driverFirstName']??'Chauffeur').toString();
              final vehicle=[(x['vehicleBrand']??'').toString(),(x['vehicleModel']??'').toString()].where((v)=>v.isNotEmpty).join(' ');
              final rating=(x['rating']??'-').toString();
            return Card(
              margin:const EdgeInsets.only(bottom:12),
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
              child:InkWell(onTap:acceptingOfferId!=null?null:()=>confirmOffer(x),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Row(children:[
                  CircleAvatar(radius:24,backgroundColor:const Color(0xFF1565C0).withValues(alpha:0.12),child:const Icon(Icons.local_taxi,color:Color(0xFF1565C0))),
                  const SizedBox(width:12),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(driverName,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
                    Row(children:[
                      const Icon(Icons.star,color:Color(0xFFF59E0B),size:16),
                      const SizedBox(width:2),
                      Text(rating,style:const TextStyle(color:Colors.black54)),
                      const SizedBox(width:8),
                      Expanded(child:Text('${x['vehicleCategory']??'VTC'} • $vehicle',style:const TextStyle(color:Colors.black54,fontSize:12),overflow:TextOverflow.ellipsis)),
                    ]),
                  ])),
                ]),
                Align(alignment:Alignment.centerRight,child:Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
                    Text(t('Total à payer'),style:const TextStyle(fontSize:11,color:Colors.black45)),
                    Text(VeyraMoneyFormatter.fromMinor(x['totalMinor']),style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Color(0xFF123A66))),
                  ])),
                Text([x['vehicleColor'],x['vehicleYear']].where((v)=>v!=null).join(' • ')),
                const SizedBox(height:8),
                if(x['driverVerified']==true)Row(children:[
                  const Icon(Icons.verified_user_outlined,size:16,color:VeyraColors.success),
                  const SizedBox(width:5),
                  Expanded(child:Text(t('Chauffeur Veyra vérifié'),style:const TextStyle(fontSize:12,color:VeyraColors.textSecondary,fontWeight:FontWeight.w600))),
                ]),
                const SizedBox(height:14),
                SizedBox(width:double.infinity,child:FilledButton(
                  style:FilledButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
                  onPressed:acceptingOfferId!=null?null:()=>confirmOffer(x),
                  child:acceptingOfferId==x['offerId'].toString()
                    ?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
                    :Text(t('Choisir cette offre')),
                )),
              ]))),
            );
          }),
          ]);
        },
      ),
    ])),
  );
}


bool bookingCanPayOnline(Map<String,dynamic>? booking)=>booking!=null&&
  booking['payment_method']=='ONLINE'&&booking['payment_status']!='CAPTURED'&&
  {'CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED'}.contains(booking['status']);

class PaymentScreen extends StatefulWidget{
  final String bookingId;
  const PaymentScreen({required this.bookingId,super.key});
  @override State<PaymentScreen> createState()=>_PaymentScreenState();
}
class _PaymentScreenState extends State<PaymentScreen>{
  bool loading=false;
  bool bookingLoading=false;
  String? error;
  Map<String,dynamic>? booking;

  @override void initState(){
    super.initState();
    loadBooking();
  }

  Future<void> loadBooking()async{
    if(bookingLoading||loading)return;
    setState((){bookingLoading=true;booking=null;error=null;});
    try{final value=await api.bookingDetail(widget.bookingId);if(mounted)setState((){booking=value;error=null;});}
    catch(e){if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));}
    finally{if(mounted)setState(()=>bookingLoading=false);}
  }

  Future<void> pay()async{
    if(loading||bookingLoading||!bookingCanPayOnline(booking))return;
    const publishableKey=String.fromEnvironment('STRIPE_PUBLISHABLE_KEY',defaultValue:'');
    if(publishableKey.isEmpty){
      setState(()=>error=t('Paiement en ligne non configuré sur cette version.'));
      return;
    }
    setState((){loading=true;error=null;});
    try{
      final idem='mobile-'+widget.bookingId+'-'+DateTime.now().microsecondsSinceEpoch.toString();
      final intent=await api.createPaymentIntent(widget.bookingId,idem);
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters:SetupPaymentSheetParameters(
          paymentIntentClientSecret:intent['clientSecret'] as String,
          merchantDisplayName:'Veyra',
          // DEC-04: with the customer and its ephemeral key, the sheet
          // lists the cards saved at previous bookings and saves the new
          // one (the backend sets setup_future_usage on the intent).
          customerId:intent['customerId'] as String?,
          customerEphemeralKeySecret:intent['ephemeralKey'] as String?,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      // The webhook is authoritative; the reservation displays its result.
      if(mounted){
        await showDialog<void>(
          context:context,
          barrierDismissible:false,
          builder:(dialogContext)=>AlertDialog(
            icon:const Icon(Icons.check_circle,color:Color(0xFF16A34A),size:48),
            title:Text(t('Paiement transmis')),
            content:Text(t('Consultez votre réservation pour suivre la confirmation du paiement.')),
            actions:[
              FilledButton(style:FilledButton.styleFrom(minimumSize:const Size(0,52)),onPressed:()=>Navigator.pop(dialogContext),child:Text(t('Continuer'))),
            ],
          ),
        );
        if(mounted)context.go('/booking/'+widget.bookingId);
      }
    }on DioException catch(e){
      final code=e.response?.data is Map?(e.response!.data as Map)['code']:null;
      if(code=='ALREADY_PAID'&&mounted){context.go('/booking/'+widget.bookingId);}
      else if(mounted){setState(()=>error=VeyraErrorMessages.forException(e));}
    }catch(_){
      if(mounted)setState(()=>error=t('Le paiement n’a pas été finalisé.'));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(title:Text(t('Paiement sécurisé')),actions:[IconButton(onPressed:loading||bookingLoading?null:loadBooking,icon:const Icon(Icons.refresh),tooltip:t('Actualiser'))]),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
        const Icon(Icons.lock_outline,size:56),
        const SizedBox(height:16),
        Text(t('Total à payer : ')+VeyraMoneyFormatter.fromMinor(booking?['customer_total_amount_minor']),style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold),textAlign:TextAlign.center),
        const SizedBox(height:12),
        const Text('Ce total inclut le prix proposé par le chauffeur et la commission Veyra.',textAlign:TextAlign.center),
        if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error),textAlign:TextAlign.center)),
        if(booking==null&&error!=null)TextButton(onPressed:loadBooking,child:Text(t('Réessayer'))),
        if(booking?['payment_status']=='CAPTURED')Text(t('Ce paiement est déjà réglé.'),textAlign:TextAlign.center),
        if(booking!=null&&booking?['payment_status']!='CAPTURED'&&!bookingCanPayOnline(booking))Text(t('Cette réservation ne nécessite pas de paiement en ligne à cette étape.'),textAlign:TextAlign.center),
        const SizedBox(height:20),
        FilledButton.icon(
          onPressed:loading||bookingLoading||!bookingCanPayOnline(booking)?null:pay,
          icon:const Icon(Icons.credit_card),
          label:loading?Text(t('Paiement…')):Text(t('Payer maintenant')),
        ),
      ])),
    );
  }
}


String paymentStatusLabel(String? status)=>switch(status){
  'CAPTURED'=>t('Payé'), 'PENDING'=>t('En cours de confirmation'),
  'FAILED'=>t('Échec — réessayez le paiement'), 'CANCELED'=>t('Annulé'),
  'REFUNDED'=>t('Remboursé'), _=>t('À payer'),
};

class BookingDetailScreen extends StatefulWidget{
  final String bookingId;
  const BookingDetailScreen({required this.bookingId,super.key});
  @override State<BookingDetailScreen> createState()=>_BookingDetailScreenState();
}
class _BookingDetailScreenState extends State<BookingDetailScreen>{
  late Future<Map<String,dynamic>> future;
  Timer? statusTimer;
  bool refreshing=false;
  String? pin;
  String? message;
  String? refreshError;
  int ratingScore=0;
  bool ratingSubmitting=false;
  bool cancelling=false;
  bool ratingSubmitted=false;
  bool favorite=false;
  bool favoriteBusy=false;

  @override void initState(){
    super.initState();
    future=api.bookingDetail(widget.bookingId).then((value){favorite=value['favorite_driver']==true;return value;});
    statusTimer=Timer.periodic(const Duration(seconds:8),(_)=>refreshStatus());
    RefreshBus.tick.addListener(refreshStatus);
  }

  Future<void> toggleFavorite(Map<String,dynamic> booking)async{
    if(favoriteBusy)return;setState(()=>favoriteBusy=true);
    try{if(favorite){await api.removeFavoriteDriver(booking['selected_driver_id'].toString());}else{await api.addFavoriteDriver(widget.bookingId);}if(mounted)setState(()=>favorite=!favorite);}
    catch(e){if(mounted)setState(()=>message=VeyraErrorMessages.forException(e));}
    finally{if(mounted)setState(()=>favoriteBusy=false);}
  }
  Future<void> refreshStatus()async{
    if(refreshing||cancelling||loadingPreview||favoriteBusy)return;
    refreshing=true;
    try{final value=await api.bookingDetail(widget.bookingId);if(mounted)setState((){future=Future.value(value);favorite=value['favorite_driver']==true;refreshError=null;});}
    catch(e){if(mounted)setState(()=>refreshError=t('Actualisation interrompue. Les données affichées peuvent être anciennes.'));}
    finally{refreshing=false;}
  }
  @override void dispose(){RefreshBus.tick.removeListener(refreshStatus);statusTimer?.cancel();super.dispose();}
  void reload()=>setState((){future=api.bookingDetail(widget.bookingId);});

  Future<void> loadPin()async{
    try{
      final value=await api.pin(widget.bookingId);
      if(mounted)setState(()=>pin=value);
    }on DioException catch(e){
      final code=e.response?.data is Map?(e.response?.data as Map)['code']?.toString():null;
      final text=code=='PIN_NOT_YET_AVAILABLE'
        ?t('Le PIN sera disponible à H-1.')
        :code=='PIN_NOT_CREATED'
          ?t('Le PIN sera créé dès qu’un chauffeur aura été confirmé.')
          :VeyraErrorMessages.forException(e);
      if(mounted)setState(()=>message=text);
    }catch(e){
      if(mounted)setState(()=>message=t('Impossible de récupérer le PIN pour le moment.'));
    }
  }

  Future<void> submitRating()async{
    if(ratingScore<1)return;
    setState(()=>ratingSubmitting=true);
    try{
      await api.rate(widget.bookingId,ratingScore);
      if(mounted)setState((){ratingSubmitted=true;ratingSubmitting=false;});
    }on DioException catch(e){
      final alreadyRated=(e.response?.data is Map)&&((e.response?.data as Map)['code']=='ALREADY_RATED');
      if(mounted)setState((){
        if(alreadyRated)ratingSubmitted=true;
        else message=t('Impossible d’envoyer la note pour le moment.');
        ratingSubmitting=false;
      });
    }
  }

  bool loadingPreview=false;

  Future<void> confirmAndCancel()async{
    if(cancelling||loadingPreview)return;
    setState(()=>loadingPreview=true);
    Map<String,dynamic>? preview;
    String? previewError;
    try{
      preview=await api.cancellationPreview(widget.bookingId);
    }catch(e){
      previewError=VeyraErrorMessages.forException(e);
    }finally{
      if(mounted)setState(()=>loadingPreview=false);
    }
    if(!mounted)return;

    // Real gap this closes: a confirmation dialog already existed, but
    // deliberately avoided showing an exact figure (see the git history
    // for why -- the admin-configurable policy endpoint was ADMIN-only,
    // not reachable from here). The new cancellation-preview endpoint
    // unblocks exactly that: the server's own calculated fee, shown
    // before the client commits to anything irreversible.
    final isFree=previewError==null&&preview?['free']==true;
    final feeMinor=preview?['cancellationFeeMinor'];
    final confirmed=await showDialog<bool>(
      context:context,
      builder:(dialogContext)=>AlertDialog(
        title:Text(t('Annuler cette réservation ?')),
        content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          if(previewError!=null)
            Text(t('Impossible de calculer les frais pour le moment. Vous pouvez réessayer.'),style:TextStyle(color:Theme.of(context).colorScheme.error))
          else if(isFree)...[
            Text(t('L’annulation est gratuite.')),
            const SizedBox(height:8),
            Text(t('Frais d’annulation')+' : '+VeyraMoneyFormatter.fromMinor(0),style:const TextStyle(fontWeight:FontWeight.bold)),
          ]else...[
            Text(t('Des frais d’annulation s’appliquent.')),
            const SizedBox(height:8),
            Text(t('Frais d’annulation'),style:const TextStyle(color:Colors.black54,fontSize:12)),
            Text(VeyraMoneyFormatter.fromMinor(feeMinor),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:20)),
          ],
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:Text(t('Garder la réservation'))),
          FilledButton(style:FilledButton.styleFrom(minimumSize:const Size(0,52)),onPressed:previewError!=null?null:()=>Navigator.pop(dialogContext,true),child:Text(t('Confirmer l’annulation'))),
        ],
      ),
    );
    if(confirmed!=true||!mounted)return;
    await cancel();
  }

  Future<void> cancel()async{
    if(cancelling)return;
    setState(()=>cancelling=true);
    try{
      final result=await api.cancel(widget.bookingId);
      RefreshBus.bump();
      if(!mounted)return;
      setState(()=>message=t('Réservation annulée. Frais éventuels : ')+VeyraMoneyFormatter.fromMinor(result['cancellationFeeMinor']));
      reload();
    }catch(e){
      if(mounted)setState(()=>message=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>cancelling=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Détail réservation')),actions:[IconButton(onPressed:refreshStatus,icon:const Icon(Icons.refresh),tooltip:t('Actualiser'))]),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
          ?VeyraOfflineBanner(onRetry:reload)
          :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:reload);
        final x=s.data??{};
        final status=(x['status']??'').toString();
        final driverName=((x['driver_first_name']??'') as Object).toString()+' '+((x['driver_last_name']??'') as Object).toString();
        final driverPhone=x['driver_phone']?.toString();
        return RefreshIndicator(onRefresh:refreshStatus,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(20),children:[
          Text((x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString(),style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          Text(VeyraDateFormatter.dateTime(x['scheduled_at'])),
          Text((x['category_name']??'').toString()+' • '+(x['passenger_count']??1).toString()+' passager(s) • '+(x['baggage_count']??0).toString()+' bagage(s)'),
          if((x['customer_notes']??'').toString().isNotEmpty)Text(t('Remarques')+' : '+x['customer_notes'].toString()),
          if({'OPEN_FOR_OFFERS','OFFERS_RECEIVED'}.contains(status))...[
            Text(t('Réception des offres jusqu’au')+' '+VeyraDateFormatter.dateTime(x['offer_window_ends_at'])),
            Text(x['offer_count']==1?t('1 offre reçue'):(x['offer_count']??0).toString()+' '+t('offres reçues')),
            FilledButton(onPressed:()=>context.push('/offers/'+widget.bookingId),child:Text(t('Voir les offres'))),
            TextButton(onPressed:cancelling?null:confirmAndCancel,child:Text(t('Annuler la réservation'))),
          ],
          if(status=='CONFIRMED')Text(t('Votre chauffeur est engagé. Vous serez informé de son départ et de son arrivée.')),
          if(x['selected_driver_id']!=null)Text([x['vehicle_brand'],x['vehicle_model'],x['vehicle_color'],x['plate_number']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' • ')),
          if(x['payment_method']=='ONLINE')Text(t('Paiement')+' : '+paymentStatusLabel(x['payment_status']?.toString())),
          const SizedBox(height:12),
          Card(child:Padding(padding:const EdgeInsets.all(16),child:SizedBox(width:double.infinity,child:Wrap(
            alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,
            spacing:8,runSpacing:8,children:[Text(t('Statut')),VeyraStatusBadge(status:status)],
          )))),
          Card(
            child:Padding(
              padding:const EdgeInsets.all(16),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(t('Étapes de votre réservation'),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
                const SizedBox(height:8),
                Text(
                  {'OPEN_FOR_OFFERS':t('Demande publiée • En attente des offres des chauffeurs'),
                   'OFFERS_RECEIVED':t('Offres reçues • Comparez et choisissez librement votre chauffeur'),
                   'PENDING_PAYMENT':t('Chauffeur choisi • Paiement à finaliser'),
                   'CONFIRMED':t('Trajet confirmé • Votre chauffeur se prépare'),
                   'DRIVER_EN_ROUTE':t('Chauffeur en route vers le lieu de prise en charge'),
                   'DRIVER_ARRIVED':t('Chauffeur arrivé • Vérifiez le véhicule et communiquez le PIN à bord'),
                   'IN_PROGRESS':t('Course en cours'),
                   'COMPLETED':t('Course terminée • Vous pouvez noter votre chauffeur'),
                   'CLOSED':t('Course terminée'),
                  }[status]??VeyraStatusLabels.bookingStatus(status),
                ),
              ]),
            ),
          ),
          if(!{'COMPLETED','CLOSED','CANCELLED','CANCELLED_BY_CLIENT','CANCELLED_BY_DRIVER','DRIVER_CANCELLED','CUSTOMER_NO_SHOW','EXPIRED','NO_OFFER','NO_DRIVER'}.contains(status))
            Card(
              child:Padding(
                padding:const EdgeInsets.all(16),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(t('Bon à savoir'),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
                  const SizedBox(height:8),
                  Text(t('Présentez-vous au point de prise en charge à l’heure prévue.')),
                  const SizedBox(height:6),
                  Text(t('Les éventuels frais d’annulation sont calculés selon les conditions de votre réservation. Leur montant exact est affiché avant confirmation de l’annulation.')),
                ]),
              ),
            ),
          if({'CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'}.contains(status))
            Card(
              child:Padding(
                padding:const EdgeInsets.all(16),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(t('Préparer votre trajet'),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
                  const SizedBox(height:8),
                  Text(t('Départ : ')+(x['pickup_address']??'').toString()),
                  const SizedBox(height:6),
                  Text(t('Destination : ')+(x['dropoff_address']??'').toString()),
                  const SizedBox(height:6),
                  Text(t('Prise en charge prévue : ')+VeyraDateFormatter.dateTime(x['scheduled_at'])),
                  if(x['selected_driver_id']!=null)...[
                    const SizedBox(height:8),
                    Text(t('Vérifiez le véhicule et son immatriculation avant de monter.')),
                  ],
                ]),
              ),
            ),
          if(x['selected_driver_id']!=null)Card(child:ListTile(
            leading:const CircleAvatar(child:Icon(Icons.person)),
            title:Text(driverName.trim().isEmpty?t('Chauffeur confirmé'):driverName.trim()),
            subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Note : '+(x['driver_rating']??'-').toString()),
              if(x['driver_verified']==true)Text(t('Chauffeur Veyra vérifié')),
            ]),
          )),
          if(x['customer_total_amount_minor']!=null)BookingFinancialSummary(booking:x,paymentLabel:paymentStatusLabel(x['payment_status']?.toString())),
          if(bookingCanPayOnline(x))
            FilledButton.icon(onPressed:()=>context.push('/payment/'+widget.bookingId),icon:const Icon(Icons.credit_card),label:Text(t('Payer en ligne'))),
          if({'CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'}.contains(status))...[
            OutlinedButton.icon(onPressed:()=>context.push('/chat/'+widget.bookingId),icon:const Icon(Icons.chat_bubble_outline),label:Text(t('Chat Veyra'))),
            OutlinedButton.icon(
              onPressed:driverPhone==null||driverPhone.isEmpty?null:()=>launchUrl(Uri(scheme:'tel',path:driverPhone)),
              icon:const Icon(Icons.phone_outlined),label:Text(t('Appeler le chauffeur'))),
          ],
          if({'DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'}.contains(status))
            FilledButton.icon(onPressed:()=>context.push('/live/'+widget.bookingId),icon:const Icon(Icons.map_outlined),label:Text(t('Suivre la course'))),
          if(status=='DRIVER_ARRIVED')
            Card(color:const Color(0xFF16A34A),child:Padding(padding:const EdgeInsets.all(16),child:Row(children:[
              const Icon(Icons.directions_car,color:Colors.white,size:28),
              const SizedBox(width:12),
              Expanded(child:Text(t('Votre chauffeur est arrivé'),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:16))),
            ]))),
          if(status=='CONFIRMED'||status=='DRIVER_EN_ROUTE'||status=='DRIVER_ARRIVED')...[
            if(pin==null)
              OutlinedButton(onPressed:loadPin,child:Text(t('Afficher le PIN')))
            else...[
              Text(t('Communiquez ce code au chauffeur uniquement lorsque vous êtes dans le véhicule.'),style:const TextStyle(fontSize:13,color:Colors.black54)),
              const SizedBox(height:8),
              VeyraPinDisplay(pin:pin!),
            ],
            TextButton(onPressed:(cancelling||loadingPreview)?null:confirmAndCancel,child:Text(cancelling?t('Annulation…'):loadingPreview?t('Calcul des frais…'):t('Annuler la réservation'))),
          ],
          if({'COMPLETED','CLOSED','CANCELLED','CANCELLED_BY_CLIENT','CANCELLED_BY_DRIVER','DRIVER_CANCELLED','CUSTOMER_NO_SHOW','EXPIRED','NO_OFFER','NO_DRIVER'}.contains(status))
            OutlinedButton.icon(onPressed:()=>context.push('/addresses',extra:x),icon:const Icon(Icons.replay),label:Text(t('Réserver à nouveau'))),
          if({'COMPLETED','CLOSED'}.contains(status))OutlinedButton.icon(onPressed:favoriteBusy?null:()=>toggleFavorite(x),icon:Icon(favorite?Icons.favorite:Icons.favorite_border),label:Text(favorite?t('Retirer des favoris'):t('Ajouter le chauffeur aux favoris'))),
          if({'COMPLETED','CLOSED'}.contains(status))
            Card(child:Padding(padding:const EdgeInsets.all(16),child:ratingSubmitted?Row(children:[Icon(Icons.check_circle,color:Colors.green),SizedBox(width:8),Text(t('Merci pour votre avis !'))]):Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(t('Noter le chauffeur'),style:const TextStyle(fontWeight:FontWeight.bold)),
              const SizedBox(height:8),
              Row(children:[for(int i=1;i<=5;i++)IconButton(
                icon:Icon(i<=ratingScore?Icons.star:Icons.star_border,color:Colors.amber),
                tooltip:AppLocale.code.value=='en'
                  ?(i==1?'1 star':'$i stars')
                  :(i==1?'1 étoile':'$i étoiles'),
                onPressed:ratingSubmitting?null:()=>setState(()=>ratingScore=i),
              )]),
              FilledButton(onPressed:ratingSubmitting||ratingScore<1?null:submitRating,child:Text(ratingSubmitting?t('Envoi…'):t('Envoyer la note'))),
            ]))),
          if(refreshError!=null)Text(refreshError!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
          if(message!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(message!)),
        ]));
      },
    ),
  );
}

class ChatScreen extends StatefulWidget{
  final String bookingId;
  const ChatScreen({required this.bookingId,super.key});
  @override State<ChatScreen> createState()=>_ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen>{
  final input=TextEditingController();
  final scrollController=ScrollController();
  final List<Map<String,dynamic>> messages=[];
  String? myUserId;
  Map<String,dynamic>? chatBooking;
  Future<void> loadChatBooking()async{try{final b=await api.bookingDetail(widget.bookingId);if(mounted)setState(()=>chatBooking=b);}catch(_){}}
  bool loading=true;
  bool loadError=false;
  bool sending=false;
  ChatSocket? socket;

  Timer? fallbackPoller;

  @override void initState(){
    super.initState();
    _load();
    loadChatBooking();
    fallbackPoller=Timer.periodic(const Duration(seconds:5),(_)=>_pollForNewMessages());
  }

  Future<void> _pollForNewMessages()async{
    if(!mounted)return;
    loadChatBooking();
    try{
      final history=await api.chatMessages(widget.bookingId);
      if(!mounted)return;
      final fresh=history.map((e)=>Map<String,dynamic>.from(e as Map))
        .where((m)=>!_isDuplicate(m['id'])).toList();
      if(fresh.isEmpty)return;
      setState(()=>messages.addAll(fresh));
      _scrollToBottom();
    }catch(_){}
  }

  Future<void> _load() async {
    setState((){loading=true;loadError=false;});
    try{
      final me=await api.me();
      final history=await api.chatMessages(widget.bookingId);
      if(!mounted)return;
      setState((){
        myUserId=(me['id']??'').toString();
        messages
          ..clear()
          ..addAll(history.map((e)=>Map<String,dynamic>.from(e as Map)));
        loading=false;
      });
      _scrollToBottom();
      socket?.dispose();
      socket=ChatSocket(api:api,bookingId:widget.bookingId,onMessage:_onIncoming)..connect();
    }catch(_){
      if(mounted)setState((){loading=false;loadError=true;});
    }
  }

  bool _isDuplicate(Object? id)=>id!=null&&messages.any((m)=>(m['id']?.toString())==id.toString());

  void _onIncoming(Map<String,dynamic> msg){
    if(!mounted)return;
    if(_isDuplicate(msg['id']))return;
    setState(()=>messages.add(msg));
    _scrollToBottom();
  }

  void _scrollToBottom(){
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(scrollController.hasClients){
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration:const Duration(milliseconds:250),
          curve:Curves.easeOut,
        );
      }
    });
  }

  Future<void> send() async {
    if(sending)return;
    final draft=input.text;
    final body=draft.trim();
    if(body.isEmpty)return;
    setState(()=>sending=true);
    try{
      final sent=await api.sendMessage(widget.bookingId,body);
      if(mounted&&input.text==draft)input.clear();
      if(mounted&&!_isDuplicate(sent['id'])){
        setState(()=>messages.add(sent));
        _scrollToBottom();
      }
    }catch(_){
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t("Message non envoyé, réessayez"))));
      }
    }finally{
      if(mounted)setState(()=>sending=false);
    }
  }

  @override void dispose(){
    fallbackPoller?.cancel();
    socket?.dispose();
    scrollController.dispose();
    input.dispose();
    super.dispose();
  }

  String? _timeLabel(Map<String,dynamic> m){
    final raw=m['sentAt']??m['sent_at'];
    if(raw==null)return null;
    try{
      final dt=DateTime.parse(raw.toString()).toLocal();
      return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    }catch(_){return null;}
  }

  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor:const Color(0xFFF2F6FB),
      appBar:AppBar(title:Text(t('Chat Veyra'))),
      body:Column(children:[
        if(chatBooking!=null)ListTile(
          title:Text((chatBooking?['driver_name']??t('Votre interlocuteur')).toString()),
          subtitle:Text((chatBooking?['pickup_address']??'').toString()+' → '+(chatBooking?['dropoff_address']??'').toString()),
          trailing:VeyraStatusBadge(status:chatBooking?['status']?.toString()??''),
        ),
        Expanded(child:
          loading?const Center(child:CircularProgressIndicator())
          :loadError?Center(child:FilledButton(onPressed:_load,child:Text(t('Réessayer'))))
          :messages.isEmpty?Center(child:Text(t('Aucun message pour le moment.')))
          :ListView.builder(
              controller:scrollController,
              padding:const EdgeInsets.symmetric(horizontal:12,vertical:16),
              itemCount:messages.length,
              itemBuilder:(context,i){
                final m=messages[i];
                final senderId=(m['senderUserId']??m['sender_user_id'])?.toString();
                final isMine=myUserId!=null&&senderId==myUserId;
                final time=_timeLabel(m);
                return Align(
                  alignment:isMine?Alignment.centerRight:Alignment.centerLeft,
                  child:Container(
                    margin:const EdgeInsets.symmetric(vertical:3),
                    padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
                    constraints:BoxConstraints(maxWidth:MediaQuery.of(context).size.width*0.75),
                    decoration:BoxDecoration(
                      color:isMine?scheme.primary:Colors.white,
                      borderRadius:BorderRadius.only(
                        topLeft:const Radius.circular(16),
                        topRight:const Radius.circular(16),
                        bottomLeft:Radius.circular(isMine?16:4),
                        bottomRight:Radius.circular(isMine?4:16),
                      ),
                      boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:0.06),blurRadius:4,offset:const Offset(0,2))],
                    ),
                    child:Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisSize:MainAxisSize.min,children:[
                      Text((m['body']??'').toString(),style:TextStyle(color:isMine?Colors.white:const Color(0xFF1F2937))),
                      if(time!=null)...[
                        const SizedBox(height:4),
                        Text(time,style:TextStyle(fontSize:11,color:isMine?Colors.white70:const Color(0xFF9CA3AF))),
                      ],
                    ]),
                  ),
                );
              },
            ),
        ),
        SafeArea(child:Padding(
          padding:const EdgeInsets.all(12),
          child:Row(children:[
            Expanded(child:TextField(
              controller:input,
              maxLength:2000,
              textCapitalization:TextCapitalization.sentences,
              decoration:InputDecoration(
                hintText:t('Votre message'),
                counterText:'',
                filled:true,
                fillColor:Colors.white,
                border:OutlineInputBorder(borderRadius:BorderRadius.circular(24),borderSide:BorderSide.none),
                contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:10),
              ),
              onSubmitted:(_)=>sending?null:send(),
            )),
            const SizedBox(width:8),
            CircleAvatar(radius:22,backgroundColor:scheme.primary,child:sending
              ?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
              :IconButton(onPressed:send,tooltip:t('Envoyer'),icon:const Icon(Icons.send,color:Colors.white,size:20)),
            ),
          ]),
        )),
      ]),
    );
  }
}

class LiveLocationScreen extends StatefulWidget{
  final String bookingId;
  const LiveLocationScreen({required this.bookingId,super.key});
  @override State<LiveLocationScreen> createState()=>_LiveLocationScreenState();
}
class _LiveLocationScreenState extends State<LiveLocationScreen>{
  Timer? timer;
  Timer? etaTimer;
  Map<String,dynamic>? location;
  Map<String,dynamic>? bookingMap;
  Map<String,dynamic>? etaInfo;
  int etaRevision=0;
  String? error;

  @override void initState(){
    super.initState();
    refresh();
    timer=Timer.periodic(const Duration(seconds:10),(_)=>refresh());
    etaTimer=Timer.periodic(const Duration(seconds:30),(_)=>refreshEta());
    RefreshBus.tick.addListener(refresh);
  }

  @override void dispose(){
    timer?.cancel();
    etaTimer?.cancel();
    RefreshBus.tick.removeListener(refresh);
    super.dispose();
  }

  Future<void> refresh()async{
    try{
      final latest=await api.bookingDetail(widget.bookingId);
      if(mounted)setState((){if(bookingMap?['status']!=latest['status']){etaRevision++;etaInfo=null;}bookingMap=latest;});
      final value=await api.currentLocation(widget.bookingId);
      if(mounted)setState((){location=value;error=null;});
      await refreshEta();
    }catch(_){
      if(mounted)setState((){etaRevision++;etaInfo=null;error=t('La position du chauffeur est momentanément indisponible. Le suivi reprendra automatiquement dès sa prochaine position GPS.');});
    }
  }

  // Fiche C09 : "Si GPS stale : afficher dernière mise à jour, ne pas
  // inventer l'ETA." Seuil de 2 minutes = plusieurs cycles du refresh
  // de 10s ci-dessus, largement au-delà d'une simple gigue réseau.
  static const _staleThreshold = Duration(minutes: 2);

  bool get _isStale {
    final raw = location?['recorded_at'];
    if (raw == null) return false;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return false;
    return DateTime.now().toUtc().difference(dt.toUtc()) > _staleThreshold;
  }

  Future<void> refreshEta()async{
    final revision=++etaRevision;
    final live=location;
    final booking=bookingMap;
    if(!canEstimateTrackingEta(booking,live,DateTime.now())){
      // Une position obsolète ne doit jamais servir de base à un ETA
      // recalculé -- on efface plutôt un ETA précédent qui deviendrait
      // trompeur.
      if(mounted&&etaInfo!=null)setState(()=>etaInfo=null);
      return;
    }
    final inProgress=booking!['status']=='IN_PROGRESS';
    final toLat=(booking[inProgress?'dropoff_lat':'pickup_lat'] as num?)?.toDouble();
    final toLng=(booking[inProgress?'dropoff_lng':'pickup_lng'] as num?)?.toDouble();
    if(toLat==null||toLng==null)return;
    try{
      final eta=await api.routeEstimate(
        fromLat:(live!['lat'] as num).toDouble(),
        fromLng:(live['lng'] as num).toDouble(),
        toLat:toLat,toLng:toLng,
      );
      if(mounted&&revision==etaRevision&&identical(live,location)&&identical(booking,bookingMap)&&canEstimateTrackingEta(booking,live,DateTime.now()))setState(()=>etaInfo=eta);
    }catch(_){if(mounted&&revision==etaRevision)setState(()=>etaInfo=null);}
  }

  @override Widget build(BuildContext context){
    final available=location?['available']==true;
    final pickupLat=(bookingMap?['pickup_lat'] as num?)?.toDouble();
    final pickupLng=(bookingMap?['pickup_lng'] as num?)?.toDouble();
    final dropoffLat=(bookingMap?['dropoff_lat'] as num?)?.toDouble();
    final dropoffLng=(bookingMap?['dropoff_lng'] as num?)?.toDouble();
    final lat=available?((location!['lat'] as num).toDouble()):(pickupLat??43.2965);
    final lng=available?((location!['lng'] as num).toDouble()):(pickupLng??5.3698);
    return Scaffold(
      appBar:AppBar(title:Text(t('Suivi en direct'))),
      body:Stack(children:[
        FlutterMap(
          options:MapOptions(initialCenter:LatLng(lat,lng),initialZoom:available?14:9),
          children:[
            TileLayer(
              urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName:'com.veyra.client',
            ),
            MarkerLayer(markers:[
              if(pickupLat!=null&&pickupLng!=null)Marker(
                point:LatLng(pickupLat,pickupLng),
                width:44,height:44,
                child:const Icon(Icons.trip_origin,size:34),
              ),
              if(dropoffLat!=null&&dropoffLng!=null)Marker(
                point:LatLng(dropoffLat,dropoffLng),
                width:44,height:44,
                child:const Icon(Icons.location_on,size:38),
              ),
              if(available)Marker(
                point:LatLng(lat,lng),
                width:56,height:56,
                child:const Icon(Icons.local_taxi,size:44),
              ),
            ]),
          ],
        ),
        Positioned(
          left:16,right:16,bottom:20,
          child:Card(child:Padding(
            padding:const EdgeInsets.all(16),
            child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
              VeyraStatusBadge(status:bookingMap?['status']?.toString()),
              Text(available?t('Position actuelle du chauffeur'):t('Position indisponible'),style:const TextStyle(fontWeight:FontWeight.bold)),
              Text(error??(available?t('Mise à jour automatique toutes les 10 secondes.'):t('En attente de la première position GPS.'))),
              if(etaInfo!=null&&canEstimateTrackingEta(bookingMap,location,DateTime.now()))Text(
                (bookingMap?['status']=='IN_PROGRESS'?t('ETA destination : '):t('Arrivée du chauffeur : '))+VeyraMoneyFormatter.duration(etaInfo!['durationSeconds'])+
                ' • '+VeyraMoneyFormatter.distance(etaInfo!['distanceMeters']),
                style:const TextStyle(fontWeight:FontWeight.w600),
              ),
              if(available&&location!['recorded_at']!=null)Text(
                t('Dernière position : ')+VeyraDateFormatter.dateTime(location!['recorded_at']),
                style:TextStyle(color:_isStale?const Color(0xFFDC2626):null),
              ),
              if(available&&_isStale)Padding(
                padding:const EdgeInsets.only(top:4),
                child:Text(
                  t('Position possiblement obsolète — le chauffeur n’a pas transmis de nouvelle position récemment.'),
                  style:const TextStyle(color:Color(0xFFDC2626),fontSize:12),
                ),
              ),
            ]),
          )),
        ),
      ]),
    );
  }
}


class RegisterScreen extends StatefulWidget{
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState()=>_RegisterScreenState();
}
class _RegisterScreenState extends State<RegisterScreen>{
  final firstName=TextEditingController();
  final lastName=TextEditingController();
  final phone=TextEditingController();
  final email=TextEditingController();
  final password=TextEditingController();
  final formKey=GlobalKey<FormState>();
  bool loading=false;
  String? error;
  bool offline=false;
  bool acceptTerms=false;
  bool acceptPrivacy=false;
  bool marketingOptIn=false;
  bool consentErrors=false;

  @override void dispose(){firstName.dispose();lastName.dispose();phone.dispose();email.dispose();password.dispose();super.dispose();}

  Future<void> submit()async{
    if(loading||!formKey.currentState!.validate())return;
    if(firstName.text.trim().isEmpty||phone.text.trim().length<6||email.text.trim().isEmpty||password.text.length<10){
      setState((){error=t('Prénom, téléphone, e-mail et mot de passe de 10 caractères minimum requis.');offline=false;});
      return;
    }
    if(!SignupConsents.mandatoryAccepted(acceptTerms,acceptPrivacy)){
      setState((){consentErrors=true;error=t('Acceptez les CGU et la politique de confidentialité pour continuer.');offline=false;});
      return;
    }
    setState((){loading=true;error=null;offline=false;});
    try{
      await api.register(
        email:email.text,
        password:password.text,
        firstName:firstName.text,
        lastName:lastName.text,
        phone:phone.text,
        acceptTerms:acceptTerms,
        acceptPrivacy:acceptPrivacy,
        marketingOptIn:marketingOptIn,
      );
      if(!mounted)return;
      // CL-AUTH-05: confirm the phone number by SMS before entering the app.
      context.go('/verify-phone',extra:phone.text);
      await configurePush();
    }catch(e){
      if(!mounted)return;
      final isOffline=e is DioException&&(
        e.type==DioExceptionType.connectionError||
        e.type==DioExceptionType.connectionTimeout||
        e.type==DioExceptionType.receiveTimeout||
        e.type==DioExceptionType.sendTimeout);
      setState((){
        offline=isOffline;
        error=isOffline?null:VeyraErrorMessages.forException(e);
      });
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(title:Text(t('Créer un compte')),backgroundColor:const Color(0xFFF2F6FB),elevation:0),
    body:SafeArea(child:Form(key:formKey,autovalidateMode:AutovalidateMode.onUserInteraction,child:ListView(padding:const EdgeInsets.all(24),children:[
      TextFormField(controller:firstName,validator:(v)=>(v??'').trim().isEmpty?t('Prénom requis'):null,decoration:appFieldDecoration(t('Prénom'),icon:Icons.person_outline)),
      const SizedBox(height:12),
      TextFormField(controller:lastName,decoration:appFieldDecoration(t('Nom'),icon:Icons.person_outline)),
      const SizedBox(height:12),
      TextFormField(controller:phone,validator:(v)=>(v??'').trim().length<6?t('Téléphone incomplet'):null,keyboardType:TextInputType.phone,decoration:appFieldDecoration(t('Téléphone'),icon:Icons.phone_outlined)),
      const SizedBox(height:12),
      TextFormField(controller:email,validator:(v)=>RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v??'').trim())?null:t('E-mail invalide'),keyboardType:TextInputType.emailAddress,decoration:appFieldDecoration(t('Email'),icon:Icons.mail_outline)),
      const SizedBox(height:12),
      TextFormField(controller:password,validator:(v)=>(v??'').length<10?t('10 caractères minimum'):null,obscureText:true,decoration:appFieldDecoration(t('Mot de passe'),icon:Icons.lock_outline,helperText:t('10 caractères minimum'))),
      const SizedBox(height:12),
      SignupConsents(
        acceptTerms:acceptTerms,
        acceptPrivacy:acceptPrivacy,
        marketingOptIn:marketingOptIn,
        showErrors:consentErrors,
        onTerms:(v)=>setState(()=>acceptTerms=v),
        onPrivacy:(v)=>setState(()=>acceptPrivacy=v),
        onMarketing:(v)=>setState(()=>marketingOptIn=v),
      ),
      if(offline)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:VeyraOfflineBanner(onRetry:submit)),
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:16),
      VeyraPrimaryButton(label:t('Créer mon compte'),loading:loading,onPressed:submit),
    ]))),
  );
}

class ForgotPasswordScreen extends StatefulWidget{
  const ForgotPasswordScreen({super.key});
  @override State<ForgotPasswordScreen> createState()=>_ForgotPasswordScreenState();
}
class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>{
  final email=TextEditingController();
  bool loading=false;
  String? message;

  Future<void> submit()async{
    setState((){loading=true;message=null;});
    try{
      await api.forgotPassword(email.text);
      if(mounted)setState(()=>message=t('Si cet e-mail existe, les instructions de réinitialisation ont été envoyées.'));
    }catch(_){
      if(mounted)setState(()=>message=t('Impossible d’envoyer la demande pour le moment.'));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(title:Text(t('Mot de passe oublié')),backgroundColor:const Color(0xFFF2F6FB),elevation:0),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
      Text(t('Saisissez votre e-mail. Le message ne révèle pas si un compte existe.')),
      const SizedBox(height:16),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:appFieldDecoration(t('Email'),icon:Icons.mail_outline)),
      const SizedBox(height:16),
      FilledButton(
        style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:16),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
        onPressed:loading?null:submit,
        child:Text(t('Envoyer les instructions')),
      ),
      if(message!=null)Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Text(message!)),
      const SizedBox(height:8),
      TextButton(
        onPressed:()=>context.push('/reset-password'),
        child:Text(t('J’ai déjà un code de réinitialisation')),
      ),
    ])),
  );
}

/// Complète le flow "mot de passe oublié" -- le backend
/// (PasswordController.reset) attend {token,newPassword} en clair, le
/// jeton étant envoyé par email sous forme de texte brut à recopier
/// (pas de deep-link). Gap réel trouvé : /api/v1/auth/reset-password
/// existait et était fonctionnel côté backend, mais rien ne le
/// consommait -- un utilisateur pouvait demander une réinitialisation
/// mais jamais la terminer depuis l'app.
class ResetPasswordScreen extends StatefulWidget{
  const ResetPasswordScreen({super.key});
  @override State<ResetPasswordScreen> createState()=>_ResetPasswordScreenState();
}
class _ResetPasswordScreenState extends State<ResetPasswordScreen>{
  final token=TextEditingController();
  final newPassword=TextEditingController();
  bool loading=false;
  bool success=false;
  String? error;

  Future<void> submit()async{
    if(token.text.trim().isEmpty){
      setState(()=>error=t('Saisissez le code reçu par e-mail.'));
      return;
    }
    if(newPassword.text.length<10){
      setState(()=>error=t('Le nouveau mot de passe doit contenir au moins 10 caractères.'));
      return;
    }
    setState((){loading=true;error=null;});
    try{
      await api.resetPassword(token.text,newPassword.text);
      if(mounted)setState(()=>success=true);
    }on DioException catch(e){
      // Le backend ne renvoie aucun corps JSON sur ces deux statuts
      // (juste badRequest()/unprocessableEntity().build()) -- pas de
      // "code" à extraire, le statut HTTP est la seule information
      // disponible pour distinguer les deux causes.
      final status=e.response?.statusCode;
      if(mounted)setState(()=>error=status==422
        ?t('Mot de passe trop faible (10 caractères minimum).')
        :status==400
          ?t('Code invalide ou expiré. Demandez un nouveau code.')
          :VeyraErrorMessages.forException(e));
    }catch(_){
      if(mounted)setState(()=>error=t('Une erreur est survenue. Veuillez réessayer.'));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(title:Text(t('Réinitialiser le mot de passe')),backgroundColor:const Color(0xFFF2F6FB),elevation:0),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
      if(success)...[
        const Icon(Icons.check_circle,color:Color(0xFF16A34A),size:48),
        const SizedBox(height:16),
        Text(t('Mot de passe mis à jour. Vous pouvez vous reconnecter.')),
        const SizedBox(height:16),
        FilledButton(onPressed:()=>context.go('/login'),child:Text(t('Retour à la connexion'))),
      ]else...[
        Text(t('Collez le code reçu par e-mail et choisissez un nouveau mot de passe.')),
        const SizedBox(height:16),
        TextField(controller:token,decoration:appFieldDecoration(t('Code reçu par e-mail'),icon:Icons.vpn_key_outlined)),
        const SizedBox(height:16),
        TextField(controller:newPassword,obscureText:true,decoration:appFieldDecoration(t('Nouveau mot de passe'),icon:Icons.lock_outline,helperText:t('10 caractères minimum'))),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
        const SizedBox(height:16),
        VeyraPrimaryButton(label:t('Réinitialiser'),loading:loading,onPressed:submit),
      ],
    ])),
  );
}


class NotificationsScreen extends StatefulWidget{
  const NotificationsScreen({super.key});
  @override State<NotificationsScreen> createState()=>_NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>{
  late Future<List<dynamic>> future;
  @override void initState(){super.initState();future=api.notifications();}
  void reload()=>setState((){future=api.notifications();});

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Notifications'))),
    body:RefreshIndicator(
      onRefresh:()async{reload();try{await future;}catch(_){/* FutureBuilder displays the load error. */}},
      child:FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done){
            return ListView(physics:const AlwaysScrollableScrollPhysics(),children:const [SizedBox(height:220),Center(child:CircularProgressIndicator())]);
          }
          if(s.hasError){
            final offline=VeyraErrorMessages.isOffline(s.error!);
            return ListView(physics:const AlwaysScrollableScrollPhysics(),children:[
              const SizedBox(height:160),
              if(offline) VeyraOfflineBanner(onRetry:reload)
              else VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:reload),
            ]);
          }
          final items=s.data??[];
          if(items.isEmpty){
            return ListView(physics:const AlwaysScrollableScrollPhysics(),children:[
              SizedBox(height:160),
              Icon(Icons.notifications_none,size:56),
              Center(child:Text(t('Aucune notification pour le moment.'))),
            ]);
          }
          return ListView.separated(physics:const AlwaysScrollableScrollPhysics(),
            padding:const EdgeInsets.all(16),
            itemCount:items.length,
            separatorBuilder:(_,__)=>const SizedBox(height:8),
            itemBuilder:(context,index){
              final x=Map<String,dynamic>.from(items[index] as Map);
              final rawData=x['data'];
              final data=rawData is Map
                ?Map<String,dynamic>.from(rawData)
                :rawData is String&&rawData.isNotEmpty
                  ?((){try{return Map<String,dynamic>.from(jsonDecode(rawData) as Map);}catch(_){return <String,dynamic>{};}})()
                  :<String,dynamic>{};
              final bookingId=data['bookingId']?.toString();
              final template=(x['template_code']??'').toString();
              final pickup=(x['pickup_address']??'').toString(),dropoff=(x['dropoff_address']??'').toString(),scheduled=x['scheduled_at'];
              return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.notifications_active_outlined)),title:Text(VeyraStatusLabels.notificationTemplate(template),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[if(pickup.isNotEmpty&&dropoff.isNotEmpty)Text(pickup+' → '+dropoff,style:const TextStyle(fontWeight:FontWeight.w600)),if(scheduled!=null)Text(VeyraDateFormatter.dateTime(scheduled),style:const TextStyle(color:VeyraColors.primaryDark)),Text(t('Reçue le')+' '+VeyraDateFormatter.dateTime(x['created_at']))]),isThreeLine:true,trailing:bookingId==null?null:const Icon(Icons.chevron_right),onTap:bookingId==null?null:()=>router.go(clientNotificationRoute(bookingId,template,data))));
            },
          );
        },
      ),
    ),
  );
}
