import '../entities/merchant_rule_entity.dart';

/// Contratto per l'accesso alle regole di classificazione scontrini.
abstract class MerchantRuleRepository {
  /// Regole non cancellate, per priorità decrescente.
  Stream<List<MerchantRuleEntity>> watchAll();

  /// Lettura una tantum (usata dal matcher al momento della scansione).
  Future<List<MerchantRuleEntity>> getAll();

  Future<int> addRule(MerchantRuleEntity rule);

  Future<void> updateRule(MerchantRuleEntity rule);

  Future<void> deleteRule(int id);
}
