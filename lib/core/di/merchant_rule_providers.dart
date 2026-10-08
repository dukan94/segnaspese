import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'sync_providers.dart';

/// Logga un fallimento della sync scatenata dopo un salvataggio (M58) —
/// stesso pattern fire-and-forget di `transaction_providers.dart` (M32),
/// mai mostrato all'utente.
void _logPostSaveSyncError(Object error, StackTrace stackTrace) {
  debugPrint('Sync Turso fallita (dopo salvataggio regola): $error\n$stackTrace');
}

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

/// M58: dopo il salvataggio locale lancia anche una sync Turso in
/// background — stesso trattamento di transazioni (M32) e budget (M56),
/// mancante qui da sempre.
final addMerchantRuleProvider =
    Provider<Future<int> Function(MerchantRuleEntity)>((ref) {
  final useCase = AddMerchantRule(ref.watch(merchantRuleRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (rule) async {
    final id = await useCase.call(rule);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
    return id;
  };
});

/// M58: v. [addMerchantRuleProvider].
final updateMerchantRuleProvider =
    Provider<Future<void> Function(MerchantRuleEntity)>((ref) {
  final useCase = UpdateMerchantRule(ref.watch(merchantRuleRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (rule) async {
    await useCase.call(rule);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// M58: v. [addMerchantRuleProvider].
final deleteMerchantRuleProvider = Provider<Future<void> Function(int)>((ref) {
  final useCase = DeleteMerchantRule(ref.watch(merchantRuleRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (id) async {
    await useCase.call(id);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

// --- Servizi puri (stateless, condivisibili come singleton) ---

final ruleMatcherServiceProvider = Provider<RuleMatcherService>((ref) {
  return const RuleMatcherService();
});

final receiptParserServiceProvider = Provider<ReceiptParserService>((ref) {
  return const ReceiptParserService();
});
