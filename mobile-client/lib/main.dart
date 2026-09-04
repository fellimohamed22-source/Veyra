import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'api.dart';

final api=Api(const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080'));

void main()=>runApp(const App());

class App extends StatelessWidget{
  const App({super.key});
  @override Widget build(BuildContext context)=>MaterialApp.router(
    title:'Veyra',
    theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.indigo),
    routerConfig:router,
  );
}

final router=GoRouter(initialLocation:'/login',routes:[
  GoRoute(path:'/login',builder:(c,s)=>const LoginScreen()),
  GoRoute(path:'/home',builder:(c,s)=>const HomeScreen()),
  GoRoute(path:'/addresses',builder:(c,s)=>const AddressScreen()),
  GoRoute(path:'/offers/:id',builder:(c,s)=>OffersScreen(bookingId:s.pathParameters['id']!)),
]);

class LoginScreen extends StatefulWidget{
  const LoginScreen({super.key});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen>{
  final email=TextEditingController();
  final password=TextEditingController();
  bool loading=false; String? error;

  Future<void> submit()async{
    setState(()=>{loading=true,error=null});
    try{
      await api.login(email.text,password.text);
      if(mounted)context.go('/home');
    }catch(_){
      if(mounted)setState(()=>error='Identifiants invalides ou service indisponible.');
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Connexion Veyra')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
      const Text('Bienvenue',style:TextStyle(fontSize:30,fontWeight:FontWeight.bold)),
      const SizedBox(height:24),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email')),
      const SizedBox(height:12),
      TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Mot de passe')),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:20),
      FilledButton(onPressed:loading?null:submit,child:loading?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Text('Se connecter')),
      TextButton(onPressed:(){},child:const Text('Mot de passe oublié ?')),
      TextButton(onPressed:(){},child:const Text('Créer un compte')),
    ])),
  );
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
    appBar:AppBar(title:const Text('Veyra'),actions:[
      IconButton(onPressed:()async{await api.logout();if(context.mounted)context.go('/login');},icon:const Icon(Icons.logout))
    ]),
    body:RefreshIndicator(
      onRefresh:()async{retry();await future;},
      child:ListView(padding:const EdgeInsets.all(20),children:[
        const Text('Planifiez votre trajet',style:TextStyle(fontSize:28,fontWeight:FontWeight.bold)),
        const SizedBox(height:16),
        FilledButton.icon(onPressed:()=>context.go('/addresses'),icon:const Icon(Icons.calendar_month),label:const Text('Nouvelle réservation')),
        const SizedBox(height:28),
        const Text('Mes réservations',style:TextStyle(fontSize:20,fontWeight:FontWeight.w600)),
        FutureBuilder<List<dynamic>>(
          future:future,
          builder:(context,s){
            if(s.connectionState!=ConnectionState.done){
              return const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()));
            }
            if(s.hasError){
              return Card(child:ListTile(
                leading:const Icon(Icons.cloud_off),
                title:const Text('Impossible de charger vos réservations'),
                subtitle:const Text('Vérifiez votre connexion puis réessayez.'),
                trailing:TextButton(onPressed:retry,child:const Text('Réessayer')),
              ));
            }
            final items=s.data??[];
            if(items.isEmpty){
              return const Card(child:ListTile(
                leading:Icon(Icons.event_available),
                title:Text('Aucune réservation'),
                subtitle:Text('Votre prochain trajet apparaîtra ici.'),
              ));
            }
            return Column(children:items.map((raw){
              final x=Map<String,dynamic>.from(raw as Map);
              final title=(x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString();
              final subtitle=(x['scheduled_at']??'').toString()+'\n'+(x['status']??'').toString();
              return Card(child:ListTile(
                title:Text(title),subtitle:Text(subtitle),isThreeLine:true,
                trailing:const Icon(Icons.chevron_right),
                onTap:(){
                  final id=x['id']?.toString();
                  if(id!=null&&(x['status']=='OPEN_FOR_OFFERS'||x['status']=='OFFERS_RECEIVED'))context.go('/offers/'+id);
                },
              ));
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
  List<dynamic> pickupResults=[]; List<dynamic> dropoffResults=[];
  bool loadingPickup=false,loadingDropoff=false;

  Future<void> search(bool isPickup,String q)async{
    if(q.trim().length<3){
      setState(()=>isPickup?pickupResults=[]:dropoffResults=[]);return;
    }
    setState(()=>isPickup?loadingPickup=true:loadingDropoff=true);
    try{
      final r=await api.autocomplete(q);
      if(mounted)setState(()=>isPickup?pickupResults=r:dropoffResults=r);
    }finally{
      if(mounted)setState(()=>isPickup?loadingPickup=false:loadingDropoff=false);
    }
  }

  Widget addressField(bool isPickup){
    final c=isPickup?pickup:dropoff;
    final results=isPickup?pickupResults:dropoffResults;
    final loading=isPickup?loadingPickup:loadingDropoff;
    return Column(children:[
      TextField(
        controller:c,onChanged:(q)=>search(isPickup,q),
        decoration:InputDecoration(
          labelText:isPickup?'Adresse de départ':'Destination',
          prefixIcon:Icon(isPickup?Icons.trip_origin:Icons.location_on),
          suffixIcon:loading?const Padding(padding:EdgeInsets.all(14),child:SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2))):null,
        ),
      ),
      for(final item in results.take(5))
        ListTile(
          dense:true,leading:const Icon(Icons.place_outlined),
          title:Text((item as Map)['label']?.toString()??''),
          onTap:()=>setState((){
            c.text=item['label']?.toString()??'';
            if(isPickup)pickupResults=[];else dropoffResults=[];
          }),
        ),
    ]);
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Votre trajet')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      addressField(true),const SizedBox(height:16),addressField(false),const SizedBox(height:24),
      const Card(child:ListTile(
        leading:Icon(Icons.info_outline),
        title:Text('Réservation programmée'),
        subtitle:Text('Le départ doit être planifié au minimum 2 heures à l’avance.'),
      )),
      FilledButton(onPressed:(){},child:const Text('Continuer')),
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
  @override void initState(){super.initState();future=api.offers(widget.bookingId);}

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Offres reçues')),
    body:FutureBuilder<List<dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return Center(child:FilledButton(onPressed:()=>setState(()=>future=api.offers(widget.bookingId)),child:const Text('Réessayer')));
        final items=s.data??[];
        if(items.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Aucune offre pour le moment. Vous serez notifié dès qu’un chauffeur propose un prix.')));
        return ListView(padding:const EdgeInsets.all(16),children:[
          const Text('Choisissez librement selon le prix, le véhicule et le chauffeur.'),
          const SizedBox(height:12),
          for(final raw in items)Builder(builder:(context){
            final x=Map<String,dynamic>.from(raw as Map);
            final total=((x['totalMinor']??0) as num).toDouble()/100;
            final driver=((x['driverPriceMinor']??0) as num).toDouble()/100;
            return Card(child:ListTile(
              leading:const CircleAvatar(child:Icon(Icons.local_taxi)),
              title:Text(total.toStringAsFixed(2)+' € total'),
              subtitle:Text('Prix chauffeur: '+driver.toStringAsFixed(2)+' € • Note: '+(x['rating']??'-').toString()),
              trailing:FilledButton(
                onPressed:()async{
                  await api.accept(widget.bookingId,x['offerId'].toString());
                  if(context.mounted)context.go('/home');
                },
                child:const Text('Choisir'),
              ),
            ));
          }),
        ]);
      },
    ),
  );
}
