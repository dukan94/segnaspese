import '../../domain/entities/merchant_rule_entity.dart';
import '../../domain/repositories/merchant_rule_repository.dart';
import '../local/database/daos/merchant_rule_dao.dart';
import '../mappers/merchant_rule_mapper.dart';

/// Implementazione Drift di [MerchantRuleRepository].
class MerchantRuleRepositoryImpl implements MerchantRuleRepository {
  MerchantRuleRepositoryImpl(this._dao);

  final MerchantRuleDao _dao;

  @override
  Stream<List<MerchantRuleEntity>> watchAll() {
    return _dao
        .watchAll()
        .map((rows) => rows.map((row) => row.toEntity()).toList());
  }

  @override
  Future<List<MerchantRuleEntity>> getAll() async {
    final rows = await _dao.getAll();
    return rows.map((row) => row.toEntity()).toList();
  }

  @override
  Future<int> addRule(MerchantRuleEntity rule) {
    return _dao.insertRule(rule.toInsertCompanion());
  }

  @override
  Future<void> updateRule(MerchantRuleEntity rule) async {
    await _dao.updateRule(rule.toUpdateCompanion());
  }

  @override
  Future<void> deleteRule(int id) async {
    await _dao.softDelete(id);
  }
}
