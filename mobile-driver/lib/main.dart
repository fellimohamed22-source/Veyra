import 'core/widgets/profile_dialog.dart';
import 'dart:async';
import 'core/active_booking.dart';
import 'core/notifications/notification_launch.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:go_router/go_router.dart';
import 'api.dart';
import 'app_locale.dart';
import 'chat_socket.dart';
import 'app/theme.dart';
import 'core/formatters/error_messages.dart';
import 'core/formatters/status_labels.dart';
import 'core/formatters/date_formatter.dart';
import 'core/formatters/money_formatter.dart';
import 'core/widgets/veyra_button.dart';
import 'core/widgets/welcome_hero.dart';
import 'onboarding/driver_signup_flow.dart';
import 'ui/driver_home_screen.dart';
import 'ui/driver_profile.dart';
import 'core/widgets/notifications_view.dart';
import 'ui/driver_ui.dart';
import 'core/widgets/veyra_ui.dart';
import 'core/widgets/state_views.dart';
import 'core/widgets/password_dialog.dart';
import 'core/widgets/driver_documents.dart';
import 'core/widgets/status_badge.dart';
import 'core/widgets/offer_price_preview.dart';
import 'core/widgets/suggested_price_hint.dart';
import 'core/maps/route_geometry.dart';
import 'core/maps/veyra_map.dart';
import 'core/maps/driver_location_tracker.dart';

/// Short alias used throughout this file.
String t(String french) => AppLocale.t(french);

bool driverPushHandlersConfigured=false;

/// Same real gap and same fix as the client app -- see its own comment
/// for the full explanation. A notification+data push is only delivered
/// to onMessage while the app is foreground, and nothing listened to it.
final FlutterLocalNotificationsPlugin _driverLocalNotifications=FlutterLocalNotificationsPlugin();
bool _driverLocalNotificationsInitialized=false;

Future<void> _ensureDriverLocalNotifications(void Function(String payload) onTap)async{
  if(_driverLocalNotificationsInitialized)return;
  const androidInit=AndroidInitializationSettings('@mipmap/ic_launcher');
  await _driverLocalNotifications.initialize(
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
  await _driverLocalNotifications
    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
    ?.createNotificationChannel(channel);
  _driverLocalNotificationsInitialized=true;
  await resumeNotificationLaunch(_driverLocalNotifications,onTap);
}

Future<void> _showDriverForegroundPush(RemoteMessage message)async{
  final notification=message.notification;
  if(notification==null)return;
  await _driverLocalNotifications.show(
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

String driverNotificationRoute(String bookingId,String? template,Map<String,dynamic> data){
  if(template=='NEW_BOOKING')return '/request/$bookingId';
  return '/ride/$bookingId';
}
Future<void> resumeActiveBooking()async{
  try{
    final id=activeBookingId(await api.bookings(scope:'active'));
    if(id!=null&&router.routeInformationProvider.value.uri.path=='/home')router.go('/ride/'+Uri.encodeComponent(id));
  }catch(_){
    // Keep the usable home screen when the server cannot confirm an active ride.
  }
}

void openDriverPush(RemoteMessage message){
  final bookingId=message.data['bookingId']?.toString();
  if(bookingId==null||bookingId.isEmpty)return;
  router.go(driverNotificationRoute(bookingId,message.data['templateCode']?.toString(),Map<String,dynamic>.from(message.data)));
}

/// Voir RefreshBus côté client (même fichier main.dart, app soeur) pour
/// le raisonnement complet -- section 19 : mécanisme de rafraîchissement
/// explicite, indépendant de la fiabilité incertaine de
/// RouteObserver/didPopNext avec le Navigator imbriqué du shell.
class RefreshBus {
  RefreshBus._();
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static void bump() => tick.value++;
}

Future<void> configureDriverPush() async {
  try{
    if(Firebase.apps.isEmpty)await Firebase.initializeApp();
    if(!driverPushHandlersConfigured){
      driverPushHandlersConfigured=true;
      FirebaseMessaging.onMessageOpenedApp.listen(openDriverPush);
      FirebaseMessaging.instance.onTokenRefresh.listen((token)async{try{await api.registerDevice(token,platform:'android');}catch(e){debugPrint('DRIVER_PUSH_TOKEN_REFRESH_FAILED: $e');}});
      final initial=await FirebaseMessaging.instance.getInitialMessage();
      if(initial!=null)WidgetsBinding.instance.addPostFrameCallback((_){openDriverPush(initial);});
      await _ensureDriverLocalNotifications((payload){
        try{
          final data=Map<String,dynamic>.from(jsonDecode(payload) as Map);
          final bookingId=data['bookingId']?.toString();
          if(bookingId!=null&&bookingId.isNotEmpty){
            router.go(driverNotificationRoute(bookingId,data['templateCode']?.toString(),data));
          }
        }catch(_){}
      });
      FirebaseMessaging.onMessage.listen((message){RefreshBus.bump();_showDriverForegroundPush(message);});
    }
    await FirebaseMessaging.instance.requestPermission();
    final token=await FirebaseMessaging.instance.getToken();
    if(token!=null)await api.registerDevice(token,platform:'android');
  }catch(e){
    debugPrint('PUSH_CONFIGURE_FAILED: $e');
  }
}

final api=Api(const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080'));

/// DEC-10: best-effort current position for 'arrived'/'start'; null when
/// permission is missing or the fix times out (the server then falls
/// back to the last tracked position).
Future<Position?> currentPositionOrNull()async{
  try{
    final permission=await Geolocator.checkPermission();
    if(permission!=LocationPermission.always&&permission!=LocationPermission.whileInUse)return null;
    return await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:8)));
  }catch(_){return null;}
}
final activeRideTracker=DriverLocationTracker(api:api);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never gate the first frame on anything async that could stall --
  // same lesson as the client app's Stripe fix. French remains correct
  // as the default until this background read resolves.
  unawaited(AppLocale.load());
  // Bell badge follows every app refresh signal (push, offer sent…).
  RefreshBus.tick.addListener(()=>unawaited(refreshUnreadNotifications()));
  runApp(const DriverApp());
}

/// Same widget/design as the client app's LanguageSwitch.
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

class DriverApp extends StatelessWidget{
  const DriverApp({super.key});
  @override Widget build(BuildContext context)=>ValueListenableBuilder<String>(
    valueListenable:AppLocale.code,
    builder:(context,localeCode,_)=>MaterialApp.router(
      title:'Veyra Chauffeur',
      theme:veyraTheme(),
      locale:Locale(localeCode),
      supportedLocales:const [Locale('fr'),Locale('en')],
      localizationsDelegates:const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig:router,
    ),
  );
}

/// Same refresh-on-return pattern as the client app's routeObserver.
final routeObserver=RouteObserver<PageRoute>();

final router=GoRouter(
  initialLocation:'/login',
  routes:[
  GoRoute(path:'/login',builder:(c,s)=>const LoginScreen()),
  // Board 08 B: driver sign-up wizard; /onboarding resumes a draft dossier.
  GoRoute(path:'/register',builder:(c,s)=>DriverSignupFlow(
    api:api,
    pickFile:pickDriverFile,
    onAccountCreated:configureDriverPush,
    onSubmitted:()=>c.go('/kyc'),
    onExit:()=>c.canPop()?c.pop():c.go('/login'),
  )),
  GoRoute(path:'/onboarding',builder:(c,s)=>DriverSignupFlow(
    api:api,
    pickFile:pickDriverFile,
    onAccountCreated:configureDriverPush,
    onSubmitted:()=>c.go('/kyc'),
    onExit:()=>c.go('/account'),
    resume:true,
  )),
  GoRoute(path:'/kyc',builder:(c,s)=>const KycScreen()),
  GoRoute(path:'/forgot',builder:(c,s)=>const ForgotPasswordScreen()),
  GoRoute(path:'/reset-password',builder:(c,s)=>const ResetPasswordScreen()),
  // Coquille de navigation persistante (bottom nav), conforme à D14 :
  // Demandes/Planning/Revenus/Compte. Notifications et les écrans de
  // flux (détail demande, course) restent des routes racine poussées
  // par-dessus la coquille entière.
  StatefulShellRoute.indexedStack(
    builder:(c,s,navigationShell)=>AppShell(navigationShell:navigationShell),
    branches:[
      // Boards 02/12/13: Accueil, Demandes, Mes courses, Revenus, Profil.
      StatefulShellBranch(routes:[GoRoute(path:'/home',builder:(c,s)=>DriverHomeScreen(api:api,refresh:RefreshBus.tick,go:c.go,push:(r)=>c.push(r)))]),
      StatefulShellBranch(routes:[GoRoute(path:'/requests',builder:(c,s)=>const OpportunitiesScreen())]),
      StatefulShellBranch(routes:[GoRoute(path:'/agenda',builder:(c,s)=>const AgendaScreen())]),
      StatefulShellBranch(routes:[GoRoute(path:'/wallet',builder:(c,s)=>const WalletScreen())]),
      StatefulShellBranch(routes:[GoRoute(path:'/account',builder:(c,s)=>DriverProfileScreen(api:api,go:c.go,push:(r)=>c.push(r),logout:()=>driverLogout(c)))]),
    ],
  ),
  GoRoute(path:'/settings',builder:(c,s)=>const AccountScreen()),
  GoRoute(path:'/vehicles',builder:(c,s)=>DriverVehiclesScreen(api:api,push:(r)=>c.push(r))),

  GoRoute(path:'/request/:id',builder:(c,s)=>RequestScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/driver/offers',builder:(c,s)=>const MesOffresScreen()),
  GoRoute(path:'/ride/:id',builder:(c,s)=>RideScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/chat/:id',builder:(c,s)=>DriverChatScreen(bookingId:s.pathParameters['id']!)),
  // Board 16: grouped list with read state (CL-18).
  GoRoute(path:'/notifications',builder:(c,s)=>VeyraNotificationsScreen(
    load:()=>api.notifications(),
    markRead:api.markNotificationRead,
    markAllRead:api.markAllNotificationsRead,
    open:(n){if(n.bookingId!=null)c.go(driverNotificationRoute(n.bookingId!,n.template,n.data));},
  )),
],
  observers:[routeObserver],
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


class VeyraPaginationBar extends StatelessWidget{
  final int page;
  final bool hasNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const VeyraPaginationBar({
    super.key,
    required this.page,
    required this.hasNext,
    this.onPrevious,
    this.onNext,
  });

  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.only(top:14,bottom:4),
    child:Row(children:[
      Expanded(child:OutlinedButton.icon(
        onPressed:page>0?onPrevious:null,
        icon:const Icon(Icons.chevron_left),
        label:Text(t('Précédent')),
      )),
      Padding(
        padding:const EdgeInsets.symmetric(horizontal:14),
        child:Text(
          t('Page')+' '+(page+1).toString(),
          style:const TextStyle(fontWeight:FontWeight.w700,color:Color(0xFF4B5563)),
        ),
      ),
      Expanded(child:FilledButton.icon(
        onPressed:hasNext?onNext:null,
        icon:const Icon(Icons.chevron_right),
        label:Text(t('Suivant')),
      )),
    ]),
  );
}

class LoginScreen extends StatefulWidget{
  const LoginScreen({super.key});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen>{
  final email=TextEditingController();
  final password=TextEditingController();
  bool loading=false;
  String? error;
  bool offline=false;

  bool startupChecking=false;
  bool startupRetryAvailable=false;

  @override void initState(){
    super.initState();
    // P0 fix: root cause of "driver session lost at restart, sent to
    // onboarding instead" -- any exception from onboardingStatus() was
    // previously treated identically (context.go('/kyc')), including a
    // plain network timeout or a 5xx from Render's free tier cold-starting
    // (the exact scenario already confirmed and fixed once this session
    // for _refreshToken()). A driver with a perfectly valid, active
    // session reopening the app while the backend is briefly slow was
    // being sent straight to the onboarding screen, looking exactly like
    // they needed to register again.
    //
    // Startup must preserve a valid persisted session across transient
    // network/backend failures. The backend now reports a missing driver
    // profile explicitly instead of collapsing that onboarding state into
    // an INTERNAL_ERROR, so technical failures remain retryable here.
    WidgetsBinding.instance.addPostFrameCallback((_)=>_restoreSession());
  }

  @override void dispose(){
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _restoreSession()async{
    String? accessToken;
    String? refreshToken;
    try{
      accessToken=await api.storage.read(key:'accessToken');
      refreshToken=await api.storage.read(key:'refreshToken');
    }catch(_){
      return;
    }
    // A refresh token is itself a valid persisted session. Requiring an
    // access token here stranded users after an interrupted token rotation
    // even though the Dio interceptor can transparently refresh them.
    final hasSession=(accessToken!=null&&accessToken.isNotEmpty)||
        (refreshToken!=null&&refreshToken.isNotEmpty);
    if(!hasSession||!mounted)return;
    setState((){startupChecking=true;startupRetryAvailable=false;});
    try{
      final status=await api.onboardingStatus();
      if(!mounted)return;
      final approved=status['kyc_status']=='APPROVED'&&status['marketplace_enabled']==true;
      context.go(approved?'/home':'/kyc');
      if(approved){await resumeActiveBooking();await configureDriverPush();}
    }on DioException catch(e){
      if(!mounted)return;
      if(e.response?.statusCode==401||e.response?.statusCode==403){
        // The token itself was genuinely rejected (this app's own
        // interceptor already tried a silent refresh before this
        // surfaces) -- a real, expired/invalid session, not a technical
        // hiccup. Clear it and let the person log in again explicitly.
        try{await api.storage.deleteAll();}catch(_){}
        setState((){startupChecking=false;startupRetryAvailable=false;});
        return;
      }
      // Any other failure (timeout, connection error, 5xx, or the
      // no-profile-yet case this backend endpoint can't currently
      // distinguish from a real error) -- session stays untouched,
      // offer a retry instead of guessing.
      setState((){startupChecking=false;startupRetryAvailable=true;});
    }catch(_){
      if(!mounted)return;
      setState((){startupChecking=false;startupRetryAvailable=true;});
    }
  }

  Future<void> submit()async{
    setState((){loading=true;error=null;offline=false;});
    try{
      await api.login(email.text,password.text);
      await api.createProfile();
      if(!mounted)return;
      // Do not reinterpret a timeout/5xx while loading onboarding status as
      // "the driver needs KYC". Let the outer error handling preserve the
      // authenticated session and present the technical failure instead.
      final status=await api.onboardingStatus();
      if(!mounted)return;
      final approved=status['kyc_status']=='APPROVED'&&status['marketplace_enabled']==true;
      context.go(approved?'/home':'/kyc');
      await configureDriverPush();
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

  Future<void> _finishFirebase(UserCredential credential) async {
    final token=await credential.user?.getIdToken();
    if(token==null||token.isEmpty)throw StateError('FIREBASE_ID_TOKEN_MISSING');
    await api.loginWithFirebase(token);
    // Firebase login on the driver app provisions a minimal driver row in
    // the backend. The onboarding flow then remains the single source of
    // truth for KYC/vehicle eligibility.
    final status=await api.onboardingStatus();
    if(!mounted)return;
    final approved=status['kyc_status']=='APPROVED'&&status['marketplace_enabled']==true;
    context.go(approved?'/home':'/kyc');
    await configureDriverPush();
  }

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
      await _finishFirebase(
        await FirebaseAuth.instance.signInWithCredential(credential),
      );
    }catch(e){
      debugPrint('GOOGLE_LOGIN_FAILED: $e');
      if(mounted)setState(()=>error=e is DioException?VeyraErrorMessages.forException(e):t('Connexion Google impossible. Vérifiez la configuration Firebase et réessayez.'));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  /// Owner decision 20/10/2026: « Continuer avec Apple » (boards 08 A1/B1),
  /// through Firebase's Apple provider and the same /auth/firebase endpoint.
  Future<void> _appleLogin() async {
    setState((){loading=true;error=null;offline=false;});
    try{
      if(Firebase.apps.isEmpty)await Firebase.initializeApp();
      final provider=AppleAuthProvider()..addScope('email')..addScope('name');
      await _finishFirebase(await FirebaseAuth.instance.signInWithProvider(provider));
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

  Future<String?> _askPhone() async {
    final controller=TextEditingController(text:'+33');
    final result=await showDialog<String>(
      context:context,
      builder:(dialogContext)=>AlertDialog(
        title:Text(t('Connexion par téléphone')),
        content:TextField(
          controller:controller,
          keyboardType:TextInputType.phone,
          autofocus:true,
          decoration:InputDecoration(
            labelText:t('Numéro de téléphone'),
            hintText:'+33 6 12 34 56 78',
          ),
        ),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext),child:Text(t('Annuler'))),
          FilledButton(style:FilledButton.styleFrom(minimumSize:const Size(0,52)),
            onPressed:()=>Navigator.pop(dialogContext,controller.text.trim()),
            child:Text(t('Envoyer le code')),
          ),
        ],
      ),
    );
    // Pas de controller.dispose() ici : le TextField est encore monté pendant
    // l'animation de fermeture du dialogue (assertion '_dependents.isEmpty').
    // Le controller n'a aucune ressource native, le GC suffit.
    return result;
  }

  Future<String?> _askSmsCode() async {
    final controller=TextEditingController();
    final result=await showDialog<String>(
      context:context,
      barrierDismissible:false,
      builder:(dialogContext)=>AlertDialog(
        title:Text(t('Code SMS')),
        content:TextField(
          controller:controller,
          keyboardType:TextInputType.number,
          autofocus:true,
          maxLength:6,
          decoration:InputDecoration(labelText:t('Code à 6 chiffres')),
        ),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext),child:Text(t('Annuler'))),
          FilledButton(style:FilledButton.styleFrom(minimumSize:const Size(0,52)),
            onPressed:()=>Navigator.pop(dialogContext,controller.text.trim()),
            child:Text(t('Valider')),
          ),
        ],
      ),
    );
    // Pas de controller.dispose() ici : le TextField est encore monté pendant
    // l'animation de fermeture du dialogue (assertion '_dependents.isEmpty').
    // Le controller n'a aucune ressource native, le GC suffit.
    return result;
  }

  Future<void> _phoneLogin() async {
    final phone=await _askPhone();
    if(phone==null||phone.isEmpty)return;
    setState((){loading=true;error=null;offline=false;});
    try{
      if(Firebase.apps.isEmpty)await Firebase.initializeApp();
      final completer=Completer<void>();
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber:phone,
        verificationCompleted:(credential)async{
          if(completer.isCompleted)return;
          try{
            await _finishFirebase(
              await FirebaseAuth.instance.signInWithCredential(credential),
            );
            completer.complete();
          }catch(e){
            completer.completeError(e);
          }
        },
        verificationFailed:(e){
          if(!completer.isCompleted)completer.completeError(e);
        },
        codeSent:(verificationId,_)async{
          if(completer.isCompleted)return;
          final code=await _askSmsCode();
          if(code==null||code.isEmpty){
            completer.complete();
            return;
          }
          try{
            final credential=PhoneAuthProvider.credential(
              verificationId:verificationId,
              smsCode:code,
            );
            await _finishFirebase(
              await FirebaseAuth.instance.signInWithCredential(credential),
            );
            if(!completer.isCompleted)completer.complete();
          }catch(e){
            if(!completer.isCompleted)completer.completeError(e);
          }
        },
        codeAutoRetrievalTimeout:(_){
          if(!completer.isCompleted)completer.complete();
        },
      );
      await completer.future;
    }catch(e){
      debugPrint('PHONE_LOGIN_FAILED: $e');
      if(mounted)setState(()=>error=e is DioException?VeyraErrorMessages.forException(e):t('Connexion par téléphone impossible. Vérifiez le numéro ou le code SMS.'));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }


  /// Board 08 B1 shows the welcome actions; « Se connecter » opens the
  /// sign-in form (e-mail, phone) on the same screen.
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

  Widget orDivider()=>Row(children:[
    const Expanded(child:Divider()),
    Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Text(t('OU'),style:const TextStyle(color:VeyraColors.textSecondary,fontWeight:FontWeight.w600))),
    const Expanded(child:Divider()),
  ]);

  List<Widget> sessionState()=>[
    if(startupChecking)Padding(padding:const EdgeInsets.only(bottom:12),child:Row(children:[
      const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)),
      const SizedBox(width:12),
      Expanded(child:Text(t('Restauration de votre session…'),style:const TextStyle(color:VeyraColors.textSecondary))),
    ])),
    if(startupRetryAvailable)Card(
      color:VeyraColors.warningBackground,
      margin:const EdgeInsets.only(bottom:12),
      child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(t('Connexion impossible'),style:const TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:4),
        Text(t('Votre session est conservée.'),style:const TextStyle(color:VeyraColors.textSecondary)),
        const SizedBox(height:12),
        OutlinedButton(onPressed:_restoreSession,child:Text(t('Réessayer'))),
      ])),
    ),
  ];

  List<Widget> welcomeActions()=>[
    ...sessionState(),
    FilledButton(onPressed:loading?null:()=>context.push('/register'),child:Text(t('Créer un compte chauffeur'))),
    const SizedBox(height:12),
    FilledButton(
      style:FilledButton.styleFrom(backgroundColor:VeyraColors.infoBackground,foregroundColor:VeyraColors.primary),
      onPressed:loading?null:()=>setState(()=>showForm=true),
      child:Text(t('Se connecter')),
    ),
    const SizedBox(height:16),
    orDivider(),
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
    ...sessionState(),
    Text(t('E-mail'),style:const TextStyle(fontWeight:FontWeight.w600)),
    const SizedBox(height:6),
    TextField(controller:email,keyboardType:TextInputType.emailAddress,autofillHints:const [AutofillHints.email],decoration:const InputDecoration(hintText:'nom@exemple.fr')),
    const SizedBox(height:14),
    Text(t('Mot de passe'),style:const TextStyle(fontWeight:FontWeight.w600)),
    const SizedBox(height:6),
    TextField(controller:password,obscureText:true,autofillHints:const [AutofillHints.password]),
    Align(alignment:Alignment.centerRight,child:TextButton(onPressed:()=>context.push('/forgot'),child:Text(t('Mot de passe oublié ?')))),
    if(offline)Padding(padding:const EdgeInsets.only(bottom:12),child:VeyraOfflineBanner(onRetry:submit)),
    if(error!=null)Padding(padding:const EdgeInsets.only(bottom:12),child:Text(error!,style:const TextStyle(color:VeyraColors.danger))),
    VeyraPrimaryButton(label:t('Se connecter'),loading:loading,onPressed:submit),
    const SizedBox(height:16),
    orDivider(),
    const SizedBox(height:16),
    // Firebase phone sign-in (DEC-07) stays available for drivers.
    socialButton(t('Continuer avec le téléphone'),const Icon(Icons.phone_android_rounded),loading?null:_phoneLogin),
  ];

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:VeyraColors.primary,
    body:Column(children:[
      // Photo hero (board 08 B1): wordmark, « Rejoignez VEYRA », languages.
      Expanded(child:Stack(clipBehavior:Clip.none,children:[
        Positioned(left:0,right:0,top:0,bottom:-28,child:VeyraWelcomeHero(
          asset:VeyraAssets.welcomeDriver,
          title:t('Rejoignez VEYRA'),
          titleAtBottom:true,
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

/// Gap complet trouvé côté chauffeur : ni la demande ("mot de passe
/// oublié") ni la complétion du flow n'existaient -- aucun lien depuis
/// l'écran de connexion, alors que le backend (PasswordController)
/// expose les deux endpoints et fonctionne déjà côté client depuis le
/// début de session.
class ForgotPasswordScreen extends StatefulWidget{
  const ForgotPasswordScreen({super.key});
  @override State<ForgotPasswordScreen> createState()=>_ForgotPasswordScreenState();
}
class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>{
  final email=TextEditingController();
  bool loading=false;
  String? message;

  @override void dispose(){
    email.dispose();
    super.dispose();
  }

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
      TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:InputDecoration(labelText:t('Email'),prefixIcon:const Icon(Icons.mail_outline),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none))),
      const SizedBox(height:16),
      VeyraPrimaryButton(label:t('Envoyer les instructions'),loading:loading,onPressed:submit),
      if(message!=null)Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Text(message!)),
      const SizedBox(height:8),
      TextButton(
        onPressed:()=>context.push('/reset-password'),
        child:Text(t('J’ai déjà un code de réinitialisation')),
      ),
    ])),
  );
}

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

  @override void dispose(){
    token.dispose();
    newPassword.dispose();
    super.dispose();
  }

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
        TextField(controller:token,decoration:InputDecoration(labelText:t('Code reçu par e-mail'),prefixIcon:const Icon(Icons.vpn_key_outlined),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none))),
        const SizedBox(height:16),
        TextField(controller:newPassword,obscureText:true,decoration:InputDecoration(labelText:t('Nouveau mot de passe'),helperText:t('10 caractères minimum'),prefixIcon:const Icon(Icons.lock_outline),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none))),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
        const SizedBox(height:16),
        VeyraPrimaryButton(label:t('Réinitialiser'),loading:loading,onPressed:submit),
      ],
    ])),
  );
}

