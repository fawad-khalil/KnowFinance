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
