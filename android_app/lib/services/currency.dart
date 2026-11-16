import 'dart:ui' show PlatformDispatcher;

import 'package:intl/intl.dart';

/// Common currencies for the picker. Any 3-letter ISO code also works.
const Map<String, String> kCurrencies = {
  'INR': 'Indian Rupee',
  'USD': 'US Dollar',
  'EUR': 'Euro',
  'GBP': 'British Pound',
  'JPY': 'Japanese Yen',
  'CNY': 'Chinese Yuan',
  'AUD': 'Australian Dollar',
  'CAD': 'Canadian Dollar',
  'CHF': 'Swiss Franc',
  'SGD': 'Singapore Dollar',
  'AED': 'UAE Dirham',
  'SAR': 'Saudi Riyal',
  'QAR': 'Qatari Riyal',
  'KWD': 'Kuwaiti Dinar',
  'BHD': 'Bahraini Dinar',
  'OMR': 'Omani Rial',
  'PKR': 'Pakistani Rupee',
  'BDT': 'Bangladeshi Taka',
  'LKR': 'Sri Lankan Rupee',
  'NPR': 'Nepalese Rupee',
  'IDR': 'Indonesian Rupiah',
  'MYR': 'Malaysian Ringgit',
  'THB': 'Thai Baht',
  'VND': 'Vietnamese Dong',
  'PHP': 'Philippine Peso',
  'KRW': 'South Korean Won',
  'HKD': 'Hong Kong Dollar',
  'NZD': 'New Zealand Dollar',
  'ZAR': 'South African Rand',
  'NGN': 'Nigerian Naira',
  'KES': 'Kenyan Shilling',
  'EGP': 'Egyptian Pound',
  'TRY': 'Turkish Lira',
  'RUB': 'Russian Ruble',
  'SEK': 'Swedish Krona',
  'NOK': 'Norwegian Krone',
  'DKK': 'Danish Krone',
  'PLN': 'Polish Zloty',
  'BRL': 'Brazilian Real',
  'MXN': 'Mexican Peso',
  'ARS': 'Argentine Peso',
};

/// Locale tag used for number formatting, with a safe fallback.
String deviceLocale() {
  final l = PlatformDispatcher.instance.locale;
  final tag = (l.countryCode == null || l.countryCode!.isEmpty)
      ? l.languageCode
      : '${l.languageCode}_${l.countryCode}';
  return Intl.verifiedLocale(tag, NumberFormat.localeExists,
          onFailure: (_) => 'en_IN') ??
      'en_IN';
}

/// Home currency suggested from the phone's region on first launch.
/// India = INR, USA = USD, Japan = JPY, and so on. Falls back to INR.
String detectHomeCurrency() {
  try {
    final name = NumberFormat.simpleCurrency(locale: deviceLocale()).currencyName;
    if (name != null && RegExp(r'^[A-Z]{3}$').hasMatch(name)) return name;
  } catch (_) {}
  return 'INR';
}

/// Formats an amount with the right symbol and decimals, for example
/// 1250 INR -> "₹1,250.00", 5 USD -> "$5.00", 500 JPY -> "¥500".
String formatMoney(double amount, String currency) {
  try {
    return NumberFormat.simpleCurrency(locale: deviceLocale(), name: currency)
        .format(amount);
  } catch (_) {
    return '$currency ${amount.toStringAsFixed(2)}';
  }
}

/// "fruits_vegetables" -> "Fruits Vegetables"
String pretty(String key) => key
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');
