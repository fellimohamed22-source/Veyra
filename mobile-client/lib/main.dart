import 'dart:math' as math;
import 'core/widgets/chat_view.dart';
import 'core/maps/veyra_map_marks.dart';
import 'core/widgets/profile_dialog.dart';
import 'dart:async';
import 'core/active_booking.dart';
import 'core/maps/tracking_eta.dart';
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
import 'package:latlong2/latlong.dart';
import 'api.dart';
import 'app_locale.dart';
import 'app/theme.dart';
import 'core/formatters/error_messages.dart';
import 'core/formatters/date_formatter.dart';
import 'core/formatters/money_formatter.dart';
import 'core/formatters/status_labels.dart';
import 'core/widgets/veyra_button.dart';
import 'core/widgets/signup_consents.dart';
import 'core/widgets/auth_ui.dart';
import 'core/widgets/welcome_hero.dart';
import 'core/widgets/notifications_view.dart';
import 'core/widgets/saved_cards_screen.dart';
import 'core/widgets/phone_verification_screen.dart';
import 'core/widgets/veyra_ui.dart';
import 'core/widgets/state_views.dart';
import 'core/widgets/password_dialog.dart';
import 'core/widgets/pin_display.dart';
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
    onDone:()=>c.go('/account-created'),
    onLater:()=>c.go('/account-created'),
  )),
  // Board 08 A6.
  GoRoute(path:'/account-created',builder:(c,s)=>Scaffold(body:VeyraSuccessView(
    title:t('Bienvenue sur VEYRA !'),
    text:t('Votre compte client a été créé avec succès.'),
    actionLabel:t('Commencer'),
    onAction:()=>c.go('/home'),
  ))),
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
      StatefulShellBranch(routes:[GoRoute(path:'/reservations',builder:(c,s)=>const ReservationsScreen())]),
      StatefulShellBranch(routes:[GoRoute(path:'/account',builder:(c,s)=>const AccountScreen())]),
    ],
  ),
  // Notifications open from the home bell (boards 05, 15), above the shell.
  // Board 16: grouped list with read state (CL-18).
  GoRoute(path:'/notifications',builder:(c,s)=>VeyraNotificationsScreen(
    load:()=>api.notifications(),
    markRead:api.markNotificationRead,
    markAllRead:api.markAllNotificationsRead,
    open:(n){if(n.bookingId!=null)c.push(clientNotificationRoute(n.bookingId!,n.template,n.data));},
  )),
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

  /// Owner decision 20/10/2026: « Continuer avec Apple » (board 08 A1),
  /// through Firebase's Apple provider and the same /auth/firebase endpoint.
  Future<void> _appleLogin() async {
    setState((){loading=true;error=null;offline=false;});
    try{
      if(Firebase.apps.isEmpty)await Firebase.initializeApp();
      final provider=AppleAuthProvider()..addScope('email')..addScope('name');
      final userCredential=await FirebaseAuth.instance.signInWithProvider(provider);
      final token=await userCredential.user?.getIdToken();
      if(token==null||token.isEmpty)throw StateError('FIREBASE_ID_TOKEN_MISSING');
      await api.loginWithFirebase(token);
      if(!mounted)return;
      context.go('/home');
      await configurePush();
    }on FirebaseAuthException catch(e){
      if(e.code=='canceled'||e.code=='web-context-canceled')return;
      debugPrint('APPLE_LOGIN_FAILED: ${e.code}');
      if(mounted)setState(()=>error=t('Connexion Apple impossible. Vérifiez la configuration Firebase et réessayez.'));
    }catch(e){
      debugPrint('APPLE_LOGIN_FAILED: $e');
      if(mounted)setState(()=>error=e is DioException?VeyraErrorMessages.forException(e):t('Connexion Apple impossible. Vérifiez la configuration Firebase et réessayez.'));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  /// Board 08 A1 shows the welcome actions; « Se connecter » opens the
  /// e-mail form on the same screen.
  bool showForm=false;

  Widget languagePill(String code,String flag,String label)=>ValueListenableBuilder<String>(
    valueListenable:AppLocale.code,
    builder:(context,current,_){
      final on=current==code;
      return Material(
        color:on?Colors.white:Colors.white.withValues(alpha:.14),
        borderRadius:BorderRadius.circular(VeyraRadius.pill),
        child:InkWell(
          borderRadius:BorderRadius.circular(VeyraRadius.pill),
          onTap:()=>AppLocale.set(code),
          child:Padding(
            padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              Text(flag,style:const TextStyle(fontSize:16)),
              const SizedBox(width:6),
              Text(label,style:TextStyle(fontWeight:FontWeight.w700,color:on?VeyraColors.primary:Colors.white)),
            ]),
          ),
        ),
      );
    },
  );

  Widget socialButton(String label,Widget icon,VoidCallback? onPressed,{Key? key})=>OutlinedButton(
    key:key,
    onPressed:onPressed,
    style:OutlinedButton.styleFrom(foregroundColor:VeyraColors.textPrimary,minimumSize:const Size.fromHeight(52)),
    child:Row(children:[icon,const SizedBox(width:12),Expanded(child:Text(label,textAlign:TextAlign.center)),const SizedBox(width:28)]),
  );

  List<Widget> welcomeActions()=>[
    FilledButton(onPressed:loading?null:()=>context.push('/register'),child:Text(t('Créer un compte'))),
    const SizedBox(height:12),
    FilledButton(
      style:FilledButton.styleFrom(backgroundColor:VeyraColors.infoBackground,foregroundColor:VeyraColors.primary),
      onPressed:loading?null:()=>setState(()=>showForm=true),
      child:Text(t('Se connecter')),
    ),
    const SizedBox(height:16),
    Row(children:[
      const Expanded(child:Divider()),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Text(t('OU'),style:const TextStyle(color:VeyraColors.textSecondary,fontWeight:FontWeight.w600))),
      const Expanded(child:Divider()),
    ]),
    const SizedBox(height:16),
    socialButton(t('Continuer avec Google'),const Text('G',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800,color:Color(0xFF4285F4))),loading?null:_googleLogin),
    const SizedBox(height:10),
    socialButton(t('Continuer avec Apple'),const Icon(Icons.apple,size:26,color:Colors.black),loading?null:_appleLogin,key:const ValueKey('apple-login')),
  ];

  List<Widget> loginForm()=>[
    Row(children:[
      IconButton(tooltip:t('Retour'),onPressed:()=>setState((){showForm=false;error=null;offline=false;}),icon:const Icon(Icons.chevron_left,size:30)),
      Text(t('Se connecter'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800)),
    ]),
    const SizedBox(height:8),
    VeyraFieldLabel(t('E-mail')),
    TextField(controller:email,keyboardType:TextInputType.emailAddress,autofillHints:const [AutofillHints.email],decoration:const InputDecoration(hintText:'nom@exemple.fr')),
    const SizedBox(height:14),
    VeyraFieldLabel(t('Mot de passe')),
    TextField(controller:password,obscureText:true,autofillHints:const [AutofillHints.password]),
    Align(alignment:Alignment.centerRight,child:TextButton(onPressed:()=>context.push('/forgot'),child:Text(t('Mot de passe oublié ?')))),
    if(offline)Padding(padding:const EdgeInsets.only(bottom:12),child:VeyraOfflineBanner(onRetry:submit)),
    if(error!=null)Padding(padding:const EdgeInsets.only(bottom:12),child:VeyraBanner(tone:VeyraTone.danger,text:error!)),
    VeyraPrimaryButton(label:t('Se connecter'),loading:loading,onPressed:submit),
  ];

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:VeyraColors.primary,
    body:Column(children:[
      // Photo hero (board 08 A1): wordmark, tagline, language choice. It
      // runs 28 px under the sheet so the rounded corners sit on the photo.
      Expanded(child:Stack(clipBehavior:Clip.none,children:[
        Positioned(left:0,right:0,top:0,bottom:-28,child:VeyraWelcomeHero(
          asset:VeyraAssets.welcomeClient,
          title:t('Voyagez en toute confiance'),
          focal:Alignment.centerRight,
          languages:(_)=>Wrap(spacing:10,runSpacing:10,alignment:WrapAlignment.center,children:[
            languagePill('fr','🇫🇷','Français'),
            languagePill('en','🇬🇧','English'),
          ]),
        )),
      ])),
      Container(
        width:double.infinity,
        decoration:const BoxDecoration(color:Colors.white,borderRadius:BorderRadius.vertical(top:Radius.circular(28))),
        // The sheet never takes the whole screen; its content scrolls.
        constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(context).height*.72),
        child:SafeArea(top:false,child:SingleChildScrollView(
          padding:const EdgeInsets.fromLTRB(24,24,24,16),
          child:AutofillGroup(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:showForm?loginForm():welcomeActions())),
        )),
      ),
    ]),
  );
}

// ---------------------------------------------------------------------
// Écrans principaux client (planches 05, 15, 03, 04) : Accueil, Mes
// demandes, Mes réservations, Profil. Les onglets de la barre suivent les
// planches 05/09/11/17 (Accueil, Mes demandes, Mes réservations, Profil).
// ---------------------------------------------------------------------

const _offerPhaseStates={'OPEN_FOR_OFFERS','OFFERS_RECEIVED'};
const _activeRideStates={'CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'};
const _pastStates={'COMPLETED','CLOSED'};
const _cancelledStates={'CANCELLED','CANCELLED_BY_CLIENT','CANCELLED_BY_DRIVER','DRIVER_CANCELLED','CUSTOMER_NO_SHOW','EXPIRED','NO_OFFER','NO_DRIVER'};

/// "18 oct. 2025 · 08:30" (local time), as on boards 05 and 15.
String veyraBookingWhen(dynamic raw){
  final at=DateTime.tryParse(raw?.toString()??'')?.toLocal();
  if(at==null)return '';
  final en=AppLocale.code.value=='en';
  final months=en?['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']:['janv.','févr.','mars','avr.','mai','juin','juil.','août','sept.','oct.','nov.','déc.'];
  return '${at.day} ${months[at.month-1]} ${at.year} · ${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}';
}

/// First segment of an address ("Paris" from "Paris, France").
String veyraPlaceTitle(dynamic label){
  final s=(label??'').toString();
  final i=s.indexOf(',');
  return i<0?s:s.substring(0,i).trim();
}

String _initials(String name){
  final parts=name.trim().split(RegExp(r'\s+')).where((p)=>p.isNotEmpty).toList();
  if(parts.isEmpty)return '?';
  return parts.take(2).map((p)=>p[0].toUpperCase()).join();
}

/// Pastille d'état des cartes de demande (planche 05).
class _StatePill extends StatelessWidget{
  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;
  const _StatePill(this.text,{required this.fg,required this.bg,this.icon});
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
    decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(VeyraRadius.pill)),
    child:Row(mainAxisSize:MainAxisSize.min,children:[
      if(icon!=null)...[Icon(icon,size:14,color:fg),const SizedBox(width:4)],
      // Flexible: wraps instead of overflowing with enlarged text.
      Flexible(child:Text(text,style:TextStyle(color:fg,fontSize:12,fontWeight:FontWeight.w700))),
    ]),
  );
}

Widget _pillFor(Map<String,dynamic> x){
  final status=(x['status']??'').toString();
  final offers=(x['offer_count'] as num?)?.toInt()??0;
  if(_offerPhaseStates.contains(status)&&offers>0)return _StatePill('$offers '+(offers>1?t('offres reçues'):t('offre reçue')),fg:VeyraColors.accent,bg:VeyraColors.infoBackground);
  if(_offerPhaseStates.contains(status))return _StatePill(t('En attente d’offres'),fg:VeyraColors.warning,bg:VeyraColors.warningBackground);
  // Short labels as on the boards (« Confirmée », « Annulée »).
  const short={'CONFIRMED':'Confirmée','DRIVER_EN_ROUTE':'Chauffeur en route','DRIVER_ARRIVED':'Chauffeur arrivé','IN_PROGRESS':'En cours','COMPLETED':'Terminée','CLOSED':'Terminée'};
  if(_activeRideStates.contains(status))return _StatePill(t(short[status]!),fg:VeyraColors.success,bg:VeyraColors.successBackground,icon:Icons.verified_outlined);
  if(_pastStates.contains(status))return _StatePill(t(short[status]!),fg:VeyraColors.neutral,bg:VeyraColors.neutralBackground);
  return _StatePill(status=='EXPIRED'||status=='NO_OFFER'?t('Expirée'):t('Annulée'),fg:VeyraColors.danger,bg:VeyraColors.dangerBackground);
}

