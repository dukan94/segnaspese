import 'transaction_entity.dart';

/// Frequenza di ripetizione di un movimento ricorrente.
enum RecurringFrequencyType { weekly, monthly, yearly }

/// Rappresentazione di dominio di un movimento ricorrente (es. "Netflix
/// 12,99€ ogni mese", "Stipendio 1.800€ ogni mese").
///
/// Non dipende da Drift né da Flutter: è l'oggetto che circola tra UseCase,
/// Repository (interfacce) e Presentation. Ogni ricorrenza genera
/// automaticamente le [TransactionEntity] corrispondenti quando è dovuta la
/// prossima occorrenza (v. GenerateDueRecurring).
class RecurringEntity {
  final int? id;
  final String description;
  final double amount;
  final TransactionType type;
  final int categoryId;
  final int? subCategoryId;
  final RecurringFrequencyType frequency;

  /// Giorno del mese in cui generare la transazione (solo per
  /// [RecurringFrequencyType.monthly]). Se null si usa il giorno della
  /// prossima occorrenza.
  final int? dayOfMonth;

  /// Data della prossima occorrenza da generare.
  final DateTime nextOccurrence;

  /// Se false, la ricorrenza è in pausa: non genera nuove transazioni.
  final bool active;

  const RecurringEntity({
    this.id,
    required this.description,
    required this.amount,
    required this.type,
    required this.categoryId,
    this.subCategoryId,
    required this.frequency,
    this.dayOfMonth,
    required this.nextOccurrence,
    this.active = true,
  });

  RecurringEntity copyWith({
    int? id,
    String? description,
    double? amount,
    TransactionType? type,
    int? categoryId,
    int? subCategoryId,
    RecurringFrequencyType? frequency,
    int? dayOfMonth,
    DateTime? nextOccurrence,
    bool? active,
  }) {
    return RecurringEntity(
      id: id ?? this.id,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      subCategoryId: subCategoryId ?? this.subCategoryId,
      frequency: frequency ?? this.frequency,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      nextOccurrence: nextOccurrence ?? this.nextOccurrence,
      active: active ?? this.active,
    );
  }
}
