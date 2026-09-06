import 'dart:async';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'app_locale.dart';

/// Short alias used throughout this file -- AppLocale.t() everywhere
/// would be far noisier across ~100 call sites.
String t(String french) => AppLocale.t(french);

bool pushHandlersConfigured=false;

void openPush(RemoteMessage message){
  final bookingId=message.data['bookingId'];
  if(bookingId==null)return;
  final template=message.data['templateCode'];
  if(template=='NEW_OFFER'){
    router.go('/offers/'+bookingId);
  }else{
    router.go('/booking/'+bookingId);
  }
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
  }catch(_){}
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

class App extends StatelessWidget{
  const App({super.key});
  @override Widget build(BuildContext context)=>ValueListenableBuilder<String>(
    valueListenable:AppLocale.code,
    builder:(context,localeCode,_)=>MaterialApp.router(
      title:'Veyra',
      theme:ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xFF1565C0)),
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

final router=GoRouter(initialLocation:'/login',routes:[
  GoRoute(path:'/login',builder:(c,s)=>const LoginScreen()),
  GoRoute(path:'/register',builder:(c,s)=>const RegisterScreen()),
  GoRoute(path:'/forgot',builder:(c,s)=>const ForgotPasswordScreen()),
  GoRoute(path:'/home',builder:(c,s)=>const HomeScreen()),
  GoRoute(path:'/addresses',builder:(c,s)=>const AddressScreen()),
  GoRoute(path:'/offers/:id',builder:(c,s)=>OffersScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/payment/:id',builder:(c,s)=>PaymentScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/booking/:id',builder:(c,s)=>BookingDetailScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/chat/:id',builder:(c,s)=>ChatScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/live/:id',builder:(c,s)=>LiveLocationScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/notifications',builder:(c,s)=>const NotificationsScreen()),
]);

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

/// Colored status badge matching the mockup's chip treatment (green for
/// confirmed/completed states, blue for in-progress, amber for pending,
/// red for cancelled) -- replaces plain status text with something that
/// reads at a glance.
Widget statusBadge(String status){
  final Map<String,Color> colors={
    'OPEN_FOR_OFFERS':const Color(0xFFF59E0B),
    'OFFERS_RECEIVED':const Color(0xFFF59E0B),
    'CONFIRMED':const Color(0xFF2563EB),
    'DRIVER_EN_ROUTE':const Color(0xFF2563EB),
    'DRIVER_ARRIVED':const Color(0xFF2563EB),
    'IN_PROGRESS':const Color(0xFF2563EB),
    'COMPLETED':const Color(0xFF16A34A),
    'CLOSED':const Color(0xFF16A34A),
    'CANCELLED':const Color(0xFFDC2626),
    'DRIVER_CANCELLED':const Color(0xFFDC2626),
    'CUSTOMER_NO_SHOW':const Color(0xFFDC2626),
  };
  final color=colors[status]??const Color(0xFF6B7280);
  return Container(
    padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
    decoration:BoxDecoration(color:color.withValues(alpha:0.12),borderRadius:BorderRadius.circular(20)),
    child:Text(status.replaceAll('_',' '),style:TextStyle(color:color,fontSize:12,fontWeight:FontWeight.w600)),
  );
}

class LoginScreen extends StatefulWidget{
  const LoginScreen({super.key});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen>{
  final email=TextEditingController();
  final password=TextEditingController();
  bool loading=false; String? error;

  Future<void> submit()async{
    setState((){loading=true;error=null;});
    try{
      await api.login(email.text,password.text);
      await configurePush();
      if(mounted)context.go('/home');
    }catch(_){
      if(mounted)setState(()=>error='Identifiants invalides ou service indisponible.');
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
        if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
        const SizedBox(height:20),
        FilledButton(
          style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:16),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
          onPressed:loading?null:submit,
          child:loading?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):Text(t('Se connecter')),
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
class _HomeScreenState extends State<HomeScreen>{
  late Future<List<dynamic>> future;
  @override void initState(){super.initState();future=api.bookings();}
  void retry()=>setState(()=>future=api.bookings());

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(
      backgroundColor:const Color(0xFFF2F6FB),elevation:0,
      title:Row(mainAxisSize:MainAxisSize.min,children:const [Icon(Icons.location_on,color:Color(0xFF1565C0)),SizedBox(width:6),Text('Veyra',style:TextStyle(color:Color(0xFF123A66),fontWeight:FontWeight.bold))]),
      actions:[
      const LanguageSwitch(),
      IconButton(onPressed:()=>context.push('/notifications'),icon:const Icon(Icons.notifications_outlined)),
      IconButton(onPressed:()async{await api.logout();if(context.mounted)context.go('/login');},icon:const Icon(Icons.logout))
    ]),
    body:RefreshIndicator(
      onRefresh:()async{retry();await future;},
      child:ListView(padding:const EdgeInsets.all(20),children:[
        Text(t('Planifiez votre trajet'),style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold,color:Color(0xFF123A66))),
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
              Expanded(child:Text(t('Nouvelle réservation'),style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w600))),
              const Icon(Icons.arrow_forward_ios,color:Colors.white70,size:16),
            ])),
          )),
        ),
        const SizedBox(height:28),
        Text(t('Mes réservations'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
        const SizedBox(height:8),
        FutureBuilder<List<dynamic>>(
          future:future,
          builder:(context,s){
            if(s.connectionState!=ConnectionState.done){
              return const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()));
            }
            if(s.hasError){
              return Card(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),child:ListTile(
                leading:const Icon(Icons.cloud_off),
                title:Text(t('Impossible de charger vos réservations')),
                subtitle:Text(t('Vérifiez votre connexion puis réessayez.')),
                trailing:TextButton(onPressed:retry,child:Text(t('Réessayer'))),
              ));
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
              final scheduled=(x['scheduled_at']??'').toString();
              final status=(x['status']??'').toString();
              return Card(
                margin:const EdgeInsets.only(bottom:10),
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
                child:ListTile(
                  contentPadding:const EdgeInsets.all(14),
                  title:Text(title,style:const TextStyle(fontWeight:FontWeight.w600)),
                  subtitle:Padding(padding:const EdgeInsets.only(top:6),child:Row(children:[
                    Expanded(child:Text(scheduled,style:const TextStyle(color:Colors.black54,fontSize:13))),
                    statusBadge(status),
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
  late Future<List<dynamic>> categories;
  bool loadingPickup=false;
  bool loadingDropoff=false;
  bool locating=false;
  bool submitting=false;
  String? error;

  @override void initState(){
    super.initState();
    categories=api.vehicleCategories();
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
      if(mounted)setState(()=>error='Recherche d’adresse indisponible.');
    }finally{
      if(mounted)setState((){if(isPickup)loadingPickup=false;else loadingDropoff=false;});
    }
  }

  Future<void> useMyLocation()async{
    if(!await Geolocator.isLocationServiceEnabled()){
      if(mounted)setState(()=>error='Activez la localisation du téléphone.');
      return;
    }
    var permission=await Geolocator.checkPermission();
    if(permission==LocationPermission.denied){
      permission=await Geolocator.requestPermission();
    }
    if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever){
      if(mounted)setState(()=>error='La localisation est nécessaire pour utiliser votre position actuelle.');
      return;
    }
    setState(()=>locating=true);
    try{
      final p=await Geolocator.getCurrentPosition(
        locationSettings:const LocationSettings(accuracy:LocationAccuracy.high),
      );
      final place=await api.reverseGeocode(p.latitude,p.longitude);
      if(place==null){
        if(mounted)setState(()=>error='Aucune adresse trouvée pour votre position actuelle.');
        return;
      }
      if(mounted)setState((){
        pickup.text=place['label']?.toString()??'';
        pickupPlace=place;
        pickupResults=[];
      });
    }catch(_){
      if(mounted)setState(()=>error='Impossible d’obtenir votre position actuelle.');
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
          search(isPickup,q);
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
          },
        ),
    ]);
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
      setState(()=>error='Complétez le trajet, la date et la catégorie.');
      return;
    }
    if(scheduledAt!.difference(DateTime.now())<const Duration(hours:2)){
      setState(()=>error='Le départ doit être planifié au moins 2 heures à l’avance.');
      return;
    }
    setState((){submitting=true;error=null;});
    try{
      await api.createBooking({
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
      if(mounted)context.go('/home');
    }on DioException catch(e){
      final code=(e.response?.data is Map)?(e.response?.data as Map)['code']?.toString():null;
      if(mounted)setState(()=>error=code=='PICKUP_OUTSIDE_SERVICE_ZONE'
        ?t('Cette adresse de départ est hors de la zone de service actuelle (Marseille → Menton).')
        :t('La réservation n’a pas pu être publiée. Vérifiez les informations puis réessayez.')+(code==null?'':' ($code)'));
    }catch(_){
      if(mounted)setState(()=>error=t('La réservation n’a pas pu être publiée. Vérifiez les informations puis réessayez.'));
    }finally{
      if(mounted)setState(()=>submitting=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Planifier une réservation'))),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      addressField(true),
      const SizedBox(height:16),
      addressField(false),
      const SizedBox(height:18),
      ListTile(
        contentPadding:EdgeInsets.zero,
        leading:const Icon(Icons.event),
        title:Text(t('Date et heure de départ')),
        subtitle:Text(scheduledAt==null?t('Minimum 2 h à l’avance'):scheduledAt.toString()),
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
            onChanged:(v)=>setState(()=>categoryId=v),
          );
        },
      ),
      const SizedBox(height:18),
      Row(children:[
        Expanded(child:DropdownButtonFormField<int>(
          initialValue:passengerCount,
          decoration:InputDecoration(labelText:t('Passagers')),
          items:List.generate(8,(i)=>DropdownMenuItem(value:i+1,child:Text('${i+1}'))),
          onChanged:(v){if(v!=null)setState(()=>passengerCount=v);},
        )),
        const SizedBox(width:12),
        Expanded(child:DropdownButtonFormField<int>(
          initialValue:baggageCount,
          decoration:InputDecoration(labelText:t('Bagages')),
          items:List.generate(7,(i)=>DropdownMenuItem(value:i,child:Text('$i'))),
          onChanged:(v){if(v!=null)setState(()=>baggageCount=v);},
        )),
      ]),
      const SizedBox(height:18),
      const Text('Paiement',style:TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
      DropdownButtonFormField<String>(
        initialValue:paymentMethod,
        decoration:InputDecoration(labelText:t('Mode de paiement')),
        items:[
          DropdownMenuItem(value:'CASH',child:Text(t('Cash — le total inclut la commission Veyra'))),
          DropdownMenuItem(value:'ONLINE',child:Text(t('En ligne — paiement sécurisé'))),
        ],
        onChanged:(v){if(v!=null)setState(()=>paymentMethod=v);},
      ),
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
  String? error;
  String? acceptingOfferId;
  @override void initState(){super.initState();future=api.offers(widget.bookingId);}

  Future<void> chooseOffer(String offerId)async{
    setState((){acceptingOfferId=offerId;error=null;});
    try{
      await api.accept(widget.bookingId,offerId);
      final booking=await api.bookingDetail(widget.bookingId);
      if(!mounted)return;
      if(booking['payment_method']=='ONLINE'){
        context.push('/payment/'+widget.bookingId);
      }else{
        context.go('/home');
      }
    }on DioException catch(e){
      final code=(e.response?.data is Map)?(e.response?.data as Map)['code']?.toString():null;
      final message=switch(code){
        'BOOKING_CLOSED'=>t('Cette réservation n’est plus ouverte aux offres.'),
        'OFFER_CLOSED'=>t('Cette offre n’est plus disponible.'),
        'PARTNER_CREDIT_LIMIT_EXCEEDED'=>t('Limite de crédit partenaire dépassée pour cette réservation.'),
        _=>t('Impossible de choisir cette offre pour le moment.')+(code==null?'':' ($code)'),
      };
      if(mounted)setState(()=>error=message);
    }catch(_){
      if(mounted)setState(()=>error=t('Impossible de choisir cette offre pour le moment.'));
    }finally{
      if(mounted)setState(()=>acceptingOfferId=null);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF2F6FB),
    appBar:AppBar(title:Text(t('Offres reçues')),backgroundColor:const Color(0xFFF2F6FB),elevation:0),
    body:FutureBuilder<List<dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return Center(child:FilledButton(onPressed:()=>setState(()=>future=api.offers(widget.bookingId)),child:Text(t('Réessayer'))));
        final items=s.data??[];
        if(items.isEmpty)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(t('Aucune offre pour le moment. Vous serez notifié dès qu’un chauffeur propose un prix.'))));
        return ListView(padding:const EdgeInsets.all(16),children:[
          Text(t('Choisissez librement selon le prix, le véhicule et le chauffeur.'),style:const TextStyle(color:Colors.black54)),
          if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
          const SizedBox(height:14),
          for(final raw in items)Builder(builder:(context){
            final x=Map<String,dynamic>.from(raw as Map);
            final total=((x['totalMinor']??0) as num).toDouble()/100;
            final driver=((x['driverPriceMinor']??0) as num).toDouble()/100;
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
                  Text('${total.toStringAsFixed(0)} €',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Color(0xFF123A66))),
                ]),
                const SizedBox(height:4),
                Text(t('Prix chauffeur: ')+driver.toStringAsFixed(2)+' €',style:const TextStyle(fontSize:12,color:Colors.black45)),
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
    api.bookingDetail(widget.bookingId).then((v){if(mounted)setState(()=>booking=v);}).catchError((_){if(mounted)setState(()=>error='Impossible de charger le paiement.');});
  }

  Future<void> pay()async{
    const publishableKey=String.fromEnvironment('STRIPE_PUBLISHABLE_KEY',defaultValue:'');
    if(publishableKey.isEmpty){
      setState(()=>error='Paiement en ligne non configuré sur cette version.');
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
      if(mounted)setState(()=>error='Le paiement n’a pas été finalisé.');
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context){
    final total=((booking?['customer_total_amount_minor']??0) as num).toDouble()/100;
    return Scaffold(
      appBar:AppBar(title:Text(t('Paiement sécurisé'))),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
        const Icon(Icons.lock_outline,size:56),
        const SizedBox(height:16),
        Text('Total à payer : '+total.toStringAsFixed(2)+' €',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold),textAlign:TextAlign.center),
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
  bool ratingSubmitted=false;

  @override void initState(){
    super.initState();
    future=api.bookingDetail(widget.bookingId);
  }

  void reload()=>setState(()=>future=api.bookingDetail(widget.bookingId));

  Future<void> loadPin()async{
    try{
      final value=await api.pin(widget.bookingId);
      if(mounted)setState(()=>pin=value);
    }catch(_){
      if(mounted)setState(()=>message='Le PIN sera disponible à H-1.');
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

  Future<void> cancel()async{
    try{
      final result=await api.cancel(widget.bookingId);
      if(mounted)setState(()=>message=t('Réservation annulée. Frais éventuels : ')+(((result['cancellationFeeMinor']??0) as num).toDouble()/100).toStringAsFixed(2)+' €');
      reload();
    }catch(_){
      if(mounted)setState(()=>message='Annulation impossible dans l’état actuel.');
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Détail réservation'))),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return Center(child:FilledButton(onPressed:reload,child:Text(t('Réessayer'))));
        final x=s.data??{};
        final status=(x['status']??'').toString();
        final driverName=((x['driver_first_name']??'') as Object).toString()+' '+((x['driver_last_name']??'') as Object).toString();
        final driverPhone=x['driver_phone']?.toString();
        final total=((x['customer_total_amount_minor']??0) as num).toDouble()/100;
        return ListView(padding:const EdgeInsets.all(20),children:[
          Text((x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString(),style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          Text((x['scheduled_at']??'').toString()),
          const SizedBox(height:12),
          Card(child:ListTile(title:Text(t('Statut')),trailing:Text(status))),
          if(x['selected_driver_id']!=null)Card(child:ListTile(
            leading:const CircleAvatar(child:Icon(Icons.person)),
            title:Text(driverName.trim().isEmpty?t('Chauffeur confirmé'):driverName.trim()),
            subtitle:Text('Note : '+(x['driver_rating']??'-').toString()),
          )),
          if(x['customer_total_amount_minor']!=null)Card(child:ListTile(
            title:Text(t('Total client')),
            subtitle:Text((x['payment_method']??'').toString()),
            trailing:Text(total.toStringAsFixed(2)+' €'),
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
          if(status=='CONFIRMED'||status=='DRIVER_EN_ROUTE'||status=='DRIVER_ARRIVED')...[
            OutlinedButton(onPressed:loadPin,child:Text(pin==null?t('Afficher le PIN'):t('PIN : ')+pin!)),
            TextButton(onPressed:cancel,child:Text(t('Annuler la réservation'))),
          ],
          if({'COMPLETED','CLOSED'}.contains(status))
            Card(child:Padding(padding:const EdgeInsets.all(16),child:ratingSubmitted?Row(children:[Icon(Icons.check_circle,color:Colors.green),SizedBox(width:8),Text(t('Merci pour votre avis !'))]):Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('Noter le chauffeur',style:TextStyle(fontWeight:FontWeight.bold)),
              const SizedBox(height:8),
              Row(children:[for(int i=1;i<=5;i++)IconButton(
                icon:Icon(i<=ratingScore?Icons.star:Icons.star_border,color:Colors.amber),
                onPressed:ratingSubmitting?null:()=>setState(()=>ratingScore=i),
              )]),
              FilledButton(onPressed:ratingSubmitting||ratingScore<1?null:submitRating,child:Text(ratingSubmitting?'Envoi…':'Envoyer la note')),
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
  late Future<List<dynamic>> future;
  bool sending=false;

  @override void initState(){super.initState();future=api.chatMessages(widget.bookingId);}
  void reload()=>setState(()=>future=api.chatMessages(widget.bookingId));

  Future<void> send()async{
    final body=input.text.trim();
    if(body.isEmpty)return;
    setState(()=>sending=true);
    try{
      await api.sendMessage(widget.bookingId,body);
      input.clear();reload();
    }finally{
      if(mounted)setState(()=>sending=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('Chat Veyra'))),
    body:Column(children:[
      Expanded(child:FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
          if(s.hasError)return Center(child:FilledButton(onPressed:reload,child:Text(t('Réessayer'))));
          final items=s.data??[];
          if(items.isEmpty)return Center(child:Text(t('Aucun message pour le moment.')));
          return ListView(padding:const EdgeInsets.all(12),children:items.map((raw){
            final x=Map<String,dynamic>.from(raw as Map);
            return Card(child:ListTile(title:Text((x['body']??'').toString()),subtitle:Text((x['sent_at']??'').toString())));
          }).toList());
        },
      )),
      SafeArea(child:Padding(
        padding:const EdgeInsets.all(12),
        child:Row(children:[
          Expanded(child:TextField(controller:input,maxLength:2000,decoration:InputDecoration(hintText:t('Votre message'),counterText:''))),
          IconButton(onPressed:sending?null:send,icon:const Icon(Icons.send)),
        ]),
      )),
    ]),
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
  String? error;

  @override void initState(){
    super.initState();
    api.bookingDetail(widget.bookingId).then((value){
      if(mounted)setState(()=>bookingMap=value);
    }).catchError((_){});
    refresh();
    timer=Timer.periodic(const Duration(seconds:10),(_)=>refresh());
    etaTimer=Timer.periodic(const Duration(seconds:30),(_)=>refreshEta());
  }

  @override void dispose(){
    timer?.cancel();
    etaTimer?.cancel();
    super.dispose();
  }

  Future<void> refresh()async{
    try{
      final value=await api.currentLocation(widget.bookingId);
      if(mounted)setState((){location=value;error=null;});
      await refreshEta();
    }catch(_){
      if(mounted)setState(()=>error='Position en cours de mise à jour.');
    }
  }

  Future<void> refreshEta()async{
    final live=location;
    final booking=bookingMap;
    if(live?['available']!=true||booking==null)return;
    final toLat=(booking['dropoff_lat'] as num?)?.toDouble();
    final toLng=(booking['dropoff_lng'] as num?)?.toDouble();
    if(toLat==null||toLng==null)return;
    try{
      final eta=await api.routeEstimate(
        fromLat:(live!['lat'] as num).toDouble(),
        fromLng:(live['lng'] as num).toDouble(),
        toLat:toLat,toLng:toLng,
      );
      if(mounted)setState(()=>etaInfo=eta);
    }catch(_){}
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
              Text(available?t('Position actuelle du chauffeur'):t('Position indisponible'),style:const TextStyle(fontWeight:FontWeight.bold)),
              Text(error??(available?t('Mise à jour automatique toutes les 10 secondes.'):t('En attente de la première position GPS.'))),
              if(etaInfo!=null)Text(
                t('ETA destination : ')+(((etaInfo!['durationSeconds']??0) as num).toDouble()/60).ceil().toString()+
                ' min • '+(((etaInfo!['distanceMeters']??0) as num).toDouble()/1000).toStringAsFixed(1)+' km',
                style:const TextStyle(fontWeight:FontWeight.w600),
              ),
              if(available&&location!['recorded_at']!=null)Text('Dernière position : '+location!['recorded_at'].toString()),
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
  bool loading=false;
  String? error;

  Future<void> submit()async{
    if(firstName.text.trim().isEmpty||email.text.trim().isEmpty||password.text.length<10){
      setState(()=>error='Prénom, e-mail et mot de passe de 10 caractères minimum requis.');
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
      await configurePush();
      if(mounted)context.go('/home');
    }catch(_){
      if(mounted)setState(()=>error='Création du compte impossible. Vérifiez les informations ou utilisez un autre e-mail.');
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
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:16),
      FilledButton(
        style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:16),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
        onPressed:loading?null:submit,
        child:loading?Text(t('Création…')):Text(t('Créer mon compte')),
      ),
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
      if(mounted)setState(()=>message='Si cet e-mail existe, les instructions de réinitialisation ont été envoyées.');
    }catch(_){
      if(mounted)setState(()=>message='Impossible d’envoyer la demande pour le moment.');
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
  void reload()=>setState(()=>future=api.notifications());

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
                title:Text(template.replaceAll('_',' ')),
                subtitle:Text((x['created_at']??'').toString()),
                trailing:bookingId==null?null:const Icon(Icons.chevron_right),
                onTap:bookingId==null?null:(){
                  if(template=='NEW_OFFER')context.push('/offers/'+bookingId);
                  else context.push('/booking/'+bookingId);
                },
              ));
            },
          );
        },
      ),
    ),
  );
}
