import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/category_providers.dart';
import '../../core/di/google_sheets_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../data/local/database/app_database.dart';
import '../../data/services/google_sheets_service.dart';
import '../../domain/entities/transaction_entity.dart';
import '../home/home_providers.dart';

enum _SheetsTestStatus { unknown, testing, valid, invalid }

/// Strumenti interni, fuori dal flusso normale di Impostazioni: import CSV
/// (v. memoria "project-csv-import-dev-only" — solo per sviluppo/backfill,
/// non il vero import da estratto conto) e il bridge temporaneo verso il
/// foglio Google "Copia di Spese" (v. CLAUDE.md), disattivabile da qui.
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  final _credentialsController = TextEditingController();
  final _spreadsheetController = TextEditingController();
  final _sheetNameController = TextEditingController();
  bool _fieldsLoaded = false;
  bool _busy = false;
  bool _alreadyConfigured = false;
  _SheetsTestStatus _testStatus = _SheetsTestStatus.unknown;

  final _deleteSearchController = TextEditingController();
  String _deleteQuery = '';
  bool _purgeBusy = false;
  int? _hardDeletingId;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final configured =
        await ref.read(googleSheetsCredentialsStoreProvider).isConfigured();
    if (!mounted) return;
    setState(() => _alreadyConfigured = configured);
  }

  void _fillFieldsOnce(String spreadsheetId, String sheetName) {
    if (_fieldsLoaded) return;
    _fieldsLoaded = true;
    _spreadsheetController.text = spreadsheetId;
    _sheetNameController.text = sheetName;
  }

  @override
  void dispose() {
    _credentialsController.dispose();
    _spreadsheetController.dispose();
    _sheetNameController.dispose();
    _deleteSearchController.dispose();
    super.dispose();
  }

  /// Se la sync Turso è configurata, la esegue prima di un'eliminazione
  /// definitiva: propaga il tombstone (soft delete) al server remoto, così
  /// la riga non ricompare da un altro dispositivo alla sync successiva.
  Future<void> _syncBeforeHardDelete() async {
    final syncService = ref.read(syncServiceProvider);
    if (await syncService.isConfigured()) {
      await syncService.syncNow();
    }
  }

  Future<void> _confirmAndPurge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pulisci database'),
        content: const Text(
          'Elimina per sempre tutte le transazioni già cancellate '
          '(operazione irreversibile). Se la sync Turso è configurata, '
          'viene eseguita prima, per evitare che ricompaiano da un altro '
          'dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Elimina per sempre'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _purgeBusy = true);
    try {
      await _syncBeforeHardDelete();
      final count = await ref.read(purgeDeletedTransactionsProvider)();
      if (!mounted) return;
      showSuccessSnackBar(context, 'Eliminate per sempre $count transazioni');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Errore durante la pulizia: $e');
    } finally {
      if (mounted) setState(() => _purgeBusy = false);
    }
  }

  Future<void> _confirmAndHardDelete(TransactionEntity tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina definitivamente'),
        content: Text(
          '${tx.note?.isNotEmpty == true ? tx.note : 'Senza nota'} · '
          '${AppFormatters.signedCurrency(tx.signedAmount)} · '
          '${AppFormatters.shortDate(tx.date)}\n\n'
          'Operazione irreversibile: non finisce nel cestino, sparisce del '
          'tutto. Se la sync Turso è configurata, viene eseguita prima.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Elimina per sempre'),
          ),
        ],
      ),
    );
    if (confirmed != true || tx.id == null || !mounted) return;

    setState(() => _hardDeletingId = tx.id);
    try {
      await ref.read(deleteTransactionProvider).call(tx.id!);
      await _syncBeforeHardDelete();
      await ref.read(hardDeleteTransactionProvider)(tx.id!);
      if (!mounted) return;
      showSuccessSnackBar(context, 'Transazione eliminata per sempre');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Errore durante l\'eliminazione: $e');
    } finally {
      if (mounted) setState(() => _hardDeletingId = null);
    }
  }

  List<TransactionEntity> _filterForDelete(
    List<TransactionEntity> all,
    Map<int, Category> catById,
  ) {
    if (_deleteQuery.isEmpty) return const [];
    return all.where((t) {
      final cat = catById[t.categoryId]?.name ?? '';
      final haystack = [
        t.note ?? '',
        cat,
        AppFormatters.shortDate(t.date),
        t.amount.toStringAsFixed(2),
        t.amount.toStringAsFixed(2).replaceAll('.', ','),
      ].join(' ').toLowerCase();
      return haystack.contains(_deleteQuery);
    }).toList();
  }

  Future<void> _save() async {
    final credentials = _credentialsController.text.trim();
    final spreadsheetInput = _spreadsheetController.text.trim();
    final sheetName = _sheetNameController.text.trim();

    if (credentials.isEmpty && !_alreadyConfigured) {
      showErrorSnackBar(context, 'Incolla la chiave JSON del service account');
      return;
    }
    if (spreadsheetInput.isEmpty) {
      showErrorSnackBar(context, 'Inserisci l\'URL o l\'id del foglio Google');
      return;
    }
    if (sheetName.isEmpty) {
      showErrorSnackBar(context, 'Inserisci il nome del tab');
      return;
    }

    setState(() => _busy = true);
    try {
      if (credentials.isNotEmpty) {
        await ref.read(googleSheetsCredentialsStoreProvider).write(credentials);
      }
      final spreadsheetId =
          GoogleSheetsService.extractSpreadsheetId(spreadsheetInput);
      await ref.read(setGoogleSheetsSpreadsheetIdProvider)(spreadsheetId);
      await ref.read(setGoogleSheetsSheetNameProvider)(sheetName);
      if (!mounted) return;
      setState(() => _alreadyConfigured = true);
      showSuccessSnackBar(context, 'Configurazione salvata');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Errore durante il salvataggio: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() async {
    var credentials = _credentialsController.text.trim();
    if (credentials.isEmpty) {
      credentials =
          await ref.read(googleSheetsCredentialsStoreProvider).read() ?? '';
    }
    final spreadsheetInput = _spreadsheetController.text.trim();
    final sheetName = _sheetNameController.text.trim();
    if (!mounted) return;
    if (credentials.isEmpty || spreadsheetInput.isEmpty || sheetName.isEmpty) {
      showErrorSnackBar(context, 'Compila prima tutti i campi');
      return;
    }

    setState(() => _testStatus = _SheetsTestStatus.testing);
    try {
      await ref.read(googleSheetsServiceProvider).testConnection(
            serviceAccountJson: credentials,
            spreadsheetId:
                GoogleSheetsService.extractSpreadsheetId(spreadsheetInput),
            sheetName: sheetName,
          );
      if (!mounted) return;
      setState(() => _testStatus = _SheetsTestStatus.valid);
      showSuccessSnackBar(context, 'Connessione riuscita');
    } catch (e) {
      if (!mounted) return;
      setState(() => _testStatus = _SheetsTestStatus.invalid);
      showErrorSnackBar(context, 'Connessione fallita: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabledAsync = ref.watch(googleSheetsEnabledProvider);
    final enabled = enabledAsync.valueOrNull ?? false;
    final spreadsheetIdAsync = ref.watch(googleSheetsSpreadsheetIdProvider);
    final sheetNameAsync = ref.watch(googleSheetsSheetNameProvider);
    if (spreadsheetIdAsync.hasValue && sheetNameAsync.hasValue) {
      _fillFieldsOnce(spreadsheetIdAsync.value!, sheetNameAsync.value!);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Strumenti interni', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Importa operazioni da CSV'),
              subtitle: const Text('Solo sviluppo/backfill, non il vero import da estratto conto'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/import'),
            ),
          ),
          const SizedBox(height: 24),
          Text('Google Sheet spese (temporaneo)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Finché l\'app non è completa e testata al 100%, ogni entrata/uscita '
            'salvata può essere copiata anche sul foglio Google usato finora, '
            'seguendo lo stesso schema di colonne. Da disattivare qui quando non '
            'serve più.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Bridge attivo'),
              subtitle: Text(_alreadyConfigured
                  ? 'Configurato'
                  : 'Configura prima le credenziali qui sotto'),
              value: enabled && _alreadyConfigured,
              onChanged: !_alreadyConfigured
                  ? null
                  : (value) => ref.read(setGoogleSheetsEnabledProvider)(value),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _credentialsController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Chiave JSON del service account',
              hintText: _alreadyConfigured
                  ? 'Già configurata — lascia vuoto per non cambiarla'
                  : '{ "type": "service_account", ... }',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _spreadsheetController,
            decoration: const InputDecoration(
              labelText: 'URL o id del foglio Google',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sheetNameController,
            decoration: const InputDecoration(
              labelText: 'Nome del tab',
              hintText: googleSheetsSheetNameDefault,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salva'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _testStatus == _SheetsTestStatus.testing
                ? null
                : _testConnection,
            icon: _testStatus == _SheetsTestStatus.testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_outlined),
            label: const Text('Testa connessione'),
          ),
          if (_testStatus == _SheetsTestStatus.valid ||
              _testStatus == _SheetsTestStatus.invalid) ...[
            const SizedBox(height: 12),
            Card(
              color: _testStatus == _SheetsTestStatus.valid
                  ? theme.colorScheme.surfaceContainerHigh
                  : theme.colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(
                  _testStatus == _SheetsTestStatus.valid
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                ),
                title: Text(
                  _testStatus == _SheetsTestStatus.valid
                      ? 'Foglio raggiungibile'
                      : 'Connessione fallita',
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Manutenzione dati', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Il database elimina di norma solo "a metà" (soft delete): serve '
            'per propagare le cancellazioni alla sync. Qui invece elimini '
            'per sempre, senza possibilità di recupero.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
            onPressed: _purgeBusy ? null : _confirmAndPurge,
            icon: _purgeBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined),
            label: const Text('Pulisci database'),
          ),
          const SizedBox(height: 20),
          Text('Elimina definitivamente una transazione',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _deleteSearchController,
            decoration: InputDecoration(
              hintText: 'Cerca per nota, categoria, importo, data...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _deleteQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _deleteSearchController.clear();
                        setState(() => _deleteQuery = '');
                      },
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) =>
                setState(() => _deleteQuery = v.trim().toLowerCase()),
          ),
          if (_deleteQuery.isNotEmpty)
            Consumer(
              builder: (context, ref, _) {
                final txAsync = ref.watch(allTransactionsProvider);
                final categories =
                    ref.watch(allCategoriesProvider).valueOrNull ?? const [];
                final catById = {for (final c in categories) c.id: c};
                return txAsync.when(
                  data: (all) {
                    final results = _filterForDelete(all, catById);
                    if (results.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('Nessun risultato'),
                      );
                    }
                    return Column(
                      children: [
                        for (final tx in results)
                          Card(
                            margin: const EdgeInsets.only(top: 8),
                            child: ListTile(
                              title: Text(tx.note?.isNotEmpty == true
                                  ? tx.note!
                                  : (catById[tx.categoryId]?.name ??
                                      'Senza categoria')),
                              subtitle: Text(
                                '${AppFormatters.signedCurrency(tx.signedAmount)} · '
                                '${AppFormatters.shortDate(tx.date)}',
                              ),
                              trailing: _hardDeletingId == tx.id
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : IconButton(
                                      icon: Icon(Icons.delete_forever_outlined,
                                          color: theme.colorScheme.error),
                                      tooltip: 'Elimina per sempre',
                                      onPressed: () =>
                                          _confirmAndHardDelete(tx),
                                    ),
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Errore: $e'),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
