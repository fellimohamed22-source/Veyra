import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/formatters/money_formatter.dart';

void main() {
  test('amounts use French grouping as on the boards', () {
    expect(VeyraMoneyFormatter.fromMinor(4800), '48,00 €');
    expect(VeyraMoneyFormatter.fromMinor(125000), '1 250,00 €');
    expect(VeyraMoneyFormatter.fromMinor(123456789), '1 234 567,89 €');
    expect(VeyraMoneyFormatter.fromMinor(-1500), '-15,00 €');
    expect(VeyraMoneyFormatter.fromMinor(null), '—');
  });
}