/// Carte blanche à ombre douce des listes (planches 05, 15).
class _ShadowCard extends StatelessWidget{
  final Widget child;
  final VoidCallback? onTap;
  const _ShadowCard({required this.child,this.onTap});
  @override Widget build(BuildContext context)=>Container(
    margin:const EdgeInsets.only(bottom:14),
    decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(VeyraRadius.card),boxShadow:VeyraShadows.card,border:Border.all(color:VeyraColors.border.withValues(alpha:.6))),
    child:Material(color:Colors.transparent,child:InkWell(borderRadius:BorderRadius.circular(VeyraRadius.card),onTap:onTap,child:Padding(padding:const EdgeInsets.all(16),child:child))),
  );
}

class _MiniRoute extends StatelessWidget{
  final Map<String,dynamic> x;
  const _MiniRoute(this.x);
  @override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[const Icon(Icons.circle,size:10,color:VeyraColors.accent),const SizedBox(width:10),Expanded(child:Text(veyraPlaceTitle(x['pickup_address']),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w600)))]),
    const SizedBox(height:6),
    Row(children:[const Icon(Icons.location_on,size:14,color:VeyraColors.pinRed),const SizedBox(width:8),Expanded(child:Text(veyraPlaceTitle(x['dropoff_address']),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w600)))]),
  ]);
}

class _PaxBags extends StatelessWidget{
  final Map<String,dynamic> x;
  const _PaxBags(this.x);
  @override Widget build(BuildContext context){
    final p=(x['passenger_count'] as num?)?.toInt()??1;
    final b=(x['baggage_count'] as num?)?.toInt()??0;
    // Wrap, not Row: stays on two lines with enlarged text.
    return Wrap(spacing:18,runSpacing:4,children:[
      Row(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.person_outline,size:18,color:VeyraColors.textSecondary),const SizedBox(width:4),Flexible(child:Text('$p '+(p>1?t('passagers'):t('passager')),style:const TextStyle(color:VeyraColors.textSecondary)))]),
      Row(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.luggage_outlined,size:18,color:VeyraColors.textSecondary),const SizedBox(width:4),Flexible(child:Text('$b '+(b>1?t('bagages'):t('bagage')),style:const TextStyle(color:VeyraColors.textSecondary)))]),
    ]);
  }
}

/// Bandeau « Meilleur prix disponible » (planche 05) : prix final client,
/// commission comprise, figé sur l'offre.
class _BestPriceBanner extends StatelessWidget{
  final dynamic totalMinor;
  const _BestPriceBanner(this.totalMinor);
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.all(14),
    decoration:BoxDecoration(color:VeyraColors.warningBackground,borderRadius:BorderRadius.circular(VeyraRadius.md)),
    child:Row(children:[
      const Icon(Icons.emoji_events_outlined,color:VeyraColors.goldEnd,size:30),
      const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(t('Meilleur prix disponible'),style:const TextStyle(color:VeyraColors.textSecondary,fontWeight:FontWeight.w600)),
        Text(VeyraMoneyFormatter.fromMinor(totalMinor),style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800,color:VeyraColors.textPrimary)),
        Text(t('(commission VEYRA incluse)'),style:const TextStyle(fontSize:12,color:VeyraColors.textSecondary)),
      ])),
    ]),
  );
}

class _DriverLine extends StatelessWidget{
  final Map<String,dynamic> x;
  const _DriverLine(this.x);
  @override Widget build(BuildContext context){
    final name=(x['driver_name']??'').toString().trim();
    return Row(children:[
      CircleAvatar(radius:20,backgroundColor:VeyraColors.surfaceMuted,child:Text(_initials(name),style:const TextStyle(color:VeyraColors.primary,fontWeight:FontWeight.w700))),
      const SizedBox(width:10),
      Expanded(child:Text(name.isEmpty?t('Chauffeur confirmé'):name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w700))),
    ]);
  }
}

/// Carte d'une demande ou réservation (planche 05 P1, planche 04 P5).
class _RequestCard extends StatelessWidget{
  final Map<String,dynamic> x;
  const _RequestCard(this.x);
  @override Widget build(BuildContext context){
    final id=x['id']?.toString();
    final status=(x['status']??'').toString();
    final offerPhase=_offerPhaseStates.contains(status);
    final offers=(x['offer_count'] as num?)?.toInt()??0;
    void open(){if(id!=null)context.push(offerPhase?'/offers/$id':'/booking/$id');}
    return _ShadowCard(onTap:open,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        const Icon(Icons.calendar_today_outlined,size:18,color:VeyraColors.accent),
        const SizedBox(width:8),
        Expanded(child:Text(veyraBookingWhen(x['scheduled_at']),style:const TextStyle(fontWeight:FontWeight.w600))),
        const SizedBox(width:8),
        Flexible(child:_pillFor(x)),
      ]),
      const SizedBox(height:12),
      Row(children:[Expanded(child:_MiniRoute(x)),const SizedBox(width:10),VeyraVehicleThumb(width:72,category:x['category_name']?.toString())]),
      const SizedBox(height:10),
      _PaxBags(x),
      if(offerPhase&&offers>0&&x['best_offer_total_minor']!=null)...[const SizedBox(height:12),_BestPriceBanner(x['best_offer_total_minor'])],
      const SizedBox(height:12),
      if(x['selected_driver_id']!=null&&!offerPhase)Row(children:[
        Expanded(child:_DriverLine(x)),
        const SizedBox(width:8),
        Flexible(child:FilledButton(
          style:FilledButton.styleFrom(minimumSize:const Size(0,40),backgroundColor:VeyraColors.surfaceMuted,foregroundColor:VeyraColors.textPrimary,padding:const EdgeInsets.symmetric(horizontal:12),textStyle:const TextStyle(fontFamily:veyraFontFamily,fontSize:13,fontWeight:FontWeight.w700)),
          onPressed:open,child:Text(t('Voir ma réservation'),textAlign:TextAlign.center),
        )),
      ])
      else if(offerPhase&&offers>0)FilledButton(onPressed:open,child:Row(mainAxisSize:MainAxisSize.min,children:[Flexible(child:Text(t('Voir les offres'),textAlign:TextAlign.center)),const SizedBox(width:6),const Icon(Icons.chevron_right)]))
      else FilledButton(
        style:FilledButton.styleFrom(backgroundColor:VeyraColors.surfaceMuted,foregroundColor:VeyraColors.textPrimary),
        onPressed:open,child:Row(mainAxisSize:MainAxisSize.min,children:[Flexible(child:Text(t('Voir les détails'),textAlign:TextAlign.center)),const SizedBox(width:6),const Icon(Icons.chevron_right)]),
      ),
    ]));
  }
}

/// Onglets en pilule avec compteurs (« En attente (2) », planche 05).
class _PillTabs extends StatelessWidget{
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const _PillTabs({required this.labels,required this.selected,required this.onSelect});
  @override Widget build(BuildContext context)=>SingleChildScrollView(
    scrollDirection:Axis.horizontal,
    child:Row(children:[
      for(var i=0;i<labels.length;i++)Padding(
        padding:const EdgeInsets.only(right:8),
        child:Semantics(selected:i==selected,button:true,child:Material(
          color:i==selected?VeyraColors.primary:VeyraColors.surfaceMuted,
          borderRadius:BorderRadius.circular(VeyraRadius.pill),
          child:InkWell(
            borderRadius:BorderRadius.circular(VeyraRadius.pill),
            onTap:()=>onSelect(i),
            child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:9),child:Text(labels[i],style:TextStyle(color:i==selected?Colors.white:VeyraColors.textPrimary,fontWeight:FontWeight.w600,fontSize:12))),
          ),
        )),
      ),
    ]),
  );
}

/// Liste filtrée par onglet, rafraîchissable, avec états chargement,
/// hors ligne, erreur et vide.
class _TabbedBookings extends StatefulWidget{
  final String title;
  final String? subtitle;
  final List<String> tabNames;
  final List<bool Function(Map<String,dynamic>)> filters;
  final String emptyMessage;
  const _TabbedBookings({required this.title,this.subtitle,required this.tabNames,required this.filters,required this.emptyMessage});
  @override State<_TabbedBookings> createState()=>_TabbedBookingsState();
}
class _TabbedBookingsState extends State<_TabbedBookings>{
  late Future<List<dynamic>> future;
  int tab=0;
  @override void initState(){super.initState();future=api.bookings(sort:'asc');RefreshBus.tick.addListener(retry);}
  @override void dispose(){RefreshBus.tick.removeListener(retry);super.dispose();}
  void retry()=>setState((){future=api.bookings(sort:'asc');});
  @override Widget build(BuildContext context)=>Scaffold(
    body:SafeArea(child:RefreshIndicator(
      onRefresh:()async{retry();try{await future;}catch(_){/* FutureBuilder shows the error. */}},
      child:FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          final all=(s.data??[]).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).toList();
          final counts=[for(final f in widget.filters)all.where(f).length];
          final visible=all.where(widget.filters[tab]).toList();
          return ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(20,16,20,20),children:[
            Text(widget.title,style:const TextStyle(fontSize:26,fontWeight:FontWeight.w800)),
            if(widget.subtitle!=null)...[const SizedBox(height:4),Text(widget.subtitle!,style:const TextStyle(color:VeyraColors.textSecondary))],
            const SizedBox(height:16),
            _PillTabs(labels:[for(var i=0;i<widget.tabNames.length;i++)s.hasData?'${widget.tabNames[i]} (${counts[i]})':widget.tabNames[i]],selected:tab,onSelect:(i)=>setState(()=>tab=i)),
            const SizedBox(height:16),
            if(s.connectionState!=ConnectionState.done)const Padding(padding:EdgeInsets.symmetric(vertical:48),child:VeyraLoadingView())
            else if(s.hasError)(VeyraErrorMessages.isOffline(s.error!)?VeyraOfflineBanner(onRetry:retry):VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:retry))
            else if(visible.isEmpty)Padding(padding:const EdgeInsets.only(top:24),child:VeyraEmptyView(icon:Icons.event_available,message:widget.emptyMessage))
            else ...visible.map((x)=>_RequestCard(x)),
          ]);
        },
      ),
    )),
  );
}

/// Onglet « Mes demandes » (planche 05 P1).
class HomeScreen extends StatelessWidget{
  const HomeScreen({super.key});
  @override Widget build(BuildContext context)=>_TabbedBookings(
    title:t('Mes demandes'),
    subtitle:t('Retrouvez et suivez vos prochains trajets.'),
    tabNames:[t('En attente'),t('Offres reçues'),t('Confirmées')],
    filters:[
      (x)=>x['status']=='OPEN_FOR_OFFERS'||(x['status']=='OFFERS_RECEIVED'&&((x['offer_count'] as num?)??0)==0),
      (x)=>x['status']=='OFFERS_RECEIVED'&&((x['offer_count'] as num?)??0)>0,
      (x)=>_activeRideStates.contains(x['status']),
    ],
    emptyMessage:t('Aucune demande dans cette catégorie.'),
  );
}

/// Onglet « Mes réservations » (planches 03 P5, 04 P5).
class ReservationsScreen extends StatelessWidget{
  const ReservationsScreen({super.key});
  @override Widget build(BuildContext context)=>_TabbedBookings(
    title:t('Mes réservations'),
    tabNames:[t('À venir'),t('Passées'),t('Annulées')],
    filters:[
      (x)=>_activeRideStates.contains(x['status']),
      (x)=>_pastStates.contains(x['status']),
      (x)=>_cancelledStates.contains(x['status']),
    ],
    emptyMessage:t('Aucune réservation dans cette catégorie.'),
  );
}

/// Accueil (planche 15 P1/P2, planche 03 P1).
class AccueilScreen extends StatefulWidget{
  const AccueilScreen({super.key});
  @override State<AccueilScreen> createState()=>_AccueilScreenState();
}
class _AccueilScreenState extends State<AccueilScreen>{
  late Future<Map<String,dynamic>> me;
  late Future<List<dynamic>> bookings;
  Uint8List? avatar;

  @override void initState(){
    super.initState();
    _load();
    RefreshBus.tick.addListener(_refresh);
    api.avatarBytes().then((v){if(mounted&&v!=null&&v.isNotEmpty)setState(()=>avatar=v);}).catchError((_){});
  }
  void _refresh()=>setState(_load);
  void _load(){me=api.me();bookings=api.bookings();unawaited(refreshUnreadNotifications());}
  // Lives inside the shell's nested navigator: refreshed through
  // RefreshBus, never through the root RouteObserver (see git history).
  @override void dispose(){RefreshBus.tick.removeListener(_refresh);super.dispose();}

