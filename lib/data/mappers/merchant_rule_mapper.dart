import 'package:drift/drift.dart';

import '../../domain/entities/merchant_rule_entity.dart';
import '../local/database/app_database.dart';

/// Conversioni tra la riga Drift [MerchantRule]/[MerchantRulesCompanion] e
/// l'entità di dominio [MerchantRuleEntity].
extension MerchantRuleDataMapper on MerchantRule {
  MerchantRuleEntity toEntity() {
    return MerchantRuleEntity(
      id: id,
      pattern: pattern,
      categoryId: categoryId,
      subCategoryId: subCategoryId,
      priority: priority,
      isUserDefined: isUserDefined,
    );
  }
}

extension MerchantRuleEntityMapper on MerchantRuleEntity {
  MerchantRulesCompanion toInsertCompanion() {
    return MerchantRulesCompanion.insert(
      pattern: pattern,
      categoryId: categoryId,
      subCategoryId: Value(subCategoryId),
      priority: Value(priority),
      isUserDefined: Value(isUserDefined),
      updatedAt: Value(DateTime.now()),
    );
  }

  MerchantRulesCompanion toUpdateCompanion() {
    assert(id != null, 'id richiesto per aggiornare una regola esistente');
    return MerchantRulesCompanion(
      id: Value(id!),
      pattern: Value(pattern),
      categoryId: Value(categoryId),
      subCategoryId: Value(subCategoryId),
      priority: Value(priority),
      isUserDefined: Value(isUserDefined),
      updatedAt: Value(DateTime.now()),
    );
  }
}
