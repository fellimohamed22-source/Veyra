import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/formatters/money_formatter.dart';

void main() {
  test('converts minor units to a French-formatted amount', () {
    expect(VeyraMoneyFormatter.fromMinor(19500), '195,00 €');
    expect(VeyraMoneyFormatter.fromMinor(500), '5,00 €');
    expect(VeyraMoneyFormatter.fromMinor(0), '0,00 €');
  });

  test('handles null and non-numeric input without crashing or inventing a number', () {
    expect(VeyraMoneyFormatter.fromMinor(null), '—');
    expect(VeyraMoneyFormatter.fromMinor('not-a-number'), '—');
  });

  test('accepts a numeric string as returned by some JSON decoders', () {
    expect(VeyraMoneyFormatter.fromMinor('19500'), '195,00 €');
  });
}
