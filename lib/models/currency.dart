import 'package:intl/intl.dart';

class Currency {
  const Currency(this.code, this.name, {this.decimals = 2});

  final String code;
  final String name;
  final int decimals;
}

const defaultCurrencyCode = 'PKR';

/// Currencies offered in pickers. PKR first, then common ones for
/// Pakistan-based users (remittances, travel, online purchases).
const currencies = <Currency>[
  Currency('PKR', 'Pakistani Rupee'),
  Currency('USD', 'US Dollar'),
  Currency('EUR', 'Euro'),
  Currency('GBP', 'British Pound'),
  Currency('AED', 'UAE Dirham'),
  Currency('SAR', 'Saudi Riyal'),
  Currency('QAR', 'Qatari Riyal'),
  Currency('KWD', 'Kuwaiti Dinar', decimals: 3),
  Currency('OMR', 'Omani Rial', decimals: 3),
  Currency('BHD', 'Bahraini Dinar', decimals: 3),
  Currency('CAD', 'Canadian Dollar'),
  Currency('AUD', 'Australian Dollar'),
  Currency('CNY', 'Chinese Yuan'),
  Currency('TRY', 'Turkish Lira'),
  Currency('MYR', 'Malaysian Ringgit'),
  Currency('INR', 'Indian Rupee'),
  Currency('JPY', 'Japanese Yen', decimals: 0),
];

Currency currencyFor(String code) => currencies.firstWhere(
      (c) => c.code == code,
      orElse: () => Currency(code, code),
    );

/// Whole amounts are shown without decimals ("PKR 4,500"); fractional
/// amounts use the currency's usual number of decimals.
String formatMoney(double amount, String code) {
  final c = currencyFor(code);
  final whole = amount == amount.roundToDouble();
  return NumberFormat.currency(
    locale: 'en_US',
    symbol: '${c.code} ',
    decimalDigits: whole ? 0 : c.decimals,
  ).format(amount);
}

/// Short form for chart labels: "PKR 1.2M".
String compactMoney(double amount, String code) =>
    '$code ${NumberFormat.compact(locale: 'en_US').format(amount)}';

/// Symbol shown before amounts on summary cards: "Rs" for PKR, a sign for a
/// few well-known currencies, otherwise the ISO code.
String currencySymbol(String code) => switch (code) {
      'PKR' => 'Rs',
      'INR' => '₹',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      'JPY' => '¥',
      _ => code,
    };

String _withSymbol(String number, String code) {
  final s = currencySymbol(code);
  // Letter symbols ("Rs", "AED") need a space; signs ("$", "€") don't.
  return RegExp(r'[A-Za-z]$').hasMatch(s) ? '$s $number' : '$s$number';
}

/// Full amount with the currency symbol and an explicit sign: "+Rs 53,950",
/// "−Rs 4,200", "Rs 0".
String formatSignedMoney(double amount, String code) {
  final c = currencyFor(code);
  final abs = amount.abs();
  final whole = abs == abs.roundToDouble();
  final number = NumberFormat.decimalPatternDigits(locale: 'en_US', decimalDigits: whole ? 0 : c.decimals).format(abs);
  final sign = amount > 0 ? '+' : amount < 0 ? '−' : '';
  return '$sign${_withSymbol(number, code)}';
}

/// Short amount with the currency symbol and at most one decimal:
/// "Rs 950", "Rs 40K", "Rs 397.7K", "Rs 1.2M". Negative amounts get "−".
String formatMoneyShort(double amount, String code) {
  const units = ['', 'K', 'M', 'B', 'T'];
  var v = amount.abs();
  var i = 0;
  while (i < units.length - 1 && v >= 1000) {
    v /= 1000;
    i++;
  }
  // 999,950 rounds to "1000K"; carry into the next unit instead.
  if (i > 0 && i < units.length - 1 && double.parse(v.toStringAsFixed(1)) >= 1000) {
    v /= 1000;
    i++;
  }
  final number = i == 0
      ? NumberFormat.decimalPatternDigits(locale: 'en_US', decimalDigits: 0).format(v)
      : '${v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}${units[i]}';
  return '${amount < 0 && number != '0' ? '−' : ''}${_withSymbol(number, code)}';
}
