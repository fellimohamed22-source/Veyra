import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main(){
  testWidgets('welcome screen is visible',(tester)async{
    await tester.pumpWidget(const App());
    // The redirect added for session persistence reads secure storage
    // asynchronously before GoRouter settles on a route.
    await tester.pumpAndSettle();
    // Board 08 A1: wordmark, tagline and the welcome actions.
    expect(find.text('VEYRA'),findsOneWidget);
    expect(find.text('Voyagez en toute confiance'),findsOneWidget);
    expect(find.text('Créer un compte'),findsOneWidget);
    expect(find.text('Se connecter'),findsOneWidget);
  });
}
