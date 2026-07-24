import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/merchant_rules_table.dart';

part 'merchant_rule_dao.g.dart';

/// Accesso ai dati grezzi delle regole di classificazione ([MerchantRules]).
/// La conversione verso [MerchantRuleEntity] avviene nel mapper.
@DriftAccessor(tables: [MerchantRules])
class MerchantRuleDao extends DatabaseAccessor<AppDatabase>
    with _$MerchantRuleDaoMixin {
  MerchantRuleDao(super.db);

  /// Tutte le regole non cancellate, per priorità decrescente (poi per id
  /// crescente a parità di priorità, per un ordine stabile).
  Stream<List<MerchantRule>> watchAll() {
    final query = select(merchantRules)
      ..where((r) => r.isDeleted.equals(false))
      ..orderBy([
        (r) => OrderingTerm.desc(r.priority),
        (r) => OrderingTerm.asc(r.id),
      ]);
    return query.watch();
  }

  /// Tutte le regole non cancellate (lettura una tantum), stesso ordinamento.
  Future<List<MerchantRule>> getAll() {
    final query = select(merchantRules)
      ..where((r) => r.isDeleted.equals(false))
      ..orderBy([
        (r) => OrderingTerm.desc(r.priority),
        (r) => OrderingTerm.asc(r.id),
      ]);
    return query.get();
  }

  Future<int> insertRule(MerchantRulesCompanion entry) {
    return into(merchantRules).insert(entry);
  }

  Future<bool> updateRule(MerchantRulesCompanion entry) {
    return update(merchantRules).replace(entry);
  }

  Future<int> softDelete(int id) {
    return (update(merchantRules)..where((r) => r.id.equals(id))).write(
      MerchantRulesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