class KycScreen extends StatefulWidget{
  const KycScreen({super.key});
  @override State<KycScreen> createState()=>_KycScreenState();
}
class _KycScreenState extends State<KycScreen>{
  late Future<Map<String,dynamic>> future;
  late Future<List<dynamic>> categories;

  final legalName=TextEditingController();
  final siren=TextEditingController();
  final siret=TextEditingController();
  final registrationNumber=TextEditingController();
  final cardNumber=TextEditingController();
  final brand=TextEditingController();
  final model=TextEditingController();
  final year=TextEditingController(text:DateTime.now().year.toString());
  final plate=TextEditingController();
  final color=TextEditingController();

  String? categoryId;
  String? uploadingType;
  String? message;
  bool saving=false;
  bool prefilled=false;
  bool hasVehicle=false;

  @override void initState(){
    super.initState();
    future=loadDossier();
    categories=api.vehicleCategories();
  }

  Future<Map<String,dynamic>> loadDossier()async{
    final result=await api.onboardingStatus();
    if(!prefilled&&mounted){
      final companies=(result['company'] as List? ??[]).whereType<Map>();
      final registrations=(result['registration'] as List? ??[]).whereType<Map>();
      if(companies.isNotEmpty){final c=companies.first;legalName.text=(c['legal_name']??'').toString();siren.text=(c['siren']??'').toString();siret.text=(c['siret']??'').toString();}
      if(registrations.isNotEmpty){final c=registrations.first;registrationNumber.text=(c['registration_number']??'').toString();cardNumber.text=(c['card_number']??'').toString();}
      final vehicles=(result['vehicles'] as List? ??[]).whereType<Map>();
      if(vehicles.isNotEmpty){final v=vehicles.first;hasVehicle=true;categoryId=v['category_id']?.toString();brand.text=v['brand'].toString();model.text=v['model'].toString();year.text=v['year'].toString();plate.text=v['plate_number'].toString();color.text=(v['color']??'').toString();}
      prefilled=true;
    }
    return result;
  }
  @override void dispose(){
    for(final controller in [legalName,siren,siret,registrationNumber,cardNumber,brand,model,year,plate,color]){
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> saveProfessionalData()async{
    if(saving)return;
    if(legalName.text.trim().isEmpty||registrationNumber.text.trim().isEmpty||
       cardNumber.text.trim().isEmpty||brand.text.trim().isEmpty||
       model.text.trim().isEmpty||plate.text.trim().isEmpty||categoryId==null){
      setState(()=>message=t('Complétez les informations professionnelles et le véhicule.'));
      return;
    }
    final parsedYear=int.tryParse(year.text);
    if(parsedYear==null){
      setState(()=>message=t('Année du véhicule invalide.'));
      return;
    }
    setState((){saving=true;message=null;});
    try{
      await api.saveCompany(
        legalName:legalName.text.trim(),
        siren:siren.text.trim().isEmpty?null:siren.text.trim(),
        siret:siret.text.trim().isEmpty?null:siret.text.trim(),
      );
      await api.saveVtc(
        registrationNumber:registrationNumber.text.trim(),
        cardNumber:cardNumber.text.trim(),
      );
      if(!hasVehicle){await api.addVehicle(
        categoryId:categoryId!,
        brand:brand.text.trim(),
        model:model.text.trim(),
        year:parsedYear,
        plateNumber:plate.text.trim(),
        color:color.text.trim(),
      );
      hasVehicle=true;}
      if(mounted)setState((){message=t('Informations professionnelles enregistrées.');future=loadDossier();});
    }catch(e){
      if(mounted)setState(()=>message=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>saving=false);
    }
  }

  Future<void> upload(String type)async{
    if(uploadingType!=null)return;
    final result=await FilePicker.platform.pickFiles(
      type:FileType.custom,
      allowedExtensions:['pdf','jpg','jpeg','png'],
    );
    if(result==null||result.files.single.path==null)return;
    setState((){uploadingType=type;message=null;});
    try{
      await api.uploadDocument(type,result.files.single.path!);
      if(mounted)setState((){
        message=t('Document envoyé. Il sera vérifié par Veyra.');
        future=api.onboardingStatus();
      });
    }catch(e){
      if(mounted)setState(()=>message=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>uploadingType=null);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Statut du compte'))),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState((){future=loadDossier();}));
        final status=s.data??{};
        // A dossier never submitted is completed in the sign-up wizard
        // (board 08 B); this screen shows the review status afterwards.
        if(status['kyc_status']=='DRAFT'){
          WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)context.go('/onboarding');});
          return const Center(child:CircularProgressIndicator());
        }
        final approved=status['kyc_status']=='APPROVED'&&status['marketplace_enabled']==true&&
          (status['vehicles'] as List? ??[]).whereType<Map>().any((v)=>v['status']=='APPROVED');

        final kycStatus=status['kyc_status']?.toString();
        final rejected=kycStatus=='REJECTED';
        // Board 08 C8 « Statut du compte »: icon, state, explanation.
        final (statusIcon,statusFg,statusBg)=approved
          ?(Icons.verified_rounded,VeyraColors.success,VeyraColors.successBackground)
          :rejected
            ?(Icons.error_outline,VeyraColors.danger,VeyraColors.dangerBackground)
            :(Icons.hourglass_top_rounded,VeyraColors.accent,VeyraColors.infoBackground);
        return ListView(padding:const EdgeInsets.all(20),children:[
          Container(
            padding:const EdgeInsets.all(20),
            decoration:BoxDecoration(color:statusBg,borderRadius:BorderRadius.circular(VeyraRadius.card)),
            child:Column(children:[
              Icon(statusIcon,size:52,color:statusFg),
              const SizedBox(height:10),
              Text(
                approved?t('Dossier validé'):rejected?t('Corrections demandées'):t('Dossier en cours de vérification'),
                textAlign:TextAlign.center,
                style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800),
              ),
              const SizedBox(height:6),
              Text(t('Statut du dossier')+' : '+VeyraStatusLabels.kycStatus(kycStatus),textAlign:TextAlign.center,style:const TextStyle(color:VeyraColors.textSecondary)),
              const SizedBox(height:6),
              Text(
                approved
                  ?t('Vous pouvez recevoir des demandes et proposer vos offres.')
                  :rejected
                    ?t('Remplacez les documents refusés ci-dessous, votre dossier repartira en vérification.')
                    :t('Nous vous informerons par e-mail et par notification dès que votre dossier sera validé.'),
                textAlign:TextAlign.center,
              ),
            ]),
          ),
          const SizedBox(height:12),
          if(!approved)Text(t('L’accès aux demandes nécessite un dossier et un véhicule approuvés. Complétez les informations et remplacez les documents refusés.'),style:const TextStyle(color:VeyraColors.textSecondary)),
          for(final v in (status['vehicles'] as List? ??[]).whereType<Map>())Card(child:ListTile(title:Text([v['brand'],v['model'],v['plate_number']].join(' • ')),subtitle:Text([v['color'],v['category_name'],v['status']=='APPROVED'?t('Véhicule validé'):t('Véhicule en attente de validation')].where((x)=>x!=null).join(' • ')))),
          if(hasVehicle)Text(t('Véhicule enregistré. Contactez le support pour modifier un véhicule soumis à validation.')),
          const SizedBox(height:16),
          const Text('Informations professionnelles',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          TextField(controller:legalName,decoration:InputDecoration(labelText:t('Raison sociale'))),
          TextField(controller:siren,decoration:const InputDecoration(labelText:'SIREN')),
          TextField(controller:siret,decoration:const InputDecoration(labelText:'SIRET')),
          TextField(controller:registrationNumber,decoration:InputDecoration(labelText:t('N° inscription registre VTC'))),
          TextField(controller:cardNumber,decoration:InputDecoration(labelText:t('N° carte professionnelle VTC'))),
          const SizedBox(height:12),
          const Text('Véhicule',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          FutureBuilder<List<dynamic>>(
            future:categories,
            builder:(context,cs){
              if(cs.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
              if(cs.hasError)return VeyraErrorView(customMessage:VeyraErrorMessages.forException(cs.error!),onRetry:()=>setState((){categories=api.vehicleCategories();}));
              final items=cs.data??[];
              return DropdownButtonFormField<String>(
                initialValue:items.any((raw)=>(raw as Map)['id'].toString()==categoryId)?categoryId:null,
                isExpanded:true,
                decoration:InputDecoration(labelText:t('Catégorie')),
                items:items.map((raw){
                  final x=Map<String,dynamic>.from(raw as Map);
                  return DropdownMenuItem<String>(
                    value:x['id'].toString(),
                    child:Text((x['display_name']??x['code']).toString()),
                  );
                }).toList(),
                onChanged:hasVehicle?null:(v)=>setState(()=>categoryId=v),
              );
            },
          ),
          TextField(enabled:!hasVehicle,controller:brand,decoration:InputDecoration(labelText:t('Marque'))),
          TextField(enabled:!hasVehicle,controller:model,decoration:InputDecoration(labelText:t('Modèle'))),
          TextField(enabled:!hasVehicle,controller:year,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t('Année'))),
          TextField(enabled:!hasVehicle,controller:plate,decoration:InputDecoration(labelText:t('Immatriculation'))),
          TextField(enabled:!hasVehicle,controller:color,decoration:InputDecoration(labelText:t('Couleur'))),
          const SizedBox(height:12),
          FilledButton(onPressed:saving?null:saveProfessionalData,child:Text(saving?t('Enregistrement…'):t('Enregistrer les informations'))),
          const SizedBox(height:24),
          const Text('Documents obligatoires',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          for(final item in const [
            ('IDENTITY','Pièce d’identité'),
            ('VTC_CARD','Carte professionnelle VTC'),
            ('DRIVING_LICENSE','Permis de conduire'),
            ('INSURANCE','Assurance professionnelle / véhicule'),
            ('VEHICLE_REGISTRATION','Carte grise du véhicule'),
          ])Builder(builder:(context){
            final docs=(status['documents'] as List? ?? const []).whereType<Map>().where((d)=>d['type']?.toString()==item.$1).toList();
            final doc=docs.isEmpty?null:docs.first;
            final docStatus=doc?['status']?.toString();
            final rejected=docStatus=='REJECTED';
            final reason=doc?['rejection_reason_code']?.toString();
            final sentAt=doc?['created_at'];
            return Card(child:ListTile(
              leading:Icon(docStatus=='APPROVED'?Icons.verified_outlined:rejected?Icons.error_outline:docStatus==null?Icons.description_outlined:Icons.schedule_outlined),
              title:Text(item.$2),
              subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(docStatus==null?t('À compléter'):docStatus=='APPROVED'?t('Validé'):rejected?t('Refusé'):t('En vérification')),
                if(sentAt!=null)Text(t('Envoyé le')+' '+VeyraDateFormatter.dateTime(sentAt),style:const TextStyle(fontSize:12)),
                if(rejected&&reason!=null)Text(t('Motif')+' : '+reason,style:TextStyle(color:Theme.of(context).colorScheme.error)),
                if(docStatus==null)Text(t('PDF, JPG ou PNG — 10 Mo max'),style:const TextStyle(fontSize:12)),
              ]),
              trailing:uploadingType==item.$1
                ?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2))
                :IconButton(onPressed:uploadingType!=null?null:()=>upload(item.$1),tooltip:t(rejected?'Remplacer':'Téléverser'),icon:Icon(rejected?Icons.refresh:Icons.upload_file)),
            ));
          }),
          if(message!=null)Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Text(message!)),
          if(approved)FilledButton(onPressed:()=>context.go('/home'),child:Text(t('Accéder aux demandes'))),
          if(!approved)Text(
            t('Après envoi, l’équipe Veyra vérifie le dossier avant d’activer l’accès aux demandes.'),
            textAlign:TextAlign.center,
          ),
        ]);
      },
    ),
  );
}

