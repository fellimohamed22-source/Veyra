import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_locale.dart';
import '../formatters/error_messages.dart';

/// Opens an invoice PDF: the backend hands out a short-lived signed link
/// (15 min) that the phone's browser shows or downloads.
/// Replaceable in tests.
Future<bool> Function(Uri uri) invoiceLauncher=(uri)=>launchUrl(uri,mode:LaunchMode.externalApplication);

/// Absolute URL of a link path returned by the API ("/api/v1/guest/invoices/...").
Uri invoiceUri(String baseUrl,String path)=>Uri.parse(baseUrl).resolve(path);

Future<void> openInvoiceLink(BuildContext context,Future<Uri> Function() link)async{
  final messenger=ScaffoldMessenger.of(context);
  try{
    final uri=await link();
    if(!await invoiceLauncher(uri))messenger.showSnackBar(SnackBar(content:Text(_t('Impossible d’ouvrir la facture.'))));
  }catch(e){
    messenger.showSnackBar(SnackBar(content:Text(VeyraErrorMessages.forException(e))));
  }
}

String _t(String french)=>AppLocale.t(french);