  Widget hero(String firstName)=>Container(
    padding:EdgeInsets.fromLTRB(20,MediaQuery.paddingOf(context).top+12,20,64),
    decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xFF021C38),Color(0xFF0B3A6B)])),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        const VeyraWordmark(color:Colors.white,size:24),
        const Spacer(),
        IconButton(tooltip:t('Notifications'),onPressed:()=>context.push('/notifications'),icon:ValueListenableBuilder<int>(
          valueListenable:veyraUnreadNotifications,
          builder:(context,n,_)=>Badge(isLabelVisible:n>0,label:Text(n>9?'9+':'$n'),child:const Icon(Icons.notifications_none,color:Colors.white,size:28)),
        )),
        const SizedBox(width:4),
        GestureDetector(onTap:()=>context.go('/account'),child:CircleAvatar(radius:20,backgroundColor:Colors.white24,backgroundImage:avatar==null?null:MemoryImage(avatar!),child:avatar==null?const Icon(Icons.person,color:Colors.white):null)),
      ]),
      const SizedBox(height:24),
      Text(firstName.isEmpty?t('Bonjour !'):t('Bonjour')+' '+firstName,style:const TextStyle(color:Colors.white,fontSize:26,fontWeight:FontWeight.w800)),
      const SizedBox(height:4),
      Text(t('Planifiez votre prochain trajet'),style:const TextStyle(color:Colors.white70,fontSize:15)),
    ]),
  );

  Widget fakeField(IconData icon,Color color,String label,String hint)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
    decoration:BoxDecoration(borderRadius:BorderRadius.circular(VeyraRadius.md),border:Border.all(color:VeyraColors.border)),
    child:Row(children:[
      Icon(icon,color:color),
      const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:const TextStyle(fontSize:12,color:VeyraColors.textSecondary)),
        Text(hint,style:const TextStyle(fontSize:15,color:VeyraColors.textTertiary)),
      ])),
    ]),
  );

  Widget searchCard()=>Container(
    padding:const EdgeInsets.all(18),
    decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),boxShadow:VeyraShadows.card),
    child:Material(color:Colors.transparent,child:InkWell(
      borderRadius:BorderRadius.circular(20),
      onTap:()=>context.push('/addresses'),
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          const Icon(Icons.event_note_outlined,color:VeyraColors.primary,size:28),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(t('Où souhaitez-vous aller ?'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
            Text(t('Réservez un trajet en quelques étapes'),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
          ])),
        ]),
        const SizedBox(height:14),
        fakeField(Icons.circle,VeyraColors.accent,t('Adresse de départ'),t('Ex : 12 rue de Rivoli, Paris')),
        const SizedBox(height:10),
        fakeField(Icons.location_on,VeyraColors.pinRed,t('Destination'),t('Ex : Aéroport Charles-de-Gaulle')),
        const SizedBox(height:14),
        FilledButton(onPressed:()=>context.push('/addresses'),child:Row(mainAxisSize:MainAxisSize.min,children:[Flexible(child:Text(t('Rechercher mon trajet'),textAlign:TextAlign.center)),const SizedBox(width:6),const Icon(Icons.chevron_right)])),
      ]),
    )),
  );

  Widget quick(IconData icon,String label,VoidCallback onTap,{int badge=0})=>Expanded(child:Padding(
    padding:const EdgeInsets.symmetric(horizontal:4),
    child:Material(
      color:Colors.white,
      borderRadius:BorderRadius.circular(VeyraRadius.lg),
      child:InkWell(
        borderRadius:BorderRadius.circular(VeyraRadius.lg),
        onTap:onTap,
        child:Container(
          height:92,
          decoration:BoxDecoration(borderRadius:BorderRadius.circular(VeyraRadius.lg),border:Border.all(color:VeyraColors.border)),
          child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            Badge(isLabelVisible:badge>0,label:Text('$badge'),backgroundColor:VeyraColors.danger,child:Icon(icon,color:VeyraColors.primary,size:28)),
            const SizedBox(height:8),
            // Two-word labels break between words as on board 15 (« Mes / réservations »).
            Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:FittedBox(fit:BoxFit.scaleDown,child:Text(label.replaceFirst(' ','\n'),textAlign:TextAlign.center,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600,height:1.2)))),
          ]),
        ),
      ),
    ),
  ));

  Widget sectionHeader(String title,String action,VoidCallback onTap)=>Row(children:[
    Expanded(child:Text(title,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800))),
    TextButton(onPressed:onTap,child:Text(action)),
  ]);

  @override Widget build(BuildContext context)=>Scaffold(
    body:RefreshIndicator(
      onRefresh:()async{setState(_load);try{await Future.wait([me,bookings]);}catch(_){/* FutureBuilders show the error. */}},
      child:FutureBuilder<List<dynamic>>(
        future:bookings,
        builder:(context,s){
          final all=(s.data??[]).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).toList();
          // Nearest active booking, whatever order the server returns.
          Map<String,dynamic>? next;DateTime? nextAt;
          for(final x in all){
            if(!_activeRideStates.contains(x['status'])&&!_offerPhaseStates.contains(x['status']))continue;
            if(_offerPhaseStates.contains(x['status']))continue;
            final at=DateTime.tryParse(x['scheduled_at']?.toString()??'');
            if(at!=null&&(nextAt==null||at.isBefore(nextAt))){next=x;nextAt=at;}
          }
          final pending=all.where((x)=>_offerPhaseStates.contains(x['status'])).toList();
          final offersReceived=pending.where((x)=>((x['offer_count'] as num?)??0)>0).length;
          return ListView(physics:const AlwaysScrollableScrollPhysics(),padding:EdgeInsets.zero,children:[
            FutureBuilder<Map<String,dynamic>>(future:me,builder:(context,m)=>hero((m.data?['first_name']??'').toString())),
            Transform.translate(offset:const Offset(0,-44),child:Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:searchCard())),
            Padding(padding:const EdgeInsets.fromLTRB(20,0,20,24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Transform.translate(offset:const Offset(0,-28),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                Text(t('Actions rapides'),style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800)),
                const SizedBox(height:12),
                Row(children:[
                  quick(Icons.event_available_outlined,t('Mes réservations'),()=>context.go('/reservations')),
                  quick(Icons.description_outlined,t('Mes demandes'),()=>context.go('/bookings'),badge:offersReceived),
                  quick(Icons.notifications_none,t('Notifications'),()=>context.push('/notifications')),
                  quick(Icons.person_outline,t('Profil'),()=>context.go('/account')),
                ]),
              ])),
              if(s.connectionState!=ConnectionState.done)const VeyraLoadingView()
              else if(s.hasError)(VeyraErrorMessages.isOffline(s.error!)?VeyraOfflineBanner(onRetry:()=>setState(_load)):VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState(_load)))
              else ...[
                sectionHeader(t('Mon prochain trajet'),t('Voir tous'),()=>context.go('/reservations')),
                const SizedBox(height:6),
                if(next==null)VeyraEmptyView(icon:Icons.event_available,message:t('Aucune réservation à venir. Votre prochain trajet apparaîtra ici.'))
                else _RequestCard(next),
                if(pending.isNotEmpty)...[
                  const SizedBox(height:10),
                  sectionHeader(t('Mes demandes en attente'),t('Voir toutes'),()=>context.go('/bookings')),
                  const SizedBox(height:6),
                  ...pending.take(2).map((x)=>_RequestCard(x)),
                ],
              ],
            ])),
          ]);
        },
      ),
    ),
  );
}

/// Profil (planche 15 P3, planche 03 P8) : seules les entrées dont la
/// fonction existe sont affichées (aucun bouton inerte).
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

  Widget item(IconData icon,String label,VoidCallback onTap,{Color color=VeyraColors.textPrimary,bool chevron=true})=>ListTile(
    contentPadding:const EdgeInsets.symmetric(horizontal:4),
    leading:Icon(icon,color:color),
    title:Text(label,style:TextStyle(fontWeight:FontWeight.w600,color:color)),
    trailing:chevron?const Icon(Icons.chevron_right,color:VeyraColors.textSecondary):null,
    onTap:onTap,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          return ListView(padding:EdgeInsets.zero,children:[
            Container(
              color:VeyraColors.primary,
              padding:EdgeInsets.fromLTRB(20,MediaQuery.paddingOf(context).top+16,20,40),
              child:Text(t('Mon profil'),style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800)),
            ),
            Transform.translate(offset:const Offset(0,-24),child:Container(
              margin:const EdgeInsets.symmetric(horizontal:16),
              padding:const EdgeInsets.fromLTRB(16,18,16,8),
              decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),boxShadow:VeyraShadows.card),
              child:Column(children:[
                Row(children:[
                  Stack(children:[
                    CircleAvatar(radius:36,backgroundColor:VeyraColors.surfaceMuted,backgroundImage:avatar==null?null:MemoryImage(avatar!),child:avatar==null?const Icon(Icons.person,size:36,color:VeyraColors.primary):null),
                    Positioned(right:-6,bottom:-6,child:IconButton(tooltip:t('Changer la photo'),onPressed:busy?null:photo,icon:const CircleAvatar(radius:14,backgroundColor:VeyraColors.accent,child:Icon(Icons.camera_alt_outlined,size:15,color:Colors.white)))),
                  ]),
                  const SizedBox(width:14),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(name.isEmpty?t('Client Veyra'):name,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
                    if((profile['phone']??'').toString().isNotEmpty)Text(profile['phone'].toString(),style:const TextStyle(color:VeyraColors.textSecondary)),
                    Text((profile['email']??'').toString(),style:const TextStyle(color:VeyraColors.textSecondary)),
                  ])),
                ]),
                const SizedBox(height:12),
                FilledButton(
                  style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(44),backgroundColor:const Color(0xFFF3EBDD),foregroundColor:VeyraColors.textPrimary),
                  onPressed:()=>edit(profile),child:Text(t('Modifier mon profil')),
                ),
                const SizedBox(height:8),
              ]),
            )),
            Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Column(children:[
              item(Icons.event_available_outlined,t('Mes réservations'),()=>context.go('/reservations')),
              item(Icons.description_outlined,t('Mes demandes d’offres'),()=>context.go('/bookings')),
              item(Icons.credit_card,t('Mes moyens de paiement'),()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SavedCardsScreen(load:api.savedCards,remove:api.removeSavedCard)))),
              item(Icons.notifications_none,t('Notifications'),()=>context.push('/notifications')),
              const Divider(),
              item(Icons.favorite_border,t('Favoris'),()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const FavoriteDriversScreen()))),
              item(Icons.place_outlined,t('Adresses enregistrées'),()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const SavedAddressesScreen()))),
              const Divider(),
              item(Icons.lock_outline,t('Modifier mon mot de passe'),password),
              const Padding(padding:EdgeInsets.symmetric(vertical:4),child:LanguageSwitch()),
              const Divider(),
              item(Icons.logout,t('Déconnexion'),logout,color:VeyraColors.danger,chevron:false),
              const SizedBox(height:16),
            ])),
          ]);
        },
      ),
    );
  }
}

/// Barre de navigation (planches 05, 09, 11, 17).
class AppShell extends StatelessWidget{
  final StatefulNavigationShell navigationShell;
  const AppShell({required this.navigationShell,super.key});

  @override Widget build(BuildContext context)=>Scaffold(
    body:navigationShell,
    bottomNavigationBar:DecoratedBox(
      decoration:const BoxDecoration(border:Border(top:BorderSide(color:VeyraColors.border))),
      child:NavigationBar(
        selectedIndex:navigationShell.currentIndex,
        onDestinationSelected:(i)=>navigationShell.goBranch(i,initialLocation:i==navigationShell.currentIndex),
        destinations:[
          NavigationDestination(icon:const Icon(Icons.home_outlined),selectedIcon:const Icon(Icons.home),label:t('Accueil')),
          NavigationDestination(icon:const Icon(Icons.description_outlined),selectedIcon:const Icon(Icons.description),label:t('Mes demandes')),
          NavigationDestination(icon:const Icon(Icons.calendar_month_outlined),selectedIcon:const Icon(Icons.calendar_month),label:t('Mes réservations')),
          NavigationDestination(icon:const Icon(Icons.person_outline),selectedIcon:const Icon(Icons.person),label:t('Profil')),
        ],
      ),
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
    // While typing, results sit right under the actions so the keyboard
    // never hides them; the map comes back once a place is chosen.
    if(pickupResults.isNotEmpty)...[const SizedBox(height:14),...suggestions(true)]
    else...[
      const SizedBox(height:14),
      VeyraRouteMap(pickup:point(pickupPlace),height:190),
      const SizedBox(height:18),
      ...suggestions(true),
    ],
  ]);

