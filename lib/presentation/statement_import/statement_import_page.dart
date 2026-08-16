import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/merchant_rule_providers.dart';
import '../../core/di/statement_import_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/parsed_statement_row.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/services/bank_statement_parser.dart';
import '../transaction/add_transaction_page.dart';
import '../transaction/widgets/category_picker.dart';

/// Import di un estratto conto bancario (Excel), un parser per banca (v.
/// `core/di/statement_import_providers.dart`). A differenza dell'import CSV
/// di backfill (Impostazioni > Admin), qui ogni riga viene proposta con una
/// categoria (dedotta da `RuleMatcherService`, le stesse regole usate per gli
/// scontrini) modificabile singolarmente, ed è segnalata se sembra un
/// doppione di una transazione già presente in locale — l'utente conferma
/// riga per riga prima del salvataggio.
class StatementImportPage extends ConsumerStatefulWidget {
  const StatementImportPage({super.key});

  @override
  ConsumerState<StatementImportPage> createState() => _StatementImportPageState();
}

class _ReviewRow {
  _ReviewRow({
    required this.row,
    required this.isPossibleDuplicate,
    this.selection,
  })  : include = !isPossibleDuplicate,
        date = row.date,
        amount = row.amount,
        type = row.type,
        note = row.description;

  /// Riga così come l'ha letta il parser — non più modificata dopo la
  /// modifica utente: serve solo come riferimento (il badge "possibile
  /// doppione" resta quello calcolato all'analisi del file).
  final ParsedStatementRow row;

  final bool isPossibleDuplicate;
  bool include;
  SubCategorySelection? selection;

  // Campi modificabili dall'utente (partono dai valori letti dal file, v.
  // "Modifica" per riga — riusa la stessa schermata di "Nuova Operazione").
  DateTime date;
  double amount;
  TransactionType type;
  String note;
}

class _StatementImportPageState extends ConsumerState<StatementImportPage> {
  BankStatementParser? _bank;
  String? _fileName;
  List<_ReviewRow> _rows = [];
  bool _busy = false;

  int get _readyCount =>
      _rows.where((r) => r.include && r.selection != null).length;
  int get _duplicateCount => _rows.where((r) => r.isPossibleDuplicate).length;
  int get _missingCategoryCount =>
      _rows.where((r) => r.include && r.selection == null).length;

  @override
  void initState() {
    super.initState();
    final banks = ref.read(bankStatementParsersProvider);
    _bank = banks.isNotEmpty ? banks.first : null;
  }

