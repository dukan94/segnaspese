import '../../entities/merchant_rule_entity.dart';
import '../../repositories/merchant_rule_repository.dart';

/// Crea una nuova regola di classificazione. Ritorna l'id generato.
class AddMerchantRule {
  AddMerchantRule(this._repository);

  final MerchantRuleRepository _repository;

  Future<int> call(MerchantRuleEntity rule) => _repository.addRule(rule);
}
