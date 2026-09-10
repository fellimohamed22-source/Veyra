import 'dart:async';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
import 'core/widgets/state_views.dart';
import 'core/widgets/status_badge.dart';

/// Short alias used throughout this file.
String t(String french) => AppLocale.t(french);

bool driverPushHandlersConfigured=false;

void openDriverPush(RemoteMessage message){
  final bookingId=message.data['bookingId'];
  if(bookingId==null)return;
  final template=message.data['templateCode'];
  if(template=='NEW_BOOKING'){
    router.go('/request/'+bookingId);
  }else{
    router.go('/ride/'+bookingId);
  }
}

Future<void> configureDriverPush() async {
  try{
    if(Firebase.apps.isEmpty)await Firebase.initializeApp();
    await FirebaseMessaging.instance.requestPermission();
    final token=await FirebaseMessaging.instance.getToken();
    if(token!=null)await api.registerDevice(token);
    if(!driverPushHandlersConfigured){
      driverPushHandlersConfigured=true;
      FirebaseMessaging.onMessageOpenedApp.listen(openDriverPush);
      final initial=await FirebaseMessaging.instance.getInitialMessage();
      if(initial!=null)openDriverPush(initial);
    }
  }catch(e){
    debugPrint('PUSH_CONFIGURE_FAILED: $e');
  }
}

