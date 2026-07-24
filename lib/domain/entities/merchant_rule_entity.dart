/// Regola di classificazione automatica: un pattern (regex) che, se trovato
/// nel testo di uno scontrino, propone una categoria/sottocategoria.
///
/// Oggetto di dominio, indipendente da Drift/Flutter.
class MerchantRuleEntity {
  final int? id;

  /// Espressione regolare applicata (case-insensitive) al testo dello
  /// scontrino, es. `ESSEL.*`.
  final String pattern;

  final int categoryId;
  final int? subCategoryId;

  /// Priorità di match: a parità di testo, vince la regola con priorità più
  /// alta.
  final int priority;

  /// true se creata manualmente dall'utente; false se generata dal flusso di
  /// apprendimento (negozio sconosciuto → scelta categoria una tantum).
  final bool isUserDefined;

  const MerchantRuleEntity({
    this.id,
    required this.pattern,
    required this.categoryId,
    this.subCategoryId,
    this.priority = 0,
    this.isUserDefined = true,
  });

  MerchantRuleEntity copyWith({
    int? id,
    String? pattern,
    int? categoryId,
    int? subCategoryId,
    int? priority,
    bool? isUserDefined,
  }) {
    return MerchantRuleEntity(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      categoryId: categoryId ?? this.categoryId,
      subCategoryId: subCategoryId ?? this.subCategoryId,
      priority: priority ?? this.priority,
      isUserDefined: isUserDefined ?? this.isUserDefined,
    );
  }
}