  Future<void> _pickAndAnalyze() async {
    final bank = _bank;
    if (bank == null) return;
    setState(() => _busy = true);
    try {
      // file_picker 12.x (M24): v. commento analogo in import_page.dart.
      final pickedFile = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (pickedFile == null) {
        setState(() => _busy = false);
        return;
      }
      final bytes = await pickedFile.readAsBytes();

      final parsedRows = bank.parse(bytes);
      if (parsedRows.isEmpty) {
        setState(() {
          _busy = false;
          _fileName = pickedFile.name;
          _rows = [];
        });
        return;
      }

      // Finestra temporale coperta dal file, allargata della tolleranza di
      // dedup, per recuperare in un colpo solo le transazioni locali contro
      // cui confrontare ogni riga (v. StatementDuplicateMatcher).
      final dates = parsedRows.map((r) => r.date);
      final matcher = ref.read(statementDuplicateMatcherProvider);
      final from = dates
          .reduce((a, b) => a.isBefore(b) ? a : b)
          .subtract(Duration(days: matcher.toleranceDays));
      final to = dates
          .reduce((a, b) => a.isAfter(b) ? a : b)
          .add(Duration(days: matcher.toleranceDays));
      final existing = await ref
          .read(transactionRepositoryProvider)
          .watchByPeriod(from: from, to: to)
          .first;

      final rules = await ref.read(merchantRulesProvider.future);
      final matcherService = ref.read(ruleMatcherServiceProvider);

      final reviewRows = parsedRows.map((row) {
        final rule = matcherService.match(row.description, rules);
        final selection = rule?.subCategoryId != null
            ? SubCategorySelection(
                categoryId: rule!.categoryId,
                subCategoryId: rule.subCategoryId!,
              )
            : null;
        return _ReviewRow(
          row: row,
          isPossibleDuplicate: matcher.isPossibleDuplicate(row, existing),
          selection: selection,
        );
      }).toList();

      setState(() {
        _busy = false;
        _fileName = pickedFile.name;
        _rows = reviewRows;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, 'Errore lettura file: $e');
    }
  }

  /// Apre la stessa schermata di modifica di "Nuova Operazione", precompilata
  /// coi valori correnti della riga (già editati in precedenza, se il caso).
  /// Non scrive sul database: `onDraftSaved` riporta l'operazione compilata
  /// indietro su questa riga, l'import vero avviene solo alla conferma finale.
  Future<void> _editRow(_ReviewRow review) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AddTransactionPage(
        draftDate: review.date,
        draftAmount: review.amount,
        draftType: review.type,
        draftNote: review.note,
        draftSelection: review.selection,
        onDraftSaved: (entity) {
          setState(() {
            review.date = entity.date;
            review.amount = entity.amount;
            review.type = entity.type;
            review.note = entity.note ?? '';
            review.selection = SubCategorySelection(
              categoryId: entity.categoryId,
              subCategoryId: entity.subCategoryId!,
            );
          });
        },
      ),
    ));
  }

  Future<void> _confirm() async {
    final toImport =
        _rows.where((r) => r.include && r.selection != null).toList();
    if (toImport.isEmpty) return;
    setState(() => _busy = true);
    final repo = ref.read(transactionRepositoryProvider);
    final count = toImport.length;
    try {
      // Import atomico, stesso principio dell'import CSV: o tutte le
      // operazioni selezionate vengono salvate, o nessuna.
      await repo.addAll(toImport.map((r) {
        final sel = r.selection!;
        return TransactionEntity(
          date: r.date,
          amount: r.amount,
          type: r.type,
          categoryId: sel.categoryId,
          subCategoryId: sel.subCategoryId,
          note: r.note.isEmpty ? null : r.note,
        );
      }).toList());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _rows = [];
        _fileName = null;
      });
      showSuccessSnackBar(context, 'Importate $count operazioni');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, 'Errore durante l\'import: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(bankStatementParsersProvider);
    final analyzed = _fileName != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Importa estratto conto')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<BankStatementParser>(
                  initialValue: _bank,
                  decoration: const InputDecoration(labelText: 'Banca'),
                  items: [
                    for (final b in banks)
                      DropdownMenuItem(value: b, child: Text(b.bankName)),
                  ],
                  onChanged: _busy ? null : (b) => setState(() => _bank = b),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: (_busy || _bank == null) ? null : _pickAndAnalyze,
                  icon: const Icon(Icons.upload_file_outlined),
                  label:
                      Text(analyzed ? 'Scegli un altro file' : 'Scegli file Excel'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
          if (analyzed && !_busy)
            Expanded(
              child: _rows.isEmpty
                  ? const Center(child: Text('Nessun movimento trovato nel file.'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _rows.length,
                      itemBuilder: (context, i) => _RowCard(
                        review: _rows[i],
                        onChanged: () => setState(() {}),
                        onEdit: () => _editRow(_rows[i]),
                      ),
                    ),
            ),
          if (analyzed && !_busy && _rows.isNotEmpty)
            SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_duplicateCount > 0 || _missingCategoryCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        [
                          if (_duplicateCount > 0)
                            '$_duplicateCount possibili doppioni',
                          if (_missingCategoryCount > 0)
                            '$_missingCategoryCount incluse senza categoria (non verranno importate)',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (_busy || _readyCount == 0) ? null : _confirm,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Importa $_readyCount operazioni'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.review,
    required this.onChanged,
    required this.onEdit,
  });

  final _ReviewRow review;
  final VoidCallback onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = review.type == TransactionType.expense;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: review.include,
                  onChanged: (v) {
                    review.include = v ?? false;
                    onChanged();
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppFormatters.shortDate(review.date),
                          style: theme.textTheme.labelMedium),
                      Text(review.note,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Text(
                  '${isExpense ? '-' : '+'}${AppFormatters.currency(review.amount)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color:
                        isExpense ? theme.colorScheme.error : Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Modifica operazione',
                  onPressed: onEdit,
                ),
              ],
            ),
            if (review.isPossibleDuplicate)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 40),
                child: Row(
                  children: [
                    Icon(Icons.content_copy, size: 14, color: theme.colorScheme.error),
                    const SizedBox(width: 4),
                    Text('Possibile doppione, esclusa di default',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 40),
              child: SubCategoryPicker(
                type: review.type,
                selection: review.selection,
                onChanged: (s) {
                  review.selection = s;
                  onChanged();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