class OpportunitiesScreen extends StatefulWidget{
  const OpportunitiesScreen({super.key});
  @override State<OpportunitiesScreen> createState()=>_OpportunitiesScreenState();
}
class _OpportunitiesScreenState extends State<OpportunitiesScreen> with RouteAware{
  String sort='date';
  String? categoryId;
  DateTimeRange? dates;
  late Future<List<dynamic>> categories;
  int page=0;
  int revision=0;
  late Future<Position?> listPosition;
  Future<Position?> locate()async{
    try{
      final permission=await Geolocator.checkPermission();
      if(permission!=LocationPermission.always&&permission!=LocationPermission.whileInUse)return null;
      return await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:10)));
    }catch(_){return null;}
  }
  final pickupFilter=TextEditingController();
  final destinationFilter=TextEditingController();
  int? minPassengers;
  late Future<List<dynamic>> future;

  @override void initState(){
    super.initState();
    future=load();
    categories=api.vehicleCategories();
    // The collapsed filters do not mount their FutureBuilder immediately.
    // Handle early failures without changing the future's error for that UI.
    categories.ignore();
    RefreshBus.tick.addListener(reload);
  }
  // Even risk, same fix as mobile-client's AccueilScreen/HomeScreen
  // (137f30f "prevent blank booking navigation screen"): subscribing
  // this ModalRoute to the root RouteObserver is unsafe inside a
  // StatefulShellRoute -- the shell's nested navigator can expose a
  // route type/lifecycle that is not the root PageRoute, and the
  // `as PageRoute` cast throws a synchronous exception that leaves this
  // branch with a blank body on a real device, invisible to
  // flutter analyze/tests since mocked widget tests never exercise the
  // real shell's nested Navigator. RefreshBus (already wired above) is
  // the explicit cross-navigator refresh mechanism used after
  // submitting/withdrawing an offer, so keep this screen's lifecycle
  // independent from the root observer.
  @override void dispose(){
    RefreshBus.tick.removeListener(reload);
    pickupFilter.dispose();
    destinationFilter.dispose();
    super.dispose();
  }
  Future<List<dynamic>> load(){revision++;listPosition=locate();return api.opportunities(
    page:page,
    sort:sort,
    pickupQuery:pickupFilter.text,
    destinationQuery:destinationFilter.text,
    minPassengers:minPassengers,
    categoryId:categoryId,
    from:dates?.start,
    to:dates==null?null:dates!.end.add(const Duration(days:1)).subtract(const Duration(microseconds:1)),
  );}
  void reload()=>setState((){future=load();});

  // Fail-safe: an unknown availability is shown as online.
  late Future<bool> online=safeAvailability();
  Future<bool> safeAvailability()=>api.availability().catchError((_)=>true);
  bool goingOnline=false;

  bool get filtered=>pickupFilter.text.trim().isNotEmpty||destinationFilter.text.trim().isNotEmpty||minPassengers!=null||categoryId!=null||dates!=null;

  void resetFilters(){
    pickupFilter.clear();
    destinationFilter.clear();
    setState((){minPassengers=null;sort='date';categoryId=null;dates=null;page=0;future=load();});
  }

  Future<void> goOnline()async{
    setState(()=>goingOnline=true);
    try{await api.setAvailability(true);if(mounted)setState((){online=Future.value(true);page=0;future=load();});}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));}
    finally{if(mounted)setState(()=>goingOnline=false);}
  }

  /// « Filtrer » (planche 13 P2) : tri et filtres dans une feuille.
  Future<void> openFilters()async{
    await showModalBottomSheet<void>(
      context:context,
      isScrollControlled:true,
      showDragHandle:true,
      builder:(sheet)=>StatefulBuilder(builder:(sheet,setSheet){
        void update(VoidCallback f){setState(f);setSheet((){});}
        return Padding(
          padding:EdgeInsets.fromLTRB(20,0,20,20+MediaQuery.viewInsetsOf(sheet).bottom),
          child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
            Text(t('Filtrer les demandes'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
            const SizedBox(height:14),
            DropdownButtonFormField<String>(
              key:ValueKey('sort-$sort'),
              isExpanded:true,
              initialValue:sort,
              decoration:InputDecoration(labelText:t('Trier les demandes')),
              items:[
                DropdownMenuItem(value:'date',child:Text(t('Date de départ'))),
                DropdownMenuItem(value:'newest',child:Text(t('Plus récentes'))),
                DropdownMenuItem(value:'pickup',child:Text(t('Lieu de départ (A → Z)'))),
                DropdownMenuItem(value:'destination',child:Text(t('Destination (A → Z)'))),
              ],
              onChanged:(v){if(v!=null)update(()=>sort=v);},
            ),
            const SizedBox(height:10),
            FutureBuilder<List<dynamic>>(future:categories,builder:(context,s){
              if(s.hasError)return TextButton(onPressed:()=>update((){categories=api.vehicleCategories();}),child:Text(t('Réessayer le chargement des catégories')));
              if(!s.hasData)return const LinearProgressIndicator();
              return DropdownButtonFormField<String>(key:ValueKey('cat-$categoryId'),initialValue:categoryId,isExpanded:true,
                decoration:InputDecoration(labelText:t('Catégorie')),
                items:[DropdownMenuItem<String>(value:null,child:Text(t('Toutes'))),...(s.data??[]).map((x)=>DropdownMenuItem<String>(value:x['id'].toString(),child:Text(x['display_name'].toString())))],
                onChanged:(v)=>update(()=>categoryId=v));
            }),
            const SizedBox(height:10),
            OutlinedButton.icon(icon:const Icon(Icons.date_range),label:Text(dates==null?t('Toutes les dates'):VeyraDateFormatter.dateTime(dates!.start.toIso8601String())+' – '+VeyraDateFormatter.dateTime(dates!.end.toIso8601String())),onPressed:()async{
              final chosen=await showDateRangePicker(context:context,firstDate:DateTime.now().subtract(const Duration(days:1)),lastDate:DateTime.now().add(const Duration(days:730)),initialDateRange:dates);
              if(chosen!=null&&mounted)update(()=>dates=chosen);
            }),
            const SizedBox(height:10),
            TextField(controller:pickupFilter,decoration:InputDecoration(labelText:t('Lieu de départ contient'))),
            const SizedBox(height:8),
            TextField(controller:destinationFilter,decoration:InputDecoration(labelText:t('Destination contient'))),
            const SizedBox(height:8),
            DropdownButtonFormField<int?>(
              key:ValueKey('pax-$minPassengers'),
              initialValue:minPassengers,
              decoration:InputDecoration(labelText:t('Minimum passagers')),
              items:[DropdownMenuItem<int?>(value:null,child:Text(t('Tous'))), ...List.generate(8,(i)=>DropdownMenuItem<int?>(value:i+1,child:Text('${i+1}+')))],
              onChanged:(v)=>update(()=>minPassengers=v),
            ),
            const SizedBox(height:16),
            Row(children:[
              Expanded(child:OutlinedButton(onPressed:(){Navigator.pop(sheet);resetFilters();},child:Text(t('Réinitialiser')))),
              const SizedBox(width:10),
              Expanded(child:FilledButton(onPressed:(){Navigator.pop(sheet);setState((){page=0;future=load();});},child:Text(t('Appliquer')))),
            ]),
          ])),
        );
      }),
    );
  }

  Widget emptyState(){
    return FutureBuilder<bool>(future:online,builder:(context,o){
      if(o.data==false){
        return DriverCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[
            const Icon(Icons.pause_circle_filled,color:VeyraColors.neutral),
            const SizedBox(width:10),
            Expanded(child:Text(t('Vous êtes hors ligne'),style:const TextStyle(fontWeight:FontWeight.w800))),
          ]),
          const SizedBox(height:6),
          Text(t('Passez en ligne pour recevoir les nouvelles demandes de trajet.'),style:const TextStyle(color:VeyraColors.textSecondary)),
          const SizedBox(height:12),
          FilledButton(onPressed:goingOnline?null:goOnline,child:Text(t('Passer en ligne'))),
        ]));
      }
      return DriverCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          const Icon(Icons.inbox_outlined,color:VeyraColors.textSecondary),
          const SizedBox(width:10),
          Expanded(child:Text(filtered?t('Aucune demande ne correspond aux filtres.'):t('Aucune demande ouverte'),style:const TextStyle(fontWeight:FontWeight.w800))),
        ]),
        const SizedBox(height:6),
        Text(filtered?t('Modifiez ou réinitialisez les filtres pour élargir la recherche.'):t('Les nouvelles demandes apparaîtront ici.'),style:const TextStyle(color:VeyraColors.textSecondary)),
        if(filtered)Align(alignment:Alignment.centerRight,child:TextButton(onPressed:resetFilters,child:Text(t('Réinitialiser')))),
      ]));
    });
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:Colors.white,
    appBar:DriverTopBar(onNotifications:()=>context.push('/notifications')),
    body:RefreshIndicator(
      onRefresh:()async{final refreshed=load();setState((){future=refreshed;online=safeAvailability();});try{await refreshed;}catch(_){/* FutureBuilder displays the load error. */}},
      child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
        Row(children:[
          Expanded(child:Text(t('Demandes disponibles'),style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800))),
          OutlinedButton.icon(
            onPressed:openFilters,
            style:OutlinedButton.styleFrom(minimumSize:const Size(0,40),foregroundColor:VeyraColors.textPrimary,padding:const EdgeInsets.symmetric(horizontal:12)),
            icon:Badge(isLabelVisible:filtered,smallSize:8,child:const Icon(Icons.tune,size:18)),
            label:Text(t('Filtrer')),
          ),
        ]),
        Align(alignment:Alignment.centerLeft,child:TextButton.icon(
          onPressed:()=>context.push('/driver/offers'),
          icon:const Icon(Icons.local_offer_outlined,size:18),
          label:Text(t('Mes offres')),
        )),
        FutureBuilder<List<dynamic>>(
          future:future,
          builder:(context,s){
            if(s.connectionState!=ConnectionState.done)return const Padding(padding:EdgeInsets.symmetric(vertical:48),child:VeyraLoadingView());
            if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
              ?VeyraOfflineBanner(onRetry:reload)
              :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:reload);
            final items=s.data??[];
            if(items.isEmpty){
              if(page>0)return TextButton(onPressed:()=>setState((){page--;future=load();}),child:Text(t('Page précédente')));
              return emptyState();
            }
            return Column(children:[
              for(final raw in items)Builder(builder:(context){
                final x=Map<String,dynamic>.from(raw as Map);
                final id=x['id'].toString();
                return DriverRequestCard(
                  request:x,
                  onTap:()=>context.push('/request/'+id),
                );
              }),
              VeyraPaginationBar(
                page:page,
                hasNext:items.length==10,
                onPrevious:()=>setState((){page--;future=load();}),
                onNext:()=>setState((){page++;future=load();}),
              ),
            ]);
          },
        ),
      ]),
    ),
  );
}

/// D18 -- "Mes offres" : 3 onglets En attente/Retenues/Closes, consomme
/// GET /api/v1/driver/offers?scope=... (déjà créé et testé en tout début
/// de session -- l'endpoint existait, mais aucun écran ne l'appelait,
/// c'est ce gap précis que cet écran comble).
class MesOffresScreen extends StatefulWidget{
  const MesOffresScreen({super.key});
  @override State<MesOffresScreen> createState()=>_MesOffresScreenState();
}
class _MesOffresScreenState extends State<MesOffresScreen> with SingleTickerProviderStateMixin{
  late TabController tabController;
  late Future<List<dynamic>> active;
  late Future<List<dynamic>> won;
  late Future<List<dynamic>> closed;
  int activePage=0;
  int wonPage=0;
  int closedPage=0;
  final Set<String> withdrawingOffers={};

  @override void initState(){
    super.initState();
    tabController=TabController(length:3,vsync:this);
    _load();
    RefreshBus.tick.addListener(refreshOffers);
  }

  void refreshOffers(){if(mounted)setState(_load);}

  void _load(){
    active=api.driverOffers(scope:'active',page:activePage);
    won=api.driverOffers(scope:'won',page:wonPage);
    closed=api.driverOffers(scope:'closed',page:closedPage);
    active.ignore();won.ignore();closed.ignore();
  }

  void _changePage(String scope,int delta){
    setState((){
      if(scope=='active')activePage=(activePage+delta).clamp(0,1<<30).toInt();
      if(scope=='won')wonPage=(wonPage+delta).clamp(0,1<<30).toInt();
      if(scope=='closed')closedPage=(closedPage+delta).clamp(0,1<<30).toInt();
      _load();
    });
  }

  @override void dispose(){
    RefreshBus.tick.removeListener(refreshOffers);
    tabController.dispose();
    super.dispose();
  }

