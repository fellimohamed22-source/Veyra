import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'api.dart';

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
  String? uploadingType;
  String? message;

  @override void initState(){
    super.initState();
    future=api.onboardingStatus();
  }

  Future<void> upload(String type)async{
    final result=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['pdf','jpg','jpeg','png']);
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
          const SizedBox(height:12),
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
            'Les demandes de réservation seront accessibles après validation manuelle du dossier par Veyra.',
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
  late Future<List<dynamic>> future;

  @override void initState(){super.initState();future=api.opportunities(sort:sort);}
  void reload()=>setState(()=>future=api.opportunities(sort:sort));

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Demandes disponibles'),actions:[
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
          ],
          onChanged:(v){if(v!=null){sort=v;reload();}},
        ),
        const SizedBox(height:10),
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
  bool sending=false;
  String? error;

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
        final lat=position?.latitude??43.2965;
        final lng=position?.longitude??5.3698;

        if(Set.of('DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS').contains(status)&&gpsTimer==null){
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
          if(error!=null)Padding(
            padding:const EdgeInsets.symmetric(vertical:10),
            child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
          ),
          if(status=='CONFIRMED')
            FilledButton(onPressed:busy?null:()=>action(()=>api.enRoute(widget.bookingId),startGps:true),child:const Text('Je suis en route')),
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
