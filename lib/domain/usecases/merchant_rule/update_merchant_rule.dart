import '../../entities/merchant_rule_entity.dart';
import '../../repositories/merchant_rule_repository.dart';

/// Aggiorna una regola di classificazione esistente.
class UpdateMerchantRule {
  UpdateMerchantRule(this._repository);

  final MerchantRuleRepository _repository;

  Future<void> call(MerchantRuleEntity rule) => _repository.updateRule(rule);
}