  Widget _list(
    Future<List<dynamic>> future,{
    required bool isWon,
    required String scope,
    required int page,
  }){
    return RefreshIndicator(
      onRefresh:()async{
        late Future<List<dynamic>> refreshed;
        setState((){
          _load();
          refreshed=scope=='active'?active:scope=='won'?won:closed;
        });
        try{await refreshed;}catch(_){/* FutureBuilder displays the load error. */}
      },
      child:FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done){
            return ListView(physics:const AlwaysScrollableScrollPhysics(),children:const [VeyraLoadingView()]);
          }
          if(s.hasError){
            return ListView(physics:const AlwaysScrollableScrollPhysics(),children:[VeyraErrorMessages.isOffline(s.error!)
              ?VeyraOfflineBanner(onRetry:()=>setState(_load))
              :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState(_load))]);
          }
          final items=s.data??[];
          if(items.isEmpty){
              if(page>0)return ListView(physics:const AlwaysScrollableScrollPhysics(),children:[TextButton(onPressed:()=>_changePage(scope,-1),child:Text(t('Page précédente')))]);
            return ListView(physics:const AlwaysScrollableScrollPhysics(),children:[VeyraEmptyView(
              icon:Icons.local_offer_outlined,
              message:t('Aucune offre dans cette catégorie.'),
            )]);
          }
          return ListView.builder(
            physics:const AlwaysScrollableScrollPhysics(),
            padding:const EdgeInsets.all(16),
            itemCount:items.length+1,
            itemBuilder:(context,i){
              if(i==items.length){
                return VeyraPaginationBar(
                  page:page,
                  hasNext:items.length==10,
                  onPrevious:()=>_changePage(scope,-1),
                  onNext:()=>_changePage(scope,1),
                );
              }
              final x=Map<String,dynamic>.from(items[i] as Map);
              final title=(x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString();
              final bookingId=x['booking_id']?.toString();
              final offerId=x['offer_id']?.toString();
              final expires=x['expires_at'];
              final bookingStatus=x['booking_status']?.toString();
              Future<void> withdraw()async{
                if(offerId==null||withdrawingOffers.contains(offerId))return;
                setState(()=>withdrawingOffers.add(offerId));
                try{
                final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(
                  title:Text(t('Retirer cette offre ?')),
                  content:Text(t('Elle ne sera plus proposée au client. Vous pourrez soumettre une nouvelle offre tant que la demande reste ouverte.')),
                  actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:Text(t('Garder mon offre'))),FilledButton(style:FilledButton.styleFrom(minimumSize:const Size(0,52)),onPressed:()=>Navigator.pop(d,true),child:Text(t('Retirer')))],
                ));
                if(ok!=true)return;
                try{await api.withdrawOffer(offerId);if(mounted){setState(_load);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Offre retirée.'))));}}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));}
                }finally{if(mounted)setState(()=>withdrawingOffers.remove(offerId));}
              }
              final status=x['status']?.toString()??'';
              final (pill,fg,bg,icon)=switch(status){
                'ACTIVE'=>(t('En attente'),VeyraColors.warning,VeyraColors.warningBackground,Icons.schedule),
                'ACCEPTED'=>(t('Acceptée'),VeyraColors.success,VeyraColors.successBackground,Icons.check_circle),
                'REJECTED_BY_SELECTION'=>(t('Refusée'),VeyraColors.danger,VeyraColors.dangerBackground,Icons.cancel),
                'EXPIRED'=>(t('Expirée'),VeyraColors.neutral,VeyraColors.neutralBackground,Icons.timer_off_outlined),
                'WITHDRAWN'=>(t('Retirée'),VeyraColors.neutral,VeyraColors.neutralBackground,Icons.undo),
                'SUPERSEDED'=>(t('Prix modifié'),VeyraColors.neutral,VeyraColors.neutralBackground,Icons.edit_outlined),
                _=>(VeyraStatusLabels.offerStatus(status),VeyraColors.neutral,VeyraColors.neutralBackground,Icons.info_outline),
              };
              final vehicle='${x['vehicle_brand']??''} ${x['vehicle_model']??''}'.trim();
              void open(){
                if(bookingId==null)return;
                if(isWon){
                  context.push('/ride/'+bookingId);
                }else if(scope=='active'){
                  context.push('/request/'+bookingId);
                }else{
                  showDialog<void>(context:context,builder:(d)=>AlertDialog(
                    title:Text(t('Détail de mon offre')),
                    content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text(title),Text(VeyraDateFormatter.dateTime(x['scheduled_at'])),
                      Text(VeyraMoneyFormatter.fromMinor(x['proposed_amount_minor'])),
                      Text(pill),
                    ])),
                    actions:[TextButton(onPressed:()=>Navigator.pop(d),child:Text(t('Fermer')))],
                  ));
                }
              }
              Widget priceLine(String label,dynamic minor,{bool ttc=false})=>Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                Flexible(child:Text(label,style:const TextStyle(color:VeyraColors.textSecondary))),
                const SizedBox(width:8),
                Flexible(child:Text.rich(textAlign:TextAlign.end,TextSpan(children:[
                  TextSpan(text:VeyraMoneyFormatter.fromMinor(minor),style:const TextStyle(fontWeight:FontWeight.w700)),
                  if(ttc)const TextSpan(text:' TTC',style:TextStyle(fontSize:11,color:VeyraColors.textSecondary)),
                ]))),
              ]);
              return DriverCard(
                onTap:bookingId==null?null:open,
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Row(children:[
                    Flexible(child:DriverPill(pill,fg:fg,bg:bg,icon:icon)),
                    const SizedBox(width:8),
                    const Spacer(),
                    if(status=='ACTIVE'&&expires!=null)Text(driverStartsIn(expires).replaceFirst(t('Dans')+' ',''),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:12)),
                    const Icon(Icons.chevron_right,color:VeyraColors.textSecondary),
                  ]),
                  const SizedBox(height:8),
                  Text(driverWhen(x['scheduled_at']),style:const TextStyle(color:VeyraColors.textSecondary)),
                  const SizedBox(height:6),
                  DriverMiniRoute((x['pickup_address']??'').toString(),(x['dropoff_address']??'').toString()),
                  const SizedBox(height:6),
                  DriverPaxBags(x['passenger_count'],x['baggage_count']),
                  if(vehicle.isNotEmpty)...[
                    const SizedBox(height:10),
                    Row(children:[
                      const VeyraVehicleThumb(width:72),
                      const SizedBox(width:10),
                      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Text(vehicle,style:const TextStyle(fontWeight:FontWeight.w600)),
                        if(x['vehicle_category']!=null)Text(x['vehicle_category'].toString(),style:const TextStyle(color:VeyraColors.accent,fontSize:13)),
                      ])),
                    ]),
                  ],
                  const SizedBox(height:10),
                  priceLine(t('Votre prix'),x['proposed_amount_minor']),
                  if(x['customer_total_minor']!=null)priceLine(t('Prix client'),x['customer_total_minor'],ttc:true),
                  if(bookingStatus!=null&&bookingStatus.isNotEmpty&&isWon)...[const SizedBox(height:8),VeyraStatusBadge(status:bookingStatus)],
                  if(scope=='active')Padding(padding:const EdgeInsets.only(top:10),child:Row(children:[
                    Expanded(child:OutlinedButton.icon(onPressed:bookingId==null?null:()=>context.push('/request/'+bookingId),icon:const Icon(Icons.edit_outlined),label:Text(t('Modifier')))),
                    const SizedBox(width:8),
                    Expanded(child:TextButton.icon(onPressed:offerId==null||withdrawingOffers.contains(offerId)?null:withdraw,icon:const Icon(Icons.delete_outline),label:Text(t('Retirer')))),
                  ])),
                ]),
              );            },
          );
        },
      ),
    );
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(
      title:Text(t('Mes offres')),
      bottom:TabBar(controller:tabController,tabs:[
        Tab(text:t('En attente')),
        Tab(text:t('Acceptées')),
        Tab(text:t('Refusées')),
      ]),
    ),
    body:TabBarView(controller:tabController,children:[
      _list(active,isWon:false,scope:'active',page:activePage),
      _list(won,isWon:true,scope:'won',page:wonPage),
      _list(closed,isWon:false,scope:'closed',page:closedPage),
    ]),
  );
}


class OpportunityDistanceSummary extends StatefulWidget{
  final Map<String,dynamic> booking;
  final Future<Position?> position;
  const OpportunityDistanceSummary({required this.booking,required this.position,super.key});
  @override State<OpportunityDistanceSummary> createState()=>_OpportunityDistanceSummaryState();
}
class _OpportunityDistanceSummaryState extends State<OpportunityDistanceSummary>{
  Map<String,dynamic>? trip,approach;
  bool loading=true;
  int loadRevision=0;
  @override void initState(){super.initState();load();}
  @override void didUpdateWidget(covariant OpportunityDistanceSummary oldWidget){
    super.didUpdateWidget(oldWidget);
    if(['pickup_lat','pickup_lng','dropoff_lat','dropoff_lng'].any((key)=>oldWidget.booking[key]!=widget.booking[key])||oldWidget.position!=widget.position)load();
  }
  Future<void> load()async{
    final revision=++loadRevision;
    final b=widget.booking;
    final position=widget.position.catchError((_)=>null);
    setState((){trip=null;approach=null;loading=true;});
    final a=(b['pickup_lat'] as num?)?.toDouble(),c=(b['pickup_lng'] as num?)?.toDouble();
    final d=(b['dropoff_lat'] as num?)?.toDouble(),e=(b['dropoff_lng'] as num?)?.toDouble();
    if(a!=null&&c!=null&&d!=null&&e!=null){
      try{final value=await api.routeEstimate(fromLat:a,fromLng:c,toLat:d,toLng:e);if(mounted&&revision==loadRevision)setState(()=>trip=value);}catch(_){}
      final p=await position;
      if(p!=null&&mounted&&revision==loadRevision){try{final value=await api.routeEstimate(fromLat:p.latitude,fromLng:p.longitude,toLat:a,toLng:c);if(mounted&&revision==loadRevision)setState(()=>approach=value);}catch(_){}}
    }
    if(mounted&&revision==loadRevision)setState(()=>loading=false);
  }
  @override Widget build(BuildContext context){
    final tripDistance=trip?['distanceMeters'] as num?,approachDistance=approach?['distanceMeters'] as num?;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(t('Course')+' : '+(tripDistance==null?(loading?t('Calcul en cours…'):t('Itinéraire indisponible')):VeyraMoneyFormatter.distance(tripDistance))+(trip?['durationSeconds']==null?'':' • '+VeyraMoneyFormatter.duration(trip!['durationSeconds'] as num))),
      Text(t('Approche')+' : '+(approachDistance==null?(loading?t('Calcul en cours…'):t('Indisponible — vérifier le GPS')):VeyraMoneyFormatter.distance(approachDistance))),
      if(tripDistance!=null&&approachDistance!=null)Text(t('Distance totale estimée')+' : '+VeyraMoneyFormatter.distance(tripDistance+approachDistance)),
    ]);
  }
}

class RequestScreen extends StatefulWidget{
  final String bookingId;
  const RequestScreen({required this.bookingId,super.key});
  @override State<RequestScreen> createState()=>_RequestScreenState();
}
class _RequestScreenState extends State<RequestScreen>{
  late Future<Map<String,dynamic>> detail;
  Map<String,dynamic>? _tripEconomics;
  bool _tripEconomicsLoading=false;
  // Bug réel : le catch vide de _loadTripEconomics ne signalait rien -- un
  // chauffeur qui tapait "Réessayer le calcul du trajet" voyait un clignotement
  // puis exactement le même état "indisponible", sans savoir pourquoi.
  String? _tripEconomicsError;
  // Idem pour la localisation : Android ne réaffiche jamais le dialogue de
  // permission une fois deniedForever, retaper le bouton ne peut donc jamais
  // fonctionner -- seul un passage par les réglages système débloque.
  bool _approachPermissionDeniedForever=false;
  Map<String,dynamic>? approach;
  String? approachError;
  bool approachLoading=false;
  Future<void> loadApproach({bool requestPermission=false})async{
    if(approachLoading)return;setState((){approachLoading=true;_approachPermissionDeniedForever=false;});
    try{
      if(!await Geolocator.isLocationServiceEnabled())throw StateError('gps');
      var permission=await Geolocator.checkPermission();
      if(permission==LocationPermission.denied&&requestPermission)permission=await Geolocator.requestPermission();
      if(permission==LocationPermission.deniedForever){_approachPermissionDeniedForever=true;throw StateError('permission_forever');}
      if(permission==LocationPermission.denied)throw StateError('permission');
      final position=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:15)));
      final x=await detail;
      final lat=(x['pickup_lat'] as num?)?.toDouble(),lng=(x['pickup_lng'] as num?)?.toDouble();
      if(lat==null||lng==null)throw StateError('coordinates');
      final estimate=await api.routeEstimate(fromLat:position.latitude,fromLng:position.longitude,toLat:lat,toLng:lng);
      if(mounted)setState((){approach=estimate;approachError=null;});
    }catch(e){
      if(mounted)setState((){
        approach=null;
        final cause=e is StateError?e.message:'';
        approachError=cause=='permission_forever'
          ?t('La localisation est bloquée pour cette application. Autorisez-la depuis les réglages du téléphone.')
          :cause=='gps'
            ?t('Le GPS du téléphone est désactivé. Activez-le puis réessayez.')
            :cause=='permission'
              ?t('Autorisation de localisation refusée. Appuyez sur Actualiser ma position pour l’accorder.')
              :cause=='coordinates'
                ?t('Point de départ sans coordonnées, approche impossible à calculer.')
                :t('Approche non calculée pour le moment. Réessayez dans un instant.');
      });
    }
    finally{if(mounted)setState(()=>approachLoading=false);}
  }

  @override void initState(){
    super.initState();
    detail=loadDetail();
  }

  Future<Map<String,dynamic>> loadDetail(){
    final result=api.opportunityDetail(widget.bookingId);
    result.then((x){if(mounted){_loadTripEconomics(x);loadApproach();}}).catchError((_){ });
    return result;
  }
  void retryDetail()=>setState((){detail=loadDetail();});


  Future<void> _loadTripEconomics(Map<String,dynamic>x)async{
    final a=_number(_field(x,'pickup_lat','pickupLat')),b=_number(_field(x,'pickup_lng','pickupLng')),c=_number(_field(x,'dropoff_lat','dropoffLat')),e=_number(_field(x,'dropoff_lng','dropoffLng'));
    if(a==null||b==null||c==null||e==null){
      if(mounted)setState(()=>_tripEconomicsError=t('Coordonnées de départ ou de destination indisponibles pour cette réservation.'));
      return;
    }
    if(mounted)setState((){_tripEconomicsLoading=true;_tripEconomicsError=null;});
    try{
      final r=await api.routeEstimate(fromLat:a,fromLng:b,toLat:c,toLng:e);
      if(mounted)setState((){_tripEconomics=r;_tripEconomicsError=null;});
    }catch(_){
      if(mounted)setState(()=>_tripEconomicsError=t('Calcul du trajet indisponible pour le moment. Réessayez dans un instant.'));
    }finally{
      if(mounted)setState(()=>_tripEconomicsLoading=false);
    }
  }

  dynamic _field(Map<String,dynamic> x,String snake,String camel){
    if(x.containsKey(snake))return x[snake];
    if(x.containsKey(camel))return x[camel];
    final wanted={snake.toLowerCase(),camel.toLowerCase()};
    for(final e in x.entries){if(wanted.contains(e.key.toLowerCase()))return e.value;}
    return null;
  }

  double? _number(dynamic value){
    if(value is num)return value.toDouble();
    if(value==null)return null;
    return double.tryParse(value.toString());
  }

  @override void dispose(){
    super.dispose();
  }

  static (String,String?) splitPlace(String label){
    final i=label.indexOf(',');
    if(i<=0)return (label,null);
    return (label.substring(0,i).trim(),label.substring(i+1).trim());
  }

  Widget section({String? title,required Widget child})=>DriverCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    if(title!=null)...[Text(title,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),const SizedBox(height:10)],
    child,
  ]));

  Widget routeMap(Map<String,dynamic> x){
    final a=_number(_field(x,'pickup_lat','pickupLat')),b=_number(_field(x,'pickup_lng','pickupLng'));
    final c=_number(_field(x,'dropoff_lat','dropoffLat')),e=_number(_field(x,'dropoff_lng','dropoffLng'));
    if(a==null||b==null||c==null||e==null)return const SizedBox.shrink();
    final points=(_tripEconomics?['points'] as List? ??const[]).whereType<Map>()
      .map((p)=>LatLng((p['lat'] as num).toDouble(),(p['lng'] as num).toDouble())).toList();
    final meters=_number(_tripEconomics?['distanceMeters']);
    final seconds=_number(_tripEconomics?['durationSeconds']);
    return Padding(
      padding:const EdgeInsets.only(bottom:14),
      child:ClipRRect(
        borderRadius:BorderRadius.circular(VeyraRadius.card),
        child:Stack(children:[
          VeyraRouteMap(pickup:LatLng(a,b),dropoff:LatLng(c,e),route:points,height:190),
          if(meters!=null&&seconds!=null)Positioned(right:12,bottom:12,child:DriverPill(
            '${VeyraMoneyFormatter.duration(seconds)} · ${VeyraMoneyFormatter.distance(meters)}',
            fg:Colors.white,bg:VeyraColors.accent,
          )),
        ]),
      ),
    );
  }

  /// Distances de course et d'approche (repères, jamais bloquants).
  Widget economics(Map<String,dynamic> x){
    final courseMeters=_number(_tripEconomics?['distanceMeters'])??_number(_field(x,'trip_distance_meters','tripDistanceMeters'));
    final routeSeconds=_number(_tripEconomics?['durationSeconds']);
    final approachMeters=_number(approach?['distanceMeters']);
    return section(title:t('Type de trajet'),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Wrap(spacing:10,runSpacing:8,children:[
        DriverPill(t('Aller simple'),fg:VeyraColors.textPrimary,bg:VeyraColors.surfaceMuted,icon:Icons.swap_calls),
        if(courseMeters!=null)DriverPill('≈ '+VeyraMoneyFormatter.distance(courseMeters)+(routeSeconds==null?'':' · '+VeyraMoneyFormatter.duration(routeSeconds)),fg:VeyraColors.textPrimary,bg:VeyraColors.surfaceMuted,icon:Icons.schedule),
      ]),
      if(_tripEconomicsLoading)const Padding(padding:EdgeInsets.only(top:8),child:LinearProgressIndicator()),
      if(courseMeters!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(t('Distance départ → destination')+' : '+VeyraMoneyFormatter.distance(courseMeters))),
      if(routeSeconds!=null)Text(t('Durée routière estimée')+' : '+VeyraMoneyFormatter.duration(routeSeconds)),
      if(_tripEconomicsError!=null)Padding(padding:const EdgeInsets.only(top:6),child:Text(_tripEconomicsError!,style:const TextStyle(color:VeyraColors.textSecondary))),
      if(courseMeters==null&&!_tripEconomicsLoading)TextButton(onPressed:()=>detail.then(_loadTripEconomics),child:Text(t('Réessayer le calcul du trajet'))),
      const Divider(height:20),
      Text(approachMeters==null?t('Approche non calculée'):t('Distance d’approche')+' : '+VeyraMoneyFormatter.distance(approachMeters),style:const TextStyle(fontWeight:FontWeight.w600)),
      if(approachError!=null)Text(approachError!,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
      if(_approachPermissionDeniedForever)TextButton.icon(onPressed:()=>Geolocator.openAppSettings(),icon:const Icon(Icons.settings),label:Text(t('Ouvrir les réglages'))),
      Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:approachLoading?null:()=>loadApproach(requestPermission:true),icon:const Icon(Icons.my_location),label:Text(approachLoading?t('Localisation…'):t('Actualiser ma position')))),
    ]));
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:Colors.white,
    appBar:AppBar(title:Text(t('Détail de la demande'))),
    body:FutureBuilder<Map<String,dynamic>>(
      future:detail,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const VeyraLoadingView();
        if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
          ?VeyraOfflineBanner(onRetry:retryDetail)
          :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:retryDetail);
        final x=s.data??{};
        final (pTitle,pSub)=splitPlace((x['pickup_address']??'').toString());
        final (dTitle,dSub)=splitPlace((x['dropoff_address']??'').toString());
        final id=(x['id']??widget.bookingId).toString();
        final notes=(x['customer_notes']??'').toString();
        final best=x['currentBestOtherOfferMinor'];
        final own=x['ownActiveOfferAmountMinor'];
        return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
          if(x['customer_favorite']==true)Padding(padding:const EdgeInsets.only(bottom:12),child:VeyraBanner(
            tone:VeyraTone.warning,
            title:t('Vous êtes le chauffeur préféré de ce client'),
            text:t('Ce client vous a ajouté à ses chauffeurs préférés.'),
          )),
          Row(children:[
            Flexible(flex:6,child:DriverPill(x['hasActiveOffer']==true?t('Offre envoyée'):t('Nouvelle demande'),fg:VeyraColors.warning,bg:VeyraColors.warningBackground,icon:Icons.schedule)),
            const SizedBox(width:8),
            const Spacer(),
            Text('#'+(id.length>8?id.substring(0,8):id).toUpperCase(),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:12)),
          ]),
          const SizedBox(height:12),
          if((x['customer_display_name']??'').toString().isNotEmpty)section(child:DriverClientLine(name:x['customer_display_name'].toString(),rating:x['customer_rating'],count:x['customer_rating_count'],radius:26)),
          section(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            VeyraRoutePoints(pickupTitle:pTitle,pickupSubtitle:pSub,dropoffTitle:dTitle,dropoffSubtitle:dSub),
            const SizedBox(height:12),
            Row(children:[
              const Icon(Icons.calendar_today_outlined,size:18),
              const SizedBox(width:8),
              Expanded(child:Text(driverWhen(x['scheduled_at']))),
              DriverPill(driverStartsIn(x['scheduled_at']),fg:VeyraColors.accent,bg:VeyraColors.infoBackground),
            ]),
            const SizedBox(height:8),
            DriverPaxBags(x['passenger_count'],x['baggage_count']),
            if(x['category_name']!=null)...[
              const SizedBox(height:8),
              Row(children:[
                const Icon(Icons.directions_car_outlined,size:18,color:VeyraColors.textSecondary),
                const SizedBox(width:8),
                Expanded(child:Text(t('Type demandé')+' : '+x['category_name'].toString(),style:const TextStyle(color:VeyraColors.textSecondary))),
              ]),
            ],
            if(notes.isNotEmpty)...[
              const SizedBox(height:12),
              Container(
                padding:const EdgeInsets.all(12),
                decoration:BoxDecoration(color:VeyraColors.surfaceMuted,borderRadius:BorderRadius.circular(VeyraRadius.md)),
                child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  const Icon(Icons.chat_outlined,size:18,color:VeyraColors.textSecondary),
                  const SizedBox(width:10),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(t('Commentaire du client'),style:const TextStyle(fontWeight:FontWeight.w700,fontSize:13)),
                    const SizedBox(height:2),
                    Text(notes,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
                  ])),
                ]),
              ),
            ],
          ])),
          routeMap(x),
          economics(x),
          if(best!=null)section(child:Row(children:[
            const Icon(Icons.price_check_outlined,color:VeyraColors.textSecondary),
            const SizedBox(width:10),
            Expanded(child:Text(t('Offre la plus basse'),style:const TextStyle(fontWeight:FontWeight.w600))),
            Text(VeyraMoneyFormatter.fromMinor(best),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:18)),
          ])),
          if(own!=null)Padding(padding:const EdgeInsets.only(bottom:12),child:VeyraBanner(tone:VeyraTone.success,text:t('Votre offre active')+' : '+VeyraMoneyFormatter.fromMinor(own))),
          if(x['has_eligible_vehicle']==false)Padding(padding:const EdgeInsets.only(bottom:12),child:VeyraBanner(tone:VeyraTone.danger,text:t('Aucun véhicule validé de cette catégorie : offre impossible.'))),
          if(x['vtcCardExpiresBeforeRide']==true)Padding(padding:const EdgeInsets.only(bottom:12),child:VeyraBanner(tone:VeyraTone.danger,text:t('Votre carte VTC expire avant cette course : renouvelez-la pour faire une offre.'))),
          if(x['documentExpired']==true)Padding(padding:const EdgeInsets.only(bottom:12),child:VeyraBanner(tone:VeyraTone.danger,text:t('Un de vos documents a expiré : offres bloquées jusqu’à son renouvellement.'))),
        ]);
      },
    ),
    bottomNavigationBar:FutureBuilder<Map<String,dynamic>>(
      future:detail,
      builder:(context,s){
        if(!s.hasData)return const SizedBox.shrink();
        final x=s.data!;
        final adjusting=x['hasActiveOffer']==true;
        return SafeArea(child:Padding(
          padding:const EdgeInsets.fromLTRB(16,8,16,16),
          child:FilledButton(
            onPressed:x['has_eligible_vehicle']==false||x['vtcCardExpiresBeforeRide']==true||x['documentExpired']==true?null:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>OfferComposerScreen(bookingId:widget.bookingId,request:x,adjusting:adjusting))),
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              Flexible(child:Text(adjusting?t('Modifier mon offre'):t('Créer mon offre'),textAlign:TextAlign.center)),
              const SizedBox(width:8),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ));
      },
    ),
  );
}

