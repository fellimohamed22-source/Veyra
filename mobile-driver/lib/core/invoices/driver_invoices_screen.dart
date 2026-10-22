import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app_locale.dart';
import '../formatters/date_formatter.dart';
import '../formatters/error_messages.dart';
import '../formatters/money_formatter.dart';
import '../widgets/state_views.dart';
import '../widgets/veyra_ui.dart';
import 'invoice_link.dart';

/// « Mes factures » (owner decision 22/10/2026): VAT status, monthly VEYRA
/// commission invoices and the ride invoices issued on the driver's behalf.
class DriverInvoicesScreen extends StatefulWidget{
  final Future<Map<String,dynamic>> Function() load;
  final Future<Map<String,dynamic>> Function(bool registered,String? number) saveVat;
  final Future<Uri> Function(String bookingId) rideLink;
  final Future<Uri> Function(String month) commissionLink;
  const DriverInvoicesScreen({required this.load,required this.saveVat,required this.rideLink,required this.commissionLink,super.key});
  @override State<DriverInvoicesScreen> createState()=>_DriverInvoicesScreenState();
}

class _DriverInvoicesScreenState extends State<DriverInvoicesScreen>{
  late Future<Map<String,dynamic>> future=widget.load();
  final vatNumber=TextEditingController();
  bool? registered;
  bool vatLoaded=false,saving=false;
  String? busyKey,vatError;

  @override void dispose(){vatNumber.dispose();super.dispose();}

  Future<void> reload()async{
    final f=widget.load();
    setState((){future=f;vatLoaded=false;});
    try{await f;}catch(_){}
  }

  void _syncVat(Map<String,dynamic> vat){
    if(vatLoaded)return;
    vatLoaded=true;
    registered=vat['vatRegistered'] as bool?;
    vatNumber.text=(vat['vatNumber']??'').toString();
  }

