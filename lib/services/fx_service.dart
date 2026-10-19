import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/finance_repository.dart';
import '../models/entry.dart';

/// Looks up the exchange rate between two currencies on a given date.
///
/// Uses the free, key-less fawazahmed0 currency API (it includes PKR and
/// historical dates) and caches every rate it fetches in the database, so a
/// rate is downloaded at most once per date and currency pair.
class FxService {
  FxService(this._repo, {http.Client? client}) : _client = client ?? http.Client();

  final FinanceRepository _repo;
  final http.Client _client;

  /// Returns null when the rate isn't cached and can't be fetched (offline,
  /// unknown currency). The UI then asks the user to type it in.
  Future<double?> rate(String from, String to, DateTime date) async {
    if (from == to) return 1;
    final day = dateKey(_notInFuture(date));
    final cached = await _repo.cachedRate(day, from, to);
    if (cached != null) return cached;

    final base = from.toLowerCase();
    final quote = to.toLowerCase();
    for (final url in _urls(day, base)) {
      try {
        final res = await _client.get(url).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final rates = body[base] as Map<String, dynamic>?;
        final value = (rates?[quote] as num?)?.toDouble();
        if (value == null) continue;
        await _repo.cacheRate(day, from, to, value);
        return value;
      } catch (_) {
        // Try the next mirror.
      }
    }
    return null;
  }

  /// Fills in missing rates and re-bases entries saved under an older home
  /// currency. Returns how many entries still need a rate typed in.
  Future<int> refreshEntries(String homeCurrency) async {
    var missing = 0;
    for (final e in await _repo.entriesNeedingRate(homeCurrency)) {
      final r = await rate(e.currency, homeCurrency, e.date);
      if (r == null) {
        missing++;
        if (e.homeCurrency != homeCurrency) {
          await _repo.saveEntry(e.copyWith(homeCurrency: homeCurrency, fxRate: () => null));
        }
        continue;
      }
      await _repo.saveEntry(e.copyWith(homeCurrency: homeCurrency, fxRate: () => r));
    }
    return missing;
  }

  static DateTime _notInFuture(DateTime d) {
    final now = DateTime.now();
    return d.isAfter(now) ? now : d;
  }

  static List<Uri> _urls(String day, String base) => [
        Uri.parse('https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@$day/v1/currencies/$base.min.json'),
        Uri.parse('https://$day.currency-api.pages.dev/v1/currencies/$base.min.json'),
      ];
}
