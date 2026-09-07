import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main(){
  testWidgets('login screen is visible',(tester)async{
    await tester.pumpWidget(const App());
    // The redirect added for session persistence reads secure storage
    // asynchronously before GoRouter settles on a route -- without
    // letting that resolve, the widget tree can still be mid-navigation
    // when the assertions below run, showing neither the login screen
    // nor a stable value to match against.
    await tester.pumpAndSettle();
    // The redesigned screen shows the Veyra wordmark in a gradient hero
    // header rather than an AppBar title -- 'Connexion Veyra' no longer
    // appears anywhere on screen.
    expect(find.text('Veyra'),findsOneWidget);
    expect(find.text('Bienvenue'),findsOneWidget);
    expect(find.text('Se connecter'),findsOneWidget);
  });
}