/// Créer une offre → Récapitulatif → Offre envoyée (planche 14 P2-P4).
/// Le prix saisi est le montant net du chauffeur ; la commission VEYRA
/// (méthode A, DEC-01) est ajoutée pour le client. L'offre reste valable
/// jusqu'à la fin de la réception des offres (DEC-18 : pas de validité au
/// choix, pas de contre-offre).
class OfferComposerScreen extends StatefulWidget{
  final String bookingId;
  final Map<String,dynamic> request;
  final bool adjusting;
  const OfferComposerScreen({required this.bookingId,required this.request,this.adjusting=false,super.key});
  @override State<OfferComposerScreen> createState()=>_OfferComposerScreenState();
}
class _OfferComposerScreenState extends State<OfferComposerScreen>{
  final amount=TextEditingController();
  final message=TextEditingController();
  late Future<List<Map<String,dynamic>>> vehicles;
  String? vehicleId;
  /// 0 = compose, 1 = summary, 2 = sent.
  int stage=0;
  Map<String,dynamic>? quote;
  bool busy=false;
  String? error;

  @override void initState(){
    super.initState();
    final own=widget.request['ownActiveOfferAmountMinor'];
    if(own!=null)amount.text=((own as num)/100).toStringAsFixed(2).replaceAll('.',',');
    amount.addListener(()=>setState((){}));
    message.addListener(()=>setState((){}));
    vehicles=api.onboardingStatus().then((s){
      final category=widget.request['category_id']?.toString();
      final list=(s['vehicles'] as List? ??const[]).whereType<Map>().map((m)=>Map<String,dynamic>.from(m))
        .where((v)=>v['status']=='APPROVED'&&(category==null||v['category_id']?.toString()==category)).toList();
      if(list.isNotEmpty&&mounted)setState(()=>vehicleId??=list.first['id'].toString());
      return list;
    });
  }

  @override void dispose(){amount.dispose();message.dispose();super.dispose();}

  int? get amountMinor=>OfferPricePreview.parseMinor(amount.text);

  Future<void> review()async{
    final minor=amountMinor;
    if(minor==null||minor<=0)return setState(()=>error=t('Saisissez un prix valide.'));
    setState((){busy=true;error=null;});
    try{
      final q=await api.offerQuote(widget.bookingId,minor);
      if(mounted)setState((){quote=q;stage=1;});
    }catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  Future<void> send()async{
    final minor=amountMinor;
    if(minor==null||busy)return;
    setState((){busy=true;error=null;});
    try{
      if(widget.adjusting){
        await api.updateOffer(widget.bookingId,minor);
      }else{
        await api.offer(widget.bookingId,minor,vehicleId:vehicleId,message:message.text);
      }
      RefreshBus.bump();
      if(mounted)setState(()=>stage=2);
    }catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  Widget vehicleTile(Map<String,dynamic> v,{bool selectable=true}){
    final selected=v['id'].toString()==vehicleId;
    return Padding(
      padding:const EdgeInsets.only(bottom:10),
      child:Material(
        color:selected?VeyraColors.infoBackground:Colors.white,
        borderRadius:BorderRadius.circular(VeyraRadius.md),
        child:InkWell(
          borderRadius:BorderRadius.circular(VeyraRadius.md),
          onTap:selectable&&!widget.adjusting?()=>setState(()=>vehicleId=v['id'].toString()):null,
          child:Container(
            padding:const EdgeInsets.all(12),
            decoration:BoxDecoration(borderRadius:BorderRadius.circular(VeyraRadius.md),border:Border.all(color:selected?VeyraColors.accent:VeyraColors.border,width:selected?1.6:1)),
            child:Row(children:[
              const VeyraVehicleThumb(width:84),
              const SizedBox(width:12),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('${v['brand']??''} ${v['model']??''}'.trim(),style:const TextStyle(fontWeight:FontWeight.w700)),
                if(v['category_name']!=null)...[const SizedBox(height:4),DriverPill(v['category_name'].toString(),fg:VeyraColors.accent,bg:VeyraColors.infoBackground)],
                const SizedBox(height:4),
                DriverPaxBags(v['seats'],v['baggage_capacity'],labels:false),
              ])),
              if(selectable&&!widget.adjusting)Icon(selected?Icons.radio_button_checked:Icons.radio_button_unchecked,color:selected?VeyraColors.accent:VeyraColors.textTertiary),
            ]),
          ),
        ),
      ),
    );
  }

  Widget priceRow(String label,dynamic minor,{bool total=false})=>Padding(
    padding:const EdgeInsets.symmetric(vertical:4),
    child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      Flexible(child:Text(label,style:TextStyle(color:total?VeyraColors.textPrimary:VeyraColors.textSecondary,fontWeight:total?FontWeight.w800:FontWeight.w500))),
      const SizedBox(width:8),
      Text.rich(TextSpan(children:[
        TextSpan(text:VeyraMoneyFormatter.fromMinor(minor),style:TextStyle(fontWeight:total?FontWeight.w800:FontWeight.w600,fontSize:total?18:14)),
        if(total)const TextSpan(text:' TTC',style:TextStyle(fontSize:12,color:VeyraColors.textSecondary)),
      ])),
    ]),
  );

  String get validity=>t('Jusqu’à la fin de la réception des offres')+' ('+VeyraDateFormatter.dateTime(widget.request['offer_window_ends_at'])+')';

  List<Widget> composeBody()=>[
    Text(t('Votre véhicule'),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
    const SizedBox(height:10),
    FutureBuilder<List<Map<String,dynamic>>>(future:vehicles,builder:(context,s){
      if(s.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
      final list=s.data??const[];
      if(list.isEmpty)return VeyraBanner(tone:VeyraTone.danger,text:t('Aucun véhicule validé de cette catégorie : offre impossible.'));
      return Column(children:[
        for(final v in list)vehicleTile(v,selectable:list.length>1),
        Text(t('Seuls les véhicules validés de la catégorie demandée sont proposés.'),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:12)),
      ]);
    }),
    const SizedBox(height:18),
    Text(t('Prix de votre offre'),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
    const SizedBox(height:8),
    TextField(
      key:const ValueKey('offer-amount'),
      controller:amount,
      keyboardType:const TextInputType.numberWithOptions(decimal:true),
      style:const TextStyle(fontSize:26,fontWeight:FontWeight.w800),
      decoration:const InputDecoration(hintText:'0,00',suffixText:'€'),
    ),
    const SizedBox(height:6),
    SuggestedPriceHint(load:()=>api.suggestedPrice(widget.bookingId)),
    OfferPricePreview(amountText:amount.text,fetchQuote:(minor)=>api.offerQuote(widget.bookingId,minor)),
    const SizedBox(height:12),
    VeyraBanner(tone:VeyraTone.info,text:t('La commission VEYRA sera ajoutée automatiquement. Le client verra le prix total TTC.')),
    const SizedBox(height:18),
    Text(t('Validité de l’offre'),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
    const SizedBox(height:6),
    Text(validity,style:const TextStyle(color:VeyraColors.textSecondary)),
    if(!widget.adjusting)...[
      const SizedBox(height:18),
      Text.rich(TextSpan(children:[
        TextSpan(text:t('Message pour le client'),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
        TextSpan(text:' '+t('(facultatif)'),style:const TextStyle(color:VeyraColors.textSecondary)),
      ])),
      const SizedBox(height:8),
      TextField(
        key:const ValueKey('offer-message'),
        controller:message,
        maxLength:200,
        maxLines:3,
        decoration:InputDecoration(hintText:t('Ex. : je serai ponctuel, véhicule climatisé.'),helperText:t('Sans numéro de téléphone ni e-mail.')),
      ),
    ],
  ];

  List<Widget> summaryBody(){
    final r=widget.request;
    final (pTitle,pSub)=_RequestScreenState.splitPlace((r['pickup_address']??'').toString());
    final (dTitle,dSub)=_RequestScreenState.splitPlace((r['dropoff_address']??'').toString());
    final q=quote??{};
    final rate=(q['commissionRateBps'] as num?)?.toInt();
    final pct=rate==null?'':' ('+(rate/100).toStringAsFixed(rate%100==0?0:1).replaceAll('.',',')+' %)';
    return [
      DriverCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Expanded(child:Text(t('Récapitulatif de la demande'),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16))),
          TextButton(onPressed:()=>Navigator.pop(context),child:Text(t('Modifier'))),
        ]),
        VeyraRoutePoints(pickupTitle:pTitle,pickupSubtitle:pSub,dropoffTitle:dTitle,dropoffSubtitle:dSub),
        const SizedBox(height:10),
        Row(children:[
          const Icon(Icons.calendar_today_outlined,size:18),
          const SizedBox(width:8),
          Expanded(child:Text(driverWhen(r['scheduled_at']))),
          DriverPill(driverStartsIn(r['scheduled_at']),fg:VeyraColors.accent,bg:VeyraColors.infoBackground),
        ]),
        const SizedBox(height:8),
        DriverPaxBags(r['passenger_count'],r['baggage_count']),
      ])),
      DriverCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          Expanded(child:Text(t('Votre offre'),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16))),
          TextButton(onPressed:()=>setState(()=>stage=0),child:Text(t('Modifier'))),
        ]),
        FutureBuilder<List<Map<String,dynamic>>>(future:vehicles,builder:(context,s){
          final v=(s.data??const[]).where((v)=>v['id'].toString()==vehicleId).toList();
          return v.isEmpty?const SizedBox.shrink():vehicleTile(v.first,selectable:false);
        }),
        priceRow(t('Votre prix'),amountMinor),
        priceRow(t('Commission VEYRA')+pct,q['commissionMinor']),
        const Divider(height:18),
        priceRow(t('Prix total pour le client'),q['customerTotalMinor'],total:true),
        const SizedBox(height:10),
        Text(t('Validité de l’offre'),style:const TextStyle(color:VeyraColors.textSecondary)),
        Text(validity,style:const TextStyle(fontWeight:FontWeight.w600)),
        if(message.text.trim().isNotEmpty)...[
          const SizedBox(height:10),
          Text(t('Message pour le client'),style:const TextStyle(color:VeyraColors.textSecondary)),
          Text(message.text.trim()),
        ],
      ])),
    ];
  }

  Widget sentView(){
    final q=quote??{};
    return SafeArea(child:ListView(padding:const EdgeInsets.fromLTRB(24,32,24,24),children:[
      Center(child:Container(
        width:104,height:104,
        decoration:const BoxDecoration(color:VeyraColors.successBackground,shape:BoxShape.circle),
        child:const Icon(Icons.check_rounded,color:VeyraColors.success,size:64),
      )),
      const SizedBox(height:20),
      Text(widget.adjusting?t('Votre offre a été mise à jour !'):t('Votre offre a été envoyée avec succès !'),textAlign:TextAlign.center,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
      const SizedBox(height:10),
      Text(t('Le client sera notifié de votre proposition. Vous serez informé dès qu’il aura accepté ou refusé votre offre.'),textAlign:TextAlign.center,style:const TextStyle(color:VeyraColors.textSecondary)),
      const SizedBox(height:20),
      DriverCard(child:Column(children:[
        priceRow(t('Prix de votre offre'),amountMinor),
        priceRow(t('Prix total pour le client'),q['customerTotalMinor'],total:true),
        const SizedBox(height:6),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Expanded(child:Text(t('Validité de l’offre'),style:const TextStyle(color:VeyraColors.textSecondary))),
          Flexible(child:Text(VeyraDateFormatter.dateTime(widget.request['offer_window_ends_at']),textAlign:TextAlign.end,style:const TextStyle(fontWeight:FontWeight.w600))),
        ]),
      ])),
      VeyraBanner(tone:VeyraTone.info,text:t('Vous recevrez une notification dès que le client aura répondu.')),
      const SizedBox(height:20),
      FilledButton(onPressed:()=>context.go('/driver/offers'),child:Text(t('Voir mes offres'))),
      const SizedBox(height:10),
      FilledButton(
        style:FilledButton.styleFrom(backgroundColor:VeyraColors.surfaceMuted,foregroundColor:VeyraColors.textPrimary),
        onPressed:()=>context.go('/requests'),
        child:Text(t('Retour aux demandes')),
      ),
    ]));
  }

  @override Widget build(BuildContext context){
    if(stage==2)return Scaffold(backgroundColor:Colors.white,body:sentView());
    return PopScope(
      canPop:stage==0,
      onPopInvokedWithResult:(didPop,_){if(!didPop&&!busy)setState(()=>stage=0);},
      child:Scaffold(
        backgroundColor:Colors.white,
        appBar:AppBar(title:Text(stage==0?(widget.adjusting?t('Modifier mon offre'):t('Créer une offre')):t('Récapitulatif de l’offre'))),
        body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
          ...(stage==0?composeBody():summaryBody()),
          if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:VeyraBanner(tone:VeyraTone.danger,text:error!)),
        ]),
        bottomNavigationBar:SafeArea(child:Padding(
          padding:const EdgeInsets.fromLTRB(16,8,16,16),
          child:FilledButton.icon(
            onPressed:busy||(stage==0&&vehicleId==null&&!widget.adjusting)?null:(stage==0?review:send),
            icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.send_outlined),
            label:Text(stage==0?(widget.adjusting?t('Mettre à jour mon offre'):t('Envoyer mon offre')):t('Confirmer et envoyer')),
          ),
        )),
      ),
    );
  }
}

