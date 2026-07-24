import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/daos/merchant_rule_dao.dart';
import '../../data/repositories_impl/merchant_rule_repository_impl.dart';
import '../../domain/entities/merchant_rule_entity.dart';
import '../../domain/repositories/merchant_rule_repository.dart';
import '../../domain/services/receipt_parser_service.dart';
import '../../domain/services/rule_matcher_service.dart';
import '../../domain/usecases/merchant_rule/add_merchant_rule.dart';
import '../../domain/usecases/merchant_rule/delete_merchant_rule.dart';
import '../../domain/usecases/merchant_rule/update_merchant_rule.dart';
import 'database_provider.dart';

final merchantRuleDaoProvider = Provider<MerchantRuleDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.merchantRuleDao;
});

final merchantRuleRepositoryProvider = Provider<MerchantRuleRepository>((ref) {
  return MerchantRuleRepositoryImpl(ref.watch(merchantRuleDaoProvider));
});

/// Tutte le regole non cancellate, per priorità decrescente.
final merchantRulesProvider =
    StreamProvider<List<MerchantRuleEntity>>((ref) {
  return ref.watch(merchantRuleRepositoryProvider).watchAll();
});

// --- Usecase ---

final addMerchantRuleProvider = Provider<AddMerchantRule>((ref) {
  return AddMerchantRule(ref.watch(merchantRuleRepositoryProvider));
});

final updateMerchantRuleProvider = Provider<UpdateMerchantRule>((ref) {
  return UpdateMerchantRule(ref.watch(merchantRuleRepositoryProvider));
});

final deleteMerchantRuleProvider = Provider<DeleteMerchantRule>((ref) {
  return DeleteMerchantRule(ref.watch(merchantRuleRepositoryProvider));
});

// --- Servizi puri (stateless, condivisibili come singleton) ---

final ruleMatcherServiceProvider = Provider<RuleMatcherService>((ref) {
  return const RuleMatcherService();
});

final receiptParserServiceProvider = Provider<ReceiptParserService>((ref) {
  return const ReceiptParserService();
});
