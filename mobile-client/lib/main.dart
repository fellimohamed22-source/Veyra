import 'dart:async';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
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
import 'core/widgets/state_views.dart';
import 'core/widgets/status_badge.dart';
import 'core/widgets/pin_display.dart';
import 'core/maps/route_geometry.dart';
import 'core/maps/veyra_map.dart';
import 'core/maps/location_socket.dart';

/// Short alias used throughout this file -- AppLocale.t() everywhere
/// would be far noisier across ~100 call sites.
String t(String french) => AppLocale.t(french);

bool pushHandlersConfigured=false;

void openPush(RemoteMessage message){
  final bookingId=message.data['bookingId']?.toString();
  if(bookingId==null||bookingId.isEmpty)return;
  router.go('/booking/'+bookingId);
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

Future<void> configurePush() async {
  try{
    if(Firebase.apps.isEmpty)await Firebase.initializeApp();
    await FirebaseMessaging.instance.requestPermission();
    final token=await FirebaseMessaging.instance.getToken();
    if(token!=null)await api.registerDevice(token);
    if(!pushHandlersConfigured){
      pushHandlersConfigured=true;
      FirebaseMessaging.onMessageOpenedApp.listen(openPush);
      final initial=await FirebaseMessaging.instance.getInitialMessage();
      if(initial!=null)openPush(initial);
    }
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class App extends StatefulWidget{
  const App({super.key});
  @override State<App> createState()=>_AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver{
  bool _sessionCheckRunning=false;

  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override void dispose(){
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed){
      _validateSessionAfterResume();
    }
  }

  Future<void> _validateSessionAfterResume() async {
    if(_sessionCheckRunning)return;
    _sessionCheckRunning=true;
    try{
      final valid=await api.validateStoredSession();
      if(!mounted)return;
      if(valid==false){
        final current=router.routerDelegate.currentConfiguration.uri.path;
        if(current!='/login'){
          router.go('/login');
        }
      }else if(valid==true){
        // Refresh the FCM registration after a process resume/recreation.
        // Failures are already non-fatal inside configurePush().
        unawaited(configurePush());
        final current=router.routerDelegate.currentConfiguration.uri.path;
        if(current=='/login'){
          router.go('/home');
        }
      }
      if(valid==null){
        final current=router.routerDelegate.currentConfiguration.uri.path;
        if(current=='/login'&&await api.hasStoredSession()){
          router.go('/home');
        }
      }
      // A transient network/server failure never clears credentials. If a
      // stored session exists after process recreation, enter the app and
      // let individual screens present their normal offline state.
    }finally{
      _sessionCheckRunning=false;
    }
  }

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
  GoRoute(path:'/addresses',builder:(c,s)=>const AddressScreen()),
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
    WidgetsBinding.instance.addPostFrameCallback((_)=>_restoreSession());
  }

  Future<void> _restoreSession() async {
    final valid=await api.validateStoredSession();
    if(!mounted)return;
    if(valid==true){
      unawaited(configurePush());
      context.go('/home');
      return;
    }
    if(valid==null&&await api.hasStoredSession()&&mounted){
      context.go('/home');
    }
    // false: credentials were genuinely rejected and have already been
    // cleared. null with stored credentials: preserve the session and
    // enter the app, where normal offline states handle connectivity.
  }

  Future<void> submit()async{
    setState((){loading=true;error=null;offline=false;});
    try{
      await api.login(email.text,password.text);
      await configurePush();
      if(mounted)context.go('/home');
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
  @override void initState(){
    super.initState();
    future=api.bookings();
    RefreshBus.tick.addListener(retry);
  }
  void retry()=>setState((){future=api.bookings();});

  @override void didChangeDependencies(){
    super.didChangeDependencies();
    routeObserver.subscribe(this,ModalRoute.of(context) as PageRoute);
  }
  @override void dispose(){
    routeObserver.unsubscribe(this);
    RefreshBus.tick.removeListener(retry);
    super.dispose();
  }
  // Real gap fixed here: returning to Home after creating a booking,
  // accepting an offer, or completing a payment never refreshed the
  // list -- the same stale Future stayed in place until the whole app
  // was closed and reopened. didPopNext fires precisely when a screen
  // pushed on top of this one is popped back to it.
  //
  // ATTENTION -- même réserve que AccueilScreen depuis l'introduction du
  // shell de navigation (LOT 4) : cet écran vit désormais dans le
  // Navigator imbriqué de sa branche, potentiellement différent du
  // Navigator racine où /addresses, /offers/:id etc. sont réellement
  // poussés/dépilés. Non vérifié sur appareil réel. RefreshIndicator
  // reste le filet de sécurité manuel.
  @override void didPopNext(){retry();}

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(
      backgroundColor:const Color(0xFFF2F6FB),elevation:0,
      title:Text(t('Mes réservations'),style:const TextStyle(color:Color(0xFF123A66),fontWeight:FontWeight.bold)),
    ),
    body:RefreshIndicator(
      onRefresh:()async{retry();await future;},
      child:ListView(padding:const EdgeInsets.all(20),children:[
        FutureBuilder<List<dynamic>>(
          future:future,
          builder:(context,s){
            if(s.connectionState!=ConnectionState.done){
              return const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()));
            }
            if(s.hasError){
              final offline=VeyraErrorMessages.isOffline(s.error!);
              return offline
                ? VeyraOfflineBanner(onRetry:retry)
                : VeyraErrorView(errorCode:null,customMessage:VeyraErrorMessages.forException(s.error!),onRetry:retry);
            }
            final items=s.data??[];
            if(items.isEmpty){
              return Card(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),child:ListTile(
                leading:const Icon(Icons.event_available,color:Color(0xFF1565C0)),
                title:Text(t('Aucune réservation')),
                subtitle:Text(t('Votre prochain trajet apparaîtra ici.')),
              ));
            }
            return Column(children:items.map((raw){
              final x=Map<String,dynamic>.from(raw as Map);
              final title=(x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString();
              final scheduled=VeyraDateFormatter.relativeDay(x['scheduled_at']);
              final status=(x['status']??'').toString();
              return Card(
                margin:const EdgeInsets.only(bottom:10),
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
                child:ListTile(
                  contentPadding:const EdgeInsets.all(14),
                  title:Text(title,style:const TextStyle(fontWeight:FontWeight.w600)),
                  subtitle:Padding(padding:const EdgeInsets.only(top:6),child:Row(children:[
                    Expanded(child:Text(scheduled,style:const TextStyle(color:Colors.black54,fontSize:13))),
                    VeyraStatusBadge(status:status),
                  ])),
                  isThreeLine:false,
                  trailing:const Icon(Icons.chevron_right),
                  onTap:(){
                    final id=x['id']?.toString();
                    if(id==null)return;
                    if(x['status']=='OPEN_FOR_OFFERS'||x['status']=='OFFERS_RECEIVED'){
                      context.push('/offers/'+id);
                    }else{
                      context.push('/booking/'+id);
                    }
                  },
                ),
              );
            }).toList());
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
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    routeObserver.subscribe(this,ModalRoute.of(context) as PageRoute);
  }
  @override void dispose(){
    routeObserver.unsubscribe(this);
    RefreshBus.tick.removeListener(_refresh);
    super.dispose();
  }
  @override void didPopNext(){setState(_load);}

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(
      backgroundColor:const Color(0xFFF2F6FB),elevation:0,
      title:Row(mainAxisSize:MainAxisSize.min,children:const [Icon(Icons.location_on,color:Color(0xFF1565C0)),SizedBox(width:6),Text('Veyra',style:TextStyle(color:Color(0xFF123A66),fontWeight:FontWeight.bold))]),
      actions:const [LanguageSwitch()],
    ),
    body:RefreshIndicator(
      onRefresh:()async{setState(_load);await Future.wait([me,bookings]);},
      child:ListView(padding:const EdgeInsets.all(20),children:[
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
        Text(t('Où souhaitez-vous aller ?'),style:const TextStyle(color:Color(0xFF6B7280))),
        const SizedBox(height:16),
        Container(
          decoration:BoxDecoration(
            gradient:const LinearGradient(colors:[Color(0xFF123A66),Color(0xFF1565C0)]),
            borderRadius:BorderRadius.circular(16),
          ),
          child:Material(color:Colors.transparent,child:InkWell(
            borderRadius:BorderRadius.circular(16),
            onTap:()=>context.push('/addresses'),
            child:Padding(padding:const EdgeInsets.all(20),child:Row(children:[
              const Icon(Icons.add_circle,color:Colors.white,size:32),
              const SizedBox(width:16),
              Expanded(child:Text(t('Planifier un trajet'),style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w600))),
              const Icon(Icons.arrow_forward_ios,color:Colors.white70,size:16),
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
              'CANCELLED_BY_DRIVER','CUSTOMER_NO_SHOW','EXPIRED','NO_OFFER','NO_DRIVER',
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
            return Card(
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
              child:ListTile(
                contentPadding:const EdgeInsets.all(14),
                title:Text(title,style:const TextStyle(fontWeight:FontWeight.w600)),
                subtitle:Padding(padding:const EdgeInsets.only(top:6),child:Row(children:[
                  Expanded(child:Text(VeyraDateFormatter.relativeDay(x['scheduled_at']),style:const TextStyle(color:Colors.black54,fontSize:13))),
                  VeyraStatusBadge(status:status),
                ])),
                trailing:const Icon(Icons.chevron_right),
                onTap:(){
                  final id=x['id']?.toString();
                  if(id==null)return;
                  if(x['status']=='OPEN_FOR_OFFERS'||x['status']=='OFFERS_RECEIVED'){
                    context.push('/offers/'+id);
                  }else{
                    context.push('/booking/'+id);
                  }
                },
              ),
            );
          },
        ),
      ]),
    ),
  );
}

/// Écran Compte minimal : identité, langue, déconnexion. Aucune fiche du
/// kit ne le détaille finement (composant implicite de navigation dans
/// les maquettes C02/etc via la bottom nav), volontairement sobre.
class AccountScreen extends StatefulWidget{
  const AccountScreen({super.key});
  @override State<AccountScreen> createState()=>_AccountScreenState();
}
class _AccountScreenState extends State<AccountScreen>{
  late Future<Map<String,dynamic>> future;
  bool loggingOut=false;

  @override void initState(){super.initState();future=api.me();}

  Future<void> logout()async{
    setState(()=>loggingOut=true);
    try{
      await api.logout();
    }finally{
      if(mounted)context.go('/login');
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(
      backgroundColor:const Color(0xFFF2F6FB),elevation:0,
      title:Text(t('Mon compte'),style:const TextStyle(color:Color(0xFF123A66),fontWeight:FontWeight.bold)),
    ),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const VeyraLoadingView();
        if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
          ?VeyraOfflineBanner(onRetry:()=>setState((){future=api.me();}))
          :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState((){future=api.me();}));
        final me=s.data??{};
        final firstName=(me['first_name']??'').toString();
        final lastName=(me['last_name']??'').toString();
        final email=(me['email']??'').toString();
        return ListView(padding:const EdgeInsets.all(20),children:[
          Card(child:ListTile(
            leading:const CircleAvatar(child:Icon(Icons.person)),
            title:Text('$firstName $lastName'.trim().isEmpty?t('Client Veyra'):'$firstName $lastName'.trim()),
            subtitle:Text(email),
          )),
          const SizedBox(height:16),
          const Padding(padding:EdgeInsets.symmetric(horizontal:4),child:LanguageSwitch()),
          const SizedBox(height:24),
          VeyraSecondaryButton(
            label:t('Se déconnecter'),
            icon:Icons.logout,
            onPressed:loggingOut?null:logout,
          ),
        ]);
      },
    ),
  );
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

/// Repère visuel non interactif pour AddressScreen (le formulaire de
/// réservation reste un seul écran à défilement, pas 3 écrans distincts
/// comme la maquette C03→C05) -- une simple carte mentale des sections
/// du formulaire, pas un traceur de progression (rien ne distingue une
/// section "en cours" d'une autre puisque l'utilisateur peut revenir
/// modifier n'importe quel champ à tout moment dans ce même écran).
class _WizardStep extends StatelessWidget{
  final String label;
  const _WizardStep({required this.label});
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(vertical:8),
    decoration:BoxDecoration(
      color:const Color(0xFFEAF1FD),
      borderRadius:BorderRadius.circular(VeyraRadius.pill),
    ),
    alignment:Alignment.center,
    child:Text(label,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:Color(0xFF123A66))),
  );
}

class _RecapLine extends StatelessWidget{
  final IconData icon;
  final String text;
  const _RecapLine({required this.icon,required this.text});
  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:4),
    child:Row(children:[
      Icon(icon,size:18,color:Colors.black54),
      const SizedBox(width:10),
      Expanded(child:Text(text,style:const TextStyle(fontSize:14))),
    ]),
  );
}

/// Stepper mobile pour un compteur borné (passagers/bagages) -- remplace
/// les DropdownButtonFormField précédents, explicitement demandé par la
/// mission UX (section 5 : "prefer mobile steppers rather than awkward
/// dropdowns"). Boutons +/- de 48dp (section 20 : cible tactile
/// minimale confortable), désactivés proprement aux bornes plutôt que
/// de permettre un dépassement silencieux.
class _CountStepper extends StatelessWidget{
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _CountStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override Widget build(BuildContext context)=>Container(
    decoration:BoxDecoration(
      border:Border.all(color:const Color(0xFFE5E7EB)),
      borderRadius:BorderRadius.circular(VeyraRadius.md),
    ),
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Padding(
        padding:const EdgeInsets.only(left:8,top:6),
        child:Text(label,style:const TextStyle(fontSize:12,color:Colors.black54)),
      ),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        SizedBox(
          width:48,height:48,
          child:IconButton(
            onPressed:value>min?()=>onChanged(value-1):null,
            icon:const Icon(Icons.remove_circle_outline),
            tooltip:t('Diminuer'),
          ),
        ),
        Text('$value',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
        SizedBox(
          width:48,height:48,
          child:IconButton(
            onPressed:value<max?()=>onChanged(value+1):null,
            icon:const Icon(Icons.add_circle_outline),
            tooltip:t('Augmenter'),
          ),
        ),
      ]),
    ]),
  );
}

