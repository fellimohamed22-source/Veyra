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
    setState((){loading=true;error=null;});
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
  List<dynamic> pickupResults=[];
  List<dynamic> dropoffResults=[];
  Map<String,dynamic>? pickupPlace;
  Map<String,dynamic>? dropoffPlace;
  DateTime? scheduledAt;
  String paymentMethod='CASH';
  String? categoryId;
  late Future<List<dynamic>> categories;
  bool loadingPickup=false;
  bool loadingDropoff=false;
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

  Widget addressField(bool isPickup){
    final controller=isPickup?pickup:dropoff;
    final results=isPickup?pickupResults:dropoffResults;
    final loading=isPickup?loadingPickup:loadingDropoff;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      TextField(
        controller:controller,
        onChanged:(q){
          if(isPickup)pickupPlace=null;else dropoffPlace=null;
          search(isPickup,q);
        },
        decoration:InputDecoration(
          labelText:isPickup?'Adresse de départ':'Destination',
          prefixIcon:Icon(isPickup?Icons.trip_origin:Icons.location_on),
          suffixIcon:loading?const Padding(
            padding:EdgeInsets.all(14),
            child:SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)),
          ):null,
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
      });
      if(mounted)context.go('/home');
    }catch(_){
      if(mounted)setState(()=>error='La réservation n’a pas pu être publiée. Vérifiez les informations puis réessayez.');
    }finally{
      if(mounted)setState(()=>submitting=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Planifier une réservation')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      addressField(true),
      const SizedBox(height:16),
      addressField(false),
      const SizedBox(height:18),
      ListTile(
        contentPadding:EdgeInsets.zero,
        leading:const Icon(Icons.event),
        title:const Text('Date et heure de départ'),
        subtitle:Text(scheduledAt==null?'Minimum 2 h à l’avance':scheduledAt.toString()),
        trailing:OutlinedButton(onPressed:chooseDateTime,child:const Text('Choisir')),
      ),
      const SizedBox(height:12),
      FutureBuilder<List<dynamic>>(
        future:categories,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
          if(s.hasError)return const Text('Catégories indisponibles.');
          final items=s.data??[];
          return DropdownButtonFormField<String>(
            initialValue:categoryId,
            decoration:const InputDecoration(labelText:'Catégorie de véhicule'),
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
      const Text('Paiement',style:TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
      RadioListTile<String>(
        value:'CASH',groupValue:paymentMethod,
        title:const Text('Cash'),
        subtitle:const Text('Le total inclut la commission Veyra.'),
        onChanged:(v)=>setState(()=>paymentMethod=v!),
      ),
      RadioListTile<String>(
        value:'ONLINE',groupValue:paymentMethod,
        title:const Text('En ligne'),
        subtitle:const Text('Paiement sécurisé avant le démarrage de la course.'),
        onChanged:(v)=>setState(()=>paymentMethod=v!),
      ),
      if(error!=null)Padding(
        padding:const EdgeInsets.symmetric(vertical:12),
        child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      ),
      FilledButton.icon(
        onPressed:submitting?null:publish,
        icon:const Icon(Icons.campaign),
        label:submitting?const Text('Publication…'):const Text('Publier la demande'),
      ),
      const SizedBox(height:12),
      const Text(
        'Les chauffeurs VTC éligibles recevront la demande et pourront proposer leur prix. Vous verrez toutes les offres reçues.',
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