final api=Api(const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never gate the first frame on anything async that could stall --
  // same lesson as the client app's Stripe fix. French remains correct
  // as the default until this background read resolves.
  unawaited(AppLocale.load());
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
  GoRoute(path:'/register',builder:(c,s)=>const RegisterDriverScreen()),
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
      StatefulShellBranch(routes:[GoRoute(path:'/home',builder:(c,s)=>const OpportunitiesScreen())]),
      StatefulShellBranch(routes:[GoRoute(path:'/agenda',builder:(c,s)=>const AgendaScreen())]),
      StatefulShellBranch(routes:[GoRoute(path:'/wallet',builder:(c,s)=>const WalletScreen())]),
      StatefulShellBranch(routes:[GoRoute(path:'/account',builder:(c,s)=>const AccountScreen())]),
    ],
  ),
  GoRoute(path:'/request/:id',builder:(c,s)=>RequestScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/driver/offers',builder:(c,s)=>const MesOffresScreen()),
  GoRoute(path:'/ride/:id',builder:(c,s)=>RideScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/chat/:id',builder:(c,s)=>DriverChatScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/notifications',builder:(c,s)=>const DriverNotificationsScreen()),
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

  @override void initState(){
    super.initState();
    // Same reasoning as the client app: checked after the first frame
    // rather than via an async GoRouter redirect, which proved
    // genuinely unreliable to settle correctly in widget tests. Mirrors
    // the exact same approved/kyc decision submit() below already makes
    // right after a fresh login.
    WidgetsBinding.instance.addPostFrameCallback((_)async{
      String? token;
      try{
        token=await api.storage.read(key:'accessToken');
      }catch(_){
        return;
      }
      if(token==null||!mounted)return;
      try{
        final status=await api.onboardingStatus();
        final approved=status['kyc_status']=='APPROVED'&&status['marketplace_enabled']==true;
        if(mounted)context.go(approved?'/home':'/kyc');
      }catch(_){
        if(mounted)context.go('/kyc');
      }
    });
  }

  Future<void> submit()async{
    setState((){loading=true;error=null;offline=false;});
    try{
      await api.login(email.text,password.text);
      await configureDriverPush();
      await api.createProfile();
      if(!mounted)return;
      try{
        final status=await api.onboardingStatus();
        final approved=status['kyc_status']=='APPROVED'&&status['marketplace_enabled']==true;
        context.go(approved?'/home':'/kyc');
      }catch(_){
        context.go('/kyc');
      }
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
          Text(t('Espace Chauffeur'),style:const TextStyle(color:Colors.white70,fontSize:14)),
        ]),
      ),
      Expanded(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(t('Connectez-vous à votre compte'),style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:20),
        TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:InputDecoration(labelText:t('Email'),prefixIcon:const Icon(Icons.mail_outline),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none))),
        const SizedBox(height:12),
        TextField(controller:password,obscureText:true,decoration:InputDecoration(labelText:t('Mot de passe'),prefixIcon:const Icon(Icons.lock_outline),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none))),
        if(offline)Padding(padding:const EdgeInsets.only(top:12),child:VeyraOfflineBanner(onRetry:submit)),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
        const SizedBox(height:20),
        VeyraPrimaryButton(label:t('Se connecter'),loading:loading,onPressed:submit),
        TextButton(onPressed:()=>context.push('/register'),child:Text(t('Créer un compte Chauffeur'))),
        TextButton(onPressed:()=>context.push('/forgot'),child:Text(t('Mot de passe oublié ?'))),
      ]))),
    ])));
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

  @override void initState(){
    super.initState();
    future=api.onboardingStatus();
    categories=api.vehicleCategories();
  }

  Future<void> saveProfessionalData()async{
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
      await api.addVehicle(
        categoryId:categoryId!,
        brand:brand.text.trim(),
        model:model.text.trim(),
        year:parsedYear,
        plateNumber:plate.text.trim(),
        color:color.text.trim(),
      );
      if(mounted)setState(()=>message=t('Informations professionnelles enregistrées.'));
    }catch(e){
      if(mounted)setState(()=>message=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>saving=false);
    }
  }

  Future<void> upload(String type)async{
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
    appBar:AppBar(title:Text(t('Dossier Chauffeur VTC'))),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        final status=s.data??{};
        final approved=status['kyc_status']=='APPROVED'&&status['marketplace_enabled']==true;

        return ListView(padding:const EdgeInsets.all(20),children:[
          Card(child:ListTile(
            leading:Icon(approved?Icons.verified:Icons.pending_actions),
            title:Text(approved?t('Dossier approuvé'):t('Vérification en cours')),
            subtitle:Text(t('Statut du dossier')+' : '+VeyraStatusLabels.kycStatus(status['kyc_status']?.toString())),
          )),
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
              final items=cs.data??[];
              return DropdownButtonFormField<String>(
                initialValue:categoryId,
                decoration:InputDecoration(labelText:t('Catégorie')),
                items:items.map((raw){
                  final x=Map<String,dynamic>.from(raw as Map);
                  return DropdownMenuItem<String>(
                    value:x['id'].toString(),
                    child:Text((x['display_name']??x['code']).toString()),
                  );
                }).toList(),
                onChanged:(v)=>setState(()=>categoryId=v),
              );
            },
          ),
          TextField(controller:brand,decoration:InputDecoration(labelText:t('Marque'))),
          TextField(controller:model,decoration:InputDecoration(labelText:t('Modèle'))),
          TextField(controller:year,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t('Année'))),
          TextField(controller:plate,decoration:InputDecoration(labelText:t('Immatriculation'))),
          TextField(controller:color,decoration:InputDecoration(labelText:t('Couleur'))),
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
          ])
            Card(child:ListTile(
              title:Text(item.$2),
              subtitle:Text(t('PDF, JPG ou PNG — 10 Mo max')),
              trailing:uploadingType==item.$1
                ?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2))
                :IconButton(onPressed:()=>upload(item.$1),tooltip:t('Téléverser'),icon:const Icon(Icons.upload_file)),
            )),
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
  final pickupFilter=TextEditingController();
  final destinationFilter=TextEditingController();
  int? minPassengers;
  late Future<List<dynamic>> future;

  @override void initState(){super.initState();future=load();}
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    routeObserver.subscribe(this,ModalRoute.of(context) as PageRoute);
  }
  @override void dispose(){routeObserver.unsubscribe(this);super.dispose();}
  // Real gap fixed here: returning from submitting an offer, or from
  // anywhere else, never refreshed the request list -- same stale
  // Future stayed in place until the app was fully closed and reopened.
  // ATTENTION -- non vérifié sur appareil réel depuis l'introduction du
  // shell de navigation (LOT 4) : cet écran vit désormais dans le
  // Navigator imbriqué de sa branche, potentiellement différent du
  // Navigator racine où /request/:id est réellement poussé/dépilé.
  // Pull-to-refresh (RefreshIndicator ailleurs) et reload() manuel
  // restent le filet de sécurité si ce callback ne se déclenche plus.
  @override void didPopNext(){setState((){future=load();});}
  Future<List<dynamic>> load()=>api.opportunities(
    sort:sort,
    pickupQuery:pickupFilter.text,
    destinationQuery:destinationFilter.text,
    minPassengers:minPassengers,
  );
  void reload()=>setState((){future=load();});

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Demandes disponibles')),actions:[
      IconButton(onPressed:()=>context.push('/driver/offers'),icon:const Icon(Icons.local_offer_outlined),tooltip:t('Mes offres')),
      IconButton(onPressed:()=>context.push('/notifications'),tooltip:t('Notifications'),icon:const Icon(Icons.notifications_outlined)),
    ]),
    body:RefreshIndicator(
      onRefresh:()async{reload();await future;},
      child:ListView(padding:const EdgeInsets.all(16),children:[
        DropdownButtonFormField<String>(
          initialValue:sort,
          decoration:InputDecoration(labelText:t('Trier les demandes')),
          items:[
            DropdownMenuItem(value:'date',child:Text(t('Date de départ'))),
            DropdownMenuItem(value:'newest',child:Text(t('Plus récentes'))),
            DropdownMenuItem(value:'pickup',child:Text(t('Lieu de départ (A → Z)'))),
            DropdownMenuItem(value:'destination',child:Text(t('Destination (A → Z)'))),
          ],
          onChanged:(v){if(v!=null){sort=v;reload();}},
        ),
        const SizedBox(height:10),
        ExpansionTile(
          tilePadding:EdgeInsets.zero,
          title:Text(t('Filtres')),
          children:[
            TextField(controller:pickupFilter,decoration:InputDecoration(labelText:t('Lieu de départ contient'))),
            const SizedBox(height:8),
            TextField(controller:destinationFilter,decoration:InputDecoration(labelText:t('Destination contient'))),
            const SizedBox(height:8),
            DropdownButtonFormField<int?>(
              initialValue:minPassengers,
              decoration:InputDecoration(labelText:t('Minimum passagers')),
              items:[DropdownMenuItem<int?>(value:null,child:Text(t('Tous'))), ...List.generate(8,(i)=>DropdownMenuItem<int?>(value:i+1,child:Text('${i+1}+')))],
              onChanged:(v)=>setState(()=>minPassengers=v),
            ),
            const SizedBox(height:10),
            Row(children:[
              Expanded(child:OutlinedButton(onPressed:(){pickupFilter.clear();destinationFilter.clear();setState(()=>minPassengers=null);reload();},child:Text(t('Réinitialiser')))),
              const SizedBox(width:8),
              Expanded(child:FilledButton(onPressed:reload,child:Text(t('Appliquer')))),
            ]),
          ],
        ),
        Text(t('Aucun tri par proximité. Les chauffeurs ne voient jamais les prix concurrents.')),
        const SizedBox(height:16),
        FutureBuilder<List<dynamic>>(
          future:future,
          builder:(context,s){
            if(s.connectionState!=ConnectionState.done)return const Center(child:Padding(padding:EdgeInsets.all(32),child:CircularProgressIndicator()));
            if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
              ?VeyraOfflineBanner(onRetry:reload)
              :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:reload);
            final items=s.data??[];
            if(items.isEmpty)return Card(child:ListTile(
              leading:Icon(Icons.inbox_outlined),title:Text(t('Aucune demande ouverte')),
              subtitle:Text(t('Les nouvelles demandes apparaîtront ici.')),
            ));
            return Column(children:items.map((raw){
              final x=Map<String,dynamic>.from(raw as Map);
              final id=x['id'].toString();
              final title=(x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString();
              return Card(child:ListTile(
                title:Text(title),subtitle:Text(VeyraDateFormatter.dateTime(x['scheduled_at'])),
                trailing:const Icon(Icons.chevron_right),onTap:()=>context.push('/request/'+id),
              ));
            }).toList());
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

  @override void initState(){
    super.initState();
    tabController=TabController(length:3,vsync:this);
    _load();
  }

  void _load(){
    active=api.driverOffers(scope:'active');
    won=api.driverOffers(scope:'won');
    closed=api.driverOffers(scope:'closed');
  }

  @override void dispose(){
    tabController.dispose();
    super.dispose();
  }

  Widget _list(Future<List<dynamic>> future,{required bool isWon}){
    return RefreshIndicator(
      onRefresh:()async{setState(_load);await future;},
      child:FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done){
            return const VeyraLoadingView();
          }
          if(s.hasError){
            return VeyraErrorMessages.isOffline(s.error!)
              ?VeyraOfflineBanner(onRetry:()=>setState(_load))
              :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState(_load));
          }
          final items=s.data??[];
          if(items.isEmpty){
            return VeyraEmptyView(
              icon:Icons.local_offer_outlined,
              message:t('Aucune offre dans cette catégorie.'),
            );
          }
          return ListView.builder(
            padding:const EdgeInsets.all(16),
            itemCount:items.length,
            itemBuilder:(context,i){
              final x=Map<String,dynamic>.from(items[i] as Map);
              final title=(x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString();
              final bookingId=x['booking_id']?.toString();
              return Card(
                margin:const EdgeInsets.only(bottom:10),
                child:ListTile(
                  contentPadding:const EdgeInsets.all(14),
                  title:Text(title,style:const TextStyle(fontWeight:FontWeight.w600)),
                  subtitle:Padding(
                    padding:const EdgeInsets.only(top:6),
                    child:Text(VeyraDateFormatter.dateTime(x['scheduled_at'])),
                  ),
                  trailing:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.end,children:[
                    Text(VeyraMoneyFormatter.fromMinor(x['proposed_amount_minor']),style:const TextStyle(fontWeight:FontWeight.bold)),
                    const SizedBox(height:4),
                    Text(VeyraStatusLabels.offerStatus(x['status']?.toString()),style:const TextStyle(fontSize:12,color:Colors.black54)),
                  ]),
                  onTap:bookingId==null?null:(){
                    // Fiche D18 : "Offre gagnante -> D19" (réservation
                    // attribuée), "Demande encore ouverte -> D15" (détail
                    // demande, où l'offre déjà soumise est visible).
                    if(isWon){
                      context.push('/ride/'+bookingId);
                    }else{
                      context.push('/request/'+bookingId);
                    }
                  },
                ),
              );
            },
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
        Tab(text:t('Retenues')),
        Tab(text:t('Closes')),
      ]),
    ),
    body:TabBarView(controller:tabController,children:[
      _list(active,isWon:false),
      _list(won,isWon:true),
      _list(closed,isWon:false),
    ]),
  );
}

class RequestScreen extends StatefulWidget{
  final String bookingId;
  const RequestScreen({required this.bookingId,super.key});
  @override State<RequestScreen> createState()=>_RequestScreenState();
}
class _RequestScreenState extends State<RequestScreen>{
  final amount=TextEditingController();
  late Future<Map<String,dynamic>> detail;
  bool sending=false;
  String? error;

  @override void initState(){
    super.initState();
    detail=api.opportunityDetail(widget.bookingId);
  }

  Future<void> submit()async{
    final euros=double.tryParse(amount.text.replaceAll(',','.'));
    if(euros==null||euros<=0){setState(()=>error=t('Saisissez un prix valide.'));return;}
    setState((){sending=true;error=null;});
    try{
      await api.offer(widget.bookingId,(euros*100).round());
      if(!mounted)return;
      // Spec section 2, explicit: "The current Driver implementation
      // contains post-submit comparison messaging such as
      // differenceFromBestMinor / 'your offer is X more expensive'.
      // Remove this competitive comparison from the USER INTERFACE."
      // Backend still returns and computes these fields (not a backend
      // bug, not touched) -- simply never surfaced in this dialog
      // anymore.
      await showDialog(context:context,builder:(_)=>AlertDialog(
        title:Text(t('Offre envoyée')),
        content:Text(t('Votre offre : ')+VeyraMoneyFormatter.fromMinor((euros*100).round())+'\n'+t('Vous serez averti si le client vous sélectionne.')),
        actions:[FilledButton(onPressed:()=>Navigator.pop(context),child:Text(t('OK')))],
      ));
      if(mounted)context.go('/home');
    }on DioException catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }catch(_){
      if(mounted)setState(()=>error=t('L’offre n’a pas pu être envoyée ou la demande est déjà fermée.'));
    }finally{
      if(mounted)setState(()=>sending=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Proposer un prix'))),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      FutureBuilder<Map<String,dynamic>>(
        future:detail,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
          if(s.hasError)return Card(child:ListTile(
            leading:const Icon(Icons.error_outline),
            title:Text(t('Demande indisponible')),
            subtitle:Text(t('Elle a peut-être déjà été fermée.')),
            trailing:TextButton(onPressed:()=>setState((){detail=api.opportunityDetail(widget.bookingId);}),child:Text(t('Réessayer'))),
          ));
          final x=s.data??{};
          return Column(children:[
            Card(child:ListTile(
              leading:const Icon(Icons.route),
              title:Text((x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString()),
              subtitle:Text(VeyraDateFormatter.dateTime(x['scheduled_at'])+'\n'+(x['category_name']??'').toString()),
              isThreeLine:true,
            )),
            Card(child:ListTile(
              leading:const Icon(Icons.luggage_outlined),
              title:Text((x['passenger_count']??1).toString()+' passager(s)'),
              subtitle:Text((x['baggage_count']??0).toString()+' bagage(s)'+((x['customer_notes']??'').toString().isEmpty?'':' • '+x['customer_notes'].toString())),
            )),
          ]);
        },
      ),
      FutureBuilder<Map<String,dynamic>>(
        future:detail,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const SizedBox.shrink();
          if(s.hasError)return const SizedBox.shrink();
          final x=s.data??{};
          final mode=(x['offer_visibility_mode']??'PRIVATE').toString();
          if(mode=='BEST_VISIBLE'){
            final bestMinor=x['currentBestOtherOfferMinor'];
            final subtitle=bestMinor==null
              ?t('Aucune autre offre active pour le moment. Vous restez libre de fixer votre prix.')
              :t('Meilleure offre actuelle des autres chauffeurs')+' : '+VeyraMoneyFormatter.fromMinor(bestMinor);
            return Card(child:ListTile(
              leading:const Icon(Icons.visibility_outlined),
              title:Text(t('Meilleure offre visible')),
              subtitle:Text(subtitle),
            ));
          }
          return Card(child:ListTile(
            leading:const Icon(Icons.visibility_off_outlined),title:Text(t('Offre privée')),
            subtitle:Text(t('Les offres des autres chauffeurs et le meilleur prix ne sont jamais affichés.')),
          ));
        },
      ),
      FutureBuilder<Map<String,dynamic>>(
        future:detail,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const SizedBox.shrink();
          if(s.hasError)return const SizedBox.shrink();
          final x=s.data??{};
          // Gap réel trouvé : hasActiveOffer existait déjà côté backend
          // (DriverOpportunityController) mais n'était lu nulle part côté
          // Flutter -- un chauffeur ayant déjà soumis une offre retombait
          // sur ce même formulaire vide, pouvait retaper un prix et
          // recevait alors ACTIVE_OFFER_EXISTS sans comprendre pourquoi.
          if(x['hasActiveOffer']==true){
            return Card(child:ListTile(
              leading:const Icon(Icons.check_circle_outline,color:Color(0xFF16A34A)),
              title:Text(t('Vous avez déjà une offre active pour cette demande.')),
              subtitle:Text(t('Retrouvez-la dans Mes offres.')),
              trailing:TextButton(onPressed:()=>context.push('/driver/offers'),child:Text(t('Voir'))),
            ));
          }
          return Column(children:[
            TextField(
              controller:amount,
              keyboardType:const TextInputType.numberWithOptions(decimal:true),
              decoration:InputDecoration(
                labelText:t('Votre prix net (€)'),
                helperText:t('C’est le montant exact que vous devez recevoir pour la course.'),
              ),
            ),
            if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
            const SizedBox(height:20),
            FilledButton(onPressed:sending?null:submit,child:sending?const CircularProgressIndicator():Text(t('Envoyer mon offre'))),
          ]);
        },
      ),
    ]),
  );
}

