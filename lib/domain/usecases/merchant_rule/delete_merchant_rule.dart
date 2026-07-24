import '../../repositories/merchant_rule_repository.dart';

/// Soft delete di una regola di classificazione.
class DeleteMerchantRule {
  DeleteMerchantRule(this._repository);

  final MerchantRuleRepository _repository;

  Future<void> call(int id) => _repository.deleteRule(id);
}