  Future<void> _saveVat()async{
    if(registered==null)return;
    if(registered==true&&!RegExp(r'^[A-Z]{2}[A-Z0-9]{2,13}$').hasMatch(vatNumber.text.replaceAll(' ','').toUpperCase())){
      setState(()=>vatError=_t('Numéro de TVA intracommunautaire invalide (ex. FR12345678901).'));
      return;
    }
    setState((){saving=true;vatError=null;});
    try{
      await widget.saveVat(registered!,registered==true?vatNumber.text.replaceAll(' ','').toUpperCase():null);
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_t('Statut TVA enregistré.'))));
      await reload();
    }catch(e){
      if(mounted)setState(()=>vatError=VeyraErrorMessages.forException(e));
    }finally{
      if(mounted)setState(()=>saving=false);
    }
  }

  Future<void> _open(String key,Future<Uri> Function() link)async{
    setState(()=>busyKey=key);
    await openInvoiceLink(context,link);
    if(mounted){setState(()=>busyKey=null);reload();}
  }

  static const _monthsFr=['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'];
  static const _monthsEn=['January','February','March','April','May','June','July','August','September','October','November','December'];
  static String monthLabel(String ym){
    final p=ym.split('-');
    if(p.length!=2)return ym;
    final m=int.tryParse(p[1])??1;
    final name=AppLocale.code.value=='en'?_monthsEn[m-1]:_monthsFr[m-1];
    return '${name[0].toUpperCase()}${name.substring(1)} ${p[0]}';
  }

  Widget _vatCard(Map<String,dynamic> vat){
    final company=vat['managedByCompany'];
    if(company!=null){
      final reg=vat['vatRegistered'];
      return VeyraBanner(
        tone:reg==null?VeyraTone.warning:VeyraTone.info,
        title:_t('Statut TVA géré par votre société'),
        text:'$company · '+(reg==null?_t('À compléter par votre société sur le portail VEYRA.'):reg==true?_t('Assujettie à la TVA'):_t('Franchise de TVA')),
      );
    }
    return Container(
      padding:const EdgeInsets.all(16),
      decoration:BoxDecoration(border:Border.all(color:VeyraColors.border),borderRadius:BorderRadius.circular(VeyraRadius.lg)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(_t('Statut TVA'),style:const TextStyle(fontWeight:FontWeight.w700,fontSize:16)),
        const SizedBox(height:4),
        Text(_t('Il figure sur les factures de course émises en votre nom.'),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
        if(vat['vatRegistered']==null)...[const SizedBox(height:10),VeyraBanner(tone:VeyraTone.warning,text:_t('Indiquez votre statut TVA : sans lui, les factures de vos courses ne peuvent pas être émises.'))],
        const SizedBox(height:12),
        VeyraSelectableCard(key:const Key('vat-registered'),selected:registered==true,onTap:()=>setState(()=>registered=true),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(_t('Assujetti à la TVA'),style:const TextStyle(fontWeight:FontWeight.w600)),
          Text(_t('TVA 10 % (transport de personnes) sur vos factures.'),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
        ])),
        const SizedBox(height:8),
        VeyraSelectableCard(key:const Key('vat-franchise'),selected:registered==false,onTap:()=>setState(()=>registered=false),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(_t('Franchise de TVA (micro-entreprise)'),style:const TextStyle(fontWeight:FontWeight.w600)),
          Text(_t('Mention « TVA non applicable, art. 293 B du CGI ».'),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
        ])),
        if(registered==true)...[
          const SizedBox(height:12),
          TextField(key:const Key('vat-number'),controller:vatNumber,textCapitalization:TextCapitalization.characters,decoration:InputDecoration(labelText:_t('N° de TVA intracommunautaire'),hintText:'FR12345678901')),
        ],
        if(vatError!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(vatError!,style:const TextStyle(color:VeyraColors.danger))),
        const SizedBox(height:12),
        FilledButton(key:const Key('vat-save'),onPressed:registered==null||saving?null:_saveVat,child:Text(saving?_t('Enregistrement…'):_t('Enregistrer'))),
      ]),
    );
  }

  Widget _row({required Key key,required String title,required String subtitle,required String amount,String? number,required bool available,required bool busy,required VoidCallback onTap,String? pending}){
    return Container(
      key:key,
      margin:const EdgeInsets.only(bottom:10),
      padding:const EdgeInsets.all(14),
      decoration:BoxDecoration(border:Border.all(color:VeyraColors.border),borderRadius:BorderRadius.circular(VeyraRadius.md)),
      child:Row(children:[
        const Icon(Icons.receipt_long_outlined,color:VeyraColors.textSecondary),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(title,style:const TextStyle(fontWeight:FontWeight.w600)),
          Text(subtitle,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
          Text(number??pending??_t('Émise au premier téléchargement'),style:const TextStyle(color:VeyraColors.textTertiary,fontSize:12)),
        ])),
        const SizedBox(width:8),
        Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Text(amount,style:const TextStyle(fontWeight:FontWeight.w800)),
          available
            ?TextButton(onPressed:busy?null:onTap,child:busy?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):Text(_t('Télécharger')))
            :Padding(padding:const EdgeInsets.only(top:8),child:Text(_t('En cours'),style:const TextStyle(color:VeyraColors.warning,fontWeight:FontWeight.w600,fontSize:12))),
        ]),
      ]),
    );
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(_t('Mes factures'))),
    body:FutureBuilder<Map<String,dynamic>>(
      future:future,
      builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const VeyraLoadingView();
        if(s.hasError)return VeyraErrorMessages.isOffline(s.error!)
          ?VeyraOfflineBanner(onRetry:reload)
          :VeyraErrorView(customMessage:VeyraErrorMessages.forException(s.error!),onRetry:reload);
        final x=s.data??{};
        final vat=Map<String,dynamic>.from((x['vat'] as Map?)??const {});
        _syncVat(vat);
        final commissions=((x['commissions'] as List?)??const[]).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).toList();
        final rides=((x['rides'] as List?)??const[]).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).toList();
        return RefreshIndicator(onRefresh:reload,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(16,12,16,24),children:[
          _vatCard(vat),
          const SizedBox(height:22),
          VeyraSectionLabel(_t('Factures de commission VEYRA')),
          const SizedBox(height:4),
          Text(_t('Une facture par mois pour la commission des courses terminées.'),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
          const SizedBox(height:10),
          if(commissions.isEmpty)Text(_t('Aucune commission pour le moment.'),style:const TextStyle(color:VeyraColors.textSecondary)),
          for(final c in commissions)_row(
            key:Key('commission-${c['month']}'),
            title:monthLabel(c['month'].toString()),
            subtitle:'${c['rides']} '+(((c['rides'] as num?)??0)>1?_t('courses'):_t('course')),
            amount:VeyraMoneyFormatter.fromMinor(c['commissionMinor']),
            number:c['number']?.toString(),
            pending:c['available']==true?null:_t('Disponible après la fin du mois'),
            available:c['available']==true,
            busy:busyKey=='c-${c['month']}',
            onTap:()=>_open('c-${c['month']}',()=>widget.commissionLink(c['month'].toString())),
          ),
          const SizedBox(height:22),
          VeyraSectionLabel(_t('Factures de course')),
          const SizedBox(height:4),
          Text(_t('Émises par VEYRA en votre nom pour vos clients (mandat de facturation).'),style:const TextStyle(color:VeyraColors.textSecondary,fontSize:13)),
          const SizedBox(height:10),
          if(rides.isEmpty)Text(_t('Aucune course terminée pour le moment.'),style:const TextStyle(color:VeyraColors.textSecondary)),
          for(final r in rides)_row(
            key:Key('ride-${r['booking_id']}'),
            title:VeyraDateFormatter.dateTime(r['completed_at']),
            subtitle:'${r['pickup_address']??''} → ${r['dropoff_address']??''}',
            amount:VeyraMoneyFormatter.fromMinor(r['total_minor']),
            number:r['number']?.toString(),
            available:true,
            busy:busyKey=='r-${r['booking_id']}',
            onTap:()=>_open('r-${r['booking_id']}',()=>widget.rideLink(r['booking_id'].toString())),
          ),
        ]));
      },
    ),
  );
}

String _t(String french)=>AppLocale.t(french);