class AddressScreen extends StatefulWidget{
  const AddressScreen({super.key});
  @override State<AddressScreen> createState()=>_AddressScreenState();
}
class _AddressScreenState extends State<AddressScreen>{
  final pickup=TextEditingController();
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
  String? visibilityMode;
  bool loadingPickup=false;
  bool loadingDropoff=false;
  bool locating=false;
  bool submitting=false;
  String? error;
  Timer? _searchDebounce;
  Map<String,dynamic>? routePreview;
  bool routePreviewLoading=false;

  @override void initState(){
    super.initState();
    categories=api.vehicleCategories();
    // Real gap fixed here: the client had no way to know whether their
    // booking would show competing prices to drivers or not -- this is
    // a platform-wide policy set by an admin (not a per-booking choice),
    // but there was previously no way for anyone but an admin to even
    // see which mode is currently active.
    api.offerVisibilityMode().then((mode){if(mounted)setState(()=>visibilityMode=mode);}).catchError((_){});
  }

  @override void dispose(){
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> search(bool isPickup,String q)async{
    if(q.trim().length<3){
      setState((){if(isPickup)pickupResults=[];else dropoffResults=[];});
      return;
    }
    setState((){if(isPickup)loadingPickup=true;else loadingDropoff=true;});
    try{
      final r=await api.autocomplete(q);
      if(mounted)setState((){if(isPickup)pickupResults=r;else dropoffResults=r;});
    }catch(_){
      if(mounted)setState(()=>error=t('Recherche d’adresse indisponible.'));
    }finally{
      if(mounted)setState((){if(isPickup)loadingPickup=false;else loadingDropoff=false;});
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
      final p=await Geolocator.getCurrentPosition(
        locationSettings:const LocationSettings(accuracy:LocationAccuracy.high),
      );
      final place=await api.reverseGeocode(p.latitude,p.longitude);
      if(place==null){
        if(mounted)setState(()=>error=t('Aucune adresse trouvée pour votre position actuelle.'));
        return;
      }
      if(mounted)setState((){
        pickup.text=place['label']?.toString()??'';
        pickupPlace=place;
        pickupResults=[];
      });
      await _refreshRoutePreview();
    }catch(_){
      if(mounted)setState(()=>error=t('Impossible d’obtenir votre position actuelle.'));
    }finally{
      if(mounted)setState(()=>locating=false);
    }
  }

  Widget addressField(bool isPickup){
    final controller=isPickup?pickup:dropoff;
    final results=isPickup?pickupResults:dropoffResults;
    final loading=isPickup?loadingPickup:loadingDropoff;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      TextField(
        controller:controller,
        onChanged:(q){
          // Real bug fixed here: setting controller.text programmatically
          // (in the suggestion onTap below) also fires this onChanged --
          // resetting the place unconditionally meant the just-selected
          // address was wiped out the instant it was chosen, even though
          // the field still visibly showed the selected text. Only treat
          // this as the user genuinely editing/clearing their selection
          // when the new text actually differs from the selected place's
          // own label.
          final current=isPickup?pickupPlace:dropoffPlace;
          if(current!=null&&current['label']==q)return;
          if(isPickup)pickupPlace=null;else dropoffPlace=null;
          routePreview=null;
          // Real bug found from an actual production log: every single
          // keystroke called search() immediately, each one hitting
          // LocationIQ's geocoding API directly -- typing a normal
          // address (e.g. "Marseille") fired up to 9+ requests within
          // a couple of seconds, comfortably exceeding LocationIQ's
          // per-second rate limit and surfacing as repeated 429 "Rate
          // Limited Second" errors server-side (AddressController ->
          // LocationIqGeocodingProvider). Standard debounce: cancel any
          // pending search and wait 400ms of no further typing before
          // actually calling the API, same UX pattern virtually every
          // autocomplete field uses.
          _searchDebounce?.cancel();
          _searchDebounce=Timer(const Duration(milliseconds:400),()=>search(isPickup,q));
        },
        decoration:InputDecoration(
          labelText:isPickup?t('Adresse de départ'):t('Destination'),
          prefixIcon:Icon(isPickup?Icons.trip_origin:Icons.location_on),
          suffixIcon:loading?const Padding(
            padding:EdgeInsets.all(14),
            child:SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)),
          ):isPickup?(locating?const Padding(
            padding:EdgeInsets.all(14),
            child:SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)),
          ):IconButton(icon:const Icon(Icons.my_location),tooltip:t('Utiliser ma position actuelle'),onPressed:useMyLocation)):null,
        ),
      ),
      for(final item in results.take(5))
        ListTile(
          dense:true,
          leading:const Icon(Icons.place_outlined),
          title:Text((item as Map)['label']?.toString()??''),
          onTap:(){
            final selected=Map<String,dynamic>.from(item);
            setState((){
              controller.text=selected['label']?.toString()??'';
              if(isPickup){
                pickupPlace=selected;
                pickupResults=[];
              }else{
                dropoffPlace=selected;
                dropoffResults=[];
              }
            });
            _refreshRoutePreview();
          },
        ),
    ]);
  }

  Future<void> _refreshRoutePreview() async {
    final from=pickupPlace;
    final to=dropoffPlace;
    if(from==null||to==null){
      if(mounted)setState(()=>routePreview=null);
      return;
    }
    final fromLat=(from['lat'] as num?)?.toDouble();
    final fromLng=(from['lng'] as num?)?.toDouble();
    final toLat=(to['lat'] as num?)?.toDouble();
    final toLng=(to['lng'] as num?)?.toDouble();
    if(fromLat==null||fromLng==null||toLat==null||toLng==null)return;

    setState(()=>routePreviewLoading=true);
    try{
      final route=await api.routeEstimate(
        fromLat:fromLat,
        fromLng:fromLng,
        toLat:toLat,
        toLng:toLng,
      );
      if(mounted)setState(()=>routePreview=route);
    }catch(_){
      // The booking can still be prepared if the free routing provider is
      // temporarily unavailable. The backend remains authoritative when
      // the request is finally published.
      if(mounted)setState(()=>routePreview=null);
    }finally{
      if(mounted)setState(()=>routePreviewLoading=false);
    }
  }

  Future<void> chooseDateTime()async{
    final now=DateTime.now();
    final date=await showDatePicker(
      context:context,
      firstDate:now,
      lastDate:now.add(const Duration(days:365)),
      initialDate:scheduledAt??now.add(const Duration(hours:3)),
    );
    if(date==null||!mounted)return;
    final time=await showTimePicker(
      context:context,
      initialTime:TimeOfDay.fromDateTime(scheduledAt??now.add(const Duration(hours:3))),
    );
    if(time==null)return;
    setState(()=>scheduledAt=DateTime(date.year,date.month,date.day,time.hour,time.minute));
  }

  Future<void> publish()async{
    if(pickupPlace==null||dropoffPlace==null||scheduledAt==null||categoryId==null){
      setState(()=>error=t('Complétez le trajet, la date et la catégorie.'));
      return;
    }
    if(scheduledAt!.difference(DateTime.now())<const Duration(hours:2)){
      setState(()=>error=t('Le départ doit être planifié au moins 2 heures à l’avance.'));
      return;
    }
    setState((){submitting=true;error=null;});
    try{
      final created=await api.createBooking({
        'pickup':{
          'lat':pickupPlace!['lat'],
          'lng':pickupPlace!['lng'],
          'address':pickupPlace!['label'],
        },
        'dropoff':{
          'lat':dropoffPlace!['lat'],
          'lng':dropoffPlace!['lng'],
          'address':dropoffPlace!['label'],
        },
        'scheduledAt':scheduledAt!.toUtc().toIso8601String(),
        'categoryId':categoryId,
        'paymentMethod':paymentMethod,
        'payerType':'CLIENT',
        'passengerCount':passengerCount,
        'baggageCount':baggageCount,
      });
      if(!mounted)return;
      final newBookingId=created['id']?.toString();
      // Section 19 : déclenche le mécanisme de rafraîchissement
      // explicite plutôt que de dépendre uniquement de
      // RouteObserver/didPopNext (fiabilité incertaine avec le
      // Navigator imbriqué du shell) pour que Accueil/Réservations
      // affichent la nouvelle demande dès le retour.
      RefreshBus.bump();
      // Spec section 6, explicit: "Current behavior returning immediately
      // to Home is insufficient UX." Never implies a driver is already
      // booked -- publishing a request is not a confirmed driver, so this
      // deliberately stays about the request being sent, not about a
      // ride being arranged.
      await showModalBottomSheet(context:context,isDismissible:false,enableDrag:false,builder:(sheetContext)=>SafeArea(child:Padding(
        padding:const EdgeInsets.all(24),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Icon(Icons.check_circle,color:Color(0xFF16A34A),size:48),
          const SizedBox(height:12),
          Text(t('Demande publiée'),textAlign:TextAlign.center,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          Text(t('Votre demande a été envoyée aux chauffeurs Veyra disponibles. Vous recevrez une notification lorsqu’une nouvelle offre sera reçue.'),textAlign:TextAlign.center,style:const TextStyle(color:Colors.black54)),
          const SizedBox(height:20),
          if(newBookingId!=null)FilledButton(
            onPressed:(){
              Navigator.pop(sheetContext);
              context.go('/home');
              context.push('/offers/'+newBookingId);
            },
            child:Text(t('Voir ma demande')),
          ),
          const SizedBox(height:8),
          OutlinedButton(
            onPressed:(){Navigator.pop(sheetContext);context.go('/home');},
            child:Text(t('Retour à l’accueil')),
          ),
        ]),
      )));
    }on DioException catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }catch(_){
      if(mounted)setState(()=>error=t('La réservation n’a pas pu être publiée. Vérifiez les informations puis réessayez.'));
    }finally{
      if(mounted)setState(()=>submitting=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Planifier une réservation'))),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      // Repère visuel ajouté suite à l'étude UX/navigation : le
      // formulaire reste un seul écran (pas le wizard C03→C04→C05 en 3
      // écrans distincts de la maquette -- changement jugé trop risqué
      // à restructurer sans pouvoir tester visuellement), mais rien
      // n'indiquait auparavant à l'utilisateur où il en est dans un
      // long formulaire à défilement. Purement informatif, non
      // interactif -- ne remplace pas un vrai wizard, réduit seulement
      // la charge cognitive de "où en suis-je ?".
      Row(children:[
        Expanded(child:_WizardStep(label:t('Trajet'))),
        const SizedBox(width:6),
        Expanded(child:_WizardStep(label:t('Options'))),
        const SizedBox(width:6),
        Expanded(child:_WizardStep(label:t('Confirmation'))),
      ]),
      const SizedBox(height:20),
      addressField(true),
      const SizedBox(height:16),
      addressField(false),
      const SizedBox(height:18),
      if(pickupPlace!=null&&dropoffPlace!=null)...[
        SizedBox(
          height:220,
          child:ClipRRect(
            borderRadius:BorderRadius.circular(VeyraRadius.lg),
            child:Stack(children:[
              Positioned.fill(child:VeyraMap(
                pickup:LatLng(
                  (pickupPlace!['lat'] as num).toDouble(),
                  (pickupPlace!['lng'] as num).toDouble(),
                ),
                dropoff:LatLng(
                  (dropoffPlace!['lat'] as num).toDouble(),
                  (dropoffPlace!['lng'] as num).toDouble(),
                ),
                route:VeyraRouteGeometry.fromApi(routePreview),
                showRecenter:false,
                userAgentPackageName:'com.veyra.client',
              )),
              if(routePreviewLoading)
                const Positioned.fill(
                  child:ColoredBox(
                    color:Color(0x33000000),
                    child:Center(child:CircularProgressIndicator()),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height:8),
        if(routePreview!=null)
          Row(children:[
            const Icon(Icons.route,size:18,color:Colors.black54),
            const SizedBox(width:6),
            Text(
              VeyraMoneyFormatter.distance(routePreview!['distanceMeters'])+
              ' • '+
              VeyraMoneyFormatter.duration(routePreview!['durationSeconds']),
              style:const TextStyle(fontSize:12,color:Colors.black54,fontWeight:FontWeight.w600),
            ),
          ]),
        const SizedBox(height:10),
      ],
      ListTile(
        contentPadding:EdgeInsets.zero,
        leading:const Icon(Icons.event),
        title:Text(t('Date et heure de départ')),
        subtitle:Text(scheduledAt==null?t('Minimum 2 h à l’avance'):VeyraDateFormatter.dateTime(scheduledAt!.toIso8601String())),
        trailing:OutlinedButton(onPressed:chooseDateTime,child:Text(t('Choisir'))),
      ),
      const SizedBox(height:12),
      FutureBuilder<List<dynamic>>(
        future:categories,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
          if(s.hasError)return Text(t('Catégories indisponibles.'));
          final items=s.data??[];
          return DropdownButtonFormField<String>(
            initialValue:categoryId,
            decoration:InputDecoration(labelText:t('Catégorie de véhicule')),
            items:items.map((raw){
              final x=Map<String,dynamic>.from(raw as Map);
              return DropdownMenuItem<String>(
                value:x['id'].toString(),
                child:Text((x['display_name']??x['code']).toString()),
              );
            }).toList(),
            onChanged:(v){
              if(v==null)return;
              final match=items.firstWhere(
                (raw)=>(raw as Map)['id'].toString()==v,
                orElse:()=>null,
              );
              setState((){
                categoryId=v;
                categoryName=match==null?null:((match as Map)['display_name']??match['code'])?.toString();
              });
            },
          );
        },
      ),
      const SizedBox(height:18),
      Row(children:[
        Expanded(child:_CountStepper(
          label:t('Passagers'),
          value:passengerCount,
          min:1,
          max:8,
          onChanged:(v)=>setState(()=>passengerCount=v),
        )),
        const SizedBox(width:12),
        Expanded(child:_CountStepper(
          label:t('Bagages'),
          value:baggageCount,
          min:0,
          max:6,
          onChanged:(v)=>setState(()=>baggageCount=v),
        )),
      ]),
      const SizedBox(height:18),
      const Text('Paiement',style:TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
      DropdownButtonFormField<String>(
        initialValue:paymentMethod,
        isExpanded:true,
        decoration:InputDecoration(labelText:t('Mode de paiement')),
        items:[
          DropdownMenuItem(value:'CASH',child:Text(t('Cash — le total inclut la commission Veyra'),overflow:TextOverflow.ellipsis,maxLines:1)),
          DropdownMenuItem(value:'ONLINE',child:Text(t('En ligne — paiement sécurisé'),overflow:TextOverflow.ellipsis,maxLines:1)),
        ],
        onChanged:(v){if(v!=null)setState(()=>paymentMethod=v);},
      ),
      if(visibilityMode!=null)Padding(
        padding:const EdgeInsets.only(top:10),
        child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Icon(visibilityMode=='BEST_VISIBLE'?Icons.visibility_outlined:Icons.visibility_off_outlined,size:18,color:Colors.black54),
          const SizedBox(width:8),
          Expanded(child:Text(
            visibilityMode=='BEST_VISIBLE'
              ?t('Les chauffeurs verront le meilleur prix proposé par un autre chauffeur.')
              :t('Offre privée : les chauffeurs ne voient jamais les prix proposés par les autres.'),
            style:const TextStyle(fontSize:12,color:Colors.black54),
          )),
        ]),
      ),
      const SizedBox(height:18),
      // Ajouté suite à l'étude UX/navigation : rien ne permettait
      // auparavant de revoir d'un coup d'œil les choix faits dans ce
      // long formulaire avant de s'engager -- l'utilisateur devait
      // remonter manuellement pour vérifier chaque champ. Cette carte
      // se met à jour en direct avec les valeurs déjà saisies, sans
      // dupliquer aucun calcul serveur (aucun prix n'est estimé ici).
      Card(
        color:const Color(0xFFF7FAFD),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(VeyraRadius.md)),
        child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(t('Récapitulatif'),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
          const SizedBox(height:10),
          _RecapLine(icon:Icons.trip_origin,text:pickup.text.trim().isEmpty?t('Départ non renseigné'):pickup.text.trim()),
          _RecapLine(icon:Icons.flag_outlined,text:dropoff.text.trim().isEmpty?t('Destination non renseignée'):dropoff.text.trim()),
          _RecapLine(icon:Icons.event,text:scheduledAt==null?t('Date non choisie'):VeyraDateFormatter.dateTime(scheduledAt!.toIso8601String())),
          _RecapLine(icon:Icons.directions_car_outlined,text:categoryName??t('Catégorie non choisie')),
          _RecapLine(icon:Icons.people_outline,text:'$passengerCount '+t('passager(s)')+' • $baggageCount '+t('bagage(s)')),
          _RecapLine(icon:Icons.payments_outlined,text:VeyraStatusLabels.paymentMethod(paymentMethod)),
        ])),
      ),
      const SizedBox(height:18),
      if(error!=null)Padding(
        padding:const EdgeInsets.symmetric(vertical:12),
        child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      ),
      FilledButton.icon(
        onPressed:submitting?null:publish,
        icon:const Icon(Icons.campaign),
        label:submitting?Text(t('Publication…')):Text(t('Publier la demande')),
      ),
      const SizedBox(height:12),
      Text(
        t('Les chauffeurs VTC éligibles recevront la demande et pourront proposer leur prix. Vous verrez toutes les offres reçues.'),
        textAlign:TextAlign.center,
      ),
    ])),
  );
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
  @override void initState(){
    super.initState();
    future=api.offers(widget.bookingId);
    // Real gap fixed here: this screen only ever fetched the offers
    // list, never the booking's own details -- someone landing here
    // before any offer exists (the normal, expected state right after
    // publishing) had no way to see their own trip's pickup, dropoff,
    // date, or status anywhere, on this screen or otherwise, since this
    // is the only screen a not-yet-assigned booking actually routes to.
    bookingFuture=api.bookingDetail(widget.bookingId);
  }

  Future<void> chooseOffer(String offerId)async{
    setState((){acceptingOfferId=offerId;error=null;});
    try{
      await api.accept(widget.bookingId,offerId);
      final booking=await api.bookingDetail(widget.bookingId);
      if(!mounted)return;
      RefreshBus.bump();
      if(booking['payment_method']=='ONLINE'){
        context.push('/payment/'+widget.bookingId);
      }else{
        context.go('/home');
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
    appBar:AppBar(title:Text(t('Offres reçues')),backgroundColor:const Color(0xFFF2F6FB),elevation:0),
    body:ListView(padding:const EdgeInsets.all(16),children:[
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
              Row(children:[
                Expanded(child:Text(VeyraDateFormatter.dateTime(b['scheduled_at']),style:const TextStyle(color:Colors.black54,fontSize:13))),
                VeyraStatusBadge(status:(b['status']??'').toString()),
              ]),
            ])),
          );
        },
      ),
      const SizedBox(height:16),
      FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
          if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
            ?VeyraOfflineBanner(onRetry:()=>setState((){future=api.offers(widget.bookingId);}))
            :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState((){future=api.offers(widget.bookingId);}));
          final items=s.data??[];
          if(items.isEmpty)return Padding(padding:const EdgeInsets.all(24),child:Text(t('Aucune offre pour le moment. Vous serez notifié dès qu’un chauffeur propose un prix.')));
          return Column(children:[
            Text(t('Choisissez librement selon le prix, le véhicule et le chauffeur.'),style:const TextStyle(color:Colors.black54)),
            if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
            const SizedBox(height:14),
            for(final raw in items)Builder(builder:(context){
              final x=Map<String,dynamic>.from(raw as Map);
              final driverName=(x['driverFirstName']??'Chauffeur').toString();
              final vehicle=[(x['vehicleBrand']??'').toString(),(x['vehicleModel']??'').toString()].where((v)=>v.isNotEmpty).join(' ');
              final rating=(x['rating']??'-').toString();
            return Card(
              margin:const EdgeInsets.only(bottom:12),
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
              child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
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
                  Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
                    Text(t('Total à payer'),style:const TextStyle(fontSize:11,color:Colors.black45)),
                    Text(VeyraMoneyFormatter.fromMinor(x['totalMinor']),style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Color(0xFF123A66))),
                  ]),
                ]),
                const SizedBox(height:4),
                Text(t('Chauffeur : ')+VeyraMoneyFormatter.fromMinor(x['driverPriceMinor'])+'  •  '+t('Frais Veyra : ')+VeyraMoneyFormatter.fromMinor(x['commissionMinor']),style:const TextStyle(fontSize:12,color:Colors.black45)),
                const SizedBox(height:12),
                SizedBox(width:double.infinity,child:FilledButton(
                  style:FilledButton.styleFrom(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
                  onPressed:acceptingOfferId!=null?null:()=>chooseOffer(x['offerId'].toString()),
                  child:acceptingOfferId==x['offerId'].toString()
                    ?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
                    :Text(t('Choisir')),
                )),
              ])),
            );
          }),
          ]);
        },
      ),
    ]),
  );
}


