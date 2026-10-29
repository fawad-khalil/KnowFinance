/// A standing monthly spending limit in the home currency, either for one
/// expense type or, when [categoryId] is null, for the whole month.
///
/// With only category budgets, the month's total is their sum. With an
/// overall budget, that is the total and any category budgets are parts of
/// it; whatever they leave is unallocated.
class Budget {
  const Budget({this.id, this.categoryId, required this.amount});

  final int? id;
  final int? categoryId;
  final double amount;

  bool get isOverall => categoryId == null;

  Map<String, Object?> toMap() => {'id': id, 'category_id': categoryId, 'amount': amount};

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
        id: m['id'] as int,
        categoryId: m['category_id'] as int?,
        amount: (m['amount'] as num).toDouble(),
      );
}
