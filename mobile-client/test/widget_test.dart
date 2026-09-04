import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main(){
  testWidgets('login screen is visible',(tester)async{
    await tester.pumpWidget(const App());
    expect(find.text('Connexion Veyra'),findsOneWidget);
    expect(find.text('Se connecter'),findsOneWidget);
  });
}
