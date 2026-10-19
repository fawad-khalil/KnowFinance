import '../models/category.dart';
import '../models/enums.dart';
import '../services/analytics.dart';

/// Guesses an income or expense type for an imported transaction: first
/// from how the user filed the same merchant before, then from common
/// Pakistani merchants and billers.
class CategorySuggester {
  CategorySuggester(this.categories, this.history);

  final List<Category> categories;

  /// Normalized note -> category id the user last chose for it.
  final Map<String, int> history;

  static const _keywords = <String, List<String>>{
    'Groceries': ['imtiaz', 'naheed', 'carrefour', 'metro', 'al-fatah', 'alfatah', 'chase up', 'hyperstar', 'grocer', 'grocery', 'super market', 'supermarket'],
    'Dining out': ['kfc', 'mcdonald', 'foodpanda', 'pizza', 'burger', 'cafe', 'restaurant', 'hardee', 'subway', 'dominos'],
    'Utilities': ['k-electric', 'kelectric', 'lesco', 'iesco', 'mepco', 'fesco', 'pesco', 'gepco', 'hesco', 'sngpl', 'ssgc', 'wasa', 'electric', 'gas bill', 'water'],
    'Mobile & internet': ['jazz', 'zong', 'telenor', 'ufone', 'ptcl', 'nayatel', 'stormfiber', 'storm fiber', 'wateen', 'internet', 'mobile load', 'easyload'],
    'Fuel & transport': ['careem', 'uber', 'indrive', 'yango', 'bykea', 'pso', 'shell', 'total parco', 'attock', 'fuel', 'petrol', 'motorway', 'm-tag'],
    'Shopping': ['daraz', 'amazon', 'aliexpress', 'khaadi', 'sapphire', 'outfitters', 'gul ahmed', 'limelight'],
    'Subscriptions': ['netflix', 'spotify', 'youtube', 'google', 'apple.com', 'icloud', 'microsoft', 'chatgpt', 'openai', 'anthropic', 'claude'],
    'Health': ['pharmacy', 'medical', 'hospital', 'clinic', 'dawaai', 'servaid', 'chughtai', 'shaukat khanum', 'agha khan', 'aga khan'],
    'Education': ['school', 'university', 'college', 'academy', 'tuition', 'udemy', 'coursera'],
    'Travel': ['pia', 'airblue', 'serene', 'airsial', 'booking.com', 'airbnb', 'hotel', 'daewoo', 'faisal movers'],
    'Entertainment': ['cinepax', 'nueplex', 'cinema', 'steam', 'playstation'],
    'Salary': ['salary', 'payroll'],
    'Freelance': ['upwork', 'fiverr', 'payoneer', 'freelancer'],
    'Remittance': ['western union', 'remit', 'moneygram', 'wise', 'remitly', 'xoom'],
    'Profit & dividends': ['profit', 'dividend', 'mutual fund'],
  };

  int? suggest(EntryKind kind, String counterparty, String raw) {
    final key = normalizeNote(counterparty);
    if (key.isNotEmpty) {
      final known = history[key];
      if (known != null && categories.any((c) => c.id == known && c.kind == kind)) return known;
    }
    final hay = '${counterparty.toLowerCase()} ${raw.toLowerCase()}';
    for (final entry in _keywords.entries) {
      if (entry.value.any((k) => RegExp('(^|[^a-z])${RegExp.escape(k)}([^a-z]|\$)').hasMatch(hay))) {
        final match = categories.where((c) => c.name == entry.key && c.kind == kind && !c.archived);
        if (match.isNotEmpty) return match.first.id;
      }
    }
    final fallback = categories.where((c) => c.kind == kind && !c.archived && c.name == (kind == EntryKind.income ? 'Other income' : ''));
    return fallback.isEmpty ? null : fallback.first.id;
  }
}