class AgendaScreen extends StatefulWidget{
  const AgendaScreen({super.key});
  @override State<AgendaScreen> createState()=>_AgendaScreenState();
}
class _AgendaScreenState extends State<AgendaScreen>{
  late Future<List<dynamic>> future;
  @override void initState(){super.initState();future=api.bookings();}

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Mes courses à venir'))),
    body:FutureBuilder<List<dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
          ?VeyraOfflineBanner(onRetry:()=>setState((){future=api.bookings();}))
          :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState((){future=api.bookings();}));
        final items=s.data??[];
        if(items.isEmpty)return Center(child:Text(t('Aucune course confirmée.')));
        return ListView(padding:const EdgeInsets.all(16),children:items.map((raw){
          final x=Map<String,dynamic>.from(raw as Map);
          return Card(child:ListTile(
            title:Text((x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString()),
            subtitle:Text(VeyraDateFormatter.dateTime(x['scheduled_at'])),
            trailing:Row(mainAxisSize:MainAxisSize.min,children:[
              VeyraStatusBadge(status:(x['status']??'').toString()),
              const SizedBox(width:4),
              const Icon(Icons.chevron_right),
            ]),
            onTap:()=>context.push('/ride/'+x['id'].toString()),
          ));
        }).toList());
      },
    ),
  );
}

