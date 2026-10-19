import 'enums.dart';

/// An income type (Salary, Freelance...) or an expense type (Groceries,
/// Dining out...). Expense types always belong to a [Bucket].
class Category {
  const Category({
    this.id,
    required this.name,
    required this.kind,
    this.bucket,
    this.archived = false,
  }) : assert(kind == EntryKind.income || bucket != null);

  final int? id;
  final String name;
  final EntryKind kind;
  final Bucket? bucket;
  final bool archived;

  Category copyWith({String? name, Bucket? bucket, bool? archived}) =>
      Category(
        id: id,
        name: name ?? this.name,
        kind: kind,
        bucket: bucket ?? this.bucket,
        archived: archived ?? this.archived,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'bucket': bucket?.name,
        'archived': archived ? 1 : 0,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int,
        name: m['name'] as String,
        kind: EntryKind.fromName(m['kind'] as String),
        bucket: Bucket.fromName(m['bucket'] as String?),
        archived: (m['archived'] as int) == 1,
      );
}
