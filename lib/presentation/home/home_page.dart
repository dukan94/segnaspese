import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/sync_providers.dart';
import '../../data/services/sync_service.dart';
import '../budget/budget_providers.dart';
import 'home_providers.dart';
import 'widgets/balance_card.dart';
import 'widgets/budget_summary_card.dart';
import 'widgets/monthly_stats_row.dart';
import 'widgets/recent_transactions_list.dart';

/// Home dell'app: saldo del mese in evidenza (con il saldo dell'anno corrente
/// meno enfatizzato accanto), entrate/uscite del mese, ultime operazioni e
/// FAB "Nuova Operazione" (v. wireframe progettazione, Milestone M1).
///
/// Il "Saldo Budget" e la % di budget utilizzato del wireframe originale
/// arrivano con il modulo Budget (Milestone M2).
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(monthlySummaryProvider);
    final yearlyBalance = ref.watch(yearlyBalanceProvider);
    final recent = ref.watch(recentTransactionsProvider);
    final budgetSummary = ref.watch(homeBudgetSummaryProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Benvenuto sulla tua App SegnaSpese',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings/sync'),
            icon: Icon(_syncIcon(syncStatus)),
            tooltip: 'Sync multi-dispositivo',
          ),
          IconButton(
            onPressed: () => context.push('/history'),
            icon: const Icon(Icons.search),
            tooltip: 'Cerca nello storico',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allTransactionsProvider);
          ref.invalidate(currentMonthTransactionsProvider);
          ref.invalidate(currentYearTransactionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            summary.when(
              data: (monthly) => yearlyBalance.when(
                data: (yearly) => BalanceCard(
                  monthlyBalance: monthly.balance,
                  yearlyBalance: yearly,
                ),
                loading: () => const _CardSkeleton(),
                error: (e, _) => _ErrorTile(message: 'Errore saldo: $e'),
              ),
              loading: () => const _CardSkeleton(),
              error: (e, _) => _ErrorTile(message: 'Errore saldo: $e'),
            ),
            const SizedBox(height: 12),
            budgetSummary.when(
              data: (value) => BudgetSummaryCard(summary: value),
              loading: () => const _CardSkeleton(),
              error: (e, _) => _ErrorTile(message: 'Errore budget: $e'),
            ),
            const SizedBox(height: 12),
            summary.when(
              data: (value) => MonthlyStatsRow(summary: value),
              loading: () => const _CardSkeleton(),
              error: (e, _) => _ErrorTile(message: 'Errore statistiche: $e'),
            ),
            const SizedBox(height: 24),
            Text('Ultime operazioni',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            recent.when(
              data: (value) => RecentTransactionsList(transactions: value),
              loading: () => const _CardSkeleton(),
              error: (e, _) => _ErrorTile(message: 'Errore operazioni: $e'),
            ),
            // Spazio extra così il FAB non copre l'ultima card.
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openNewTransactionSheet(context),
        tooltip: 'Nuova operazione',
        child: const Icon(Icons.add),
      ),
    );
  }

  IconData _syncIcon(AsyncValue<SyncStatus> status) {
    return status.when(
      data: (s) => switch (s) {
        SyncStatus.offline => Icons.cloud_off_outlined,
        SyncStatus.syncing => Icons.sync,
        SyncStatus.synced => Icons.cloud_done_outlined,
        SyncStatus.error => Icons.error_outline,
      },
      loading: () => Icons.cloud_outlined,
      error: (_, __) => Icons.error_outline,
    );
  }

  void _openNewTransactionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Inserimento manuale'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/home/add-transaction');
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Scansiona scontrino'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/home/scan-receipt');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 64,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message),
      ),
    );
  }
}
