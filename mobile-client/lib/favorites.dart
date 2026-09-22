part of 'main.dart';

class SavedAddressesScreen extends StatefulWidget {
  final bool select;
  const SavedAddressesScreen({this.select=false,super.key});
  @override State<SavedAddressesScreen> createState()=>_SavedAddressesScreenState();
}
class _SavedAddressesScreenState extends State<SavedAddressesScreen>{
  late Future<List<dynamic>> future;
  bool busy=false;
  @override void initState(){super.initState();reload();}
  void reload(){future=api.savedAddresses();}
  Future<void> edit(Map<String,dynamic> item)async{
    final label=TextEditingController(text:item['label']?.toString());
    final search=TextEditingController(text:item['address']?.toString());
    Map<String,dynamic>? selected={'label':item['address'],'lat':item['lat'],'lng':item['lng']};
    List<dynamic> results=[];
    String? error;
    bool searching=false;
    final confirmed=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setDialog)=>AlertDialog(
      title:Text(t('Modifier cette adresse')),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:label,maxLength:80,decoration:InputDecoration(labelText:t('Nom : Maison, Travail…'))),
        TextField(controller:search,onChanged:(_)=>setDialog(()=>selected=null),decoration:InputDecoration(labelText:t('Adresse'))),
        TextButton(onPressed:searching?null:()async{
          setDialog((){searching=true;error=null;});
          try{final values=await api.autocomplete(search.text);if(d.mounted)setDialog(()=>results=values);}
          catch(e){if(d.mounted)setDialog(()=>error=VeyraErrorMessages.forException(e));}
          finally{if(d.mounted)setDialog(()=>searching=false);}
        },child:Text(t('Rechercher'))),
        for(final raw in results)ListTile(title:Text(raw['label'].toString()),onTap:()=>setDialog((){selected=Map<String,dynamic>.from(raw as Map);search.text=selected!['label'].toString();results=[];})),
        if(error!=null)Text(error!),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:Text(t('Annuler'))),FilledButton(onPressed:selected==null?null:()=>Navigator.pop(d,true),child:Text(t('Enregistrer')))],
    )));
    if(confirmed==true&&selected!=null&&label.text.trim().isNotEmpty){
      await mutate(()=>api.updateSavedAddress(item['id'].toString(),{'label':label.text.trim(),'address':selected!['label'],'lat':selected!['lat'],'lng':selected!['lng']}));
    }
    // Dialog animation may still reference the controllers until the next frame.
  }
  Future<void> mutate(Future<void> Function() action)async{
    if(busy)return;setState(()=>busy=true);
    try{await action();if(mounted)setState(reload);}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> remove(Map<String,dynamic> item)async{
    final yes=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:Text(t('Supprimer cette adresse ?')),content:Text(item['label'].toString()),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:Text(t('Conserver'))),FilledButton(onPressed:()=>Navigator.pop(d,true),child:Text(t('Supprimer')))]));
    if(yes==true)await mutate(()=>api.deleteSavedAddress(item['id'].toString()));
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(t('Mes adresses'))),body:FutureBuilder<List<dynamic>>(future:future,builder:(context,s){
    if(s.connectionState!=ConnectionState.done)return const VeyraLoadingView();
    if(s.hasError)return VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState(reload));
    final items=s.data??[];
    if(items.isEmpty)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(t('Enregistrez une adresse depuis le formulaire de réservation après l’avoir sélectionnée.'))));
    return ListView(children:[for(final raw in items)Builder(builder:(context){final x=Map<String,dynamic>.from(raw as Map);return Card(child:Column(children:[ListTile(title:Text(x['label'].toString()),subtitle:Text(x['address'].toString()),onTap:busy?null:(){if(widget.select){Navigator.pop(context,{'label':x['address'],'lat':x['lat'],'lng':x['lng']});}else{edit(x);}}),Wrap(children:[TextButton(onPressed:busy?null:()=>edit(x),child:Text(t('Modifier'))),TextButton(onPressed:busy?null:()=>remove(x),child:Text(t('Supprimer')))])]));})]);
  }));
}

class FavoriteDriversScreen extends StatefulWidget{
  const FavoriteDriversScreen({super.key});
  @override State<FavoriteDriversScreen> createState()=>_FavoriteDriversScreenState();
}
class _FavoriteDriversScreenState extends State<FavoriteDriversScreen>{
  late Future<List<dynamic>> future;
  bool busy=false;
  @override void initState(){super.initState();future=api.favoriteDrivers();}
  Future<void> remove(String id)async{
    if(busy)return;setState(()=>busy=true);
    try{await api.removeFavoriteDriver(id);if(mounted)setState((){future=api.favoriteDrivers();});}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> rebook(Map<String,dynamic> x)async{
    if(busy)return;setState(()=>busy=true);
    try{final booking=await api.bookingDetail(x['booking_id'].toString());if(mounted)context.push('/addresses',extra:{...booking,'preferred_driver_id':x['driver_id']});}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(t('Mes chauffeurs favoris'))),body:FutureBuilder<List<dynamic>>(future:future,builder:(context,s){
    if(s.connectionState!=ConnectionState.done)return const VeyraLoadingView();
    if(s.hasError)return VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:()=>setState((){future=api.favoriteDrivers();}));
    final items=s.data??[];
    if(items.isEmpty)return Center(child:Text(t('Ajoutez un chauffeur aux favoris après une course terminée.')));
    return ListView(children:[for(final raw in items)Builder(builder:(context){final x=Map<String,dynamic>.from(raw as Map);return Card(child:Column(children:[ListTile(title:Text([x['first_name'],x['last_name']].whereType<String>().join(' ')),subtitle:Text([x['rating'],x['brand'],x['model'],x['color'],x['category_name']].where((v)=>v!=null).join(' • ')),onTap:()=>context.push('/booking/'+x['booking_id'].toString())),Wrap(children:[FilledButton(onPressed:busy?null:()=>rebook(x),child:Text(t('Réserver à nouveau'))),TextButton(onPressed:busy?null:()=>remove(x['driver_id'].toString()),child:Text(t('Retirer des favoris')))])]));})]);
  }));
}