class RideScreen extends StatefulWidget{
  final String bookingId;
  const RideScreen({required this.bookingId,super.key});
  @override State<RideScreen> createState()=>_RideScreenState();
}
class _RideScreenState extends State<RideScreen>{
  late Future<Map<String,dynamic>> future;
  final pin=TextEditingController();
  bool busy=false;
  String? error;
  Timer? gpsTimer;
  Position? position;
  Map<String,dynamic>? etaInfo;
  int sequence=0;
  DateTime? lastEtaRefresh;
  int ratingScore=0;
  bool ratingSubmitting=false;
  bool ratingSubmitted=false;

  @override void initState(){
    super.initState();
    future=api.bookingDetail(widget.bookingId);
  }

  @override void dispose(){
    gpsTimer?.cancel();
    super.dispose();
  }

  void reload()=>setState((){future=api.bookingDetail(widget.bookingId);});

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
        else error=t('Impossible d’envoyer la note pour le moment.');
        ratingSubmitting=false;
      });
    }
  }

  Future<bool> ensureLocationPermission()async{
    if(!await Geolocator.isLocationServiceEnabled()){
      if(mounted)setState(()=>error=t('Activez la localisation du téléphone.'));
      return false;
    }
    var permission=await Geolocator.checkPermission();
    if(permission==LocationPermission.denied){
      permission=await Geolocator.requestPermission();
    }
    if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever){
      if(mounted)setState(()=>error=t('La localisation est obligatoire pendant la prise en charge et la course.'));
      return false;
    }
    return true;
  }

  Future<void> sendLocation()async{
    if(!await ensureLocationPermission())return;
    try{
      final p=await Geolocator.getCurrentPosition(
        locationSettings:const LocationSettings(accuracy:LocationAccuracy.high),
      );
      sequence++;
      await api.updateLocation(
        bookingId:widget.bookingId,
        lat:p.latitude,
        lng:p.longitude,
        sequenceNo:sequence,
        accuracyM:p.accuracy,
        heading:p.heading,
        speedMps:p.speed,
      );
      if(mounted)setState(()=>position=p);
      final now=DateTime.now();
      if(lastEtaRefresh==null||now.difference(lastEtaRefresh!)>=const Duration(seconds:30)){
        lastEtaRefresh=now;
        await refreshEta(p);
      }
    }catch(_){
      if(mounted)setState(()=>error=t('Position GPS momentanément indisponible.'));
    }
  }

  Future<void> refreshEta(Position p)async{
    try{
      final x=await api.bookingDetail(widget.bookingId);
      final status=(x['status']??'').toString();
      double? toLat;
      double? toLng;
      if(status=='DRIVER_EN_ROUTE'||status=='DRIVER_ARRIVED'){
        toLat=(x['pickup_lat'] as num?)?.toDouble();
        toLng=(x['pickup_lng'] as num?)?.toDouble();
      }else if(status=='IN_PROGRESS'){
        toLat=(x['dropoff_lat'] as num?)?.toDouble();
        toLng=(x['dropoff_lng'] as num?)?.toDouble();
      }
      if(toLat==null||toLng==null)return;
      final eta=await api.routeEstimate(
        fromLat:p.latitude,fromLng:p.longitude,toLat:toLat,toLng:toLng);
      if(mounted)setState(()=>etaInfo=eta);
    }catch(_){}
  }

  void startTracking(){
    gpsTimer?.cancel();
    sendLocation();
    gpsTimer=Timer.periodic(const Duration(seconds:10),(_)=>sendLocation());
  }

  void stopTracking(){
    gpsTimer?.cancel();
    gpsTimer=null;
  }

  Future<void> action(Future<void> Function() fn,{bool startGps=false,bool stopGps=false})async{
    setState((){busy=true;error=null;});
    try{
      await fn();
      if(startGps)startTracking();
      if(stopGps)stopTracking();
      reload();
    }catch(e){
      if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Course'))),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
          ?VeyraOfflineBanner(onRetry:reload)
          :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:reload);
        final x=s.data??{};
        final status=(x['status']??'').toString();
        final phone=x['customer_phone']?.toString();
        final paymentMethod=(x['payment_method']??'').toString();
        final pickupLat=(x['pickup_lat'] as num?)?.toDouble();
        final pickupLng=(x['pickup_lng'] as num?)?.toDouble();
        final dropoffLat=(x['dropoff_lat'] as num?)?.toDouble();
        final dropoffLng=(x['dropoff_lng'] as num?)?.toDouble();
        final lat=position?.latitude??pickupLat??43.2965;
        final lng=position?.longitude??pickupLng??5.3698;

        if({'DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'}.contains(status)&&gpsTimer==null){
          WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)startTracking();});
        }

        return ListView(padding:const EdgeInsets.all(20),children:[
          SizedBox(
            height:240,
            child:ClipRRect(
              borderRadius:BorderRadius.circular(20),
              child:FlutterMap(
                options:MapOptions(initialCenter:LatLng(lat,lng),initialZoom:position==null?9:14),
                children:[
                  TileLayer(
                    urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName:'com.veyra.driver',
                  ),
                  MarkerLayer(markers:[
                    if(pickupLat!=null&&pickupLng!=null)Marker(
                      point:LatLng(pickupLat,pickupLng),width:44,height:44,
                      child:const Icon(Icons.trip_origin,size:34),
                    ),
                    if(dropoffLat!=null&&dropoffLng!=null)Marker(
                      point:LatLng(dropoffLat,dropoffLng),width:44,height:44,
                      child:const Icon(Icons.location_on,size:38),
                    ),
                    if(position!=null)Marker(
                      point:LatLng(lat,lng),width:56,height:56,
                      child:const Icon(Icons.local_taxi,size:44),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height:16),
          Text((x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString(),
            style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          Text(t('Statut')+' : '+VeyraStatusLabels.bookingStatus(status)),
          if(etaInfo!=null)Card(child:ListTile(
            leading:const Icon(Icons.schedule),
            title:Text(t('ETA : ')+VeyraMoneyFormatter.duration(etaInfo!['durationSeconds'])),
            subtitle:Text(VeyraMoneyFormatter.distance(etaInfo!['distanceMeters'])+' '+t('restant(s)')),
          )),
          if(x['customer_name']!=null)Text(t('Client : ')+x['customer_name'].toString()),
          if(paymentMethod=='CASH')Card(child:ListTile(
            leading:const Icon(Icons.payments_outlined),
            title:Text(t('Montant à encaisser au client : ')+VeyraMoneyFormatter.fromMinor(x['customer_total_amount_minor'])),
            subtitle:Text(t('Votre montant net : ')+VeyraMoneyFormatter.fromMinor(x['driver_net_amount_minor'])+' • '+t('Commission Veyra : ')+VeyraMoneyFormatter.fromMinor(x['platform_commission_amount_minor'])+' '+t('(dette CASH après la course)')),
          )),
          if(paymentMethod=='ONLINE')Card(child:ListTile(
            leading:const Icon(Icons.credit_card),
            title:Text(t('Paiement en ligne • Net chauffeur ')+VeyraMoneyFormatter.fromMinor(x['driver_net_amount_minor'])),
            subtitle:Text(t('Le paiement doit être capturé avant le démarrage de la course.')),
          )),
          if(paymentMethod=='PARTNER_INVOICE')Card(child:ListTile(
            leading:const Icon(Icons.receipt_long),
            title:Text(t('Facturation partenaire • Net chauffeur ')+VeyraMoneyFormatter.fromMinor(x['driver_net_amount_minor'])),
            subtitle:Text(t('Le partenaire est facturé par Veyra selon son contrat.')),
          )),
          if(error!=null)Padding(
            padding:const EdgeInsets.symmetric(vertical:10),
            child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
          ),
          if(status=='CONFIRMED')...[
            FilledButton(onPressed:busy?null:()=>action(()=>api.enRoute(widget.bookingId),startGps:true),child:Text(t('Je suis en route'))),
            TextButton(
              onPressed:busy?null:()async{
                final confirm=await showDialog<bool>(
                  context:context,
                  builder:(dialogContext)=>AlertDialog(
                    title:Text(t('Annuler cette course ?')),
                    content:Text(t('La réservation sera republiée en priorité si le délai le permet. Cette annulation impactera votre qualité chauffeur.')),
                    actions:[
                      TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:Text(t('Garder la course'))),
                      FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:Text(t('Confirmer l’annulation'))),
                    ],
                  ),
                );
                if(confirm!=true)return;
                setState(()=>busy=true);
                try{
                  final result=await api.cancelAssignedBooking(widget.bookingId);
                  stopTracking();
                  if(mounted){
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content:Text(result['republished']==true
                        ?t('Course annulée et demande republiée.')
                        :t('Course annulée. Le support Veyra a été alerté.'))),
                    );
                    context.go('/agenda');
                  }
                }catch(e){
                  if(mounted)setState(()=>error=VeyraErrorMessages.forException(e));
                }finally{
                  if(mounted)setState(()=>busy=false);
                }
              },
              child:Text(t('Annuler ma prise en charge')),
            ),
          ],
          if(status=='DRIVER_EN_ROUTE')
            FilledButton(onPressed:busy?null:()=>action(()=>api.arrived(widget.bookingId)),child:Text(t('Je suis arrivé'))),
          if(status=='DRIVER_ARRIVED')...[
            TextField(
              controller:pin,maxLength:4,keyboardType:TextInputType.number,
              decoration:InputDecoration(labelText:t('PIN client (4 chiffres)')),
            ),
            FilledButton(onPressed:busy?null:()=>action(()=>api.start(widget.bookingId,pin.text),startGps:true),child:Text(t('Démarrer la course'))),
            TextButton(onPressed:busy?null:()=>action(()=>api.noShow(widget.bookingId),stopGps:true),child:Text(t('Signaler un no-show'))),
          ],
          if(status=='IN_PROGRESS')
            FilledButton(onPressed:busy?null:()=>action(()=>api.complete(widget.bookingId),stopGps:true),child:Text(t('Terminer la course'))),
          if({'COMPLETED','CLOSED'}.contains(status))
            Card(child:Padding(padding:const EdgeInsets.all(16),child:ratingSubmitted?Row(children:[Icon(Icons.check_circle,color:Colors.green),SizedBox(width:8),Text(t('Merci pour votre avis !'))]):Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(t('Noter le client'),style:const TextStyle(fontWeight:FontWeight.bold)),
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
          const SizedBox(height:10),
          if(status=='DRIVER_EN_ROUTE'&&pickupLat!=null&&pickupLng!=null)
            OutlinedButton.icon(
              onPressed:()=>launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$pickupLat,$pickupLng&travelmode=driving'),mode:LaunchMode.externalApplication),
              icon:const Icon(Icons.navigation_outlined),label:Text(t('Naviguer vers le client')),
            ),
          if(status=='IN_PROGRESS'&&dropoffLat!=null&&dropoffLng!=null)
            OutlinedButton.icon(
              onPressed:()=>launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dropoffLat,$dropoffLng&travelmode=driving'),mode:LaunchMode.externalApplication),
              icon:const Icon(Icons.navigation_outlined),label:Text(t('Naviguer vers la destination')),
            ),
          OutlinedButton.icon(
            onPressed:phone==null||phone.isEmpty?null:()=>launchUrl(Uri(scheme:'tel',path:phone)),
            icon:const Icon(Icons.phone_outlined),label:Text(t('Appeler le client')),
          ),
          OutlinedButton.icon(onPressed:()=>context.push('/chat/'+widget.bookingId),icon:const Icon(Icons.chat_bubble_outline),label:Text(t('Chat Veyra'))),
        ]);
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
  @override void initState(){super.initState();future=api.wallet();}

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Portefeuille'))),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
          ?VeyraOfflineBanner(onRetry:()=>setState((){future=api.wallet();}))
          :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState((){future=api.wallet();}));
        final x=s.data??{};
        return ListView(padding:const EdgeInsets.all(20),children:[
          Card(child:ListTile(title:Text(t('À recevoir (ONLINE)')),trailing:Text(VeyraMoneyFormatter.fromMinor(x['onlinePayableMinor'])))),
          Card(child:ListTile(title:Text(t('Dette commission CASH')),trailing:Text(VeyraMoneyFormatter.fromMinor(x['cashDebtMinor'])))),
          if(x['cashWarning']==true)Card(child:ListTile(
            leading:const Icon(Icons.warning_amber),title:Text(t('Seuil de dette atteint')),
            subtitle:Text(
              t('Alerte')+' ${VeyraMoneyFormatter.fromMinor(x['cashWarningThresholdMinor'])}'
              ' • '+t('restriction CASH')+' ${VeyraMoneyFormatter.fromMinor(x['cashRestrictedThresholdMinor'])}'
              ' • '+t('blocage CASH')+' ${VeyraMoneyFormatter.fromMinor(x['cashBlockedThresholdMinor'])}',
            ),
          )),
        ]);
      },
    ),
  );
}


/// Écran Compte minimal côté chauffeur : identité, statut KYC, langue,
/// déconnexion. Miroir de AccountScreen côté client.
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
          ?VeyraOfflineBanner(onRetry:()=>setState(()=>future=api.me()))
          :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState(()=>future=api.me()));
        final me=s.data??{};
        final firstName=(me['first_name']??'').toString();
        final lastName=(me['last_name']??'').toString();
        final email=(me['email']??'').toString();
        return ListView(padding:const EdgeInsets.all(20),children:[
          Card(child:ListTile(
            leading:const CircleAvatar(child:Icon(Icons.person)),
            title:Text('$firstName $lastName'.trim().isEmpty?t('Chauffeur Veyra'):'$firstName $lastName'.trim()),
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
        NavigationDestination(icon:const Icon(Icons.list_alt_outlined),selectedIcon:const Icon(Icons.list_alt),label:t('Demandes')),
        NavigationDestination(icon:const Icon(Icons.calendar_month_outlined),selectedIcon:const Icon(Icons.calendar_month),label:t('Planning')),
        NavigationDestination(icon:const Icon(Icons.account_balance_wallet_outlined),selectedIcon:const Icon(Icons.account_balance_wallet),label:t('Revenus')),
        NavigationDestination(icon:const Icon(Icons.person_outline),selectedIcon:const Icon(Icons.person),label:t('Compte')),
      ],
    ),
  );
}

