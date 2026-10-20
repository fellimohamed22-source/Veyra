import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/core/widgets/veyra_ui.dart' show VeyraWordmark;

void main(){
  testWidgets('driver welcome (board 08 B1)',(t)async{
    await t.pumpWidget(const DriverApp());
    await t.pumpAndSettle();
    expect(find.byType(VeyraWordmark),findsOneWidget);
    expect(find.text('Rejoignez VEYRA'),findsOneWidget);
    expect(find.text('Créer un compte chauffeur'),findsOneWidget);
    await t.tap(find.text('Se connecter'));
    await t.pumpAndSettle();
    // The sign-in form keeps e-mail and Firebase phone sign-in.
    expect(find.text('Mot de passe'),findsOneWidget);
    expect(find.text('Continuer avec le téléphone'),findsOneWidget);
  });
}
