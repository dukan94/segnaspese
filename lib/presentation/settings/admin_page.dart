import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/admin_pin_providers.dart';
import '../../core/di/category_providers.dart';
import '../../core/di/database_backup_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/categories_table.dart';
import '../../domain/entities/transaction_entity.dart';
import '../home/home_providers.dart';
import '../shared_widgets/content_width_limiter.dart';
import '../shared_widgets/section_divider.dart';

enum _PinAction { change, remove }

/// Strumenti interni, fuori dal flusso normale di Impostazioni: import CSV
/// (solo per sviluppo/backfill, non il vero import da estratto conto), il
/// backup completo del database e gli strumenti di eliminazione definitiva.
/// Protetta da PIN locale al dispositivo (M48): questo widget presuppone
/// che il gate sia già stato superato, v. `admin_pin_gate.dart` (l'unico
/// punto da cui questa pagina viene raggiunta nel router).
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  bool _backupBusy = false;

  final _deleteSearchController = TextEditingController();
  String _deleteQuery = '';
  bool _purgeBusy = false;
  int? _hardDeletingId;

  @override
  void dispose() {
    _deleteSearchController.dispose();
    super.dispose();
  }

  /// true se una cancellazione definitiva (singola o pulizia bulk) è già in
  /// corso: usato per disabilitare TUTTI i pulsanti distruttivi mentre una è
  /// in volo, non solo quello premuto (semplice cortesia per l'utente — la
  /// sicurezza vera contro le sovrapposizioni è la verifica sul server fatta
  /// da [SafeTransactionDeletionService], non questo flag).
  bool get _destructiveOpInProgress => _purgeBusy || _hardDeletingId != null;

  Future<void> _confirmAndPurge() async {
    if (_destructiveOpInProgress) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pulisci database'),
        content: const Text(
          'Elimina per sempre tutte le transazioni già cancellate, ma solo '
          'quelle di cui il server conferma la cancellazione (se la sync '
          'Turso è configurata) — le altre restano nascoste per ora. '
          'Operazione irreversibile.',
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
      final outcome = await ref
          .read(safeTransactionDeletionServiceProvider)
          .purgeSoftDeletedTransactions();
      if (!mounted) return;
      final message = outcome.skippedCount == 0
          ? 'Eliminate per sempre ${outcome.purgedCount} transazioni'
          : 'Eliminate per sempre ${outcome.purgedCount} transazioni — '
              '${outcome.skippedCount} non ancora confermate dal server, '
              'riprova più tardi';
      showSuccessSnackBar(context, message);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Errore durante la pulizia: $e');
    } finally {
      if (mounted) setState(() => _purgeBusy = false);
    }
  }

  Future<void> _confirmAndHardDelete(TransactionEntity tx) async {
    if (_destructiveOpInProgress) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina definitivamente'),
        content: Text(
          '${tx.note?.isNotEmpty == true ? tx.note : 'Senza nota'} · '
          '${AppFormatters.signedCurrency(tx.signedAmount)} · '
          '${AppFormatters.shortDate(tx.date)}\n\n'
          'Operazione irreversibile: non finisce nel cestino, sparisce del '
          'tutto, ma solo dopo conferma del server (se la sync Turso è '
          'configurata).',
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
      final outcome = await ref
          .read(safeTransactionDeletionServiceProvider)
          .hardDeleteTransaction(tx.id!);
      if (!mounted) return;
      if (outcome.deleted) {
        showSuccessSnackBar(context, 'Transazione eliminata per sempre');
      } else {
        // A questo punto la transazione è già stata rimossa dalle liste (il
        // soft delete iniziale è andato a buon fine): il messaggio non deve
        // suggerire che l'operazione sia fallita del tutto.
        showErrorSnackBar(
            context, outcome.reason ?? 'Non eliminata definitivamente');
      }
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        'La transazione non è più visibile (cancellata) ma non è stata '
        'eliminata definitivamente (errore: $e). Usa "Pulisci database" '
        'più tardi per completare la pulizia.',
      );
    } finally {
      if (mounted) setState(() => _hardDeletingId = null);
    }
  }

  List<TransactionEntity> _filterForDelete(
    List<TransactionEntity> all,
    Map<int, Category> catById,
    Map<int, String> subNameById,
  ) {
    if (_deleteQuery.isEmpty) return const [];
    return all.where((t) {
      final cat = catById[t.categoryId]?.name ?? '';
      final subCat =
          t.subCategoryId != null ? (subNameById[t.subCategoryId] ?? '') : '';
      final haystack = [
        t.note ?? '',
        cat,
        subCat,
        AppFormatters.shortDate(t.date),
        t.amount.toStringAsFixed(2),
        t.amount.toStringAsFixed(2).replaceAll('.', ','),
      ].join(' ').toLowerCase();
      return haystack.contains(_deleteQuery);
    }).toList();
  }

  /// Backup completo del database (M43): stesso pattern di salvataggio file
  /// già usato dall'export CSV (`export_page.dart`) — su mobile il plugin
  /// scrive già il file dai byte passati, su desktop `saveFile` restituisce
  /// solo il percorso scelto e tocca a noi scrivere.
  Future<void> _exportBackup() async {
    setState(() => _backupBusy = true);
    try {
      final service = ref.read(databaseBackupServiceProvider);
      final bytes = await service.readDatabaseBytes();
      final fileName = service.suggestedFileName(DateTime.now());

      final uri = await FilePicker.saveFile(
        dialogTitle: 'Salva backup completo',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['sqlite'],
        bytes: bytes,
      );

      if (!mounted) return;
      if (uri == null) {
        setState(() => _backupBusy = false); // annullato dall'utente
        return;
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(uri.toFilePath()).writeAsBytes(bytes, flush: true);
      }

      if (!mounted) return;
      setState(() => _backupBusy = false);
      showSuccessSnackBar(context, 'Backup esportato');
    } catch (e) {
      if (!mounted) return;
      setState(() => _backupBusy = false);
      showErrorSnackBar(context, 'Errore durante l\'esportazione del backup: $e');
    }
  }

  /// Menu "Cambia PIN"/"Rimuovi PIN" (M48) — l'unica azione di gestione del
  /// gate raggiungibile da dentro Admin, una volta già sbloccato.
  Future<void> _showPinSettings() async {
    final choice = await showDialog<_PinAction>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('PIN Admin'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_PinAction.change),
            child: const Text('Cambia PIN'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_PinAction.remove),
            child: const Text('Rimuovi PIN'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _PinAction.change) {
      await _showChangePinDialog();
    } else {
      await _confirmAndRemovePin();
    }
  }

  Future<void> _showChangePinDialog() async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cambia PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinController,
                obscureText: true,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(adminPinMaxLength),
                ],
                decoration: const InputDecoration(labelText: 'Nuovo PIN'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(adminPinMaxLength),
                ],
                decoration: const InputDecoration(labelText: 'Conferma PIN'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                if (pinController.text.length < adminPinMinLength) {
                  setDialogState(() =>
                      error = 'Il PIN deve avere almeno $adminPinMinLength cifre');
                  return;
                }
                if (pinController.text != confirmController.text) {
                  setDialogState(
                      () => error = 'I due PIN inseriti non coincidono');
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(adminPinStoreProvider).setPin(pinController.text);
    if (!mounted) return;
    showSuccessSnackBar(context, 'PIN aggiornato');
  }

  Future<void> _confirmAndRemovePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovi PIN'),
        content: const Text(
          'Chiunque avrà accesso a questo dispositivo potrà aprire Admin '
          'senza restrizioni. Continuare?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(adminPinStoreProvider).clear();
    if (!mounted) return;
    showSuccessSnackBar(context, 'PIN rimosso');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(
            onPressed: _showPinSettings,
            icon: const Icon(Icons.password_outlined),
            tooltip: 'Cambia/rimuovi PIN',
          ),
        ],
      ),
      body: ContentWidthLimiter(
        // Più larga del default (640): la ricerca transazioni in fondo ha
        // righe piuttosto dense (importo, data, azione di eliminazione).
        maxWidth: 900,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Import CSV', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Importa operazioni da CSV'),
                subtitle: const Text(
                    'Solo sviluppo/backfill, non il vero import da estratto conto'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/import'),
              ),
            ),
            const SectionDivider(),
            Text('Backup completo', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Salva una copia dell\'intero database locale in un file, così '
              'non serve più uno script improvvisato prima di un\'operazione '
              'rischiosa. Nessuna cifratura: contiene tutti i tuoi dati, tienilo '
              'al sicuro.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _backupBusy ? null : _exportBackup,
              icon: _backupBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt_outlined),
              label: Text(
                  _backupBusy ? 'Esportazione...' : 'Esporta backup completo'),
            ),
            const SectionDivider(),
            Text('Gestione transazioni', style: theme.textTheme.titleMedium),
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
              onPressed: _destructiveOpInProgress ? null : _confirmAndPurge,
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
                hintText:
                    'Cerca per nota, categoria, sottocategoria, importo, data...',
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
                  final expenseSubs = ref
                          .watch(subCategoriesForTypeProvider(
                              TransactionKind.expense))
                          .valueOrNull ??
                      const [];
                  final incomeSubs = ref
                          .watch(subCategoriesForTypeProvider(
                              TransactionKind.income))
                          .valueOrNull ??
                      const [];
                  final subNameById = {
                    for (final s in [...expenseSubs, ...incomeSubs])
                      s.subCategory.id: s.subCategory.name,
                  };
                  return txAsync.when(
                    data: (all) {
                      final results =
                          _filterForDelete(all, catById, subNameById);
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
                                        icon: Icon(
                                            Icons.delete_forever_outlined,
                                            color: _destructiveOpInProgress
                                                ? theme.disabledColor
                                                : theme.colorScheme.error),
                                        tooltip: 'Elimina per sempre',
                                        onPressed: _destructiveOpInProgress
                                            ? null
                                            : () => _confirmAndHardDelete(tx),
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
      ),
    );
  }
}