class RegisterDriverScreen extends StatefulWidget{
  const RegisterDriverScreen({super.key});
  @override State<RegisterDriverScreen> createState()=>_RegisterDriverScreenState();
}
class _RegisterDriverScreenState extends State<RegisterDriverScreen>{
  final firstName=TextEditingController();
  final lastName=TextEditingController();
  final phone=TextEditingController();
  final email=TextEditingController();
  final password=TextEditingController();
  bool loading=false;
  String? error;

  Future<void> submit()async{
    if(firstName.text.trim().isEmpty||email.text.trim().isEmpty||password.text.length<10){
      setState(()=>error=t('Prénom, e-mail et mot de passe de 10 caractères minimum requis.'));
      return;
    }
    setState((){loading=true;error=null;});
    try{
      await api.register(
        email:email.text,
        password:password.text,
        firstName:firstName.text,
        lastName:lastName.text,
        phone:phone.text,
      );
      await api.createProfile();
      await configureDriverPush();
      if(mounted)context.go('/kyc');
    }catch(_){
      if(mounted)setState(()=>error=t('Création du compte impossible.'));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Créer un compte Chauffeur'))),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
      TextField(controller:firstName,decoration:InputDecoration(labelText:t('Prénom'))),
      const SizedBox(height:12),
      TextField(controller:lastName,decoration:InputDecoration(labelText:t('Nom'))),
      const SizedBox(height:12),
      TextField(controller:phone,keyboardType:TextInputType.phone,decoration:InputDecoration(labelText:t('Téléphone'))),
      const SizedBox(height:12),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:InputDecoration(labelText:t('Email'))),
      const SizedBox(height:12),
      TextField(controller:password,obscureText:true,decoration:InputDecoration(labelText:t('Mot de passe'),helperText:'10 caractères minimum')),
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:16),
      FilledButton(onPressed:loading?null:submit,child:loading?Text(t('Création…')):Text(t('Continuer vers mon dossier VTC'))),
    ])),
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