  Widget stepDropoff()=>ListView(padding:const EdgeInsets.fromLTRB(20,8,20,20),children:[
    VeyraStepTitle(t('Où allez-vous ?')),
    const SizedBox(height:16),
    searchField(false),
    const SizedBox(height:10),
    VeyraTapRow(icon:Icons.map_outlined,label:pickOnMap?t('Touchez la carte pour placer la destination'):t('Choisir sur la carte'),muted:true,onTap:()=>setState(()=>pickOnMap=!pickOnMap)),
    if(dropoffResults.isNotEmpty&&!pickOnMap)...[const SizedBox(height:14),...suggestions(false)]
    else...[
    const SizedBox(height:14),
    // Board 09 step 2 shows the destination pin only.
    VeyraRouteMap(
      dropoff:point(dropoffPlace),
      dropoffLabel:dropoffPlace==null?null:splitLabel(dropoffPlace!['label']?.toString()??'').$1,
      height:pickOnMap?320:190,
      interactive:pickOnMap,
      onTap:pickOnMap?pickDestinationOnMap:null,
    ),
    const SizedBox(height:18),
    ...suggestions(false),
    ],
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
              VeyraVehicleThumb(van:(x['capacity'] as num)>4,category:(x['display_name']??x['code'])?.toString()),
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

  /// Short name written on the map (« Paris », « CDG »): airport code when
  /// present, otherwise the first part of the place title.
  static String shortPlace(String title){
    final code=RegExp(r'\(([A-Z]{3})\)').firstMatch(title);
    if(code!=null)return code.group(1)!;
    final first=title.split(',').first.trim();
    final city=RegExp(r'^(Paris|Marseille|Lyon|Nice|Cannes|Monaco|Menton|Antibes)\b').firstMatch(first);
    return city?.group(1)??first;
  }

  /// Initial compass bearing (degrees) from a to b, for the car mark.
  static double bearing(LatLng a,LatLng b){
    final p1=a.latitude*math.pi/180,p2=b.latitude*math.pi/180,dl=(b.longitude-a.longitude)*math.pi/180;
    final y=math.sin(dl)*math.cos(p2),x=math.cos(p1)*math.sin(p2)-math.sin(p1)*math.cos(p2)*math.cos(dl);
    return (math.atan2(y,x)*180/math.pi+360)%360;
  }

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
          VeyraVehicleThumb(width:84,van:categoryCapacity>4,category:categoryName),
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
      // Board 01 P5: estimate, then the map with both place names and the car at the start.
      if(km!=null&&min!=null)...[
        Row(children:[
          const Icon(Icons.directions_car_outlined,color:VeyraColors.textPrimary),
          const SizedBox(width:10),
          Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(t('Estimation du trajet'),style:const TextStyle(fontWeight:FontWeight.w700)),
            Text('$km km · $min min',style:const TextStyle(color:VeyraColors.textSecondary)),
          ]),
        ]),
        const SizedBox(height:10),
      ],
      VeyraRouteMap(pickup:point(pickupPlace),dropoff:point(dropoffPlace),route:points,height:170,
        pickupLabel:shortPlace(pTitle),dropoffLabel:shortPlace(dTitle),car:point(pickupPlace),
        carHeading:points.length>=2?bearing(points.first,points[1]):45),
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

/// Offres des chauffeurs (planche 05 P2, planches 03 P2 et 04 P3) : aucun
/// classement contraignant, prix final client commission comprise, tri et
/// filtre « Mes préférés » à la main du client. Touche une carte : détail
/// (P3), puis confirmation (P4).
class OffersScreen extends StatefulWidget{
  final String bookingId;
  const OffersScreen({required this.bookingId,super.key});
  @override State<OffersScreen> createState()=>_OffersScreenState();
}
class _OffersScreenState extends State<OffersScreen>{
  late Future<List<dynamic>> future;
  late Future<Map<String,dynamic>> bookingFuture;
  Set<String> favorites={};
  String? error;
  String? acceptingOfferId;
  Timer? refreshTimer;
  bool refreshing=false;
  bool byRating=false;
  bool favoritesOnly=false;

  @override void initState(){
    super.initState();
    refreshTimer=Timer.periodic(const Duration(seconds:10),(_)=>refreshOffers());
    RefreshBus.tick.addListener(refreshOffers);
    future=api.offers(widget.bookingId);
    // The booking itself is shown too: right after publishing there is
    // no offer yet, and this is the only screen such a booking opens.
    bookingFuture=api.bookingDetail(widget.bookingId);
    api.favoriteDrivers().then((rows){
      if(mounted)setState(()=>favorites=rows.whereType<Map>().map((r)=>r['driver_id'].toString()).toSet());
    }).catchError((_){});
  }

  Future<void> refreshOffers()async{
    if(refreshing||acceptingOfferId!=null)return;refreshing=true;
    try{final b=await api.bookingDetail(widget.bookingId);final values=await api.offers(widget.bookingId);if(mounted)setState((){future=Future.value(values);bookingFuture=Future.value(b);error=null;});}
    catch(e){if(mounted)setState(()=>error=t('Actualisation interrompue. Vérifiez votre connexion.'));}
    finally{refreshing=false;}
  }
  @override void dispose(){RefreshBus.tick.removeListener(refreshOffers);refreshTimer?.cancel();super.dispose();}

  Future<void> chooseOffer(String offerId)async{
    if(acceptingOfferId!=null)return;
    setState((){acceptingOfferId=offerId;error=null;});
    try{
      await api.accept(widget.bookingId,offerId);
      final booking=await api.bookingDetail(widget.bookingId);
      if(!mounted)return;
      RefreshBus.bump();
      // Leave the offer screens behind: the booking now lives in the
      // requests tab, with payment first when the client pays online.
      context.go('/bookings');
      context.push(booking['payment_method']=='ONLINE'?'/payment/${widget.bookingId}':'/booking/${widget.bookingId}');
    }on DioException catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
      rethrow;
    }finally{
      if(mounted)setState(()=>acceptingOfferId=null);
    }
  }

  void openOffer(Map<String,dynamic> booking,Map<String,dynamic> offer,bool best){
    Navigator.push(context,MaterialPageRoute(builder:(_)=>OfferDetailScreen(
      booking:booking,offer:offer,favorite:favorites.contains(offer['driverId']?.toString()),best:best,
      onChoose:()=>chooseOffer(offer['offerId'].toString()),
    )));
  }

  Widget summary(Map<String,dynamic> b)=>Container(
    padding:const EdgeInsets.all(14),
    decoration:BoxDecoration(borderRadius:BorderRadius.circular(VeyraRadius.lg),border:Border.all(color:VeyraColors.border)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        const Icon(Icons.location_on_outlined,size:20),
        const SizedBox(width:8),
        Expanded(child:Text('${veyraPlaceTitle(b['pickup_address'])}  →  ${veyraPlaceTitle(b['dropoff_address'])}',style:const TextStyle(fontWeight:FontWeight.w700))),
      ]),
      const SizedBox(height:6),
      Text(veyraBookingWhen(b['scheduled_at']),style:const TextStyle(color:VeyraColors.textSecondary)),
      const SizedBox(height:6),
      _PaxBags(b),
    ]),
  );

  Widget chip(String label,IconData icon,bool on,VoidCallback onTap)=>Material(
    color:on?VeyraColors.infoBackground:Colors.white,
    borderRadius:BorderRadius.circular(VeyraRadius.md),
    child:InkWell(
      borderRadius:BorderRadius.circular(VeyraRadius.md),
      onTap:onTap,
      child:Container(
        padding:const EdgeInsets.symmetric(horizontal:12,vertical:9),
        decoration:BoxDecoration(borderRadius:BorderRadius.circular(VeyraRadius.md),border:Border.all(color:on?VeyraColors.accent:VeyraColors.border)),
        child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:18,color:on?VeyraColors.accent:VeyraColors.textPrimary),const SizedBox(width:6),Flexible(child:Text(label,style:const TextStyle(fontWeight:FontWeight.w600,fontSize:13)))]),
      ),
    ),
  );

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Offres des chauffeurs')),actions:[IconButton(onPressed:refreshOffers,icon:const Icon(Icons.refresh),tooltip:t('Actualiser'))]),
    body:RefreshIndicator(onRefresh:refreshOffers,child:FutureBuilder<Map<String,dynamic>>(
      future:bookingFuture,
      builder:(context,bs){
        final b=bs.data??{};
        return ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
          if(bs.hasData)summary(b),
          const SizedBox(height:14),
          if(error!=null)Padding(padding:const EdgeInsets.only(bottom:12),child:VeyraBanner(tone:VeyraTone.danger,text:error!)),
          FutureBuilder<List<dynamic>>(
            future:future,
            builder:(context,s){
              if(s.connectionState!=ConnectionState.done)return const Padding(padding:EdgeInsets.all(32),child:Center(child:CircularProgressIndicator()));
              if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
                ?VeyraOfflineBanner(onRetry:()=>setState((){future=api.offers(widget.bookingId);}))
                :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState((){future=api.offers(widget.bookingId);}));
              var items=(s.data??[]).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).toList();
              if(items.isEmpty)return Padding(padding:const EdgeInsets.symmetric(vertical:24),child:VeyraEmptyView(icon:Icons.hourglass_empty,message:t('Aucune offre pour le moment. Vous serez notifié dès qu’un chauffeur propose un prix.')));
              final bestTotal=items.map((o)=>(o['totalMinor'] as num).toInt()).reduce((a,c)=>a<c?a:c);
              if(favoritesOnly)items=items.where((o)=>favorites.contains(o['driverId']?.toString())).toList();
              items.sort((a,c)=>byRating
                ?((c['rating'] as num?)??0).compareTo((a['rating'] as num?)??0)
                :(a['totalMinor'] as num).compareTo(c['totalMinor'] as num));
              return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                _BestPriceBanner(bestTotal),
                const SizedBox(height:12),
                Wrap(spacing:8,runSpacing:8,children:[
                  chip(byRating?t('Trier par Note'):t('Trier par Prix'),Icons.swap_vert,false,()=>setState(()=>byRating=!byRating)),
                  chip(t('Mes préférés'),favoritesOnly?Icons.favorite:Icons.favorite_border,favoritesOnly,()=>setState(()=>favoritesOnly=!favoritesOnly)),
                ]),
                const SizedBox(height:12),
                if(items.isEmpty)VeyraEmptyView(icon:Icons.favorite_border,message:t('Aucun de vos chauffeurs préférés n’a encore fait d’offre.')),
                for(final o in items)_OfferCard(
                  offer:o,
                  best:(o['totalMinor'] as num).toInt()==bestTotal,
                  favorite:favorites.contains(o['driverId']?.toString()),
                  busy:acceptingOfferId==o['offerId'].toString(),
                  onTap:acceptingOfferId!=null?null:()=>openOffer(b,o,(o['totalMinor'] as num).toInt()==bestTotal),
                ),
              ]);
            },
          ),
        ]);
      },
    )),
    // Board 01 P6: « Annuler la demande » while it waits for offers.
    bottomNavigationBar:FutureBuilder<Map<String,dynamic>>(
      future:bookingFuture,
      builder:(context,bs){
        final status=(bs.data?['status']??'').toString();
        if(!_offerPhaseStates.contains(status))return const SizedBox.shrink();
        return SafeArea(child:Padding(
          padding:const EdgeInsets.fromLTRB(16,8,16,12),
          child:OutlinedButton.icon(
            key:const ValueKey('cancel-request'),
            style:OutlinedButton.styleFrom(foregroundColor:VeyraColors.danger,side:const BorderSide(color:VeyraColors.danger),minimumSize:const Size.fromHeight(50)),
            onPressed:cancelling?null:cancelRequest,
            icon:const Icon(Icons.delete_outline),
            label:Text(cancelling?t('Annulation…'):t('Annuler la demande')),
          ),
        ));
      },
    ),
  );

  bool cancelling=false;

  Future<void> cancelRequest()async{
    final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(
      title:Text(t('Annuler la demande ?')),
      content:Text(t('Les chauffeurs ne pourront plus vous faire d’offre. Aucun frais : aucun chauffeur n’a encore été choisi.')),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(d,false),child:Text(t('Garder ma demande'))),
        FilledButton(style:FilledButton.styleFrom(backgroundColor:VeyraColors.danger,minimumSize:const Size(0,48)),onPressed:()=>Navigator.pop(d,true),child:Text(t('Annuler la demande'))),
      ],
    ));
    if(ok!=true||!mounted)return;
    setState((){cancelling=true;error=null;});
    try{
      await api.cancel(widget.bookingId);
      RefreshBus.bump();
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Demande annulée.'))));
      context.go('/home');
    }catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>cancelling=false);
    }
  }
}

class _FavoritePill extends StatelessWidget{
  const _FavoritePill();
  @override Widget build(BuildContext context)=>_StatePill(t('Mon chauffeur préféré'),fg:const Color(0xFFC0262D),bg:const Color(0xFFFDECEE),icon:Icons.favorite);
}

class _DriverAvatar extends StatelessWidget{
  final String name;
  final double radius;
  const _DriverAvatar(this.name,{this.radius=24});
  @override Widget build(BuildContext context)=>CircleAvatar(radius:radius,backgroundColor:VeyraColors.surfaceMuted,child:Text(_initials(name),style:TextStyle(color:VeyraColors.primary,fontWeight:FontWeight.w800,fontSize:radius*0.6)));
}