/// « Mes courses » (planche 12 P6) : courses confirmées à venir et
/// historique, regroupées par jour.
class AgendaScreen extends StatefulWidget{
  const AgendaScreen({super.key});
  @override State<AgendaScreen> createState()=>_AgendaScreenState();
}
class _AgendaScreenState extends State<AgendaScreen>{
  late Future<List<dynamic>> future;
  int page=0;
  /// 'upcoming' (À venir) or 'history' (Historique).
  String scope='upcoming';

  @override void initState(){
    super.initState();
    future=_load();
    RefreshBus.tick.addListener(_refresh);
  }

  Future<List<dynamic>> _load()=>api.bookings(scope:scope,page:page,sort:scope=='history'?'desc':'asc');
  @override void dispose(){
    RefreshBus.tick.removeListener(_refresh);
    super.dispose();
  }
  void _refresh()=>setState((){future=_load();});
  void _scope(String s){if(s==scope)return;setState((){scope=s;page=0;future=_load();});}

  static String dayLabel(dynamic raw){
    final d=DateTime.tryParse((raw??'').toString())?.toLocal();
    if(d==null)return '';
    final full=driverWhen(raw);
    return full.substring(0,full.lastIndexOf(' · '));
  }

  static String hhmm(dynamic raw){
    final d=DateTime.tryParse((raw??'').toString())?.toLocal();
    return d==null?'':'${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  Widget tabs()=>Container(
    padding:const EdgeInsets.all(4),
    decoration:BoxDecoration(color:VeyraColors.surfaceMuted,borderRadius:BorderRadius.circular(VeyraRadius.pill)),
    child:Row(children:[
      for(final (key,label) in [('upcoming',t('À venir')),('history',t('Historique'))])
        Expanded(child:Material(
          color:scope==key?VeyraColors.primary:Colors.transparent,
          borderRadius:BorderRadius.circular(VeyraRadius.pill),
          child:InkWell(
            borderRadius:BorderRadius.circular(VeyraRadius.pill),
            onTap:()=>_scope(key),
            child:Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Text(label,textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.w700,color:scope==key?Colors.white:VeyraColors.textPrimary))),
          ),
        )),
    ]),
  );

  Widget rideCard(Map<String,dynamic> x){
    final status=(x['status']??'').toString();
    final live={'DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'}.contains(status);
    final (pill,fg,bg)=switch(status){
      'CONFIRMED'=>(t('Confirmée'),VeyraColors.success,VeyraColors.successBackground),
      'DRIVER_EN_ROUTE'||'DRIVER_ARRIVED'||'IN_PROGRESS'=>(t('En cours'),VeyraColors.accent,VeyraColors.infoBackground),
      'COMPLETED'||'CLOSED'=>(t('Terminée'),VeyraColors.neutral,VeyraColors.neutralBackground),
      _=>(VeyraStatusLabels.bookingStatus(status),VeyraColors.danger,VeyraColors.dangerBackground),
    };
    final net=x['driver_net_amount_minor'];
    return DriverCard(
      onTap:()=>context.push('/ride/'+x['id'].toString()),
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          Text(hhmm(x['scheduled_at']),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800)),
          const SizedBox(width:8),
          Flexible(child:Align(alignment:Alignment.centerRight,child:DriverPill(pill,fg:fg,bg:bg))),
        ]),
        const SizedBox(height:8),
        DriverMiniRoute((x['pickup_address']??'').toString(),(x['dropoff_address']??'').toString()),
        const SizedBox(height:6),
        Row(children:[
          Expanded(child:DriverPaxBags(x['passenger_count'],x['baggage_count'])),
          if(net!=null)Text(VeyraMoneyFormatter.fromMinor(net),style:const TextStyle(fontWeight:FontWeight.w800)),
        ]),
        if(x['category_name']!=null)Padding(padding:const EdgeInsets.only(top:4),child:Text(x['category_name'].toString(),style:const TextStyle(color:VeyraColors.accent,fontSize:13,fontWeight:FontWeight.w600))),
        const SizedBox(height:12),
        if(scope=='upcoming')FilledButton(
          style:live?null:FilledButton.styleFrom(backgroundColor:VeyraColors.primary),
          onPressed:()=>context.push('/ride/'+x['id'].toString()),
          child:Text(live?t('Voir le trajet'):t('Voir les détails')),
        ),
      ]),
    );
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:Colors.white,
    appBar:DriverTopBar(onNotifications:()=>context.push('/notifications')),
    body:RefreshIndicator(
      onRefresh:()async{final refreshed=_load();setState((){future=refreshed;});try{await refreshed;}catch(_){/* FutureBuilder displays the load error. */}},
      child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
        Text(t('Mes courses'),style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
        const SizedBox(height:12),
        tabs(),
        const SizedBox(height:14),
        FutureBuilder<List<dynamic>>(
          future:future,
          builder:(context,s){
            if(s.connectionState!=ConnectionState.done){
              return const Padding(padding:EdgeInsets.all(32),child:Center(child:CircularProgressIndicator()));
            }
            if(s.hasError){
              return VeyraErrorMessages.isOffline(s.error!)
                ?VeyraOfflineBanner(onRetry:_refresh)
                :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:_refresh);
            }
            final items=(s.data??[]).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).toList();
            if(items.isEmpty){
              if(page>0)return TextButton(onPressed:()=>setState((){page--;future=_load();}),child:Text(t('Page précédente')));
              return DriverCard(child:Row(children:[
                const Icon(Icons.event_available_outlined,color:VeyraColors.textSecondary),
                const SizedBox(width:12),
                Expanded(child:Text(scope=='upcoming'?t('Aucune course à venir pour le moment.'):t('Aucune course dans l’historique.'),style:const TextStyle(color:VeyraColors.textSecondary))),
              ]));
            }
            final children=<Widget>[];
            String? day;
            for(final x in items){
              final label=dayLabel(x['scheduled_at']);
              if(label!=day){
                day=label;
                children.add(Padding(padding:const EdgeInsets.only(top:4,bottom:8),child:Text(label,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16))));
              }
              children.add(rideCard(x));
            }
            children.add(VeyraPaginationBar(
              page:page,
              hasNext:items.length==10,
              onPrevious:()=>setState((){page--;future=_load();}),
              onNext:()=>setState((){page++;future=_load();}),
            ));
            return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:children);
          },
        ),
      ]),
    ),
  );
}

DateTime? noShowAvailableAt(Map<String,dynamic> booking){
  final arrived=DateTime.tryParse(booking['arrived_at']?.toString()??'');
  final scheduled=DateTime.tryParse(booking['scheduled_at']?.toString()??'');
  if(arrived==null||scheduled==null)return null;
  return (arrived.isAfter(scheduled)?arrived:scheduled).add(const Duration(minutes:15));
}

class RideScreen extends StatefulWidget{
  final String bookingId;
  const RideScreen({required this.bookingId,super.key});
  @override State<RideScreen> createState()=>_RideScreenState();
}

class _RideScreenState extends State<RideScreen>{
  late Future<Map<String,dynamic>> future;
  late final DriverLocationTracker tracker;
  final pin=TextEditingController();

  Timer? statusTimer;
  bool refreshing=false;
  bool busy=false;
  String? error;
  bool locationSyncError=false;
  Position? position;
  Map<String,dynamic>? etaInfo;
  Map<String,dynamic>? tripEtaInfo;
  DateTime? lastEtaRefresh;
  int _etaRequest=0;
  int ratingScore=0;
  bool ratingSubmitting=false;
  bool ratingSubmitted=false;
  bool trackingStarting=false;
  bool trackingAttached=false;
  bool routePreviewLoading=false;

  @override void initState(){
    super.initState();
    future=api.bookingDetail(widget.bookingId);
    tracker=activeRideTracker;
    statusTimer=Timer.periodic(const Duration(seconds:8),(_)=>refreshStatus());
    RefreshBus.tick.addListener(refreshStatus);
  }

  @override void dispose(){
    statusTimer?.cancel();
    RefreshBus.tick.removeListener(refreshStatus);
    tracker.detach(this);
    pin.dispose();
    super.dispose();
  }

