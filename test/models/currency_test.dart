import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/models/currency.dart';

void main() {
  group('formatMoneyShort', () {
    test('keeps small amounts whole', () {
      expect(formatMoneyShort(0, 'PKR'), 'Rs 0');
      expect(formatMoneyShort(950, 'PKR'), 'Rs 950');
      expect(formatMoneyShort(999.6, 'PKR'), 'Rs 1,000');
    });

    test('uses one decimal and drops a trailing .0', () {
      expect(formatMoneyShort(40000, 'PKR'), 'Rs 40K');
      expect(formatMoneyShort(397700, 'PKR'), 'Rs 397.7K');
      expect(formatMoneyShort(1234567, 'PKR'), 'Rs 1.2M');
      expect(formatMoneyShort(2500000000, 'PKR'), 'Rs 2.5B');
    });

    test('carries into the next unit instead of showing 1000K', () {
      expect(formatMoneyShort(999950, 'PKR'), 'Rs 1M');
      expect(formatMoneyShort(999940, 'PKR'), 'Rs 999.9K');
    });

    test('signs negatives and uses the home currency symbol', () {
      expect(formatMoneyShort(-4200, 'PKR'), '−Rs 4.2K');
      expect(formatMoneyShort(1500, 'USD'), r'$1.5K');
      expect(formatMoneyShort(1500, 'AED'), 'AED 1.5K');
    });
  });

  group('formatSignedMoney', () {
    test('adds an explicit sign', () {
      expect(formatSignedMoney(53950, 'PKR'), '+Rs 53,950');
      expect(formatSignedMoney(-4200, 'PKR'), '−Rs 4,200');
      expect(formatSignedMoney(0, 'PKR'), 'Rs 0');
    });

    test('shows the currency decimals for fractional amounts', () {
      expect(formatSignedMoney(12.5, 'EUR'), '+€12.50');
      expect(formatSignedMoney(-1.25, 'KWD'), '−KWD 1.250');
    });
  });
}