class _Rating extends StatelessWidget{
  final dynamic rating;
  const _Rating(this.rating);
  @override Widget build(BuildContext context){
    final r=(rating as num?)?.toDouble()??0;
    return Row(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.star_rounded,size:18,color:Color(0xFFF5A623)),
      const SizedBox(width:2),
      Text(r==0?t('Nouveau'):r.toStringAsFixed(1).replaceAll('.',','),style:const TextStyle(fontWeight:FontWeight.w600)),
    ]);
  }
}

/// Carte d'offre (planche 05 P2).
class _OfferCard extends StatelessWidget{
  final Map<String,dynamic> offer;
  final bool best;
  final bool favorite;
  final bool busy;
  final VoidCallback? onTap;
  const _OfferCard({required this.offer,required this.best,required this.favorite,required this.busy,required this.onTap});
  @override Widget build(BuildContext context){
    final name='${offer['driverFirstName']??''} ${offer['driverLastName']??''}'.trim();
    final vehicle=[offer['vehicleBrand'],offer['vehicleModel']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' ');
    return Semantics(button:true,label:'$name, ${VeyraMoneyFormatter.fromMinor(offer['totalMinor'])}',child:_ShadowCard(onTap:onTap,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      // Pill left, price right (board 05 P2); a Wrap so the price drops
      // below the pill with enlarged text.
      SizedBox(width:double.infinity,child:Wrap(alignment:best?WrapAlignment.spaceBetween:WrapAlignment.end,crossAxisAlignment:WrapCrossAlignment.center,spacing:8,runSpacing:6,children:[
        if(best)_StatePill(t('Meilleur prix'),fg:VeyraColors.success,bg:VeyraColors.successBackground,icon:Icons.verified),
        Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisSize:MainAxisSize.min,children:[
          Text(VeyraMoneyFormatter.fromMinor(offer['totalMinor']),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800)),
          Text(t('TTC · commission incluse'),style:const TextStyle(fontSize:11,color:VeyraColors.textSecondary)),
        ]),
      ])),
      const SizedBox(height:8),
      Row(children:[
        _DriverAvatar(name),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(name.isEmpty?t('Chauffeur'):name,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700)),
          _Rating(offer['rating']),
          if(favorite)...[const SizedBox(height:4),const _FavoritePill()],
        ])),
      ]),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(vehicle,style:const TextStyle(color:VeyraColors.accent,fontWeight:FontWeight.w600)),
          const SizedBox(height:4),
          Wrap(spacing:6,runSpacing:4,children:[
            if(offer['vehicleCategory']!=null)Chip(label:Text(offer['vehicleCategory'].toString()),visualDensity:VisualDensity.compact,materialTapTargetSize:MaterialTapTargetSize.shrinkWrap),
            if(offer['driverVerified']==true)Chip(avatar:const Icon(Icons.verified_user_outlined,size:16,color:VeyraColors.success),label:Text(t('Vérifié')),visualDensity:VisualDensity.compact,materialTapTargetSize:MaterialTapTargetSize.shrinkWrap),
          ]),
          // Seats / luggage declared for the offered vehicle (board 05 P2).
          if(offer['vehicleSeats']!=null)...[
            const SizedBox(height:4),
            Wrap(spacing:14,children:[
              Row(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.person_outline,size:16,color:VeyraColors.textSecondary),const SizedBox(width:3),Text('${offer['vehicleSeats']}',style:const TextStyle(color:VeyraColors.textSecondary))]),
              if(offer['vehicleBaggage']!=null)Row(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.luggage_outlined,size:16,color:VeyraColors.textSecondary),const SizedBox(width:3),Text('${offer['vehicleBaggage']}',style:const TextStyle(color:VeyraColors.textSecondary))]),
            ]),
          ],
        ])),
        VeyraVehicleThumb(width:84,category:offer['vehicleCategory']?.toString()),
      ]),
      if(busy)const Padding(padding:EdgeInsets.only(top:10),child:LinearProgressIndicator()),
    ])));
  }
}

/// Détail de l'offre (planche 05 P3, planche 03 P3).
class OfferDetailScreen extends StatelessWidget{
  final Map<String,dynamic> booking;
  final Map<String,dynamic> offer;
  final bool favorite;
  final bool best;
  final Future<void> Function() onChoose;
  const OfferDetailScreen({required this.booking,required this.offer,required this.favorite,required this.best,required this.onChoose,super.key});

  @override Widget build(BuildContext context){
    final name='${offer['driverFirstName']??''} ${offer['driverLastName']??''}'.trim();
    final vehicle=[offer['vehicleBrand'],offer['vehicleModel']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' ');
    final (pTitle,pSub)=_AddressScreenState.splitLabel(booking['pickup_address']?.toString()??'');
    final (dTitle,dSub)=_AddressScreenState.splitLabel(booking['dropoff_address']?.toString()??'');
    return Scaffold(
      appBar:AppBar(title:Text(t('Détail de l’offre'))),
      body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,16),children:[
        Row(children:[
          _DriverAvatar(name,radius:30),
          const SizedBox(width:14),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(name.isEmpty?t('Chauffeur'):name,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800)),
            _Rating(offer['rating']),
            if(favorite)...[const SizedBox(height:6),const _FavoritePill()],
            if(best)...[const SizedBox(height:6),_StatePill(t('Meilleur prix'),fg:VeyraColors.success,bg:VeyraColors.successBackground,icon:Icons.verified)],
          ])),
        ]),
        const SizedBox(height:18),
        _Section(child:Row(children:[
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(vehicle,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),
            const SizedBox(height:6),
            Wrap(spacing:6,children:[
              if(offer['vehicleCategory']!=null)Chip(label:Text(offer['vehicleCategory'].toString()),visualDensity:VisualDensity.compact),
              if(offer['vehicleColor']!=null)Chip(label:Text(offer['vehicleColor'].toString()),visualDensity:VisualDensity.compact),
              if(offer['vehicleYear']!=null)Chip(label:Text(offer['vehicleYear'].toString()),visualDensity:VisualDensity.compact),
            ]),
            if(offer['driverVerified']==true)...[
              const SizedBox(height:6),
              Row(children:[const Icon(Icons.verified_user_outlined,size:18,color:VeyraColors.success),const SizedBox(width:6),Expanded(child:Text(t('Chauffeur Veyra vérifié'),style:const TextStyle(color:VeyraColors.textSecondary,fontWeight:FontWeight.w600)))]),
            ],
          ])),
          VeyraVehicleThumb(width:96,category:offer['vehicleCategory']?.toString()),
        ])),
        if((offer['driverMessage']??'').toString().trim().isNotEmpty)_Section(
          title:t('Message du chauffeur'),
          child:Text(offer['driverMessage'].toString().trim(),style:const TextStyle(color:VeyraColors.textSecondary)),
        ),
        _Section(title:t('Détails du trajet'),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          VeyraRoutePoints(pickupTitle:pTitle,pickupSubtitle:pSub,dropoffTitle:dTitle,dropoffSubtitle:dSub),
          const SizedBox(height:12),
          Row(children:[const Icon(Icons.calendar_today_outlined,size:18),const SizedBox(width:8),Expanded(child:Text(veyraBookingWhen(booking['scheduled_at'])))]),
          const SizedBox(height:8),
          _PaxBags(booking),
        ])),
        _PriceDetail(offer:offer),
      ]),
      bottomNavigationBar:SafeArea(child:Padding(
        padding:const EdgeInsets.fromLTRB(16,8,16,16),
        child:FilledButton(
          onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ConfirmBookingScreen(booking:booking,offer:offer,favorite:favorite,onConfirm:onChoose))),
          child:Text(t('Choisir ce chauffeur')),
        ),
      )),
    );
  }
}

class _Section extends StatelessWidget{
  final String? title;
  final Widget child;
  const _Section({this.title,required this.child});
  @override Widget build(BuildContext context)=>Container(
    margin:const EdgeInsets.only(bottom:12),
    padding:const EdgeInsets.all(16),
    decoration:BoxDecoration(borderRadius:BorderRadius.circular(VeyraRadius.lg),border:Border.all(color:VeyraColors.border)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(title!=null)...[VeyraSectionLabel(title!),const SizedBox(height:10)],
      child,
    ]),
  );
}

/// « Détail du prix » (planche 05 P3/P4) : prix chauffeur, commission
/// VEYRA et total TTC, tels que figés sur l'offre (méthode A).
class _PriceDetail extends StatelessWidget{
  final Map<String,dynamic> offer;
  const _PriceDetail({required this.offer});
  Widget line(String label,dynamic minor,{bool total=false})=>Padding(
    padding:const EdgeInsets.symmetric(vertical:4),
    child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      Flexible(child:Text(label,style:TextStyle(color:total?VeyraColors.textPrimary:VeyraColors.textSecondary,fontWeight:total?FontWeight.w800:FontWeight.w500,fontSize:total?16:14))),
      const SizedBox(width:8),
      Flexible(child:Text.rich(TextSpan(children:[
        TextSpan(text:VeyraMoneyFormatter.fromMinor(minor),style:TextStyle(fontWeight:total?FontWeight.w800:FontWeight.w600,fontSize:total?18:14)),
        if(total)const TextSpan(text:' TTC',style:TextStyle(fontSize:12,color:VeyraColors.textSecondary)),
      ]),textAlign:TextAlign.end)),
    ]),
  );
  @override Widget build(BuildContext context){
    final bps=(offer['commissionRateBps'] as num?)?.toInt();
    final pct=bps==null?'':' (${(bps/100).toStringAsFixed(bps%100==0?0:1).replaceAll('.',',')} %)';
    return _Section(title:t('Détail du prix'),child:Column(children:[
      line(t('Prix de la course'),offer['driverPriceMinor']),
      line(t('Commission VEYRA')+pct,offer['commissionMinor']),
      const Divider(height:18),
      line(t('Prix total à payer'),offer['totalMinor'],total:true),
    ]));
  }
}

/// Confirmer la réservation (planche 05 P4, planche 10 P1).
class ConfirmBookingScreen extends StatefulWidget{
  final Map<String,dynamic> booking;
  final Map<String,dynamic> offer;
  final bool favorite;
  final Future<void> Function() onConfirm;
  const ConfirmBookingScreen({required this.booking,required this.offer,required this.favorite,required this.onConfirm,super.key});
  @override State<ConfirmBookingScreen> createState()=>_ConfirmBookingScreenState();
}
class _ConfirmBookingScreenState extends State<ConfirmBookingScreen>{
  bool accepted=false;
  bool busy=false;
  String? error;

