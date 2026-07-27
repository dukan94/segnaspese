import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/di/merchant_rule_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/merchant_rule_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../transaction/widgets/category_picker.dart';

/// Schermata "Scansiona scontrino" (M3).
///
/// Su mobile si scatta una foto (o se ne sceglie una dalla galleria) e il
/// testo viene estratto con ML Kit OCR; su desktop (e per i test) si incolla
/// il testo a mano. In entrambi i casi il testo finisce nello stesso
/// `_analyze()`. Dopo l'analisi si conferma negozio/importo/categoria: se
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

  /// true durante lo scatto/selezione foto e l'OCR (v. [_captureAndScan]).
  bool _scanning = false;

  /// Path persistito della foto scattata (cartella "application support",
  /// non la cache temporanea di image_picker), salvato su
  /// `TransactionEntity.receiptImagePath` al momento del salvataggio.
  String? _imagePath;

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

  /// Scatta/seleziona una foto dello scontrino, la persiste, esegue l'OCR
  /// (ML Kit) sul testo riconosciuto e richiama [_analyze] — la stessa
  /// pipeline di parsing/classificazione già usata per il testo incollato,
  /// senza duplicarla.
  Future<void> _captureAndScan(ImageSource source) async {
    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(source: source, imageQuality: 85);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Fotocamera non disponibile: $e');
      return;
    }
    if (photo == null) return; // annullato dall'utente

    setState(() => _scanning = true);
    try {
      // L'XFile di image_picker vive spesso in una cache temporanea: lo
      // copiamo nella cartella "application support" (stessa scelta di
      // app_database.dart, non soggetta a redirect OneDrive) così sopravvive
      // oltre la sessione, per poterlo riaprire dallo storico in futuro.
      final supportDir = await getApplicationSupportDirectory();
      final receiptsDir = Directory(p.join(supportDir.path, 'receipts'));
      await receiptsDir.create(recursive: true);
      final savedPath = p.join(receiptsDir.path, '${const Uuid().v4()}.jpg');
      await File(photo.path).copy(savedPath);

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText result;
      try {
        result = await recognizer.processImage(InputImage.fromFilePath(savedPath));
      } finally {
        await recognizer.close();
      }

      if (!mounted) return;
      _imagePath = savedPath;
      _rawController.text = result.text;
      setState(() => _scanning = false);
      await _analyze();
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      showErrorSnackBar(context, 'Errore durante la scansione: $e');
    }
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
      receiptImagePath: _imagePath,
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
          if (Platform.isAndroid || Platform.isIOS) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanning || _saving
                        ? null
                        : () => _captureAndScan(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Scatta foto'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanning || _saving
                        ? null
                        : () => _captureAndScan(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galleria'),
                  ),
                ),
              ],
            ),
            if (_scanning) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Riconoscimento testo in corso...'),
                ],
              ),
            ],
            if (_imagePath != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(_imagePath!), height: 140, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Puoi anche correggere il testo riconosciuto qui sotto prima di analizzare:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else
            const _DesktopHint(),
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

/// Fotocamera/galleria non disponibili su desktop (`image_picker` non le
/// supporta lì): unico modo per provare il flusso è incollare il testo.
class _DesktopHint extends StatelessWidget {
  const _DesktopHint();

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
                'Fotocamera disponibile solo su telefono. Su desktop incolla '
                'qui sotto il testo dello scontrino per provare il flusso.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