class DriverNotificationsScreen extends StatefulWidget{
  const DriverNotificationsScreen({super.key});
  @override State<DriverNotificationsScreen> createState()=>_DriverNotificationsScreenState();
}

class _DriverNotificationsScreenState extends State<DriverNotificationsScreen>{
  late Future<List<dynamic>> future;
  @override void initState(){super.initState();future=api.notifications();}
  void reload()=>setState((){future=api.notifications();});

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Notifications'))),
    body:RefreshIndicator(
      onRefresh:()async{reload();await future;},
      child:FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done){
            return ListView(children:const [SizedBox(height:220),Center(child:CircularProgressIndicator())]);
          }
          if(s.hasError){
            return ListView(children:[
              const SizedBox(height:160),
              const Icon(Icons.cloud_off,size:48),
              Center(child:Text(t('Notifications indisponibles.'))),
              Center(child:TextButton(onPressed:reload,child:Text(t('Réessayer')))),
            ]);
          }
          final items=s.data??[];
          if(items.isEmpty){
            return ListView(children:[
              SizedBox(height:160),
              Icon(Icons.notifications_none,size:56),
              Center(child:Text(t('Aucune notification pour le moment.'))),
            ]);
          }
          return ListView.separated(
            padding:const EdgeInsets.all(16),
            itemCount:items.length,
            separatorBuilder:(_,__)=>const SizedBox(height:8),
            itemBuilder:(context,index){
              final x=Map<String,dynamic>.from(items[index] as Map);
              final data=x['data'] is Map?Map<String,dynamic>.from(x['data'] as Map):<String,dynamic>{};
              final bookingId=data['bookingId']?.toString();
              final template=(x['template_code']??'').toString();
              return Card(child:ListTile(
                leading:const Icon(Icons.notifications_active_outlined),
                title:Text(VeyraStatusLabels.notificationTemplate(template)),
                subtitle:Text(VeyraDateFormatter.dateTime(x['created_at'])),
                trailing:bookingId==null?null:const Icon(Icons.chevron_right),
                onTap:bookingId==null?null:(){
                  if(template=='NEW_BOOKING')context.push('/request/'+bookingId);
                  else context.push('/ride/'+bookingId);
                },
              ));
            },
          );
        },
      ),
    ),
  );
}
