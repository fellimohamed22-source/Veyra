import 'package:file_picker/file_picker.dart';
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
  GoRoute(path:'/kyc',builder:(c,s)=>const KycScreen()),
  GoRoute(path:'/home',builder:(c,s)=>const OpportunitiesScreen()),
  GoRoute(path:'/request/:id',builder:(c,s)=>RequestScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/agenda',builder:(c,s)=>const AgendaScreen()),
  GoRoute(path:'/ride/:id',builder:(c,s)=>RideScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/wallet',builder:(c,s)=>const WalletScreen()),
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

  @override void initState(){super.initState();future=api.bookingDetail(widget.bookingId);}
  void reload()=>setState(()=>future=api.bookingDetail(widget.bookingId));

  Future<void> action(Future<void> Function() fn)async{
    setState((){busy=true;error=null;});
    try{await fn();reload();}catch(_){if(mounted)setState(()=>error='Action impossible dans l’état actuel.');}
    finally{if(mounted)setState(()=>busy=false);}
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
        return ListView(padding:const EdgeInsets.all(20),children:[
          Container(height:220,decoration:BoxDecoration(color:Theme.of(context).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(20)),
            alignment:Alignment.center,child:const Column(mainAxisSize:MainAxisSize.min,children:[
              Icon(Icons.map_outlined,size:70),Text('Carte / position temps réel'),
            ])),
          const SizedBox(height:16),
          Text((x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          Text('Statut : '+status),
          if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
          if(status=='CONFIRMED')FilledButton(onPressed:busy?null:()=>action(()=>api.enRoute(widget.bookingId)),child:const Text('Je suis en route')),
          if(status=='DRIVER_EN_ROUTE')FilledButton(onPressed:busy?null:()=>action(()=>api.arrived(widget.bookingId)),child:const Text('Je suis arrivé')),
          if(status=='DRIVER_ARRIVED')...[
            TextField(controller:pin,maxLength:4,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'PIN client (4 chiffres)')),
            FilledButton(onPressed:busy?null:()=>action(()=>api.start(widget.bookingId,pin.text)),child:const Text('Démarrer la course')),
            TextButton(onPressed:busy?null:()=>action(()=>api.noShow(widget.bookingId)),child:const Text('Signaler un no-show')),
          ],
          if(status=='IN_PROGRESS')FilledButton(onPressed:busy?null:()=>action(()=>api.complete(widget.bookingId)),child:const Text('Terminer la course')),
          const SizedBox(height:10),
          const ListTile(leading:Icon(Icons.chat_bubble_outline),title:Text('Chat Veyra'),subtitle:Text('Disponible après confirmation')),
          const ListTile(leading:Icon(Icons.phone_outlined),title:Text('Appeler le client')),
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
