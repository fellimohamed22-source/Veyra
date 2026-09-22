import 'package:flutter/material.dart';
import '../../app_locale.dart';
String t(String value)=>AppLocale.t(value);
class VeyraPaginationBar extends StatelessWidget{
  final int page;
  final bool hasNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const VeyraPaginationBar({
    super.key,
    required this.page,
    required this.hasNext,
    this.onPrevious,
    this.onNext,
  });

  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.only(top:14,bottom:4),
    child:Row(children:[
      Expanded(child:OutlinedButton.icon(
        onPressed:page>0?onPrevious:null,
        icon:const Icon(Icons.chevron_left),
        label:Text(t('Précédent')),
      )),
      Padding(
        padding:const EdgeInsets.symmetric(horizontal:14),
        child:Text(
          t('Page')+' '+(page+1).toString(),
          style:const TextStyle(fontWeight:FontWeight.w700,color:Color(0xFF4B5563)),
        ),
      ),
      Expanded(child:FilledButton.icon(
        onPressed:hasNext?onNext:null,
        icon:const Icon(Icons.chevron_right),
        label:Text(t('Suivant')),
      )),
    ]),
  );
}
