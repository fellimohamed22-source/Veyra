import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'api.dart';

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
  }catch(_){}
}

final api=Api(const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080'));

void main()=>runApp(const DriverApp());

class DriverApp extends StatelessWidget{
  const DriverApp({super.key});
  @override Widget build(BuildContext context)=>MaterialApp.router(
    title:'Veyra Chauffeur',
    theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.teal),
    routerConfig:router,
  );
}

final router=GoRouter(initialLocation:'/login',routes:[
  GoRoute(path:'/login',builder:(c,s)=>const LoginScreen()),
  GoRoute(path:'/register',builder:(c,s)=>const RegisterDriverScreen()),
  GoRoute(path:'/kyc',builder:(c,s)=>const KycScreen()),
  GoRoute(path:'/home',builder:(c,s)=>const OpportunitiesScreen()),
  GoRoute(path:'/request/:id',builder:(c,s)=>RequestScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/agenda',builder:(c,s)=>const AgendaScreen()),
  GoRoute(path:'/ride/:id',builder:(c,s)=>RideScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/wallet',builder:(c,s)=>const WalletScreen()),
  GoRoute(path:'/chat/:id',builder:(c,s)=>DriverChatScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/notifications',builder:(c,s)=>const DriverNotificationsScreen()),
]);

class LoginScreen extends StatefulWidget{
  const LoginScreen({super.key});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen>{
  final email=TextEditingController();
  final password=TextEditingController();
  bool loading=false;
  String? error;

  Future<void> submit()async{
    setState((){loading=true;error=null;});
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
    }catch(_){
      if(mounted)setState(()=>error='Connexion impossible.');
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Veyra Chauffeur')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
      const Text('Espace Chauffeur VTC',style:TextStyle(fontSize:28,fontWeight:FontWeight.bold)),
      const SizedBox(height:24),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email')),
      const SizedBox(height:12),
      TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Mot de passe')),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:20),
      FilledButton(onPressed:loading?null:submit,child:loading?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Text('Se connecter')),
      TextButton(onPressed:()=>context.go('/register'),child:const Text('Créer un compte Chauffeur')),
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
      setState(()=>message='Complétez les informations professionnelles et le véhicule.');
      return;
    }
    final parsedYear=int.tryParse(year.text);
    if(parsedYear==null){
      setState(()=>message='Année du véhicule invalide.');
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
      if(mounted)setState(()=>message='Informations professionnelles enregistrées.');
    }catch(_){
      if(mounted)setState(()=>message='Impossible d’enregistrer les informations professionnelles.');
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
        message='Document envoyé. Il sera vérifié par Veyra.';
        future=api.onboardingStatus();
      });
    }catch(_){
      if(mounted)setState(()=>message='Échec de l’envoi du document.');
    }finally{
      if(mounted)setState(()=>uploadingType=null);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Dossier Chauffeur VTC')),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        final status=s.data??{};
        final approved=status['kyc_status']=='APPROVED'&&status['marketplace_enabled']==true;

        return ListView(padding:const EdgeInsets.all(20),children:[
          Card(child:ListTile(
            leading:Icon(approved?Icons.verified:Icons.pending_actions),
            title:Text(approved?'Dossier approuvé':'Vérification en cours'),
            subtitle:Text('Statut KYC : '+(status['kyc_status']??'DRAFT').toString()),
          )),
          const SizedBox(height:16),
          const Text('Informations professionnelles',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          TextField(controller:legalName,decoration:const InputDecoration(labelText:'Raison sociale')),
          TextField(controller:siren,decoration:const InputDecoration(labelText:'SIREN')),
          TextField(controller:siret,decoration:const InputDecoration(labelText:'SIRET')),
          TextField(controller:registrationNumber,decoration:const InputDecoration(labelText:'N° inscription registre VTC')),
          TextField(controller:cardNumber,decoration:const InputDecoration(labelText:'N° carte professionnelle VTC')),
          const SizedBox(height:12),
          const Text('Véhicule',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          FutureBuilder<List<dynamic>>(
            future:categories,
            builder:(context,cs){
              if(cs.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
              final items=cs.data??[];
              return DropdownButtonFormField<String>(
                initialValue:categoryId,
                decoration:const InputDecoration(labelText:'Catégorie'),
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
          TextField(controller:brand,decoration:const InputDecoration(labelText:'Marque')),
          TextField(controller:model,decoration:const InputDecoration(labelText:'Modèle')),
          TextField(controller:year,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Année')),
          TextField(controller:plate,decoration:const InputDecoration(labelText:'Immatriculation')),
          TextField(controller:color,decoration:const InputDecoration(labelText:'Couleur')),
          const SizedBox(height:12),
          FilledButton(onPressed:saving?null:saveProfessionalData,child:Text(saving?'Enregistrement…':'Enregistrer les informations')),
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
              subtitle:const Text('PDF, JPG ou PNG — 10 Mo max'),
              trailing:uploadingType==item.$1
                ?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2))
                :IconButton(onPressed:()=>upload(item.$1),icon:const Icon(Icons.upload_file)),
            )),
          if(message!=null)Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Text(message!)),
          if(approved)FilledButton(onPressed:()=>context.go('/home'),child:const Text('Accéder aux demandes')),
          if(!approved)const Text(
            'Après envoi, l’équipe Veyra vérifie le dossier avant d’activer l’accès aux demandes.',
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
class _OpportunitiesScreenState extends State<OpportunitiesScreen>{
  String sort='date';
  final pickupFilter=TextEditingController();
  final destinationFilter=TextEditingController();
  int? minPassengers;
  late Future<List<dynamic>> future;

  @override void initState(){super.initState();future=load();}
  Future<List<dynamic>> load()=>api.opportunities(
    sort:sort,
    pickupQuery:pickupFilter.text,
    destinationQuery:destinationFilter.text,
    minPassengers:minPassengers,
  );
  void reload()=>setState(()=>future=load());

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Demandes disponibles'),actions:[
      IconButton(onPressed:()=>context.go('/notifications'),icon:const Icon(Icons.notifications_outlined)),
      IconButton(onPressed:()=>context.go('/agenda'),icon:const Icon(Icons.calendar_month)),
      IconButton(onPressed:()=>context.go('/wallet'),icon:const Icon(Icons.account_balance_wallet)),
    ]),
    body:RefreshIndicator(
      onRefresh:()async{reload();await future;},
      child:ListView(padding:const EdgeInsets.all(16),children:[
        DropdownButtonFormField<String>(
          initialValue:sort,
          decoration:const InputDecoration(labelText:'Trier les demandes'),
          items:const [
            DropdownMenuItem(value:'date',child:Text('Date de départ')),
            DropdownMenuItem(value:'newest',child:Text('Plus récentes')),
            DropdownMenuItem(value:'pickup',child:Text('Lieu de départ (A → Z)')),
            DropdownMenuItem(value:'destination',child:Text('Destination (A → Z)')),
          ],
          onChanged:(v){if(v!=null){sort=v;reload();}},
        ),
        const SizedBox(height:10),
        ExpansionTile(
          tilePadding:EdgeInsets.zero,
          title:const Text('Filtres'),
          children:[
            TextField(controller:pickupFilter,decoration:const InputDecoration(labelText:'Lieu de départ contient')),
            const SizedBox(height:8),
            TextField(controller:destinationFilter,decoration:const InputDecoration(labelText:'Destination contient')),
            const SizedBox(height:8),
            DropdownButtonFormField<int?>(
              initialValue:minPassengers,
              decoration:const InputDecoration(labelText:'Minimum passagers'),
              items:[const DropdownMenuItem<int?>(value:null,child:Text('Tous')), ...List.generate(8,(i)=>DropdownMenuItem<int?>(value:i+1,child:Text('${i+1}+')))],
              onChanged:(v)=>setState(()=>minPassengers=v),
            ),
            const SizedBox(height:10),
            Row(children:[
              Expanded(child:OutlinedButton(onPressed:(){pickupFilter.clear();destinationFilter.clear();setState(()=>minPassengers=null);reload();},child:const Text('Réinitialiser'))),
              const SizedBox(width:8),
              Expanded(child:FilledButton(onPressed:reload,child:const Text('Appliquer'))),
            ]),
          ],
        ),
        const Text('Aucun tri par proximité. Les chauffeurs ne voient jamais les prix concurrents.'),
        const SizedBox(height:16),
        FutureBuilder<List<dynamic>>(
          future:future,
          builder:(context,s){
            if(s.connectionState!=ConnectionState.done)return const Center(child:Padding(padding:EdgeInsets.all(32),child:CircularProgressIndicator()));
            if(s.hasError)return Card(child:ListTile(
              leading:const Icon(Icons.error_outline),title:const Text('Impossible de charger les demandes'),
              trailing:TextButton(onPressed:reload,child:const Text('Réessayer')),
            ));
            final items=s.data??[];
            if(items.isEmpty)return const Card(child:ListTile(
              leading:Icon(Icons.inbox_outlined),title:Text('Aucune demande ouverte'),
              subtitle:Text('Les nouvelles demandes apparaîtront ici.'),
            ));
            return Column(children:items.map((raw){
              final x=Map<String,dynamic>.from(raw as Map);
              final id=x['id'].toString();
              final title=(x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString();
              return Card(child:ListTile(
                title:Text(title),subtitle:Text((x['scheduled_at']??'').toString()),
                trailing:const Icon(Icons.chevron_right),onTap:()=>context.go('/request/'+id),
              ));
            }).toList());
          },
        ),
      ]),
    ),
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
    if(euros==null||euros<=0){setState(()=>error='Saisissez un prix valide.');return;}
    setState((){sending=true;error=null;});
    try{
      await api.offer(widget.bookingId,(euros*100).round());
      if(mounted)context.go('/home');
    }catch(_){
      if(mounted)setState(()=>error='L’offre n’a pas pu être envoyée ou la demande est déjà fermée.');
    }finally{
      if(mounted)setState(()=>sending=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Proposer un prix')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      FutureBuilder<Map<String,dynamic>>(
        future:detail,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
          if(s.hasError)return Card(child:ListTile(
            leading:const Icon(Icons.error_outline),
            title:const Text('Demande indisponible'),
            subtitle:const Text('Elle a peut-être déjà été fermée.'),
            trailing:TextButton(onPressed:()=>setState(()=>detail=api.opportunityDetail(widget.bookingId)),child:const Text('Réessayer')),
          ));
          final x=s.data??{};
          return Column(children:[
            Card(child:ListTile(
              leading:const Icon(Icons.route),
              title:Text((x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString()),
              subtitle:Text((x['scheduled_at']??'').toString()+'\n'+(x['category_name']??'').toString()),
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
      const Card(child:ListTile(
        leading:Icon(Icons.visibility_off_outlined),title:Text('Offre privée'),
        subtitle:Text('Les offres des autres chauffeurs et le meilleur prix ne sont jamais affichés.'),
      )),
      TextField(
        controller:amount,
        keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:const InputDecoration(
          labelText:'Votre prix net (€)',
          helperText:'C’est le montant exact que vous devez recevoir pour la course.',
        ),
      ),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:20),
      FilledButton(onPressed:sending?null:submit,child:sending?const CircularProgressIndicator():const Text('Envoyer mon offre')),
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
    appBar:AppBar(title:const Text('Mes courses à venir')),
    body:FutureBuilder<List<dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return Center(child:FilledButton(onPressed:()=>setState(()=>future=api.bookings()),child:const Text('Réessayer')));
        final items=s.data??[];
        if(items.isEmpty)return const Center(child:Text('Aucune course confirmée.'));
        return ListView(padding:const EdgeInsets.all(16),children:items.map((raw){
          final x=Map<String,dynamic>.from(raw as Map);
          return Card(child:ListTile(
            title:Text((x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString()),
            subtitle:Text((x['scheduled_at']??'').toString()+' • '+(x['status']??'').toString()),
            trailing:const Icon(Icons.chevron_right),
            onTap:()=>context.go('/ride/'+x['id'].toString()),
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
  int sequence=0;

  @override void initState(){
    super.initState();
    future=api.bookingDetail(widget.bookingId);
  }

  @override void dispose(){
    gpsTimer?.cancel();
    super.dispose();
  }

  void reload()=>setState(()=>future=api.bookingDetail(widget.bookingId));

  Future<bool> ensureLocationPermission()async{
    if(!await Geolocator.isLocationServiceEnabled()){
      if(mounted)setState(()=>error='Activez la localisation du téléphone.');
      return false;
    }
    var permission=await Geolocator.checkPermission();
    if(permission==LocationPermission.denied){
      permission=await Geolocator.requestPermission();
    }
    if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever){
      if(mounted)setState(()=>error='La localisation est obligatoire pendant la prise en charge et la course.');
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
    }catch(_){
      if(mounted)setState(()=>error='Position GPS momentanément indisponible.');
    }
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
    }catch(_){
      if(mounted)setState(()=>error='Action impossible dans l’état actuel.');
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Course')),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return Center(child:FilledButton(onPressed:reload,child:const Text('Réessayer')));
        final x=s.data??{};
        final status=(x['status']??'').toString();
        final phone=x['customer_phone']?.toString();
        final paymentMethod=(x['payment_method']??'').toString();
        double money(dynamic value)=>((value??0) as num).toDouble()/100;
        final driverNet=money(x['driver_net_amount_minor']);
        final commission=money(x['platform_commission_amount_minor']);
        final customerTotal=money(x['customer_total_amount_minor']);
        final lat=position?.latitude??43.2965;
        final lng=position?.longitude??5.3698;

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
                  if(position!=null)MarkerLayer(markers:[
                    Marker(
                      point:LatLng(lat,lng),width:56,height:56,
                      child:const Icon(Icons.local_taxi,size:44),
                    )
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height:16),
          Text((x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString(),
            style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          Text('Statut : '+status),
          if(x['customer_name']!=null)Text('Client : '+x['customer_name'].toString()),
          if(paymentMethod=='CASH')Card(child:ListTile(
            leading:const Icon(Icons.payments_outlined),
            title:Text('Montant à encaisser au client : '+customerTotal.toStringAsFixed(2)+' €'),
            subtitle:Text('Votre montant net : '+driverNet.toStringAsFixed(2)+' € • Commission Veyra : '+commission.toStringAsFixed(2)+' € (dette CASH après la course)'),
          )),
          if(paymentMethod=='ONLINE')Card(child:ListTile(
            leading:const Icon(Icons.credit_card),
            title:Text('Paiement en ligne • Net chauffeur '+driverNet.toStringAsFixed(2)+' €'),
            subtitle:const Text('Le paiement doit être capturé avant le démarrage de la course.'),
          )),
          if(paymentMethod=='PARTNER_INVOICE')Card(child:ListTile(
            leading:const Icon(Icons.receipt_long),
            title:Text('Facturation partenaire • Net chauffeur '+driverNet.toStringAsFixed(2)+' €'),
            subtitle:const Text('Le partenaire est facturé par Veyra selon son contrat.'),
          )),
          if(error!=null)Padding(
            padding:const EdgeInsets.symmetric(vertical:10),
            child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
          ),
          if(status=='CONFIRMED')...[
            FilledButton(onPressed:busy?null:()=>action(()=>api.enRoute(widget.bookingId),startGps:true),child:const Text('Je suis en route')),
            TextButton(
              onPressed:busy?null:()async{
                final confirm=await showDialog<bool>(
                  context:context,
                  builder:(dialogContext)=>AlertDialog(
                    title:const Text('Annuler cette course ?'),
                    content:const Text('La réservation sera republiée en priorité si le délai le permet. Cette annulation impactera votre qualité chauffeur.'),
                    actions:[
                      TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Garder la course')),
                      FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Confirmer l’annulation')),
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
                        ?'Course annulée et demande republiée.'
                        :'Course annulée. Le support Veyra a été alerté.')),
                    );
                    context.go('/agenda');
                  }
                }catch(_){
                  if(mounted)setState(()=>error='Annulation impossible dans l’état actuel.');
                }finally{
                  if(mounted)setState(()=>busy=false);
                }
              },
              child:const Text('Annuler ma prise en charge'),
            ),
          ],
          if(status=='DRIVER_EN_ROUTE')
            FilledButton(onPressed:busy?null:()=>action(()=>api.arrived(widget.bookingId)),child:const Text('Je suis arrivé')),
          if(status=='DRIVER_ARRIVED')...[
            TextField(
              controller:pin,maxLength:4,keyboardType:TextInputType.number,
              decoration:const InputDecoration(labelText:'PIN client (4 chiffres)'),
            ),
            FilledButton(onPressed:busy?null:()=>action(()=>api.start(widget.bookingId,pin.text),startGps:true),child:const Text('Démarrer la course')),
            TextButton(onPressed:busy?null:()=>action(()=>api.noShow(widget.bookingId),stopGps:true),child:const Text('Signaler un no-show')),
          ],
          if(status=='IN_PROGRESS')
            FilledButton(onPressed:busy?null:()=>action(()=>api.complete(widget.bookingId),stopGps:true),child:const Text('Terminer la course')),
          const SizedBox(height:10),
          OutlinedButton.icon(
            onPressed:phone==null||phone.isEmpty?null:()=>launchUrl(Uri(scheme:'tel',path:phone)),
            icon:const Icon(Icons.phone_outlined),label:const Text('Appeler le client'),
          ),
          OutlinedButton.icon(onPressed:()=>context.go('/chat/'+widget.bookingId),icon:const Icon(Icons.chat_bubble_outline),label:const Text('Chat Veyra')),
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
    appBar:AppBar(title:const Text('Portefeuille')),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return Center(child:FilledButton(onPressed:()=>setState(()=>future=api.wallet()),child:const Text('Réessayer')));
        final x=s.data??{};
        double money(dynamic v)=>((v??0) as num).toDouble()/100;
        return ListView(padding:const EdgeInsets.all(20),children:[
          Card(child:ListTile(title:const Text('À recevoir (ONLINE)'),trailing:Text(money(x['onlinePayableMinor']).toStringAsFixed(2)+' €'))),
          Card(child:ListTile(title:const Text('Dette commission CASH'),trailing:Text(money(x['cashDebtMinor']).toStringAsFixed(2)+' €'))),
          if(x['cashWarning']==true)const Card(child:ListTile(
            leading:Icon(Icons.warning_amber),title:Text('Seuil de dette atteint'),
            subtitle:Text('Alerte 50 € • restriction CASH 100 € • blocage CASH 150 €'),
          )),
        ]);
      },
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
      await api.createProfile();
      await configureDriverPush();
      if(mounted)context.go('/kyc');
    }catch(_){
      if(mounted)setState(()=>error='Création du compte impossible.');
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Créer un compte Chauffeur')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
      TextField(controller:firstName,decoration:const InputDecoration(labelText:'Prénom')),
      const SizedBox(height:12),
      TextField(controller:lastName,decoration:const InputDecoration(labelText:'Nom')),
      const SizedBox(height:12),
      TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Téléphone')),
      const SizedBox(height:12),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email')),
      const SizedBox(height:12),
      TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Mot de passe',helperText:'10 caractères minimum')),
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:16),
      FilledButton(onPressed:loading?null:submit,child:loading?const Text('Création…'):const Text('Continuer vers mon dossier VTC')),
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
      input.clear();
      reload();
    }finally{
      if(mounted)setState(()=>sending=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Chat Veyra')),
    body:Column(children:[
      Expanded(child:FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
          if(s.hasError)return Center(child:FilledButton(onPressed:reload,child:const Text('Réessayer')));
          final items=s.data??[];
          if(items.isEmpty)return const Center(child:Text('Aucun message pour le moment.'));
          return ListView(padding:const EdgeInsets.all(12),children:items.map((raw){
            final x=Map<String,dynamic>.from(raw as Map);
            return Card(child:ListTile(title:Text((x['body']??'').toString()),subtitle:Text((x['sent_at']??'').toString())));
          }).toList());
        },
      )),
      SafeArea(child:Padding(
        padding:const EdgeInsets.all(12),
        child:Row(children:[
          Expanded(child:TextField(controller:input,maxLength:2000,decoration:const InputDecoration(hintText:'Votre message',counterText:''))),
          IconButton(onPressed:sending?null:send,icon:const Icon(Icons.send)),
        ]),
      )),
    ]),
  );
}


class DriverNotificationsScreen extends StatefulWidget{
  const DriverNotificationsScreen({super.key});
  @override State<DriverNotificationsScreen> createState()=>_DriverNotificationsScreenState();
}

class _DriverNotificationsScreenState extends State<DriverNotificationsScreen>{
  late Future<List<dynamic>> future;
  @override void initState(){super.initState();future=api.notifications();}
  void reload()=>setState(()=>future=api.notifications());

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Notifications')),
    body:RefreshIndicator(
      onRefresh:()async{reload();await future;},
      child:FutureBuilder<List<dynamic>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done){
            return const ListView(children:[SizedBox(height:220),Center(child:CircularProgressIndicator())]);
          }
          if(s.hasError){
            return ListView(children:[
              const SizedBox(height:160),
              const Icon(Icons.cloud_off,size:48),
              const Center(child:Text('Notifications indisponibles.')),
              Center(child:TextButton(onPressed:reload,child:const Text('Réessayer'))),
            ]);
          }
          final items=s.data??[];
          if(items.isEmpty){
            return const ListView(children:[
              SizedBox(height:160),
              Icon(Icons.notifications_none,size:56),
              Center(child:Text('Aucune notification pour le moment.')),
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
                  if(template=='NEW_BOOKING')context.go('/request/'+bookingId);
                  else context.go('/ride/'+bookingId);
                },
              ));
            },
          );
        },
      ),
    ),
  );
}
