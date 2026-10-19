/// Whether money came in or went out.
enum EntryKind {
  income,
  expense;

  static EntryKind fromName(String name) =>
      EntryKind.values.firstWhere((k) => k.name == name);
}

/// The top-level bucket every expense type belongs to.
enum Bucket {
  needs('Needs'),
  wants('Wants'),
  savings('Savings');

  const Bucket(this.label);
  final String label;

  static Bucket? fromName(String? name) => name == null
      ? null
      : Bucket.values.firstWhere((b) => b.name == name);
}

/// Where an entry was created from.
enum EntrySource {
  manual,
  sms,
  email,
  statement;

  static EntrySource fromName(String name) =>
      EntrySource.values.firstWhere((s) => s.name == name);
}
