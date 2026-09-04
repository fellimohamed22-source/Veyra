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
  GoRoute(path:'/home',builder:(c,s)=>const OpportunitiesScreen()),
  GoRoute(path:'/request/:id',builder:(c,s)=>RequestScreen(bookingId:s.pathParameters['id']!)),
  GoRoute(path:'/wallet',builder:(c,s)=>const WalletScreen()),
]);

class LoginScreen extends StatefulWidget{
  const LoginScreen({super.key});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen>{
  final email=TextEditingController();
  final password=TextEditingController();
  bool loading=false;String? error;

  Future<void> submit()async{
    setState((){loading=true;error=null;});
    try{
      await api.login(email.text,password.text);
      if(mounted)context.go('/home');
    }catch(_){
      if(mounted)setState(()=>error='Connexion impossible.');
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Veyra Chauffeur')),
    body:ListView(padding:const EdgeInsets.all(24),children:[
      const Text('Espace Chauffeur VTC',style:TextStyle(fontSize:28,fontWeight:FontWeight.bold)),
      const SizedBox(height:24),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email')),
      const SizedBox(height:12),
      TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Mot de passe')),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:20),
      FilledButton(onPressed:loading?null:submit,child:loading?const CircularProgressIndicator():const Text('Se connecter')),
    ]),
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
      IconButton(onPressed:()=>context.go('/wallet'),icon:const Icon(Icons.account_balance_wallet))
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
        const SizedBox(height:16),
        FutureBuilder<List<dynamic>>(
          future:future,
          builder:(context,s){
            if(s.connectionState!=ConnectionState.done)return const Center(child:Padding(padding:EdgeInsets.all(32),child:CircularProgressIndicator()));
            if(s.hasError)return Card(child:ListTile(
              leading:const Icon(Icons.error_outline),
              title:const Text('Impossible de charger les demandes'),
              trailing:TextButton(onPressed:reload,child:const Text('Réessayer')),
            ));
            final items=s.data??[];
            if(items.isEmpty)return const Card(child:ListTile(
              leading:Icon(Icons.inbox_outlined),
              title:Text('Aucune demande ouverte'),
              subtitle:Text('Les nouvelles demandes apparaîtront ici automatiquement.'),
            ));
            return Column(children:items.map((raw){
              final x=Map<String,dynamic>.from(raw as Map);
              final id=x['id'].toString();
              final title=(x['pickup_address']??'Départ').toString()+' → '+(x['dropoff_address']??'Destination').toString();
              return Card(child:ListTile(
                title:Text(title),
                subtitle:Text((x['scheduled_at']??'').toString()),
                trailing:const Icon(Icons.chevron_right),
                onTap:()=>context.go('/request/'+id),
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
  bool sending=false;String? error;

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
        leading:Icon(Icons.visibility_off_outlined),
        title:Text('Offre privée'),
        subtitle:Text('Vous ne voyez jamais le prix proposé par les autres chauffeurs ni le meilleur prix actuel.'),
      )),
      TextField(
        controller:amount,
        keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:const InputDecoration(labelText:'Votre prix net (€)',helperText:'C’est le montant exact que vous devez recevoir pour la course.'),
      ),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:20),
      FilledButton(onPressed:sending?null:submit,child:sending?const CircularProgressIndicator():const Text('Envoyer mon offre')),
    ]),
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
          if(x['cashWarning']==true)const Card(child:ListTile(leading:Icon(Icons.warning_amber),title:Text('Seuil de dette atteint'),subtitle:Text('Régularisez votre dette pour éviter les restrictions CASH.'))),
        ]);
      },
    ),
  );
}