  Future<void> confirm()async{
    if(busy||!accepted)return;
    setState((){busy=true;error=null;});
    try{
      await widget.onConfirm();
    }catch(e){
      if(mounted)setState(()=>error=e is DioException?VeyraErrorMessages.forException(e):t('Impossible de choisir cette offre pour le moment.'));
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  @override Widget build(BuildContext context){
    final o=widget.offer,b=widget.booking;
    final name='${o['driverFirstName']??''} ${o['driverLastName']??''}'.trim();
    final vehicle=[o['vehicleBrand'],o['vehicleModel']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' ');
    final online=b['payment_method']=='ONLINE';
    return Scaffold(
      appBar:AppBar(title:Text(t('Confirmer la réservation'))),
      body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,16),children:[
        _Section(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            _DriverAvatar(name),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(name.isEmpty?t('Chauffeur'):name,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),
              _Rating(o['rating']),
              if(widget.favorite)...[const SizedBox(height:4),const _FavoritePill()],
            ])),
          ]),
          const SizedBox(height:10),
          Row(children:[
            VeyraVehicleThumb(width:84,category:o['vehicleCategory']?.toString()),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(vehicle,style:const TextStyle(fontWeight:FontWeight.w700)),
              if(o['vehicleCategory']!=null)Text(o['vehicleCategory'].toString(),style:const TextStyle(color:VeyraColors.accent)),
            ])),
          ]),
        ])),
        _Section(title:t('Récapitulatif du trajet'),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Builder(builder:(_){
            final (pTitle,pSub)=_AddressScreenState.splitLabel((b['pickup_address']??'').toString());
            final (dTitle,dSub)=_AddressScreenState.splitLabel((b['dropoff_address']??'').toString());
            return VeyraRoutePoints(pickupTitle:pTitle,pickupSubtitle:pSub,dropoffTitle:dTitle,dropoffSubtitle:dSub);
          }),
          const SizedBox(height:12),
          Row(children:[const Icon(Icons.calendar_today_outlined,size:18),const SizedBox(width:8),Expanded(child:Text(veyraBookingWhen(b['scheduled_at'])))]),
          const SizedBox(height:6),
          _PaxBags(b),
        ])),
        _PriceDetail(offer:o),
        _Section(title:t('Méthode de paiement'),child:Row(children:[
          Icon(online?Icons.credit_card:Icons.payments_outlined,color:VeyraColors.primary),
          const SizedBox(width:12),
          Expanded(child:Text(online?t('Carte bancaire — débit à la confirmation'):t('Paiement en cash au chauffeur'),style:const TextStyle(fontWeight:FontWeight.w600))),
        ])),
        CheckboxListTile(
          value:accepted,
          onChanged:(v)=>setState(()=>accepted=v??false),
          controlAffinity:ListTileControlAffinity.leading,
          contentPadding:EdgeInsets.zero,
          title:Text(t('J’accepte les conditions d’utilisation et la politique d’annulation.'),style:const TextStyle(fontSize:13)),
        ),
        // Board 05 P4: amber cancellation note. The free-cancellation delay
        // is admin-configurable (DEC-09), so the exact fee is shown by the
        // cancellation preview rather than hard-coded here.
        VeyraBanner(tone:VeyraTone.warning,text:t('Les éventuels frais d’annulation dépendent de la politique en vigueur et sont affichés avant toute annulation.')),
        if(error!=null)...[const SizedBox(height:10),VeyraBanner(tone:VeyraTone.danger,text:error!)],
      ]),
      bottomNavigationBar:SafeArea(child:Padding(
        padding:const EdgeInsets.fromLTRB(16,8,16,16),
        child:FilledButton.icon(
          onPressed:busy||!accepted?null:confirm,
          icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):Icon(online?Icons.lock_outline:Icons.check),
          label:Text(online?t('Confirmer et payer'):t('Confirmer la réservation')),
        ),
      )),
    );
  }
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

  static const _rideStates={'DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'};
  static const _cancellableStates={'OPEN_FOR_OFFERS','OFFERS_RECEIVED','CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED'};
  static const _pinStates={'CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED'};
  static const _terminalStates={'COMPLETED','CLOSED','CANCELLED','CANCELLED_BY_CLIENT','CANCELLED_BY_DRIVER','DRIVER_CANCELLED','CUSTOMER_NO_SHOW','EXPIRED','NO_OFFER','NO_DRIVER'};

  /// « 2 h 45 min » (planche 10 P2), « 25 min » (P3), « 1 j 02 h 45 min » (planche 05 P5).
  static String countdown(Duration d){
    if(d.isNegative)return t('Imminent');
    String two(int v)=>v.toString().padLeft(2,'0');
    final days=d.inDays,h=d.inHours%24,m=d.inMinutes%60;
    if(days>0)return '$days j ${two(h)} h ${two(m)} min';
    if(h>0)return '$h h ${two(m)} min';
    return '$m min';
  }

  Widget statusPill(Map<String,dynamic> x){
    final status=(x['status']??'').toString();
    // Terminal outcomes keep their full wording (« Demande expirée »…).
    if(_terminalStates.contains(status)&&!_pastStates.contains(status)){
      final cancelled=status.contains('CANCEL')||status=='CUSTOMER_NO_SHOW';
      return _StatePill(VeyraStatusLabels.bookingStatus(status),fg:cancelled?VeyraColors.danger:VeyraColors.neutral,bg:cancelled?VeyraColors.dangerBackground:VeyraColors.neutralBackground);
    }
    return _pillFor(x);
  }

  Widget countdownCard(DateTime when,Duration left){
    final soon=left.inMinutes<=30;
    final fg=soon?VeyraColors.success:VeyraColors.accent;
    return Container(
      margin:const EdgeInsets.only(bottom:12),
      padding:const EdgeInsets.all(18),
      decoration:BoxDecoration(color:soon?VeyraColors.successBackground:VeyraColors.infoBackground,borderRadius:BorderRadius.circular(VeyraRadius.lg)),
      child:Row(children:[
        Icon(Icons.schedule,size:52,color:fg),
        const SizedBox(width:18),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(t('Départ dans'),style:const TextStyle(fontWeight:FontWeight.w600)),
          Text(countdown(left),style:TextStyle(fontSize:26,fontWeight:FontWeight.w800,color:soon?VeyraColors.textPrimary:fg)),
          Text(veyraBookingWhen(when.toUtc().toIso8601String()),style:const TextStyle(color:VeyraColors.textSecondary)),
        ])),
      ]),
    );
  }

  Widget rideBanner(String status){
    final (title,sub)=switch(status){
      'DRIVER_ARRIVED'=>(t('Votre chauffeur est arrivé'),t('Vérifiez le véhicule et communiquez le PIN à bord.')),
      'IN_PROGRESS'=>(t('Course en cours'),t('Bon trajet avec VEYRA.')),
      _=>(t('Votre chauffeur est en route'),t('Suivez son arrivée en temps réel.')),
    };
    return Container(
      margin:const EdgeInsets.only(bottom:12),
      padding:const EdgeInsets.all(16),
      decoration:BoxDecoration(color:VeyraColors.successBackground,borderRadius:BorderRadius.circular(VeyraRadius.lg)),
      child:Row(children:[
        const Icon(Icons.directions_car_outlined,size:32,color:VeyraColors.success),
        const SizedBox(width:14),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(title,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
          Text(sub,style:const TextStyle(color:VeyraColors.textSecondary)),
        ])),
      ]),
    );
  }

  Widget driverCard(Map<String,dynamic> x){
    final name='${x['driver_first_name']??''} ${x['driver_last_name']??''}'.trim();
    final vehicle=[x['vehicle_brand'],x['vehicle_model']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' ');
    return _Section(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        _DriverAvatar(name,radius:30),
        const SizedBox(width:14),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(name.isEmpty?t('Chauffeur confirmé'):name,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),
          _Rating(x['driver_rating']),
          if(favorite)...[const SizedBox(height:4),const _FavoritePill()],
        ])),
      ]),
      const SizedBox(height:12),
      Row(children:[
        VeyraVehicleThumb(width:110,category:x['category_name']?.toString()),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          if(vehicle.isNotEmpty)Text(vehicle,style:const TextStyle(fontWeight:FontWeight.w600)),
          if(x['category_name']!=null)...[const SizedBox(height:4),_StatePill(x['category_name'].toString(),fg:VeyraColors.accent,bg:VeyraColors.infoBackground)],
          if(x['plate_number']!=null)...[const SizedBox(height:4),Text(x['plate_number'].toString(),style:const TextStyle(color:VeyraColors.textSecondary))],
        ])),
      ]),
      if(x['driver_verified']==true)...[
        const SizedBox(height:10),
        Row(children:[const Icon(Icons.verified_user_outlined,size:18,color:VeyraColors.success),const SizedBox(width:6),Expanded(child:Text(t('Chauffeur Veyra vérifié'),style:const TextStyle(color:VeyraColors.textSecondary,fontWeight:FontWeight.w600)))]),
      ],
    ]));
  }

  /// Message / Appeler (planche 10 P2-P3) : ouverts 30 min avant le départ.
  /// L'appel passe uniquement par un numéro masqué (DEC-06, CL-15) ; tant
  /// que celui-ci n'est pas branché, le bouton reste désactivé.
  Widget contactBlock(bool open)=>Padding(
    padding:const EdgeInsets.only(bottom:12),
    child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[
        Expanded(child:OutlinedButton.icon(
          onPressed:open?()=>context.push('/chat/'+widget.bookingId):null,
          icon:const Icon(Icons.chat_bubble_outline),label:Text(t('Message')),
        )),
        const SizedBox(width:10),
        Expanded(child:Tooltip(message:t('Appel par numéro masqué bientôt disponible'),child:FilledButton.icon(
          onPressed:null,
          icon:const Icon(Icons.phone_outlined),label:Text(t('Appeler')),
        ))),
      ]),
      const SizedBox(height:10),
      VeyraBanner(
        tone:open?VeyraTone.warning:VeyraTone.info,
        text:open?t('Vous pouvez contacter votre chauffeur jusqu’à 1 heure après la fin de la course.'):t('Vous pourrez contacter votre chauffeur 30 minutes avant le départ.'),
      ),
    ]),
  );

  Widget tripSection(Map<String,dynamic> x){
    final (pTitle,pSub)=_AddressScreenState.splitLabel((x['pickup_address']??'').toString());
    final (dTitle,dSub)=_AddressScreenState.splitLabel((x['dropoff_address']??'').toString());
    final notes=(x['customer_notes']??'').toString();
    return _Section(title:t('Détails du trajet'),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      VeyraRoutePoints(pickupTitle:pTitle,pickupSubtitle:pSub,dropoffTitle:dTitle,dropoffSubtitle:dSub),
      const SizedBox(height:12),
      Row(children:[const Icon(Icons.calendar_today_outlined,size:18),const SizedBox(width:8),Expanded(child:Text(veyraBookingWhen(x['scheduled_at'])))]),
      const SizedBox(height:8),
      _PaxBags(x),
      if(notes.isNotEmpty)...[
        const SizedBox(height:12),
        Container(
          padding:const EdgeInsets.all(12),
          decoration:BoxDecoration(color:VeyraColors.surfaceMuted,borderRadius:BorderRadius.circular(VeyraRadius.md)),
          child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Icon(Icons.chat_outlined,size:18,color:VeyraColors.textSecondary),
            const SizedBox(width:10),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(t('Commentaire pour le chauffeur'),style:const TextStyle(fontWeight:FontWeight.w700,fontSize:13)),
              const SizedBox(height:2),
              Text(notes,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
            ])),
          ]),
        ),
      ],
    ]));
  }

  Widget priceSection(Map<String,dynamic> x){
    final online=x['payment_method']=='ONLINE';
    return _Section(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(x['customer_total_amount_minor']!=null)Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Flexible(child:Text(t('Prix total'),style:const TextStyle(fontWeight:FontWeight.w700,fontSize:16))),
        Flexible(child:Text.rich(TextSpan(children:[
          TextSpan(text:VeyraMoneyFormatter.fromMinor(x['customer_total_amount_minor']),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:18)),
          const TextSpan(text:' TTC',style:TextStyle(fontSize:12,color:VeyraColors.textSecondary)),
        ]),textAlign:TextAlign.end)),
      ]),
      const SizedBox(height:8),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Flexible(child:Text(t('Méthode de paiement'),style:const TextStyle(color:VeyraColors.textSecondary))),
        const SizedBox(width:8),
        Flexible(child:Text(online?t('Carte bancaire'):t('Cash au chauffeur'),textAlign:TextAlign.end,style:const TextStyle(fontWeight:FontWeight.w600))),
      ]),
      if(online)...[
        const SizedBox(height:6),
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Flexible(child:Text(t('Paiement'),style:const TextStyle(color:VeyraColors.textSecondary))),
          const SizedBox(width:8),
          Flexible(child:Text(paymentStatusLabel(x['payment_status']?.toString()),textAlign:TextAlign.end,style:const TextStyle(fontWeight:FontWeight.w600))),
        ]),
      ],
    ]));
  }

  Widget pinSection()=>_Section(title:t('Code PIN de prise en charge'),child:pin==null
    ?OutlinedButton(onPressed:loadPin,child:Text(t('Afficher le PIN')))
    :Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(t('Communiquez ce code au chauffeur uniquement lorsque vous êtes dans le véhicule.'),style:const TextStyle(fontSize:13,color:VeyraColors.textSecondary)),
      const SizedBox(height:8),
      VeyraPinDisplay(pin:pin!),
    ]));

  Widget ratingSection()=>_Section(title:ratingSubmitted?null:t('Noter le chauffeur'),child:ratingSubmitted
    ?Row(children:[const Icon(Icons.check_circle,color:VeyraColors.success),const SizedBox(width:8),Expanded(child:Text(t('Merci pour votre avis !')))])
    :Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Wrap(children:[for(int i=1;i<=5;i++)IconButton(
        icon:Icon(i<=ratingScore?Icons.star_rounded:Icons.star_border_rounded,color:const Color(0xFFF5A623),size:32),
        tooltip:AppLocale.code.value=='en'?(i==1?'1 star':'$i stars'):(i==1?'1 étoile':'$i étoiles'),
        onPressed:ratingSubmitting?null:()=>setState(()=>ratingScore=i),
      )]),
      FilledButton(onPressed:ratingSubmitting||ratingScore<1?null:submitRating,child:Text(ratingSubmitting?t('Envoi…'):t('Envoyer la note'))),
    ]));

  Widget? bottomActions(Map<String,dynamic> x){
    final status=(x['status']??'').toString();
    final canCancel=_cancellableStates.contains(status);
    final canTrack=_rideStates.contains(status);
    if(!canCancel&&!canTrack)return null;
    return SafeArea(child:Padding(
      padding:const EdgeInsets.fromLTRB(16,8,16,12),
      child:Row(children:[
        if(canCancel)Expanded(child:OutlinedButton(
          style:OutlinedButton.styleFrom(foregroundColor:VeyraColors.danger,side:const BorderSide(color:VeyraColors.danger)),
          onPressed:(cancelling||loadingPreview)?null:confirmAndCancel,
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.event_busy_outlined,size:18),
            const SizedBox(width:6),
            Flexible(child:Text(cancelling?t('Annulation…'):loadingPreview?t('Calcul des frais…'):t('Annuler la réservation'),textAlign:TextAlign.center)),
          ]),
        )),
        if(canCancel&&canTrack)const SizedBox(width:10),
        if(canTrack)Expanded(child:FilledButton(
          onPressed:()=>context.push('/live/'+widget.bookingId),
          child:Text(t('Suivre mon chauffeur'),textAlign:TextAlign.center),
        )),
      ]),
    ));
  }

  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(
    future:future,
    builder:(context,s){
      final loaded=s.connectionState==ConnectionState.done&&!s.hasError;
      final x=loaded?(s.data??<String,dynamic>{}):<String,dynamic>{};
      final status=(x['status']??'').toString();
      final offerPhase=_offerPhaseStates.contains(status);
      return Scaffold(
        appBar:AppBar(title:Text(offerPhase?t('Ma demande'):t('Ma réservation')),actions:[IconButton(onPressed:refreshStatus,icon:const Icon(Icons.refresh),tooltip:t('Actualiser'))]),
        bottomNavigationBar:loaded?bottomActions(x):null,
        body:Builder(builder:(context){
          if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
          if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
            ?VeyraOfflineBanner(onRetry:reload)
            :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:reload);
          final hasDriver=x['selected_driver_id']!=null;
          final terminal=_terminalStates.contains(status);
          final when=DateTime.tryParse((x['scheduled_at']??'').toString())?.toLocal();
          final left=when?.difference(DateTime.now());
          final contactOpen=_rideStates.contains(status)||(status=='CONFIRMED'&&left!=null&&left.inMinutes<=30);
          final id=(x['id']??widget.bookingId).toString();
          final ref='#'+(id.length>8?id.substring(0,8):id).toUpperCase();
          final offers=(x['offer_count'] as num?)?.toInt()??0;
          return RefreshIndicator(onRefresh:refreshStatus,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
            Row(children:[
              Expanded(child:Align(alignment:Alignment.centerLeft,child:statusPill(x))),
              const SizedBox(width:8),
              Text(ref,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:12)),
            ]),
            const SizedBox(height:12),
            if(offerPhase)_Section(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Text(t('Réception des offres jusqu’au')+' '+VeyraDateFormatter.dateTime(x['offer_window_ends_at']),style:const TextStyle(color:VeyraColors.textSecondary)),
              if(offers>0&&x['best_offer_total_minor']!=null)...[const SizedBox(height:12),_BestPriceBanner(x['best_offer_total_minor'])],
              const SizedBox(height:12),
              FilledButton(onPressed:()=>context.push('/offers/'+widget.bookingId),child:Text(t('Voir les offres'))),
            ])),
            if(status=='CONFIRMED'&&when!=null&&left!=null)countdownCard(when,left),
            if(_rideStates.contains(status))rideBanner(status),
            if(hasDriver)driverCard(x),
            if(hasDriver&&!terminal)contactBlock(contactOpen),
            tripSection(x),
            if(!offerPhase)priceSection(x),
            if(bookingCanPayOnline(x))Padding(padding:const EdgeInsets.only(bottom:12),child:FilledButton.icon(onPressed:()=>context.push('/payment/'+widget.bookingId),icon:const Icon(Icons.credit_card),label:Text(t('Payer en ligne')))),
            if(_pinStates.contains(status))pinSection(),
            if(_pastStates.contains(status))...[
              ratingSection(),
              if(hasDriver)Padding(padding:const EdgeInsets.only(bottom:12),child:OutlinedButton.icon(onPressed:favoriteBusy?null:()=>toggleFavorite(x),icon:Icon(favorite?Icons.favorite:Icons.favorite_border,color:VeyraColors.pinRed),label:Text(favorite?t('Retirer des favoris'):t('Ajouter le chauffeur aux favoris')))),
            ],
            if(terminal)FilledButton.icon(onPressed:()=>context.push('/addresses',extra:x),icon:const Icon(Icons.replay),label:Text(t('Réserver à nouveau'))),
            if(refreshError!=null)Padding(padding:const EdgeInsets.only(top:12),child:VeyraBanner(tone:VeyraTone.warning,text:refreshError!)),
            if(message!=null)Padding(padding:const EdgeInsets.only(top:12),child:VeyraBanner(tone:VeyraTone.info,text:message!)),
          ]));
        }),
      );
    },
  );
}

