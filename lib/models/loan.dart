import 'entry.dart';
import 'enums.dart';

/// Money borrowed (a payable) or lent (a receivable). Entries linked to it
/// move money in or out without being income or spending.
class Loan {
  const Loan({
    this.id,
    required this.name,
    required this.direction,
    this.note = '',
    this.dueDate,
  });

  final int? id;

  /// Who the loan is with: a person, a bank, "Car loan".
  final String name;
  final LoanDirection direction;
  final String note;
  final DateTime? dueDate;

  Loan copyWith({String? name, LoanDirection? direction, String? note, DateTime? Function()? dueDate}) => Loan(
        id: id,
        name: name ?? this.name,
        direction: direction ?? this.direction,
        note: note ?? this.note,
        dueDate: dueDate != null ? dueDate() : this.dueDate,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'direction': direction.name,
        'note': note,
        'due_date': dueDate == null ? null : dateKey(dueDate!),
      };

  factory Loan.fromMap(Map<String, Object?> m) => Loan(
        id: m['id'] as int,
        name: m['name'] as String,
        direction: LoanDirection.values.byName(m['direction'] as String),
        note: m['note'] as String,
        dueDate: m['due_date'] == null ? null : DateTime.parse(m['due_date'] as String),
      );
}