  Future<void> refreshStatus()async{
    if(refreshing||busy)return;refreshing=true;
    try{final value=await api.bookingDetail(widget.bookingId);if(mounted)setState((){future=Future.value(value);});}
    catch(e){if(mounted)setState(()=>error=t('Actualisation interrompue. Réessayez pour vérifier le statut.'));}
    finally{refreshing=false;}
  }
  Future<void> confirmNoShow()async{
    if(busy)return;
    final confirmed=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:Text(t('Déclarer le client absent ?')),content:Text(t('Attendez au moins 15 minutes après votre arrivée et l’heure prévue. Appelez ou contactez le client avant de confirmer. Cette déclaration clôture la course et peut entraîner des frais pour le client.')),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:Text(t('Continuer à attendre'))),FilledButton(style:FilledButton.styleFrom(minimumSize:const Size(0,52)),onPressed:()=>Navigator.pop(d,true),child:Text(t('Client contacté, confirmer son absence')))]));
    if(confirmed==true&&mounted)await action(()=>api.noShow(widget.bookingId),stopGps:true);
  }
  void reload()=>setState((){future=api.bookingDetail(widget.bookingId);});

  Future<void> submitRating() async {
    if(ratingScore<1)return;
    setState(()=>ratingSubmitting=true);
    try{
      await api.rate(widget.bookingId,ratingScore);
      if(mounted)setState((){
        ratingSubmitted=true;
        ratingSubmitting=false;
      });
    }on DioException catch(e){
      final alreadyRated=(e.response?.data is Map)&&((e.response?.data as Map)['code']=='ALREADY_RATED');
      if(mounted)setState((){
        if(alreadyRated)ratingSubmitted=true;
        else error=t('Impossible d’envoyer la note pour le moment.');
        ratingSubmitting=false;
      });
    }
  }

  Future<void> _startTrackingIfNeeded(String status) async {
    if(!{'DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'}.contains(status)||
       (tracker.running&&tracker.bookingId==widget.bookingId&&trackingAttached)||
       trackingStarting){
      return;
    }
    trackingStarting=true;
    trackingAttached=true;
    try{
      await tracker.start(
        bookingId:widget.bookingId,
        owner:this,
        onPosition:(p){
          if(!mounted)return;
          setState((){
            position=p;
            if(!locationSyncError)error=null;
          });
          final now=DateTime.now();
          if(lastEtaRefresh==null||now.difference(lastEtaRefresh!)>=const Duration(seconds:30)){
            lastEtaRefresh=now;
            _refreshEta(p);
          }
        },
        onError:(e){
          if(mounted)setState((){
            locationSyncError=false;
            error=_locationErrorMessage(e);
          });
        },
        onUploadError:(e){
          if(!mounted)return;
          final message=e is DioException
            ?VeyraErrorMessages.forException(e)
            :t('Position obtenue, mais impossible de la synchroniser avec Veyra.');
          setState((){
            locationSyncError=true;
            error=message;
          });
        },
        onUploadSuccess:(){
          if(!mounted)return;
          if(locationSyncError||error!=null){
            setState((){
              locationSyncError=false;
              error=null;
            });
          }
        },
      );
    }catch(e){
      if(mounted)setState(()=>error=_locationErrorMessage(e));
    }finally{
      trackingStarting=false;
    }
  }

  String _locationErrorMessage(Object error){
    final raw=error.toString();
    if(raw.contains('LOCATION_SERVICE_DISABLED')){
      return t('Activez la localisation du téléphone.');
    }
    if(raw.contains('LOCATION_PERMISSION_DENIED')){
      return t('La localisation est obligatoire pendant la prise en charge et la course.');
    }
    return t('Position GPS momentanément indisponible.');
  }

  Future<void> _refreshEta(Position p) async {
    final request=++_etaRequest;
    try{
      final booking=await api.bookingDetail(widget.bookingId);
      final status=(booking['status']??'').toString();
      final pickupLat=(booking['pickup_lat'] as num?)?.toDouble();
      final pickupLng=(booking['pickup_lng'] as num?)?.toDouble();
      final dropoffLat=(booking['dropoff_lat'] as num?)?.toDouble();
      final dropoffLng=(booking['dropoff_lng'] as num?)?.toDouble();
      if(pickupLat==null||pickupLng==null||dropoffLat==null||dropoffLng==null)return;

      Future<Map<String,dynamic>?> activeLeg() async {
        final toPickup=status=='DRIVER_EN_ROUTE'||status=='DRIVER_ARRIVED';
        try{
          return await api.routeEstimate(
            fromLat:p.latitude,
            fromLng:p.longitude,
            toLat:toPickup?pickupLat:dropoffLat,
            toLng:toPickup?pickupLng:dropoffLng,
          );
        }catch(_){
          return null;
        }
      }

      Future<Map<String,dynamic>?> customerTrip() async {
        try{
          return await api.routeEstimate(
            fromLat:pickupLat,
            fromLng:pickupLng,
            toLat:dropoffLat,
            toLng:dropoffLng,
          );
        }catch(_){
          return null;
        }
      }

      final results=await Future.wait<Map<String,dynamic>?>([
        activeLeg(),
        customerTrip(),
      ]);
      if(mounted&&request==_etaRequest){
        setState((){
          etaInfo=results[0];
          tripEtaInfo=results[1];
        });
      }
    }catch(_){
      // Route provider failures must not turn into a persistent generic
      // course error. GPS sync and course data remain usable independently.
      if(mounted&&request==_etaRequest){
        setState((){
          etaInfo=null;
          tripEtaInfo=null;
        });
      }
    }
  }

  Future<void> _routePreview(
    double? pickupLat,
    double? pickupLng,
    double? dropoffLat,
    double? dropoffLng,
  ) async {
    if(routePreviewLoading||
       pickupLat==null||pickupLng==null||dropoffLat==null||dropoffLng==null)return;
    routePreviewLoading=true;
    try{
      final route=await api.routeEstimate(
        fromLat:pickupLat,
        fromLng:pickupLng,
        toLat:dropoffLat,
        toLng:dropoffLng,
      );
      if(mounted)setState(()=>tripEtaInfo=route);
    }catch(_){
      // Keep the course usable if routing is temporarily unavailable.
    }finally{
      routePreviewLoading=false;
    }
  }

  Future<void> action(
    Future<void> Function() fn,{
    bool startGps=false,
    bool stopGps=false,
  }) async {
    if(busy)return;
    setState((){
      busy=true;
      error=null;
      locationSyncError=false;
    });
    try{
      await fn();
      if(stopGps)await tracker.stop();
      RefreshBus.bump();
      final updated=await api.bookingDetail(widget.bookingId);
      if(!mounted)return;
      setState((){future=Future.value(updated);});
      if(startGps){
        await _startTrackingIfNeeded((updated['status']??'').toString());
      }
    }catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  Future<void> _cancelAssigned() async {
    final confirm=await showDialog<bool>(
      context:context,
      builder:(dialogContext)=>AlertDialog(
        title:Text(t('Annuler cette course ?')),
        content:Text(t('La réservation sera republiée en priorité si le délai le permet. Cette annulation impactera votre qualité chauffeur.')),
        actions:[
          TextButton(
            onPressed:()=>Navigator.pop(dialogContext,false),
            child:Text(t('Garder la course')),
          ),
          FilledButton(style:FilledButton.styleFrom(minimumSize:const Size(0,52)),
            onPressed:()=>Navigator.pop(dialogContext,true),
            child:Text(t('Confirmer l’annulation')),
          ),
        ],
      ),
    );
    if(confirm!=true)return;

    setState(()=>busy=true);
    try{
      final result=await api.cancelAssignedBooking(widget.bookingId);
      await tracker.stop();
      RefreshBus.bump();
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text(
            result['republished']==true
              ?t('Course annulée et demande republiée.')
              :t('Course annulée. Le support Veyra a été alerté.'),
          )),
        );
        context.go('/agenda');
      }
    }catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Détail de la course'))),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const VeyraLoadingView();
        if(s.hasError){
          return VeyraErrorMessages.isOffline(s.error!)
            ?VeyraOfflineBanner(onRetry:reload)
            :VeyraErrorView(
                customMessage:VeyraErrorMessages.forException(s.error!),
                onRetry:reload,
              );
        }

        final x=s.data??{};
        final status=(x['status']??'').toString();
        final paymentMethod=(x['payment_method']??'').toString();
        final pickupLat=(x['pickup_lat'] as num?)?.toDouble();
        final pickupLng=(x['pickup_lng'] as num?)?.toDouble();
        final dropoffLat=(x['dropoff_lat'] as num?)?.toDouble();
        final dropoffLng=(x['dropoff_lng'] as num?)?.toDouble();

        final pickup=pickupLat==null||pickupLng==null?null:LatLng(pickupLat,pickupLng);
        final dropoff=dropoffLat==null||dropoffLng==null?null:LatLng(dropoffLat,dropoffLng);
        final driver=position==null?null:LatLng(position!.latitude,position!.longitude);
        final route=VeyraRouteGeometry.fromApi(etaInfo);
        final tripRoute=VeyraRouteGeometry.fromApi(tripEtaInfo);
        final active={'DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'}.contains(status);

        if(active&&(!tracker.running||tracker.bookingId!=widget.bookingId||!trackingAttached)&&!trackingStarting){
          WidgetsBinding.instance.addPostFrameCallback((_){
            if(mounted)_startTrackingIfNeeded(status);
          });
        }else if(!active&&tracker.running&&tracker.bookingId==widget.bookingId){
          WidgetsBinding.instance.addPostFrameCallback((_){
            tracker.stop();
          });
        }

        if(tripEtaInfo==null){
          WidgetsBinding.instance.addPostFrameCallback((_){
            _routePreview(pickupLat,pickupLng,dropoffLat,dropoffLng);
          });
        }

        final mapHeight={'DRIVER_EN_ROUTE','IN_PROGRESS'}.contains(status)
          ?420.0
          :status=='DRIVER_ARRIVED'
            ?240.0
            :220.0;

        final (pill,pillFg,pillBg)=switch(status){
          'CONFIRMED'=>(t('Confirmée'),VeyraColors.success,VeyraColors.successBackground),
          'DRIVER_EN_ROUTE'=>(t('En route'),VeyraColors.accent,VeyraColors.infoBackground),
          'DRIVER_ARRIVED'=>(t('Arrivé'),VeyraColors.accent,VeyraColors.infoBackground),
          'IN_PROGRESS'=>(t('En cours'),VeyraColors.success,VeyraColors.successBackground),
          'COMPLETED'||'CLOSED'=>(t('Terminée'),VeyraColors.neutral,VeyraColors.neutralBackground),
          _=>(VeyraStatusLabels.bookingStatus(status),VeyraColors.danger,VeyraColors.dangerBackground),
        };
        final (pTitle,pSub)=_RequestScreenState.splitPlace((x['pickup_address']??'').toString());
        final (dTitle,dSub)=_RequestScreenState.splitPlace((x['dropoff_address']??'').toString());
        final notes=(x['customer_notes']??'').toString();
        final customer=(x['customer_name']??'').toString().trim();
        final vehicle=[x['vehicle_brand'],x['vehicle_model']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' ');
        // Board 12 P8: « 15 min · 6 km · Arrivée à 15:45 » for the leg in progress.
        final legSeconds=status=='DRIVER_EN_ROUTE'||status=='IN_PROGRESS'?route.durationSeconds:null;
        final legMeters=status=='DRIVER_EN_ROUTE'||status=='IN_PROGRESS'?route.distanceMeters:null;
        final eta=legSeconds==null?null:DateTime.now().add(Duration(seconds:legSeconds.round()));

        Widget section({String? title,required Widget child})=>DriverCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          if(title!=null)...[Text(title,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),const SizedBox(height:10)],
          child,
        ]));
        Widget money(String label,dynamic minor,{bool strong=false})=>Padding(
          padding:const EdgeInsets.symmetric(vertical:3),
          child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            Flexible(child:Text(label,style:TextStyle(color:strong?VeyraColors.textPrimary:VeyraColors.textSecondary,fontWeight:strong?FontWeight.w700:FontWeight.w500))),
            const SizedBox(width:8),
            Text(VeyraMoneyFormatter.fromMinor(minor),style:TextStyle(fontWeight:strong?FontWeight.w800:FontWeight.w600)),
          ]),
        );

        return ListView(
          padding:EdgeInsets.zero,
          children:[
            Stack(children:[
              SizedBox(
                height:mapHeight,
                child:VeyraMap(
                  pickup:pickup,
                  dropoff:dropoff,
                  driver:driver,
                  driverHeading:position?.heading,
                  route:route,
                  secondaryRoute:tripRoute,
                  userAgentPackageName:'com.veyra.driver',
                ),
              ),
              Positioned(left:16,top:12,child:DriverPill(pill,fg:pillFg,bg:pillBg,icon:active?Icons.circle:null)),
            ]),
            Padding(
              padding:const EdgeInsets.fromLTRB(16,14,16,28),
              child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                if(legSeconds!=null)section(child:Row(children:[
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(VeyraMoneyFormatter.duration(legSeconds)+(legMeters==null?'':' · '+VeyraMoneyFormatter.distance(legMeters)),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800)),
                    Text(
                      (status=='IN_PROGRESS'?t('Arrivée à destination à'):t('Arrivée chez le client à'))+' ${eta!.hour.toString().padLeft(2,'0')}:${eta.minute.toString().padLeft(2,'0')}',
                      style:const TextStyle(color:VeyraColors.textSecondary),
                    ),
                  ])),
                  Icon(status=='IN_PROGRESS'?Icons.flag_rounded:Icons.person_pin_circle_rounded,color:VeyraColors.accent,size:30),
                ])),
                if(status=='DRIVER_ARRIVED')Padding(padding:const EdgeInsets.only(bottom:14),child:VeyraBanner(
                  tone:VeyraTone.success,
                  title:t('Vous êtes arrivé'),
                  text:t('Vous êtes arrivé au point de prise en charge. Contactez le client avant toute déclaration d’absence.'),
                )),
                // Client card (board 12 P7) with masked call and chat.
                section(child:Row(children:[
                  CircleAvatar(radius:24,backgroundColor:VeyraColors.surfaceMuted,child:Text(customer.isEmpty?'?':customer.substring(0,1).toUpperCase(),style:const TextStyle(fontWeight:FontWeight.w800,color:VeyraColors.primary))),
                  const SizedBox(width:12),
                  Expanded(child:Text(customer.isEmpty?t('Client'):customer,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:16))),
                  // Calls go through a masked number only (DEC-06, CL-15):
                  // the customer's phone is never sent to the driver app.
                  IconButton.outlined(tooltip:t('Appel par numéro masqué bientôt disponible'),onPressed:null,icon:const Icon(Icons.phone_outlined)),
                  const SizedBox(width:6),
                  IconButton.outlined(tooltip:t('Message'),onPressed:()=>context.push('/chat/'+widget.bookingId),icon:const Icon(Icons.chat_bubble_outline)),
                ])),
                section(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Row(children:[
                    const Icon(Icons.calendar_today_outlined,size:18),
                    const SizedBox(width:8),
                    Expanded(child:Text(driverWhen(x['scheduled_at']))),
                    if(status=='CONFIRMED')DriverPill(driverStartsIn(x['scheduled_at']),fg:VeyraColors.accent,bg:VeyraColors.infoBackground),
                  ]),
                  const SizedBox(height:12),
                  VeyraRoutePoints(pickupTitle:pTitle,pickupSubtitle:pSub,dropoffTitle:dTitle,dropoffSubtitle:dSub),
                  const SizedBox(height:10),
                  DriverPaxBags(x['passenger_count'],x['baggage_count']),
                  if(vehicle.isNotEmpty||x['plate_number']!=null)...[
                    const SizedBox(height:10),
                    Row(children:[
                      const VeyraVehicleThumb(width:64),
                      const SizedBox(width:10),
                      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Text(vehicle,style:const TextStyle(fontWeight:FontWeight.w600)),
                        Text([x['category_name'],x['vehicle_color'],x['plate_number']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' · '),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
                      ])),
                    ]),
                  ],
                  if(notes.isNotEmpty)...[
                    const SizedBox(height:12),
                    Container(
                      padding:const EdgeInsets.all(12),
                      decoration:BoxDecoration(color:VeyraColors.surfaceMuted,borderRadius:BorderRadius.circular(VeyraRadius.md)),
                      child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        const Icon(Icons.chat_outlined,size:18,color:VeyraColors.textSecondary),
                        const SizedBox(width:10),
                        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                          Text(t('Commentaire du client'),style:const TextStyle(fontWeight:FontWeight.w700,fontSize:13)),
                          Text(notes,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
                        ])),
                      ]),
                    ),
                  ],
                ])),
                if(paymentMethod=='CASH')section(title:t('Paiement en espèces'),child:Column(children:[
                  money(t('Montant à encaisser au client'),x['customer_total_amount_minor'],strong:true),
                  money(t('Votre montant net'),x['driver_net_amount_minor']),
                  money(t('Commission Veyra (dette CASH après la course)'),x['platform_commission_amount_minor']),
                ])),
                if(paymentMethod=='ONLINE')section(title:t('Paiement en ligne'),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  money(t('Votre montant net'),x['driver_net_amount_minor'],strong:true),
                  const SizedBox(height:4),
                  Text(x['payment_status']=='CAPTURED'?t('Payé en ligne'):x['payment_status']=='REFUNDED'?t('Remboursé'):t('Paiement non confirmé. Il doit être réglé avant le démarrage.'),
                    style:TextStyle(color:x['payment_status']=='CAPTURED'?VeyraColors.success:VeyraColors.warning,fontWeight:FontWeight.w600)),
                ])),
                if(paymentMethod=='PARTNER_INVOICE')section(title:t('Facturation partenaire'),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  money(t('Votre montant net'),x['driver_net_amount_minor'],strong:true),
                  Text(t('Le partenaire est facturé par Veyra selon son contrat.'),style:const TextStyle(color:VeyraColors.textSecondary)),
                ])),
                if(error!=null)Padding(
                  padding:const EdgeInsets.symmetric(vertical:10),
                  child:VeyraErrorView(
                    customMessage:error!,
                    onRetry:active
                      ?(){
                          if(tracker.running){
                            setState((){
                              error=null;
                              locationSyncError=false;
                            });
                          }else{
                            _startTrackingIfNeeded(status);
                          }
                        }
                      :reload,
                  ),
                ),
                if(status=='CONFIRMED')...[
                  FilledButton.icon(
                    onPressed:busy?null:()=>action(()=>api.enRoute(widget.bookingId),startGps:true),
                    icon:const Icon(Icons.directions_car),
                    label:Text(t('Je suis en route')),
                  ),
                  TextButton(
                    style:TextButton.styleFrom(foregroundColor:VeyraColors.danger),
                    onPressed:busy?null:_cancelAssigned,
                    child:Text(t('Annuler ma prise en charge')),
                  ),
                ],
                if(status=='DRIVER_EN_ROUTE')
                  FilledButton.icon(
                    onPressed:busy?null:()=>action(()async{final p=await currentPositionOrNull();await api.arrived(widget.bookingId,lat:p?.latitude,lng:p?.longitude);}),
                    icon:const Icon(Icons.flag_outlined),
                    label:Text(t('Je suis arrivé')),
                  ),
                if(status=='DRIVER_ARRIVED')section(title:t('Code PIN du client'),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                  Text(t('Demandez le code à 4 chiffres au client une fois à bord.'),style:const TextStyle(color:VeyraColors.textSecondary)),
                  const SizedBox(height:8),
                  TextField(
                    key:const ValueKey('ride-pin'),
                    controller:pin,
                    maxLength:4,
                    keyboardType:TextInputType.number,
                    textAlign:TextAlign.center,
                    style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800,letterSpacing:12),
                    onChanged:(_)=>setState((){}),
                    decoration:InputDecoration(hintText:'••••',counterText:'',labelText:t('PIN client (4 chiffres)')),
                  ),
                  const SizedBox(height:8),
                  FilledButton(
                    onPressed:busy||pin.text.length!=4
                      ?null
                      :()=>action(()async{final p=await currentPositionOrNull();await api.start(widget.bookingId,pin.text,lat:p?.latitude,lng:p?.longitude);},startGps:true),
                    child:Text(t('Démarrer la course')),
                  ),
                  TextButton(
                    style:TextButton.styleFrom(foregroundColor:VeyraColors.danger),
                    onPressed:busy||noShowAvailableAt(x)==null||DateTime.now().isBefore(noShowAvailableAt(x)!)?null:confirmNoShow,
                    child:Text(t('Déclarer le client absent')),
                  ),
                  Text(noShowAvailableAt(x)==null?t('Heure d’arrivée indisponible. Actualisez la course.'):t('Déclaration possible à partir de')+' '+VeyraDateFormatter.dateTime(noShowAvailableAt(x)!.toIso8601String()),
                    textAlign:TextAlign.center,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:12)),
                ])),
                if(status=='IN_PROGRESS')
                  FilledButton(
                    style:FilledButton.styleFrom(backgroundColor:VeyraColors.danger),
                    onPressed:busy?null:()async{
                      final confirmed=await showDialog<bool>(
                        context:context,
                        builder:(dialogContext)=>AlertDialog(
                          title:Text(t('Terminer la course ?')),
                          content:Text(t('Confirmez uniquement lorsque le passager est arrivé à destination.')),
                          actions:[
                            TextButton(
                              onPressed:()=>Navigator.pop(dialogContext,false),
                              child:Text(t('Continuer la course')),
                            ),
                            FilledButton(style:FilledButton.styleFrom(minimumSize:const Size(0,52)),
                              onPressed:()=>Navigator.pop(dialogContext,true),
                              child:Text(t('Terminer la course')),
                            ),
                          ],
                        ),
                      );
                      if(confirmed==true){
                        action(()=>api.complete(widget.bookingId),stopGps:true);
                      }
                    },
                    child:Text(t('Terminer la course')),
                  ),
                if({'COMPLETED','CLOSED'}.contains(status))section(
                  title:ratingSubmitted?null:t('Noter le client'),
                  child:ratingSubmitted
                    ?Row(children:[
                        const Icon(Icons.check_circle,color:VeyraColors.success),
                        const SizedBox(width:8),
                        Expanded(child:Text(t('Merci pour votre avis !'))),
                      ])
                    :Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Wrap(children:[
                          for(int i=1;i<=5;i++)
                            IconButton(
                              icon:Icon(i<=ratingScore?Icons.star_rounded:Icons.star_border_rounded,color:const Color(0xFFF5A623),size:32),
                              tooltip:AppLocale.code.value=='en'
                                ?(i==1?'1 star':'$i stars')
                                :(i==1?'1 étoile':'$i étoiles'),
                              onPressed:ratingSubmitting?null:()=>setState(()=>ratingScore=i),
                            ),
                        ]),
                        FilledButton(
                          onPressed:ratingSubmitting||ratingScore<1?null:submitRating,
                          child:Text(ratingSubmitting?t('Envoi…'):t('Envoyer la note')),
                        ),
                      ]),
                ),
                const SizedBox(height:12),
                if({'DRIVER_EN_ROUTE','DRIVER_ARRIVED'}.contains(status)&&pickupLat!=null&&pickupLng!=null)
                  OutlinedButton.icon(
                    onPressed:()=>launchUrl(
                      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$pickupLat,$pickupLng&travelmode=driving'),
                      mode:LaunchMode.externalApplication,
                    ),
                    icon:const Icon(Icons.navigation_outlined),
                    label:Text(t('Naviguer vers le client')),
                  ),
                if(status=='IN_PROGRESS'&&dropoffLat!=null&&dropoffLng!=null)
                  OutlinedButton.icon(
                    onPressed:()=>launchUrl(
                      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dropoffLat,$dropoffLng&travelmode=driving'),
                      mode:LaunchMode.externalApplication,
                    ),
                    icon:const Icon(Icons.navigation_outlined),
                    label:Text(t('Naviguer vers la destination')),
                  ),
              ]),
            ),
          ],
        );
      },
    ),
  );
}
class WalletScreen extends StatefulWidget{
  const WalletScreen({super.key});
  @override State<WalletScreen> createState()=>_WalletScreenState();
}
class _WalletScreenState extends State<WalletScreen>{
  late Future<Map<String,dynamic>> future;
  late Future<List<dynamic>> transactionsFuture;
  int transactionsPage=0;
  DateTimeRange? transactionDates;
  Future<List<dynamic>> loadTransactions()=>api.walletTransactions(page:transactionsPage,from:transactionDates?.start,to:transactionDates==null?null:transactionDates!.end.add(const Duration(days:1)).subtract(const Duration(microseconds:1)));