class ChatScreen extends StatefulWidget{
  final String bookingId;
  const ChatScreen({required this.bookingId,super.key});
  @override State<ChatScreen> createState()=>_ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen>{
  /// Shared conversation view (same as the driver app).
  @override Widget build(BuildContext context)=>VeyraChatView(
    api:api,
    bookingId:widget.bookingId,
    counterpartName:(b)=>(b['driver_name']??'${b['driver_first_name']??''} ${b['driver_last_name']??''}').toString(),
  );
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

  /// Whole trip pickup → destination, drawn once (board 10 P4).
  List<LatLng> tripRoute=const [];
  bool tripRouteRequested=false;
  bool detailsOpen=false;

  Future<void> loadTripRoute()async{
    final b=bookingMap;
    if(tripRouteRequested||b==null)return;
    final pLat=(b['pickup_lat'] as num?)?.toDouble(),pLng=(b['pickup_lng'] as num?)?.toDouble();
    final dLat=(b['dropoff_lat'] as num?)?.toDouble(),dLng=(b['dropoff_lng'] as num?)?.toDouble();
    if(pLat==null||pLng==null||dLat==null||dLng==null)return;
    tripRouteRequested=true;
    try{
      final r=await api.routeEstimate(fromLat:pLat,fromLng:pLng,toLat:dLat,toLng:dLng);
      final pts=((r['points'] as List?)??[]).whereType<Map>().map((m)=>LatLng((m['lat'] as num).toDouble(),(m['lng'] as num).toDouble())).toList();
      if(mounted)setState(()=>tripRoute=pts);
    }catch(_){}
  }

  Future<void> reportProblem()async{
    String category='DRIVER_LATE';
    final note=TextEditingController();
    final sent=await showModalBottomSheet<bool>(
      context:context,
      isScrollControlled:true,
      builder:(sheet)=>StatefulBuilder(builder:(sheet,setSheet)=>Padding(
        padding:EdgeInsets.fromLTRB(20,20,20,20+MediaQuery.of(sheet).viewInsets.bottom),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text(t('Signaler un problème'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
          const SizedBox(height:12),
          for(final (code,label) in [('DRIVER_LATE','Chauffeur en retard'),('DRIVER_NOT_FOUND','Je ne trouve pas mon chauffeur'),('VEHICLE','Problème avec le véhicule'),('SAFETY','Sécurité'),('OTHER','Autre')])
            ListTile(
              contentPadding:EdgeInsets.zero,dense:true,
              leading:Icon(category==code?Icons.radio_button_checked:Icons.radio_button_unchecked,color:category==code?VeyraColors.accent:VeyraColors.textTertiary),
              title:Text(t(label)),
              selected:category==code,
              onTap:()=>setSheet(()=>category=code),
            ),
          TextField(controller:note,maxLength:1000,maxLines:3,decoration:InputDecoration(hintText:t('Précisez si besoin (facultatif)'))),
          const SizedBox(height:8),
          FilledButton(onPressed:()=>Navigator.pop(sheet,true),child:Text(t('Envoyer au support'))),
        ]),
      )),
    );
    if(sent!=true)return;
    try{
      await api.reportProblem(widget.bookingId,category,message:note.text.trim().isEmpty?null:note.text.trim());
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Signalement envoyé. Le support VEYRA vous recontacte.'))));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));
    }
  }

  /// Board 10 P4 « Course en cours »: status banner with the arrival
  /// estimate, live map, driver, contact, trip details, report a problem.
  @override Widget build(BuildContext context){
    final b=bookingMap??const <String,dynamic>{};
    final status=(b['status']??'').toString();
    final available=location?['available']==true;
    LatLng? at(String lat,String lng){final a=(b[lat] as num?)?.toDouble(),o=(b[lng] as num?)?.toDouble();return a==null||o==null?null:LatLng(a,o);}
    final pickup=at('pickup_lat','pickup_lng');
    final dropoff=at('dropoff_lat','dropoff_lng');
    final driver=available?LatLng((location!['lat'] as num).toDouble(),(location!['lng'] as num).toDouble()):null;
    final eta=etaInfo!=null&&canEstimateTrackingEta(bookingMap,location,DateTime.now())?etaInfo:null;
    final etaMin=eta==null?null:((eta['durationSeconds'] as num)/60).ceil();
    final livePts=((eta?['points'] as List?)??[]).whereType<Map>().map((m)=>LatLng((m['lat'] as num).toDouble(),(m['lng'] as num).toDouble())).toList();
    final id=(b['id']??widget.bookingId).toString();
    final ref='#'+(id.length>8?id.substring(0,8):id).toUpperCase();
    final (pTitle,pSub)=_AddressScreenState.splitLabel((b['pickup_address']??'').toString());
    final (dTitle,dSub)=_AddressScreenState.splitLabel((b['dropoff_address']??'').toString());
    final notes=(b['customer_notes']??'').toString();
    final (title,sub)=switch(status){
      'DRIVER_ARRIVED'=>(t('Votre chauffeur est arrivé'),t('Il vous attend au point de départ.')),
      'IN_PROGRESS'=>(t('Course en cours'),etaMin==null?t('Bon trajet avec VEYRA.'):t('Arrivée à destination dans ')+'$etaMin min'),
      _=>(t('Votre chauffeur est en route'),etaMin==null?t('Suivez son arrivée en temps réel.'):t('Arrivée estimée dans ')+'$etaMin min'),
    };
    final name='${b['driver_first_name']??''} ${b['driver_last_name']??''}'.trim();
    final vehicle=[b['vehicle_brand'],b['vehicle_model']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' ');
    if(bookingMap!=null&&!tripRouteRequested)WidgetsBinding.instance.addPostFrameCallback((_)=>loadTripRoute());
    return Scaffold(
      appBar:AppBar(
        title:Text(t('Course en cours')),
        actions:[Padding(padding:const EdgeInsets.only(right:16),child:Center(child:Text(ref,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13))))],
      ),
      body:bookingMap==null
        ?const Center(child:CircularProgressIndicator())
        :ListView(padding:const EdgeInsets.fromLTRB(16,4,16,24),children:[
          // Status banner with the arrival estimate in bold (board 10 P4).
          Container(
            padding:const EdgeInsets.all(14),
            decoration:BoxDecoration(color:VeyraColors.successBackground,borderRadius:BorderRadius.circular(VeyraRadius.lg)),
            child:Row(children:[
              const Icon(Icons.directions_car_outlined,size:32,color:VeyraColors.success),
              const SizedBox(width:14),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(title,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
                Text.rich(TextSpan(children:[
                  TextSpan(text:etaMin==null?sub:sub.substring(0,sub.length-'$etaMin min'.length)),
                  if(etaMin!=null)TextSpan(text:'$etaMin min',style:const TextStyle(fontWeight:FontWeight.w800,color:VeyraColors.textPrimary)),
                ]),style:const TextStyle(color:VeyraColors.textSecondary)),
              ])),
            ]),
          ),
          const SizedBox(height:12),
          // Full width, edge to edge, as on the board.
          SizedBox(height:270,child:OverflowBox(
            minWidth:MediaQuery.sizeOf(context).width,
            maxWidth:MediaQuery.sizeOf(context).width,
            child:Stack(children:[
              Positioned.fill(child:Container(color:const Color(0xFFE9EEF3))),
              VeyraRouteMap(
                key:ValueKey('live-${tripRoute.length}-${driver!=null}'),
                pickup:pickup,dropoff:dropoff,
                route:livePts.length>=2?livePts:tripRoute,
                height:270,interactive:true,radius:0,
                pickupLabel:_AddressScreenState.shortPlace(pTitle),
                dropoffLabel:dTitle,
                car:driver,
                carHeading:(location?['heading'] as num?)?.toDouble()??0,
                etaText:etaMin==null?null:'$etaMin min',
              ),
              Positioned(right:12,bottom:28,child:VeyraMapButton(icon:Icons.my_location,tooltip:t('Recentrer'),onPressed:refresh)),
            ]),
          )),
          if(error!=null||(available&&_isStale))...[
            const SizedBox(height:10),
            VeyraBanner(tone:VeyraTone.warning,text:error??(t('Position possiblement obsolète — dernière position : ')+VeyraDateFormatter.dateTime(location!['recorded_at']))),
          ],
          const SizedBox(height:12),
          _Section(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              _DriverAvatar(name,radius:30),
              const SizedBox(width:14),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(name.isEmpty?t('Chauffeur confirmé'):name,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),
                _Rating(b['driver_rating']),
                if(b['favorite_driver']==true)...[const SizedBox(height:4),const _FavoritePill()],
              ])),
            ]),
            const SizedBox(height:12),
            Row(children:[
              VeyraVehicleThumb(width:110,category:b['category_name']?.toString()),
              const SizedBox(width:12),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                if(vehicle.isNotEmpty)Text(vehicle,style:const TextStyle(fontWeight:FontWeight.w600)),
                if(b['category_name']!=null)...[const SizedBox(height:4),_StatePill(b['category_name'].toString(),fg:VeyraColors.accent,bg:VeyraColors.infoBackground)],
                if(b['plate_number']!=null)...[const SizedBox(height:4),Text(b['plate_number'].toString(),style:const TextStyle(color:VeyraColors.textSecondary))],
              ])),
            ]),
          ])),
          Row(children:[
            Expanded(child:OutlinedButton.icon(onPressed:()=>context.push('/chat/'+widget.bookingId),icon:const Icon(Icons.chat_bubble_outline),label:Text(t('Message')))),
            const SizedBox(width:10),
            Expanded(child:Tooltip(message:t('Appel par numéro masqué bientôt disponible'),child:OutlinedButton.icon(onPressed:null,icon:const Icon(Icons.phone_outlined),label:Text(t('Appeler'))))),
          ]),
          const SizedBox(height:10),
          Container(
            padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
            decoration:BoxDecoration(color:VeyraColors.surfaceMuted,borderRadius:BorderRadius.circular(VeyraRadius.md)),
            child:Row(children:[
              const Icon(Icons.radio_button_checked,size:16,color:Color(0xFFF5A623)),
              const SizedBox(width:8),
              Expanded(child:Text(available&&location!['recorded_at']!=null
                ?t('Suivez l’arrivée de votre chauffeur en temps réel.')+' '+t('Dernière position : ')+VeyraDateFormatter.dateTime(location!['recorded_at'])
                :t('Suivez l’arrivée de votre chauffeur en temps réel.'),style:const TextStyle(fontSize:13,color:VeyraColors.textSecondary))),
            ]),
          ),
          const SizedBox(height:12),
          _Section(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            InkWell(
              key:const ValueKey('trip-details-toggle'),
              onTap:()=>setState(()=>detailsOpen=!detailsOpen),
              child:Row(children:[
                Expanded(child:Text(t('Détails du trajet'),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16))),
                Icon(detailsOpen?Icons.expand_less:Icons.expand_more),
              ]),
            ),
            if(detailsOpen)...[
              const SizedBox(height:12),
              VeyraRoutePoints(pickupTitle:pTitle,pickupSubtitle:pSub,dropoffTitle:dTitle,dropoffSubtitle:dSub),
              const SizedBox(height:10),
              Row(children:[const Icon(Icons.calendar_today_outlined,size:18),const SizedBox(width:8),Expanded(child:Text(veyraBookingWhen(b['scheduled_at'])))]),
              const SizedBox(height:8),
              _PaxBags(b),
            ],
            if(notes.isNotEmpty)...[
              const SizedBox(height:12),
              Container(
                padding:const EdgeInsets.all(12),
                decoration:BoxDecoration(color:VeyraColors.surfaceMuted,borderRadius:BorderRadius.circular(VeyraRadius.md)),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(t('Commentaire pour le chauffeur'),style:const TextStyle(fontWeight:FontWeight.w700,fontSize:13)),
                  const SizedBox(height:2),
                  Text(notes,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
                ]),
              ),
            ],
          ])),
          OutlinedButton.icon(
            key:const ValueKey('report-problem'),
            style:OutlinedButton.styleFrom(foregroundColor:VeyraColors.danger,side:const BorderSide(color:VeyraColors.danger),minimumSize:const Size.fromHeight(50)),
            onPressed:reportProblem,
            icon:const Icon(Icons.report_gmailerrorred_outlined),
            label:Text(t('Signaler un problème')),
          ),
        ]),
    );
  }
}

