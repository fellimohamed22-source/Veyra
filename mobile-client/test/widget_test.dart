import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main(){
  testWidgets('login screen is visible',(tester)async{
    await tester.pumpWidget(const App());
    // The redesigned screen shows the Veyra wordmark in a gradient hero
    // header rather than an AppBar title -- 'Connexion Veyra' no longer
    // appears anywhere on screen.
    expect(find.text('Veyra'),findsOneWidget);
    expect(find.text('Bienvenue'),findsOneWidget);
    expect(find.text('Se connecter'),findsOneWidget);
  });
}