class PaymentScreen extends StatefulWidget{
  final String bookingId;
  const PaymentScreen({required this.bookingId,super.key});
  @override State<PaymentScreen> createState()=>_PaymentScreenState();
}
class _PaymentScreenState extends State<PaymentScreen>{
  bool loading=false;
  String? error;
  Map<String,dynamic>? booking;

  @override void initState(){
    super.initState();
    api.bookingDetail(widget.bookingId).then((v){if(mounted)setState(()=>booking=v);}).catchError((_){if(mounted)setState(()=>error=t('Impossible de charger le paiement.'));});
  }

  Future<void> pay()async{
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
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      if(mounted)context.go('/home');
    }catch(_){
      if(mounted)setState(()=>error=t('Le paiement n’a pas été finalisé.'));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(title:Text(t('Paiement sécurisé'))),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
        const Icon(Icons.lock_outline,size:56),
        const SizedBox(height:16),
        Text(t('Total à payer : ')+VeyraMoneyFormatter.fromMinor(booking?['customer_total_amount_minor']),style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold),textAlign:TextAlign.center),
        const SizedBox(height:12),
        const Text('Ce total inclut le prix proposé par le chauffeur et la commission Veyra.',textAlign:TextAlign.center),
        if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error),textAlign:TextAlign.center)),
        const SizedBox(height:20),
        FilledButton.icon(
          onPressed:loading?null:pay,
          icon:const Icon(Icons.credit_card),
          label:loading?Text(t('Paiement…')):Text(t('Payer maintenant')),
        ),
      ])),
    );
  }
}


