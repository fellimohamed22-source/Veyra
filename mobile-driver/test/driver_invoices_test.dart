import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/core/invoices/driver_invoices_screen.dart';
import 'package:veyra_driver/core/invoices/invoice_link.dart';

void main(){
  testWidgets('VAT status, monthly commission and ride invoices',(t)async{
    bool? savedRegistered;String? savedNumber;
    final opened=<Uri>[];
    invoiceLauncher=(uri)async{opened.add(uri);return true;};
    Map<String,dynamic> data()=>{
      'vat':{'managedByCompany':null,'vatRegistered':savedRegistered,'vatNumber':savedNumber},
      'commissions':[
        {'month':'2026-10','rides':2,'commissionMinor':900,'currency':'EUR','available':false,'number':null},
        {'month':'2026-09','rides':12,'commissionMinor':5400,'currency':'EUR','available':true,'number':'VC-2026-00007'},
      ],
      'rides':[{'booking_id':'b1','completed_at':'2026-09-14T08:30:00Z','pickup_address':'Nice','dropoff_address':'Monaco','total_minor':6500,'currency':'EUR','number':null}],
    };
    await t.pumpWidget(MaterialApp(home:DriverInvoicesScreen(
      load:()async=>data(),
      saveVat:(r,n)async{savedRegistered=r;savedNumber=n;return {};},
      rideLink:(id)async=>Uri.parse('https://api.test/api/v1/guest/invoices/r-$id'),
      commissionLink:(m)async=>Uri.parse('https://api.test/api/v1/guest/invoices/c-$m'),
    )));
    await t.pumpAndSettle();

    // No VAT status yet: warning, then a registered status needs a valid number.
    expect(find.textContaining('Indiquez votre statut TVA'),findsOneWidget);
    await t.tap(find.byKey(const Key('vat-registered')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('vat-number')),'12');
    await t.tap(find.byKey(const Key('vat-save')));
    await t.pumpAndSettle();
    expect(find.textContaining('invalide'),findsOneWidget);
    expect(savedRegistered,isNull);
    await t.enterText(find.byKey(const Key('vat-number')),'fr 40123456782');
    await t.tap(find.byKey(const Key('vat-save')));
    await t.pumpAndSettle();
    expect(savedRegistered,isTrue);
    expect(savedNumber,'FR40123456782');
    expect(find.textContaining('Indiquez votre statut TVA'),findsNothing);

    // Current month is still open; September downloads.
    await t.scrollUntilVisible(find.byKey(const Key('commission-2026-09')),200,scrollable:find.descendant(of:find.byType(ListView),matching:find.byType(Scrollable)).first);
    expect(find.text('Octobre 2026'),findsOneWidget);
    expect(find.text('Disponible après la fin du mois'),findsOneWidget);
    expect(find.text('VC-2026-00007'),findsOneWidget);
    await t.tap(find.descendant(of:find.byKey(const Key('commission-2026-09')),matching:find.text('Télécharger')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('ride-b1')),200,scrollable:find.descendant(of:find.byType(ListView),matching:find.byType(Scrollable)).first);
    await t.tap(find.descendant(of:find.byKey(const Key('ride-b1')),matching:find.text('Télécharger')));
    await t.pumpAndSettle();
    expect(opened.map((u)=>u.path),['/api/v1/guest/invoices/c-2026-09','/api/v1/guest/invoices/r-b1']);
  });
}
