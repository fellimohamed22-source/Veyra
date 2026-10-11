import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/widgets/recent_destinations_section.dart';

void main() {
  testWidgets('renders empty state without controls', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      RecentDestinationsSection(destinations: const [], onSelected: (_) {},
        onRemove: (_) {}))));
    expect(find.text('Destinations récentes'), findsNothing);
  });

  testWidgets('selects and deletes distinct destinations', (tester) async {
    String? selected;
    String? deleted;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      RecentDestinationsSection(
        destinations: const [{'id':'123','address':'Gare de Lyon','lat':48.8,'lng':2.3}],
        onSelected: (value) => selected = value['address'] as String,
        onRemove: (id) => deleted = id,
      ))));
    await tester.tap(find.text('Gare de Lyon'));
    expect(selected,'Gare de Lyon');
    await tester.tap(find.byTooltip('Supprimer cette destination'));
    expect(deleted,'123');
  });

  testWidgets('retry shown on error', (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      RecentDestinationsSection(destinations: const [], onSelected: (_) {},
        onRemove: (_) {}, error:'Connexion impossible',
        onRetry: () => retried = true))));
    await tester.tap(find.text('Réessayer'));
    expect(retried,isTrue);
  });
}