/// Inscription client en 3 étapes (planche 08 A2-A4) : informations,
/// mot de passe, conditions ; puis vérification SMS (A5) et compte créé (A6).
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
  final confirmPassword=TextEditingController();
  final formKey=GlobalKey<FormState>();
  int step=1;
  bool loading=false;
  String? error;
  bool offline=false;
  bool acceptTerms=false;
  bool acceptPrivacy=false;
  bool marketingOptIn=false;
  bool consentErrors=false;
  bool showPassword=false;
  bool showConfirm=false;

  @override void initState(){
    super.initState();
    password.addListener(()=>setState((){}));
    confirmPassword.addListener(()=>setState((){}));
  }
  @override void dispose(){firstName.dispose();lastName.dispose();phone.dispose();email.dispose();password.dispose();confirmPassword.dispose();super.dispose();}

  /// The field shows a +33 prefix: "6 12 34 56 78" and "06 12 34 56 78"
  /// both become +33612345678; an international number is kept as typed.
  String get e164{
    final raw=phone.text.replaceAll(RegExp(r'[\s.\-()]'),'');
    if(raw.startsWith('+'))return raw;
    return '+33'+(raw.startsWith('0')?raw.substring(1):raw);
  }

  // Backend rule (AuthController: 10 characters minimum) is stricter than
  // the board's 8, so the checklist shows the real requirement.
  bool get pwLength=>password.text.length>=10;
  bool get pwLetterDigit=>RegExp(r'[A-Za-z]').hasMatch(password.text)&&RegExp(r'\d').hasMatch(password.text);
  bool get pwSpecial=>RegExp(r'[^A-Za-z0-9]').hasMatch(password.text);
  bool get pwMatch=>confirmPassword.text.isNotEmpty&&confirmPassword.text==password.text;

  void next(){
    setState(()=>error=null);
    if(step==1){
      if(!formKey.currentState!.validate())return;
      setState(()=>step=2);
    }else if(step==2){
      if(!(pwLength&&pwLetterDigit&&pwSpecial)){setState(()=>error=t('Le mot de passe ne respecte pas encore toutes les règles.'));return;}
      if(!pwMatch){setState(()=>error=t('Les mots de passe ne correspondent pas.'));return;}
      setState(()=>step=3);
    }else{
      submit();
    }
  }

  void back(){
    if(step>1){setState((){step--;error=null;});}
    else{Navigator.maybePop(context);}
  }

  Future<void> submit()async{
    if(loading)return;
    if(!SignupConsents.mandatoryAccepted(acceptTerms,acceptPrivacy)){
      setState((){consentErrors=true;error=t('Acceptez les CGU et la politique de confidentialité pour continuer.');offline=false;});
      return;
    }
    setState((){loading=true;error=null;offline=false;});
    try{
      await api.register(
        email:email.text.trim(),
        password:password.text,
        firstName:firstName.text.trim(),
        lastName:lastName.text.trim(),
        phone:e164,
        acceptTerms:acceptTerms,
        acceptPrivacy:acceptPrivacy,
        marketingOptIn:marketingOptIn,
      );
      if(!mounted)return;
      // CL-AUTH-05: confirm the phone number by SMS before entering the app.
      context.go('/verify-phone',extra:e164);
      await configurePush();
    }catch(e){
      if(!mounted)return;
      setState((){
        offline=VeyraErrorMessages.isOffline(e);
        error=offline?null:VeyraErrorMessages.forException(e);
      });
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  Widget field(String label,TextEditingController c,{String? hint,String? Function(String?)? validator,TextInputType? keyboard,Widget? prefix,Key? key,bool required=true})=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    VeyraFieldLabel(label,required:required),
    TextFormField(key:key,controller:c,validator:validator,keyboardType:keyboard,decoration:InputDecoration(hintText:hint,prefixIcon:prefix,prefixIconConstraints:const BoxConstraints())),
    const SizedBox(height:16),
  ]);

  Widget passwordField(String label,TextEditingController c,bool visible,VoidCallback toggle,Key key)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    VeyraFieldLabel(label,required:true),
    TextField(key:key,controller:c,obscureText:!visible,decoration:InputDecoration(
      suffixIcon:IconButton(tooltip:visible?t('Masquer'):t('Afficher'),icon:Icon(visible?Icons.visibility_off_outlined:Icons.visibility_outlined),onPressed:toggle),
    )),
  ]);

  Widget consent(bool value,String label,ValueChanged<bool> onChanged,{bool required=false}){
    final missing=required&&consentErrors&&!value;
    return CheckboxListTile(
      value:value,
      onChanged:(v)=>setState(()=>onChanged(v??false)),
      controlAffinity:ListTileControlAffinity.leading,
      contentPadding:EdgeInsets.zero,
      title:Text(label,style:const TextStyle(fontWeight:FontWeight.w600)),
      subtitle:missing?Text(t('Acceptation obligatoire'),style:const TextStyle(color:VeyraColors.danger)):null,
    );
  }

  List<Widget> stepBody()=>switch(step){
    1=>[
      VeyraStepTitle(t('Vos informations')),
      const SizedBox(height:20),
      Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Expanded(child:field(t('Prénom'),firstName,key:const ValueKey('first-name'),validator:(v)=>(v??'').trim().isEmpty?t('Prénom requis'):null)),
        const SizedBox(width:12),
        Expanded(child:field(t('Nom'),lastName,key:const ValueKey('last-name'),validator:(v)=>(v??'').trim().isEmpty?t('Nom requis'):null)),
      ]),
      field(t('Téléphone'),phone,key:const ValueKey('phone'),hint:'6 12 34 56 78',keyboard:TextInputType.phone,prefix:const VeyraPhonePrefix(),
        validator:(v)=>PhoneVerificationScreen.toE164(e164)==null?t('Téléphone incomplet'):null),
      field(t('E-mail'),email,key:const ValueKey('email'),hint:'nom@exemple.fr',keyboard:TextInputType.emailAddress,
        validator:(v)=>RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v??'').trim())?null:t('E-mail invalide')),
    ],
    2=>[
      VeyraStepTitle(t('Créez votre mot de passe')),
      const SizedBox(height:20),
      passwordField(t('Mot de passe'),password,showPassword,()=>setState(()=>showPassword=!showPassword),const ValueKey('password')),
      const SizedBox(height:12),
      VeyraCheckLine(ok:pwLength,text:t('Au moins 10 caractères')),
      VeyraCheckLine(ok:pwLetterDigit,text:t('Une lettre et un chiffre')),
      VeyraCheckLine(ok:pwSpecial,text:t('Un caractère spécial (ex : !@#)')),
      const SizedBox(height:20),
      passwordField(t('Confirmez votre mot de passe'),confirmPassword,showConfirm,()=>setState(()=>showConfirm=!showConfirm),const ValueKey('password-confirm')),
    ],
    _=>[
      VeyraStepTitle(t('Conditions d’utilisation')),
      const SizedBox(height:12),
      consent(acceptTerms,t('J’accepte les conditions d’utilisation.'),(v)=>acceptTerms=v,required:true),
      consent(acceptPrivacy,t('J’accepte la politique de confidentialité.'),(v)=>acceptPrivacy=v,required:true),
      consent(marketingOptIn,t('J’accepte de recevoir des communications de VEYRA (facultatif).'),(v)=>marketingOptIn=v),
      // « Lire les documents » (board 08 A4) comes back once the legal
      // texts are published; no placeholder text is shown meanwhile.
    ],
  };

  @override Widget build(BuildContext context)=>PopScope(
    canPop:step==1,
    onPopInvokedWithResult:(didPop,_){if(!didPop)back();},
    child:Scaffold(
      appBar:VeyraStepProgress(step:step,total:3,onBack:back),
      body:Form(key:formKey,autovalidateMode:AutovalidateMode.onUserInteraction,child:ListView(padding:const EdgeInsets.fromLTRB(24,16,24,24),children:[
        ...stepBody(),
        if(offline)Padding(padding:const EdgeInsets.only(top:12),child:VeyraOfflineBanner(onRetry:submit)),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:VeyraBanner(tone:VeyraTone.danger,text:error!)),
      ])),
      bottomNavigationBar:VeyraFlowFooter(
        onNext:next,
        loading:loading,
        trailingArrow:false,
        nextLabel:step==3?t('Créer mon compte'):t('Continuer'),
      ),
    ),
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


/// Refreshes the bell badge (board 16 P1).
Future<void> refreshUnreadNotifications()async{
  try{veyraUnreadNotifications.value=await api.unreadNotifications();}catch(_){}
}
