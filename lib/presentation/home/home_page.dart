import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/settings_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../core/di/update_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/sync_service.dart';
import '../budget/budget_providers.dart';
import '../shared_widgets/content_width_limiter.dart';
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
    final syncStatusValue = syncStatus.valueOrNull;

    // Avviso soglia budget (M40): confrontato col mese chiuso dall'utente,
    // per non riproporlo ogni volta che riapre l'app finché resta nello
    // stesso mese (v. _BudgetThresholdBanner).
    final now = DateTime.now();
    final currentMonthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final dismissedMonth = ref.watch(budgetAlertDismissedMonthProvider).valueOrNull;
    final budgetSummaryValue = budgetSummary.valueOrNull;
    final showBudgetAlert = budgetSummaryValue != null &&
        shouldShowBudgetAlert(
          summary: budgetSummaryValue,
          currentMonthKey: currentMonthKey,
          dismissedMonth: dismissedMonth,
        );

    // Avviso "nuova versione disponibile" (M47): un solo controllo per
    // sessione app (v. latestBuildNumberProvider), dismiss per specifico
    // numero di build (v. _UpdateAvailableBanner).
    final latestBuildNumber = ref.watch(latestBuildNumberProvider).valueOrNull;
    final dismissedBuild = ref.watch(updateBannerDismissedBuildProvider).valueOrNull;
    final showUpdateBanner = shouldShowUpdateBanner(
      currentBuildNumber: currentBuildNumber,
      latestBuildNumber: latestBuildNumber,
      dismissedBuildNumber: dismissedBuild,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tally',
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
        child: ContentWidthLimiter(
          // Più larga del default (640): qui dentro, su finestra larga,
          // "Saldo Budget" e "Saldo Reale" stanno affiancate (M27) — serve
          // spazio per due card leggibili una a fianco all'altra, non solo
          // per una colonna singola.
          maxWidth: 760,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (syncStatusValue == SyncStatus.offline || syncStatusValue == SyncStatus.error) ...[
                _SyncAlertBanner(status: syncStatusValue!),
                const SizedBox(height: 12),
              ],
              if (showBudgetAlert) ...[
                _BudgetThresholdBanner(
                  summary: budgetSummaryValue,
                  monthKey: currentMonthKey,
                ),
                const SizedBox(height: 12),
              ],
              if (showUpdateBanner) ...[
                _UpdateAvailableBanner(latestBuildNumber: latestBuildNumber!),
                const SizedBox(height: 12),
              ],
              _BalanceAndBudgetRow(
                balance: summary.when(
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
                budget: budgetSummary.when(
                  data: (value) => BudgetSummaryCard(summary: value),
                  loading: () => const _CardSkeleton(),
                  error: (e, _) => _ErrorTile(message: 'Errore budget: $e'),
                ),
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
            // Disabilitato temporaneamente (2 set 2026, richiesto da
            // Mario): la lettura scontrino non funziona bene al momento.
            // Riabilitare (togliere `enabled: false`/subtitle/onTap: null)
            // quando il problema sarà risolto.
            const ListTile(
              enabled: false,
              leading: Icon(Icons.camera_alt_outlined),
              title: Text('Scansiona scontrino'),
              subtitle: Text('Temporaneamente non disponibile'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Alert ben visibile (non solo la piccola icona in AppBar) quando la sync
/// multi-dispositivo non è attiva: non configurata, o configurata ma in
/// errore persistente. Non compare per gli stati transitori (`syncing`,
/// `synced`).
class _SyncAlertBanner extends StatelessWidget {
  const _SyncAlertBanner({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final isError = status == SyncStatus.error;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: isError ? colorScheme.errorContainer : colorScheme.surfaceContainerHigh,
      child: ListTile(
        leading: Icon(
          isError ? Icons.error_outline : Icons.cloud_off_outlined,
          color: isError ? colorScheme.onErrorContainer : null,
        ),
        title: Text(
          isError ? 'Sincronizzazione non riuscita' : 'Sincronizzazione non configurata',
          style: isError ? TextStyle(color: colorScheme.onErrorContainer) : null,
        ),
        subtitle: Text(
          isError
              ? 'Controlla la connessione o le credenziali Turso.'
              : 'I tuoi dati restano solo su questo dispositivo.',
          style: isError ? TextStyle(color: colorScheme.onErrorContainer) : null,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/settings/sync'),
      ),
    );
  }
}

/// Avviso quando il budget del mese ha raggiunto/superato il 90% (soglia
/// fissa, M40) — un solo banner per "quasi esaurito" e "già sforato", per
/// non moltiplicare gli stati. A differenza di [_SyncAlertBanner] è
/// richiudibile: chiuderlo lo nasconde per il resto del mese corrente
/// (Settings, `budgetAlertDismissedMonthSettingsKey`), riappare da solo al
/// mese successivo o se il budget viene alzato e poi speso di nuovo oltre
/// soglia (il confronto è solo sul mese, non sul valore di usedPct).
class _BudgetThresholdBanner extends ConsumerWidget {
  const _BudgetThresholdBanner({required this.summary, required this.monthKey});

  final HomeBudgetSummary summary;
  final String monthKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final over = summary.isOverBudget;
    final colorScheme = Theme.of(context).colorScheme;
    final bg = over ? colorScheme.errorContainer : AppTheme.warningContainer(context);
    final fg = over ? colorScheme.onErrorContainer : AppTheme.onWarningContainer(context);
    final pct = (summary.usedPct * 100).round();
    return Card(
      color: bg,
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: fg),
        title: Text(
          over ? 'Budget superato' : 'Budget quasi esaurito',
          style: TextStyle(color: fg, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Hai usato il $pct% del budget di questo mese.',
          style: TextStyle(color: fg.withValues(alpha: 0.85)),
        ),
        trailing: IconButton(
          icon: Icon(Icons.close, color: fg),
          tooltip: 'Chiudi per questo mese',
          onPressed: () => ref.read(dismissBudgetAlertProvider)(monthKey),
        ),
        onTap: () => context.go('/budget'),
      ),
    );
  }
}

/// Avviso quando è disponibile una build più recente di quella in
/// esecuzione (M47) — stesso posto/stile del banner soglia budget sopra,
/// ma dismiss per specifico numero di build invece che per mese: se esce
/// una build ancora più recente di quella chiusa, riappare da solo.
class _UpdateAvailableBanner extends ConsumerWidget {
  const _UpdateAvailableBanner({required this.latestBuildNumber});

  final int latestBuildNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = colorScheme.onSecondaryContainer;
    return Card(
      color: colorScheme.secondaryContainer,
      child: ListTile(
        leading: Icon(Icons.system_update_alt, color: fg),
        title: Text(
          'Nuova versione disponibile',
          style: TextStyle(color: fg, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Tocca per scaricare l\'aggiornamento.',
          style: TextStyle(color: fg.withValues(alpha: 0.85)),
        ),
        trailing: IconButton(
          icon: Icon(Icons.close, color: fg),
          tooltip: 'Chiudi per questa versione',
          onPressed: () =>
              ref.read(dismissUpdateBannerProvider)(latestBuildNumber.toString()),
        ),
        onTap: () => _openDownloadLink(context),
      ),
    );
  }

  /// A differenza degli altri banner (che navigano con `go_router`,
  /// sempre riuscito), aprire un URL esterno può fallire (nessun browser
  /// predefinito, permesso mancante) — stessa regola generale del
  /// progetto: un errore risale sempre fino a una snackbar, mai silenzioso.
  Future<void> _openDownloadLink(BuildContext context) async {
    try {
      final launched = await launchUrl(
        Uri.parse(updateDownloadUrl()),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        showErrorSnackBar(context, 'Impossibile aprire il link di download.');
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, 'Impossibile aprire il link di download.');
      }
    }
  }
}

/// "Saldo Budget" e "Saldo Reale" affiancate su finestra larga (era già
/// l'intento del wireframe originale — v. progettazione, sezione 5 —
/// realizzabile solo ora che c'è spazio orizzontale per farlo, M27),
/// impilate come oggi sotto la soglia (Android, o Windows ridotta).
class _BalanceAndBudgetRow extends StatelessWidget {
  const _BalanceAndBudgetRow({required this.balance, required this.budget});

  final Widget balance;
  final Widget budget;

  @override
  Widget build(BuildContext context) {
    if (!isWideWindow(context)) {
      return Column(
        children: [
          balance,
          const SizedBox(height: 12),
          budget,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: balance),
        const SizedBox(width: 12),
        Expanded(child: budget),
      ],
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
