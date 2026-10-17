import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/core/widgets/offer_price_preview.dart';

void main(){
  test('net price parsing accepts comma and dot, rejects invalid input',(){
    expect(OfferPricePreview.parseMinor('48'),4800);
    expect(OfferPricePreview.parseMinor('48,5'),4850);
    expect(OfferPricePreview.parseMinor('48.50'),4850);
    expect(OfferPricePreview.parseMinor(''),isNull);
    expect(OfferPricePreview.parseMinor('-3'),isNull);
    expect(OfferPricePreview.parseMinor('abc'),isNull);
  });

  testWidgets('shows the server-computed customer total for the typed net price',(tester)async{
    int? requested;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:OfferPricePreview(
      amountText:'48',
      fetchQuote:(minor)async{
        requested=minor;
        return {'driverNetMinor':4800,'commissionMinor':480,'customerTotalMinor':5280};
      },
    ))));
    await tester.pump(const Duration(milliseconds:500));
    await tester.pump();
    expect(requested,4800);
    expect(find.text('Prix total pour le client'),findsOneWidget);
    expect(find.textContaining('52,80'),findsOneWidget);
  });
}