  @override void initState(){
    super.initState();
    future=api.wallet();
    transactionsFuture=loadTransactions();
    RefreshBus.tick.addListener(_refresh);
  }
  @override void dispose(){
    RefreshBus.tick.removeListener(_refresh);
    super.dispose();
  }
  void _refresh()=>unawaited(refreshWallet());
  Future<void> refreshWallet()async{
    final balances=api.wallet(),transactions=loadTransactions();
    setState((){future=balances;transactionsFuture=transactions;});
    try{await Future.wait<Object>([balances,transactions]);}catch(_){
      // Each FutureBuilder displays the error for its own request.
    }
  }

  late Future<List<dynamic>> history=api.bookings(scope:'history',sort:'desc');

  Widget balance(IconData icon,Color color,String label,dynamic minor,{String? note})=>DriverCard(child:Row(children:[
    Icon(icon,color:color,size:26),
    const SizedBox(width:12),
    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(label,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
      const SizedBox(height:2),
      Text(VeyraMoneyFormatter.fromMinor(minor),style:TextStyle(color:color,fontSize:20,fontWeight:FontWeight.w800)),
      if(note!=null)Text(note,style:const TextStyle(fontSize:12,color:VeyraColors.textSecondary)),
    ])),
  ]));

  Widget historyCard(Map<String,dynamic> x){
    final cash=x['payment_method']=='CASH';
    return DriverCard(
      onTap:()=>context.push('/ride/'+x['id'].toString()),
      padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
      child:Row(children:[
        const Icon(Icons.event_note_outlined,color:VeyraColors.textSecondary),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(driverWhen(x['scheduled_at']),style:const TextStyle(fontWeight:FontWeight.w600,fontSize:13)),
          Text('${x['pickup_address']??''} → ${x['dropoff_address']??''}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
        ])),
        const SizedBox(width:8),
        Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Text(VeyraMoneyFormatter.fromMinor(x['driver_net_amount_minor']),style:const TextStyle(fontWeight:FontWeight.w800)),
          const SizedBox(height:2),
          DriverPill(cash?t('Espèces'):t('En ligne'),fg:cash?VeyraColors.warning:VeyraColors.success,bg:cash?VeyraColors.warningBackground:VeyraColors.successBackground),
        ]),
      ]),
    );
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:Colors.white,
    appBar:DriverTopBar(onNotifications:()=>context.push('/notifications')),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
          ?VeyraOfflineBanner(onRetry:()=>setState((){future=api.wallet();}))
          :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState((){future=api.wallet();}));
        final x=s.data??{};
        return RefreshIndicator(onRefresh:()async{setState((){history=api.bookings(scope:'history',sort:'desc');});await refreshWallet();},child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
          // Board 12 P9 header: this month's net earnings.
          DriverCard(child:Row(children:[
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(t('Mes revenus'),style:const TextStyle(color:VeyraColors.textSecondary)),
              const SizedBox(height:4),
              Text(VeyraMoneyFormatter.fromMinor(x['monthEarningsMinor']??0),style:const TextStyle(fontSize:30,fontWeight:FontWeight.w800)),
              Text(t('Ce mois-ci'),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
            ])),
            Container(
              width:52,height:52,
              decoration:BoxDecoration(color:VeyraColors.infoBackground,borderRadius:BorderRadius.circular(VeyraRadius.md)),
              child:const Icon(Icons.bar_chart_rounded,color:VeyraColors.accent,size:30),
            ),
          ])),
          balance(Icons.account_balance_wallet_outlined,VeyraColors.success,t('Solde à recevoir'),x['onlinePayableMinor'],note:t('Montants dus par Veyra, en attente de versement.')),
          balance(Icons.warning_amber_rounded,VeyraColors.danger,t('Commissions espèces à reverser'),x['cashDebtMinor']),
          if(x['cashWarning']==true)Padding(padding:const EdgeInsets.only(bottom:14),child:VeyraBanner(
            tone:VeyraTone.warning,
            title:t('Seuil de dette atteint'),
            text:t('Alerte')+' ${VeyraMoneyFormatter.fromMinor(x['cashWarningThresholdMinor'])}'
              ' • '+t('restriction CASH')+' ${VeyraMoneyFormatter.fromMinor(x['cashRestrictedThresholdMinor'])}'
              ' • '+t('blocage CASH')+' ${VeyraMoneyFormatter.fromMinor(x['cashBlockedThresholdMinor'])}',
          )),
          DriverSectionTitle(t('Historique des courses')),
          FutureBuilder<List<dynamic>>(future:history,builder:(context,h){
            if(h.connectionState!=ConnectionState.done)return const Padding(padding:EdgeInsets.all(16),child:Center(child:CircularProgressIndicator()));
            final rides=(h.data??const[]).whereType<Map>().map((m)=>Map<String,dynamic>.from(m))
              .where((r)=>{'COMPLETED','CLOSED'}.contains(r['status'])).take(4).toList();
            if(h.hasError||rides.isEmpty)return Text(t('Aucune course terminée pour le moment.'),style:const TextStyle(color:VeyraColors.textSecondary));
            return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              for(final r in rides)historyCard(r),
              FilledButton(onPressed:()=>context.go('/agenda'),child:Text(t('Voir tout l’historique'))),
            ]);
          }),
          const SizedBox(height:18),
          DriverSectionTitle(t('Transactions')),
          OutlinedButton.icon(icon:const Icon(Icons.date_range),label:Text(transactionDates==null?t('Toutes les dates'):VeyraDateFormatter.dateTime(transactionDates!.start.toIso8601String())+' – '+VeyraDateFormatter.dateTime(transactionDates!.end.toIso8601String())),onPressed:()async{
            final chosen=await showDateRangePicker(context:context,firstDate:DateTime(2020),lastDate:DateTime.now(),initialDateRange:transactionDates);
            if(chosen!=null&&mounted)setState((){transactionDates=chosen;transactionsPage=0;transactionsFuture=loadTransactions();});
          }),
          if(transactionDates!=null)TextButton(onPressed:()=>setState((){transactionDates=null;transactionsPage=0;transactionsFuture=loadTransactions();}),child:Text(t('Réinitialiser la période'))),
          const SizedBox(height:8),
          FutureBuilder<List<dynamic>>(
            future:transactionsFuture,
            builder:(context,ts){
              if(ts.connectionState!=ConnectionState.done){
                return const Padding(padding:EdgeInsets.all(16),child:Center(child:CircularProgressIndicator()));
              }
              if(ts.hasError){
                return Card(child:ListTile(
                  leading:const Icon(Icons.cloud_off),
                  title:Text(t('Historique indisponible')),
                  trailing:TextButton(onPressed:()=>setState((){transactionsFuture=loadTransactions();}),child:Text(t('Réessayer'))),
                ));
              }
              final items=ts.data??[];
              if(items.isEmpty){
              if(transactionsPage>0)return TextButton(onPressed:()=>setState((){transactionsPage--;transactionsFuture=loadTransactions();}),child:Text(t('Page précédente')));
                return Card(child:ListTile(
                  leading:const Icon(Icons.receipt_long_outlined),
                  title:Text(t('Aucune transaction pour le moment.')),
                ));
              }
              return Column(children:[
                ...items.map((raw){
                  final tx=Map<String,dynamic>.from(raw as Map);
                  final eventType=tx['event_type']?.toString();
                  // Le sens comptable brut (DEBIT/CREDIT) ne correspond PAS
                  // directement à "bon/mauvais pour le chauffeur" ici : un
                  // DEBIT sur DRIVER_PAYABLE (compte de passif) signifie
                  // qu'il vient d'être payé (bonne nouvelle), alors qu'un
                  // DEBIT sur DRIVER_PLATFORM_DEBT (compte d'actif) signifie
                  // que sa dette augmente (mauvaise nouvelle). On classe donc
                  // explicitement par type d'événement plutôt que par sens
                  // comptable brut.
                  final isPositive={
                    'BOOKING_COMPLETED_ONLINE',
                    'BOOKING_COMPLETED_PARTNER_INVOICE',
                    'DRIVER_PAYABLE_PAID',
                    'DRIVER_CASH_DEBT_SETTLED',
                    'CUSTOMER_CASH_DEBT_PAID',
                  }.contains(eventType);
                  final amount=VeyraMoneyFormatter.fromMinor(tx['amount_minor']);
                  final bookingId=tx['booking_id']?.toString();
                  return Card(child:ListTile(
                    leading:Icon(isPositive?Icons.add_circle_outline:Icons.remove_circle_outline,color:isPositive?const Color(0xFF16A34A):const Color(0xFFDC2626)),
                    title:Text(VeyraStatusLabels.ledgerEvent(eventType)),
                    subtitle:Text(VeyraDateFormatter.dateTime(tx['created_at'])),
                    trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text((isPositive?'+ ':'- ')+amount,style:TextStyle(fontWeight:FontWeight.bold,color:isPositive?const Color(0xFF16A34A):const Color(0xFFDC2626))),if(bookingId!=null)...[const SizedBox(width:4),const Icon(Icons.chevron_right,size:18)]]),
                    onTap:bookingId==null?null:()=>context.push('/ride/'+bookingId),
                  ));
                }),
                VeyraPaginationBar(
                  page:transactionsPage,
                  hasNext:items.length==10,
                  onPrevious:(){
                    setState((){
                      transactionsPage--;
                      transactionsFuture=loadTransactions();
                    });
                  },
                  onNext:(){
                    setState((){
                      transactionsPage++;
                      transactionsFuture=loadTransactions();
                    });
                  },
                ),
              ]);
            },
          ),
        ]));
      },
    ),
  );
}


/// Écran Compte minimal côté chauffeur : identité, statut KYC, langue,
/// déconnexion. Miroir de AccountScreen côté client.
class AccountScreen extends StatefulWidget{const AccountScreen({super.key});@override State<AccountScreen> createState()=>_AccountScreenState();}class _AccountScreenState extends State<AccountScreen>{late Future<Map<String,dynamic>> future;late Future<List<dynamic>> docs;late Future<Map<String,dynamic>> kyc;Uint8List? avatar;bool busy=false;@override void initState(){super.initState();loadAccount();_loadAvatar();}void loadAccount(){future=api.me();docs=api.documents();kyc=api.onboardingStatus();docs.ignore();kyc.ignore();}Future<void> _loadAvatar()async{try{final v=await api.avatarBytes();if(mounted)setState(()=>avatar=v);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));}}Future<void> photo()async{final r=await FilePicker.platform.pickFiles(type:FileType.image,withData:true);if(r==null||r.files.isEmpty)return;final f=r.files.single;if(f.path==null&&f.bytes==null){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Impossible de lire cette image.'))));return;}setState(()=>busy=true);try{final m=f.path!=null?await api.uploadAvatar(f.path!):await api.uploadAvatarBytes(f.bytes!,f.name),v=await api.avatarBytes();if(v==null||v.isEmpty)throw StateError('AVATAR_RELOAD_EMPTY');if(mounted){setState((){future=Future.value(m);avatar=v;});ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Photo de profil mise à jour.'))));}}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e is DioException?VeyraErrorMessages.forException(e):t('Impossible d’enregistrer la photo de profil.'))));}finally{if(mounted)setState(()=>busy=false);}}Future<void> doc(String type)async{
  if(busy)return;
  setState(()=>busy=true);
  try{
    final result=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['pdf','jpg','jpeg','png']);
    if(result==null||!mounted)return;
    final path=result.files.isEmpty?null:result.files.single.path;
    if(path==null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Impossible de lire ce document.'))));return;}
    await api.uploadDocument(type,path);
    if(mounted){
      setState((){docs=api.documents();kyc=api.onboardingStatus();});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Document envoyé. Il sera vérifié par Veyra.'))));
    }
  }catch(e){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));
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
  try{await api.changePassword(change.$1,change.$2);await logout();}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));}
  finally{if(mounted)setState(()=>busy=false);}
}
Future<void> logout()async{await activeRideTracker.stop();await api.logout();try{await FirebaseAuth.instance.signOut();}catch(_){}if(mounted)context.go('/login');}@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(t('Paramètres'))),body:FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const VeyraLoadingView();if(s.hasError)return VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState(loadAccount));final m=s.data??{},name=((m['first_name']??'').toString()+' '+(m['last_name']??'').toString()).trim(),rating=double.tryParse((m['rating_average']??0).toString())??0,count=m['rating_count']??0;return ListView(padding:const EdgeInsets.all(20),children:[Center(child:Stack(children:[CircleAvatar(radius:48,backgroundImage:avatar==null?null:MemoryImage(avatar!),child:avatar==null?const Icon(Icons.person,size:42):null),Positioned(right:0,bottom:0,child:IconButton.filled(onPressed:busy?null:photo,icon:const Icon(Icons.camera_alt_outlined)))])),Center(child:Text(name.isEmpty?t('Chauffeur Veyra'):name,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),Center(child:Text((m['email']??'').toString())),Center(child:Text((m['phone']??'').toString())),Center(child:Row(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.star,color:Colors.amber),Text(' '+rating.toStringAsFixed(1)+' ('+count.toString()+' '+t('avis')+')')])),const SizedBox(height:12),FutureBuilder<Map<String,dynamic>>(future:kyc,builder:(context,ks){
            // Real gap fixed here, found during a UX/business audit:
            // kyc_status is already fetched and displayed well on the
            // dedicated KYC screen (icon, label, per-document detail),
            // but was never surfaced here at all -- a driver checking
            // their own account screen had no way to know whether they
            // were approved, pending, or rejected without separately
            // navigating to /kyc. Reuses the exact same
            // VeyraStatusLabels.kycStatus formatter as that screen for
            // consistent wording.
            if(ks.connectionState!=ConnectionState.done)return const SizedBox.shrink();
            if(ks.hasError)return const SizedBox.shrink();
            final status=ks.data?['kyc_status']?.toString();
            final approved=status=='APPROVED'&&ks.data?['marketplace_enabled']==true;
            return Card(child:ListTile(
              leading:Icon(approved?Icons.verified:Icons.pending_actions,color:approved?const Color(0xFF16A34A):null),
              title:Text(approved?t('Dossier approuvé'):t('Vérification en cours')),
              subtitle:Text(t('Statut du dossier')+' : '+VeyraStatusLabels.kycStatus(status)),
              trailing:const Icon(Icons.chevron_right),
              onTap:()=>context.push('/kyc'),
            ));
          }),Card(child:Column(children:[ListTile(leading:const Icon(Icons.edit),title:Text(t('Informations personnelles')),onTap:()=>edit(m)),ListTile(leading:const Icon(Icons.lock),title:Text(t('Modifier mon mot de passe')),onTap:password)])),Text(t('Mes documents chauffeur'),style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),DriverDocuments(documents:docs,onRetry:()=>setState((){docs=api.documents();}),onUpload:busy?null:doc),const LanguageSwitch(),const SizedBox(height:20),VeyraSecondaryButton(label:t('Se déconnecter'),icon:Icons.logout,onPressed:logout)]);}));}

/// Coquille de navigation persistante chauffeur (bottom nav 4 onglets),
/// conforme à la maquette D14 : Demandes / Planning / Revenus / Compte.
/// Notifications reste une route poussée (pas un onglet) -- absent de
/// la bottom nav sur cette maquette, contrairement à l'app Client.
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
        NavigationDestination(icon:const Icon(Icons.assignment_outlined),selectedIcon:const Icon(Icons.assignment),label:t('Demandes')),
        NavigationDestination(icon:const Icon(Icons.calendar_month_outlined),selectedIcon:const Icon(Icons.calendar_month),label:t('Mes courses')),
        NavigationDestination(icon:const Icon(Icons.euro_outlined),selectedIcon:const Icon(Icons.euro),label:t('Revenus')),
        NavigationDestination(icon:const Icon(Icons.person_outline),selectedIcon:const Icon(Icons.person),label:t('Profil')),
      ],
    ),
  );
}




class DriverChatScreen extends StatefulWidget{
  final String bookingId;
  const DriverChatScreen({required this.bookingId,super.key});
  @override State<DriverChatScreen> createState()=>_DriverChatScreenState();
}
class _DriverChatScreenState extends State<DriverChatScreen>{
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
          title:Text((chatBooking?['customer_name']??t('Votre interlocuteur')).toString()),
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


/// Document or photo for the driver dossier (PDF, JPG, PNG).
Future<String?> pickDriverFile({bool imageOnly=false})async{
  final r=await FilePicker.platform.pickFiles(
    type:imageOnly?FileType.image:FileType.custom,
    allowedExtensions:imageOnly?null:['pdf','jpg','jpeg','png'],
  );
  return r==null||r.files.isEmpty?null:r.files.single.path;
}

/// Sign-out from the profile menu (board 12 P10).
Future<void> driverLogout(BuildContext context)async{
  await activeRideTracker.stop();
  await api.logout();
  try{await FirebaseAuth.instance.signOut();}catch(_){}
  if(context.mounted)context.go('/login');
}

/// Refreshes the bell badge (board 16 P1).
Future<void> refreshUnreadNotifications()async{
  try{veyraUnreadNotifications.value=await api.unreadNotifications();}catch(_){}
}
