import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/merchant_rule_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/merchant_rule_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../transaction/widgets/category_picker.dart';

/// Schermata "Scansiona scontrino" (M3).
///
/// Su desktop (e per i test) si incolla il testo dello scontrino; su mobile
/// arriverà la fotocamera + OCR (ML Kit), che produrrà lo stesso testo dato in
/// pasto al parser. Dopo l'analisi si conferma negozio/importo/categoria: se
/// nessuna regola riconosce il negozio, un interruttore "Ricorda" crea una
/// regola automatica per le prossime volte.
class ReceiptScanPage extends ConsumerStatefulWidget {
  const ReceiptScanPage({super.key});

  @override
  ConsumerState<ReceiptScanPage> createState() => _ReceiptScanPageState();
}

class _ReceiptScanPageState extends ConsumerState<ReceiptScanPage> {
  final _rawController = TextEditingController();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();

  bool _analyzed = false;
  SubCategorySelection? _selection;
  DateTime _date = DateTime.now();
  bool _matchedByRule = false;
  bool _remember = true;
  bool _saving = false;

  @override
  void dispose() {
    _rawController.dispose();
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  double get _amount => _parseAmount(_amountController.text) ?? 0;

  bool get _canSave => _amount > 0 && _selection != null && !_saving;

  Future<void> _analyze() async {
    // Normalizza eventuali "\n"/"\r" letterali (utile quando si incolla del
    // testo su una riga sola nei test desktop): l'OCR reale produce veri
    // a-capo, così il parser individua correttamente negozio e righe.
    final raw = _normalizeReceiptText(_rawController.text);
    if (raw.trim().isEmpty) {
      showErrorSnackBar(context, 'Incolla il testo dello scontrino');
      return;
    }
    final parser = ref.read(receiptParserServiceProvider);
    final parsed = parser.parse(raw);

    // Prova a classificare con le regole esistenti.
    final rules = await ref.read(merchantRuleRepositoryProvider).getAll();
    final match = ref.read(ruleMatcherServiceProvider).match(raw, rules);

    if (!mounted) return;
    setState(() {
      _analyzed = true;
      _merchantController.text = parsed.merchantName ?? '';
      _amountController.text = parsed.total == null
          ? ''
          : parsed.total!.toStringAsFixed(2).replaceAll('.', ',');
      if (match != null && match.subCategoryId != null) {
        _selection = SubCategorySelection(
          categoryId: match.categoryId,
          subCategoryId: match.subCategoryId!,
        );
        _matchedByRule = true;
        _remember = false;
      } else {
        _selection = null;
        _matchedByRule = false;
        _remember = true;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final merchant = _merchantController.text.trim();

    final transaction = TransactionEntity(
      date: _date,
      amount: _amount,
      type: TransactionType.expense,
      categoryId: _selection!.categoryId,
      subCategoryId: _selection!.subCategoryId,
      note: merchant.isEmpty ? null : merchant,
    );

    try {
      await ref.read(addTransactionProvider).call(transaction);

      // Apprendimento: se nessuna regola ha riconosciuto il negozio e l'utente
      // ha lasciato attivo "Ricorda", crea una regola automatica.
      if (!_matchedByRule && _remember && merchant.isNotEmpty) {
        final rule = MerchantRuleEntity(
          pattern: _patternFromMerchant(merchant),
          categoryId: _selection!.categoryId,
          subCategoryId: _selection!.subCategoryId,
          isUserDefined: false,
        );
        await ref.read(addMerchantRuleProvider).call(rule);
      }

      if (!mounted) return;
      showSuccessSnackBar(context, 'Operazione salvata');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnackBar(context, 'Errore durante il salvataggio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Scansiona scontrino'),
        actions: [
          if (_analyzed)
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              onPressed: _canSave ? _save : null,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _CameraHint(),
          const SizedBox(height: 12),
          TextField(
            controller: _rawController,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Testo dello scontrino',
              hintText: 'Incolla qui il testo (negozio, righe, TOTALE...)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _saving ? null : _analyze,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(_analyzed ? 'Analizza di nuovo' : 'Analizza'),
          ),
          if (_analyzed) ...[
            const Divider(height: 32),
            if (_matchedByRule)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_outlined,
                        size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Categoria riconosciuta da una regola',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(labelText: 'Negozio'),
              // Aggiorna la visibilità dell'interruttore "Ricorda".
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration:
                  const InputDecoration(labelText: 'Importo', suffixText: '€'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            SubCategoryPicker(
              type: TransactionType.expense,
              selection: _selection,
              onChanged: (value) => setState(() => _selection = value),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Data'),
              trailing: Text(AppFormatters.shortDate(_date)),
              onTap: _pickDate,
            ),
            if (!_matchedByRule && _merchantController.text.trim().isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _remember,
                onChanged: (v) => setState(() => _remember = v),
                title: const Text('Ricorda per la prossima volta'),
                subtitle: const Text(
                    'Crea una regola per classificare automaticamente questo negozio'),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave ? _save : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Salva operazione'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Costruisce un pattern regex dal nome negozio: usa la prima parola
/// "sostanziosa" (>= 3 caratteri) come radice, per generalizzare tra scontrini
/// dello stesso negozio.
String _patternFromMerchant(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  final root = words.firstWhere(
    (w) => w.length >= 3,
    orElse: () => name.trim(),
  );
  return '${RegExp.escape(root)}.*';
}

/// Converte sequenze di escape letterali ("\n", "\r\n", "\r") in veri a-capo.
String _normalizeReceiptText(String input) => input
    .replaceAll('\\r\\n', '\n')
    .replaceAll('\\n', '\n')
    .replaceAll('\\r', '\n');

double? _parseAmount(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  }
  final value = double.tryParse(s);
  if (value == null || value < 0) return null;
  return value;
}

class _CameraHint extends StatelessWidget {
  const _CameraHint();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.surfaceContainerHigh,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.photo_camera_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Su telefono qui ci sarà la fotocamera con riconoscimento '
                'automatico del testo. Su desktop incolla il testo per provare '
                'il flusso.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
