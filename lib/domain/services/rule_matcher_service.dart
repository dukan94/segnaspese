import '../entities/merchant_rule_entity.dart';

/// Applica le regole di classificazione al testo di uno scontrino.
///
/// Logica pura (nessuna dipendenza da Drift/Flutter), quindi facilmente
/// testabile. Le regole vengono valutate in ordine di priorità decrescente;
/// la prima il cui pattern (regex, case-insensitive) trova riscontro nel
/// testo vince. Un pattern non valido viene ignorato senza far fallire il
/// matching complessivo.
class RuleMatcherService {
  const RuleMatcherService();

  MerchantRuleEntity? match(String text, List<MerchantRuleEntity> rules) {
    if (text.trim().isEmpty) return null;

    final sorted = [...rules]
      ..sort((a, b) => b.priority.compareTo(a.priority));

    for (final rule in sorted) {
      if (_matches(rule.pattern, text)) return rule;
    }
    return null;
  }

  bool _matches(String pattern, String text) {
    if (pattern.trim().isEmpty) return false;
    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(text);
    } on FormatException {
      // Pattern regex non valido: lo ignoriamo (l'utente può correggerlo
      // dalla schermata regole).
      return false;
    }
  }
}