class BookingDetailScreen extends StatefulWidget{
  final String bookingId;
  const BookingDetailScreen({required this.bookingId,super.key});
  @override State<BookingDetailScreen> createState()=>_BookingDetailScreenState();
}
class _BookingDetailScreenState extends State<BookingDetailScreen>{
  late Future<Map<String,dynamic>> future;
  String? pin;
  String? message;
  int ratingScore=0;
  bool ratingSubmitting=false;
  bool cancelling=false;
  bool ratingSubmitted=false;

  @override void initState(){
    super.initState();
    future=api.bookingDetail(widget.bookingId);
  }

  void reload()=>setState((){future=api.bookingDetail(widget.bookingId);});

  Future<void> loadPin()async{
    try{
      final value=await api.pin(widget.bookingId);
      if(mounted)setState(()=>pin=value);
    }catch(_){
      if(mounted)setState(()=>message=t('Le PIN sera disponible à H-1.'));
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
          FilledButton(onPressed:previewError!=null?null:()=>Navigator.pop(dialogContext,true),child:Text(t('Confirmer l’annulation'))),
        ],
      ),
    );
    if(confirmed!=true)return;
    await cancel();
  }

  Future<void> cancel()async{
    if(cancelling)return;
    setState(()=>cancelling=true);
    try{
      final result=await api.cancel(widget.bookingId);
      if(mounted)setState(()=>message=t('Réservation annulée. Frais éventuels : ')+VeyraMoneyFormatter.fromMinor(result['cancellationFeeMinor']));
      RefreshBus.bump();
      reload();
    }catch(e){
      if(mounted)setState(()=>message=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>cancelling=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Détail réservation'))),
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
        final total=(x['customer_total_amount_minor'] as num?)?.toInt();
        return ListView(padding:const EdgeInsets.all(20),children:[
          Text((x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString(),style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          Text(VeyraDateFormatter.dateTime(x['scheduled_at'])),
          const SizedBox(height:12),
          Card(child:ListTile(title:Text(t('Statut')),trailing:VeyraStatusBadge(status:status))),
          if({'OPEN_FOR_OFFERS','OFFERS_RECEIVED'}.contains(status))
            FilledButton.icon(
              onPressed:()=>context.push('/offers/'+widget.bookingId),
              icon:const Icon(Icons.local_offer_outlined),
              label:Text(t('Voir les offres reçues')),
            ),
          if(x['selected_driver_id']!=null)Card(child:ListTile(
            leading:const CircleAvatar(child:Icon(Icons.person)),
            title:Text(driverName.trim().isEmpty?t('Chauffeur confirmé'):driverName.trim()),
            subtitle:Text('Note : '+(x['driver_rating']??'-').toString()),
          )),
          if(x['customer_total_amount_minor']!=null)Card(child:ListTile(
            title:Text(t('Total client')),
            subtitle:Text(VeyraStatusLabels.paymentMethod(x['payment_method']?.toString())),
            trailing:Text(VeyraMoneyFormatter.fromMinor(total)),
          )),
          if(x['payment_method']=='ONLINE'&&{'CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED'}.contains(status))
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
              Text(status=='DRIVER_ARRIVED'?t('Donnez ce code à votre chauffeur'):t('Code à transmettre au chauffeur à son arrivée'),style:const TextStyle(fontSize:13,color:Colors.black54)),
              const SizedBox(height:8),
              VeyraPinDisplay(pin:pin!),
            ],
            TextButton(onPressed:(cancelling||loadingPreview)?null:confirmAndCancel,child:Text(cancelling?t('Annulation…'):loadingPreview?t('Calcul des frais…'):t('Annuler la réservation'))),
          ],
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
          if(message!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(message!)),
        ]);
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
  bool loading=true;
  bool loadError=false;
  bool sending=false;
  ChatSocket? socket;

  Timer? fallbackPoller;

  @override void initState(){
    super.initState();
    _load();
    fallbackPoller=Timer.periodic(const Duration(seconds:5),(_)=>_pollForNewMessages());
  }

  Future<void> _pollForNewMessages()async{
    if(!mounted)return;
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
    final body=input.text.trim();
    if(body.isEmpty)return;
    input.clear();
    setState(()=>sending=true);
    try{
      final sent=await api.sendMessage(widget.bookingId,body);
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
  static const _staleThreshold=Duration(minutes:2);

  Timer? fallbackTimer;
  Timer? etaTimer;
  BookingLocationSocket? locationSocket;
  Map<String,dynamic>? location;
  Map<String,dynamic>? bookingMap;
  Map<String,dynamic>? etaInfo;
  String? error;
  bool loading=true;

  @override void initState(){
    super.initState();
    _bootstrap();
    locationSocket=BookingLocationSocket(
      api:api,
      bookingId:widget.bookingId,
      onLocation:_onSocketLocation,
    )..connect();

    // WebSocket is primary; HTTP polling remains a resilient fallback
    // for captive portals, proxies or short-lived socket interruptions.
    fallbackTimer=Timer.periodic(const Duration(seconds:15),(_)=>_refreshSnapshot());
    etaTimer=Timer.periodic(const Duration(seconds:30),(_)=>_refreshEta());
  }

  Future<void> _bootstrap() async {
    setState(()=>loading=true);
    try{
      final booking=await api.bookingDetail(widget.bookingId);
      final live=await api.currentLocation(widget.bookingId);
      if(!mounted)return;
      setState((){
        bookingMap=booking;
        location=live;
        error=null;
        loading=false;
      });
      await _refreshEta();
    }catch(e){
      if(!mounted)return;
      setState((){
        loading=false;
        error=VeyraErrorMessages.forException(e);
      });
    }
  }

  Future<void> _refreshSnapshot() async {
    try{
      final booking=await api.bookingDetail(widget.bookingId);
      final live=await api.currentLocation(widget.bookingId);
      if(!mounted)return;
      setState((){
        bookingMap=booking;
        location=live;
        error=null;
      });
      await _refreshEta();
    }catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }
  }

  void _onSocketLocation(Map<String,dynamic> message){
    if(!mounted)return;
    setState((){
      location={
        'available':true,
        'lat':message['lat'],
        'lng':message['lng'],
        'accuracy_m':message['accuracyM']??message['accuracy_m'],
        'heading':message['heading'],
        'speed_mps':message['speedMps']??message['speed_mps'],
        'sequence_no':message['sequenceNo']??message['sequence_no'],
        'recorded_at':message['recordedAt']??message['recorded_at']??DateTime.now().toUtc().toIso8601String(),
      };
      error=null;
    });
  }

  DateTime? get _recordedAt {
    final raw=location?['recorded_at']??location?['recordedAt'];
    if(raw==null)return null;
    return DateTime.tryParse(raw.toString());
  }

  bool get _isStale {
    final dt=_recordedAt;
    if(dt==null)return false;
    return DateTime.now().toUtc().difference(dt.toUtc())>_staleThreshold;
  }

  Future<void> _refreshEta() async {
    final live=location;
    final booking=bookingMap;
    if(live?['available']!=true||booking==null||_isStale){
      if(mounted&&etaInfo!=null)setState(()=>etaInfo=null);
      return;
    }

    final status=(booking['status']??'').toString();
    final approaching=status=='DRIVER_EN_ROUTE'||status=='DRIVER_ARRIVED';
    final toLat=(booking[approaching?'pickup_lat':'dropoff_lat'] as num?)?.toDouble();
    final toLng=(booking[approaching?'pickup_lng':'dropoff_lng'] as num?)?.toDouble();
    final fromLat=(live?['lat'] as num?)?.toDouble();
    final fromLng=(live?['lng'] as num?)?.toDouble();
    if(toLat==null||toLng==null||fromLat==null||fromLng==null)return;

    try{
      final eta=await api.routeEstimate(
        fromLat:fromLat,
        fromLng:fromLng,
        toLat:toLat,
        toLng:toLng,
      );
      if(mounted)setState(()=>etaInfo=eta);
    }catch(_){
      // Keep the live position visible even when the routing provider is
      // temporarily unavailable. ETA/route simply disappear.
      if(mounted)setState(()=>etaInfo=null);
    }
  }

  @override void dispose(){
    fallbackTimer?.cancel();
    etaTimer?.cancel();
    locationSocket?.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext context){
    if(loading){
      return Scaffold(
        appBar:AppBar(title:Text(t('Suivi en direct'))),
        body:const VeyraLoadingView(),
      );
    }

    final booking=bookingMap;
    if(booking==null){
      return Scaffold(
        appBar:AppBar(title:Text(t('Suivi en direct'))),
        body:VeyraErrorView(
          customMessage:error??t('Suivi indisponible.'),
          onRetry:_bootstrap,
        ),
      );
    }

    final status=(booking['status']??'').toString();
    final available=location?['available']==true;
    final pickupLat=(booking['pickup_lat'] as num?)?.toDouble();
    final pickupLng=(booking['pickup_lng'] as num?)?.toDouble();
    final dropoffLat=(booking['dropoff_lat'] as num?)?.toDouble();
    final dropoffLng=(booking['dropoff_lng'] as num?)?.toDouble();
    final driverLat=(location?['lat'] as num?)?.toDouble();
    final driverLng=(location?['lng'] as num?)?.toDouble();
    final driverHeading=(location?['heading'] as num?)?.toDouble();
    final driverPhone=booking['driver_phone']?.toString();

    final pickup=pickupLat==null||pickupLng==null?null:LatLng(pickupLat,pickupLng);
    final dropoff=dropoffLat==null||dropoffLng==null?null:LatLng(dropoffLat,dropoffLng);
    final driver=available&&driverLat!=null&&driverLng!=null?LatLng(driverLat,driverLng):null;
    final route=VeyraRouteGeometry.fromApi(etaInfo);

    final approaching=status=='DRIVER_EN_ROUTE'||status=='DRIVER_ARRIVED';
    final title=status=='IN_PROGRESS'
      ?t('Course en cours')
      :status=='DRIVER_ARRIVED'
        ?t('Votre chauffeur est arrivé')
        :t('Votre chauffeur arrive');

    return Scaffold(
      body:Stack(children:[
        Positioned.fill(
          child:VeyraMap(
            pickup:pickup,
            dropoff:dropoff,
            driver:driver,
            driverHeading:driverHeading,
            route:route,
            userAgentPackageName:'com.veyra.client',
          ),
        ),
        SafeArea(
          child:Padding(
            padding:const EdgeInsets.fromLTRB(12,8,12,0),
            child:Row(
              crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                Material(
                  color:Colors.white,
                  elevation:4,
                  shadowColor:Colors.black26,
                  shape:const CircleBorder(),
                  child:IconButton(
                    tooltip:MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed:()=>Navigator.maybePop(context),
                    icon:const Icon(Icons.arrow_back,color:Color(0xFF171717)),
                  ),
                ),
                const SizedBox(width:10),
                Expanded(
                  child:Material(
                    color:Colors.white,
                    elevation:4,
                    shadowColor:Colors.black26,
                    borderRadius:BorderRadius.circular(22),
                    child:Padding(
                      padding:const EdgeInsets.symmetric(horizontal:16,vertical:11),
                      child:Row(children:[
                        Container(
                          width:9,height:9,
                          decoration:BoxDecoration(
                            shape:BoxShape.circle,
                            color:available&&!_isStale
                              ?const Color(0xFF16A34A)
                              :const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width:9),
                        Expanded(child:Text(
                          title,
                          maxLines:1,
                          overflow:TextOverflow.ellipsis,
                          style:const TextStyle(fontWeight:FontWeight.w700,fontSize:15),
                        )),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if(error!=null)
          Positioned(
            top:76,left:16,right:16,
            child:SafeArea(
              child:Material(
                elevation:3,
                borderRadius:BorderRadius.circular(14),
                color:const Color(0xFFFFF7ED),
                child:Padding(
                  padding:const EdgeInsets.all(12),
                  child:Row(children:[
                    const Icon(Icons.wifi_off,color:Color(0xFFD97706)),
                    const SizedBox(width:10),
                    Expanded(child:Text(error!,style:const TextStyle(fontSize:12))),
                    TextButton(onPressed:_refreshSnapshot,child:Text(t('Réessayer'))),
                  ]),
                ),
              ),
            ),
          ),
        DraggableScrollableSheet(
          initialChildSize:.31,
          minChildSize:.25,
          maxChildSize:.62,
          snap:true,
          snapSizes:const [.31,.62],
          builder:(context,scrollController)=>Material(
            elevation:12,
            shadowColor:Colors.black38,
            color:Colors.white,
            borderRadius:const BorderRadius.vertical(top:Radius.circular(28)),
            child:ListView(
              controller:scrollController,
              padding:const EdgeInsets.fromLTRB(20,10,20,30),
              children:[
                Center(child:Container(
                  width:42,height:5,
                  decoration:BoxDecoration(
                    color:const Color(0xFFD1D5DB),
                    borderRadius:BorderRadius.circular(3),
                  ),
                )),
                const SizedBox(height:16),
                Row(
                  crossAxisAlignment:CrossAxisAlignment.start,
                  children:[
                    Expanded(child:Column(
                      crossAxisAlignment:CrossAxisAlignment.start,
                      children:[
                        Text(title,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800,letterSpacing:-.3)),
                        const SizedBox(height:5),
                        Text(
                          approaching
                            ?(booking['pickup_address']??'').toString()
                            :(booking['dropoff_address']??'').toString(),
                          maxLines:2,
                          overflow:TextOverflow.ellipsis,
                          style:const TextStyle(color:Color(0xFF6B7280),fontSize:14,height:1.3),
                        ),
                      ],
                    )),
                    if(route.durationSeconds!=null)
                      Container(
                        margin:const EdgeInsets.only(left:12),
                        padding:const EdgeInsets.symmetric(horizontal:14,vertical:9),
                        decoration:BoxDecoration(
                          color:const Color(0xFF171717),
                          borderRadius:BorderRadius.circular(18),
                        ),
                        child:Text(
                          VeyraMoneyFormatter.duration(route.durationSeconds),
                          style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800),
                        ),
                      ),
                  ],
                ),
                if(route.distanceMeters!=null)...[
                  const SizedBox(height:12),
                  Row(children:[
                    const Icon(Icons.route_rounded,size:18,color:Color(0xFF4B5563)),
                    const SizedBox(width:7),
                    Text(
                      VeyraMoneyFormatter.distance(route.distanceMeters),
                      style:const TextStyle(color:Color(0xFF4B5563),fontWeight:FontWeight.w600),
                    ),
                  ]),
                ],
                const SizedBox(height:14),
                if(!available)
                  const LinearProgressIndicator(minHeight:3)
                else
                  Row(children:[
                    Icon(
                      _isStale?Icons.sync_problem_rounded:Icons.gps_fixed_rounded,
                      size:18,
                      color:_isStale?const Color(0xFFDC2626):const Color(0xFF16A34A),
                    ),
                    const SizedBox(width:8),
                    Expanded(child:Text(
                      _isStale
                        ?t('Position possiblement obsolète — aucun ETA n’est affiché tant qu’une position récente n’est pas reçue.')
                        :t('Position en cours de mise à jour.'),
                      style:TextStyle(
                        color:_isStale?const Color(0xFFDC2626):const Color(0xFF4B5563),
                        fontSize:12,
                        fontWeight:FontWeight.w600,
                      ),
                    )),
                  ]),
                if(!available)...[
                  const SizedBox(height:9),
                  Text(t('En attente de la première position GPS.'),style:const TextStyle(color:Color(0xFF6B7280),fontSize:12)),
                ],
                const SizedBox(height:18),
                const Divider(height:1),
                const SizedBox(height:16),
                Row(children:[
                  Expanded(child:OutlinedButton.icon(
                    style:OutlinedButton.styleFrom(
                      foregroundColor:const Color(0xFF171717),
                      side:const BorderSide(color:Color(0xFFD1D5DB)),
                      padding:const EdgeInsets.symmetric(vertical:14),
                      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
                    ),
                    onPressed:driverPhone==null||driverPhone.isEmpty
                      ?null
                      :()=>launchUrl(Uri(scheme:'tel',path:driverPhone)),
                    icon:const Icon(Icons.phone_outlined),
                    label:Text(t('Appeler')),
                  )),
                  const SizedBox(width:12),
                  Expanded(child:FilledButton.icon(
                    style:FilledButton.styleFrom(
                      backgroundColor:const Color(0xFF171717),
                      foregroundColor:Colors.white,
                      padding:const EdgeInsets.symmetric(vertical:14),
                      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
                    ),
                    onPressed:()=>context.push('/chat/'+widget.bookingId),
                    icon:const Icon(Icons.chat_bubble_outline),
                    label:Text(t('Message')),
                  )),
                ]),
                if(available&&_recordedAt!=null)...[
                  const SizedBox(height:12),
                  Center(child:Text(
                    t('Dernière position : ')+VeyraDateFormatter.dateTime(_recordedAt!.toIso8601String()),
                    style:const TextStyle(color:Color(0xFF9CA3AF),fontSize:11),
                  )),
                ],
              ],
            ),
          ),
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
  bool loading=false;
  String? error;
  bool offline=false;

  Future<void> submit()async{
    if(firstName.text.trim().isEmpty||email.text.trim().isEmpty||password.text.length<10){
      setState((){error=t('Prénom, e-mail et mot de passe de 10 caractères minimum requis.');offline=false;});
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
      );
      await configurePush();
      if(mounted)context.go('/home');
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
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
      TextField(controller:firstName,decoration:appFieldDecoration(t('Prénom'),icon:Icons.person_outline)),
      const SizedBox(height:12),
      TextField(controller:lastName,decoration:appFieldDecoration(t('Nom'),icon:Icons.person_outline)),
      const SizedBox(height:12),
      TextField(controller:phone,keyboardType:TextInputType.phone,decoration:appFieldDecoration(t('Téléphone'),icon:Icons.phone_outlined)),
      const SizedBox(height:12),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:appFieldDecoration(t('Email'),icon:Icons.mail_outline)),
      const SizedBox(height:12),
      TextField(controller:password,obscureText:true,decoration:appFieldDecoration(t('Mot de passe'),icon:Icons.lock_outline,helperText:t('10 caractères minimum'))),
      if(offline)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:VeyraOfflineBanner(onRetry:submit)),
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:16),
      VeyraPrimaryButton(label:t('Créer mon compte'),loading:loading,onPressed:submit),
    ])),
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

  @override void initState(){
    super.initState();
    future=api.notifications();
  }

  void reload()=>setState(()=>future=api.notifications());

  IconData _iconFor(String template,String event){
    if(template=='NEW_OFFER')return Icons.local_offer_rounded;
    if(event.contains('driver_en_route'))return Icons.directions_car_rounded;
    if(event.contains('driver_arrived'))return Icons.flag_rounded;
    if(event.contains('completed'))return Icons.check_circle_rounded;
    if(event.contains('cancel'))return Icons.cancel_rounded;
    if(event.contains('no_offer')||event.contains('expired'))return Icons.timer_off_rounded;
    return Icons.notifications_rounded;
  }

  Color _accentFor(String template,String event){
    if(template=='NEW_OFFER')return const Color(0xFF2563EB);
    if(event.contains('completed')||event.contains('driver_arrived')){
      return const Color(0xFF16A34A);
    }
    if(event.contains('cancel')||event.contains('expired')||event.contains('no_offer')){
      return const Color(0xFFDC2626);
    }
    return const Color(0xFF123A66);
  }

  String _detailFor(Map<String,dynamic> x,String template,String event){
    final driver=[
      x['driver_first_name']?.toString().trim(),
      x['driver_last_name']?.toString().trim(),
    ].whereType<String>().where((v)=>v.isNotEmpty).join(' ');
    final amount=x['offer_amount_minor'];

    if(template=='NEW_OFFER'){
      if(amount!=null&&driver.isNotEmpty){
        return t('Offre de ')+driver+' • '+VeyraMoneyFormatter.fromMinor(amount);
      }
      if(amount!=null){
        return t('Nouvelle proposition : ')+VeyraMoneyFormatter.fromMinor(amount);
      }
      return t('Un chauffeur a envoyé une nouvelle offre pour cette réservation.');
    }
    if(event.contains('driver_en_route'))return t('Votre chauffeur est en route vers le point de prise en charge.');
    if(event.contains('driver_arrived'))return t('Votre chauffeur est arrivé au point de prise en charge.');
    if(event.contains('in_progress'))return t('Votre course a démarré.');
    if(event.contains('completed'))return t('Votre course est terminée.');
    if(event.contains('driver_cancelled'))return t('Le chauffeur a annulé. Votre réservation a été remise à jour.');
    if(event.contains('cancel'))return t('Cette réservation a été annulée.');
    if(event.contains('no_offer'))return t('Aucune offre chauffeur n’a été reçue pour cette demande.');
    if(event.contains('expired'))return t('La période de recherche de chauffeur est terminée.');
    return t('Le statut de votre réservation a été mis à jour.');
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF5F7FA),
    appBar:AppBar(
      title:Text(t('Notifications')),
      backgroundColor:const Color(0xFFF5F7FA),
      elevation:0,
    ),
    body:RefreshIndicator(
      onRefresh:()async{
        reload();
        await future;
      },
      child:FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done){
            return ListView(children:const [
              SizedBox(height:220),
              Center(child:CircularProgressIndicator()),
            ]);
          }
          if(s.hasError){
            return ListView(children:[
              const SizedBox(height:150),
              const Icon(Icons.cloud_off_rounded,size:54,color:Color(0xFF9CA3AF)),
              const SizedBox(height:12),
              Center(child:Text(t('Notifications indisponibles.'))),
              Center(child:TextButton(onPressed:reload,child:Text(t('Réessayer')))),
            ]);
          }

          final items=s.data??[];
          if(items.isEmpty){
            return ListView(children:[
              const SizedBox(height:150),
              const Icon(Icons.notifications_none_rounded,size:58,color:Color(0xFF9CA3AF)),
              const SizedBox(height:12),
              Center(child:Text(
                t('Aucune notification pour le moment.'),
                style:const TextStyle(fontWeight:FontWeight.w600),
              )),
            ]);
          }

          return ListView.separated(
            padding:const EdgeInsets.fromLTRB(16,12,16,28),
            itemCount:items.length,
            separatorBuilder:(_,__)=>const SizedBox(height:10),
            itemBuilder:(context,index){
              final x=Map<String,dynamic>.from(items[index] as Map);
              final data=x['data'] is Map
                ?Map<String,dynamic>.from(x['data'] as Map)
                :<String,dynamic>{};
              final bookingId=(x['booking_id']??data['bookingId'])?.toString();
              final template=(x['template_code']??'').toString();
              final event=(x['event_type']??data['event']??'').toString();
              final pickup=x['pickup_address']?.toString();
              final dropoff=x['dropoff_address']?.toString();
              final scheduled=x['scheduled_at'];
              final bookingStatus=x['booking_status']?.toString();
              final accent=_accentFor(template,event);
              final route=(pickup!=null&&dropoff!=null)
                ?'$pickup → $dropoff'
                :t('Réservation Veyra');

              return Material(
                color:Colors.white,
                elevation:1,
                shadowColor:Colors.black12,
                borderRadius:BorderRadius.circular(20),
                child:InkWell(
                  borderRadius:BorderRadius.circular(20),
                  onTap:bookingId==null||bookingId.isEmpty
                    ?null
                    :()=>context.push('/booking/'+bookingId),
                  child:Padding(
                    padding:const EdgeInsets.all(16),
                    child:Column(
                      crossAxisAlignment:CrossAxisAlignment.start,
                      children:[
                        Row(
                          crossAxisAlignment:CrossAxisAlignment.start,
                          children:[
                            Container(
                              width:44,
                              height:44,
                              decoration:BoxDecoration(
                                color:accent.withValues(alpha:.10),
                                borderRadius:BorderRadius.circular(14),
                              ),
                              child:Icon(_iconFor(template,event),color:accent,size:23),
                            ),
                            const SizedBox(width:12),
                            Expanded(child:Column(
                              crossAxisAlignment:CrossAxisAlignment.start,
                              children:[
                                Text(
                                  VeyraStatusLabels.notificationTemplate(template),
                                  style:const TextStyle(
                                    fontWeight:FontWeight.w800,
                                    fontSize:16,
                                  ),
                                ),
                                const SizedBox(height:3),
                                Text(
                                  VeyraDateFormatter.dateTime(x['created_at']),
                                  style:const TextStyle(
                                    color:Color(0xFF9CA3AF),
                                    fontSize:11,
                                  ),
                                ),
                              ],
                            )),
                            if(bookingId!=null)
                              const Icon(Icons.chevron_right_rounded,color:Color(0xFF9CA3AF)),
                          ],
                        ),
                        const SizedBox(height:13),
                        Text(
                          _detailFor(x,template,event),
                          style:const TextStyle(
                            color:Color(0xFF374151),
                            fontSize:14,
                            height:1.35,
                          ),
                        ),
                        const SizedBox(height:12),
                        Container(
                          width:double.infinity,
                          padding:const EdgeInsets.all(12),
                          decoration:BoxDecoration(
                            color:const Color(0xFFF8FAFC),
                            borderRadius:BorderRadius.circular(14),
                          ),
                          child:Column(
                            crossAxisAlignment:CrossAxisAlignment.start,
                            children:[
                              Row(
                                crossAxisAlignment:CrossAxisAlignment.start,
                                children:[
                                  const Icon(Icons.route_rounded,size:18,color:Color(0xFF64748B)),
                                  const SizedBox(width:8),
                                  Expanded(child:Text(
                                    route,
                                    maxLines:2,
                                    overflow:TextOverflow.ellipsis,
                                    style:const TextStyle(
                                      fontWeight:FontWeight.w600,
                                      fontSize:13,
                                      height:1.3,
                                    ),
                                  )),
                                ],
                              ),
                              if(scheduled!=null)...[
                                const SizedBox(height:8),
                                Row(children:[
                                  const Icon(Icons.schedule_rounded,size:17,color:Color(0xFF64748B)),
                                  const SizedBox(width:8),
                                  Text(
                                    VeyraDateFormatter.dateTime(scheduled),
                                    style:const TextStyle(color:Color(0xFF64748B),fontSize:12),
                                  ),
                                ]),
                              ],
                              if(bookingStatus!=null)...[
                                const SizedBox(height:10),
                                VeyraStatusBadge(status:bookingStatus),
                              ],
                            ],
                          ),
                        ),
                        if(bookingId!=null)...[
                          const SizedBox(height:10),
                          Align(
                            alignment:Alignment.centerRight,
                            child:Text(
                              t('Voir la réservation'),
                              style:TextStyle(
                                color:accent,
                                fontSize:12,
                                fontWeight:FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}
