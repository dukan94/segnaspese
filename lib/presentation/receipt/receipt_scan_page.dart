import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/di/gemini_providers.dart';
import '../../core/di/merchant_rule_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../data/services/gemini_vision_service.dart';
import '../../domain/entities/merchant_rule_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../transaction/widgets/category_picker.dart';

/// Schermata "Scansiona scontrino" (M3).
///
/// Su mobile si scatta una foto (o se ne sceglie una dalla galleria): se una
/// API key Gemini è configurata (v. `gemini_vision_service.dart`), la foto
/// viene analizzata dall'AI cloud; altrimenti (o se la chiamata fallisce) si
/// ripiega sul testo estratto con ML Kit OCR + regex. Su desktop si incolla
/// il testo a mano. In tutti i casi i dati riconosciuti finiscono in
/// `_finishAnalysis()`. Dopo l'analisi si conferma negozio/importo/categoria: se
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
    await _finishAnalysis(
      merchant: parsed.merchantName,
      total: parsed.total,
      textForRuleMatching: raw,
    );
  }

  /// Applica i dati riconosciuti (da OCR+regex o da vision-LLM) ai campi del
  /// form e prova a classificare il negozio con le regole esistenti. Comune
  /// a entrambi i percorsi (mobile e desktop) per non duplicare la logica di
  /// classificazione/apprendimento.
  Future<void> _finishAnalysis({
    required String? merchant,
    required double? total,
    DateTime? date,
    required String textForRuleMatching,
  }) async {
    final rules = await ref.read(merchantRuleRepositoryProvider).getAll();
    final match =
        ref.read(ruleMatcherServiceProvider).match(textForRuleMatching, rules);

    if (!mounted) return;
    setState(() {
      _analyzed = true;
      _merchantController.text = merchant ?? '';
      _amountController.text =
          total == null ? '' : total.toStringAsFixed(2).replaceAll('.', ',');
      if (date != null) _date = date;
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

  /// Scatta/seleziona una foto dello scontrino, la persiste e la analizza:
  /// prova prima Gemini (se una API key è configurata), altrimenti — o se la
  /// chiamata cloud fallisce — ripiega sull'OCR ML Kit + regex, così l'app
  /// resta utilizzabile anche offline o senza key configurata.
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
      final savedPath = await _persistImage(File(photo.path));
      if (!mounted) return;
      setState(() => _imagePath = savedPath);

      final apiKey = await ref.read(geminiApiKeyStoreProvider).read();
      if (apiKey != null && apiKey.isNotEmpty) {
        try {
          final model =
              ref.read(geminiModelProvider).valueOrNull ?? geminiModelDefault;
          final aiResult =
              await ref.read(geminiVisionServiceProvider).analyzeReceipt(
                    File(savedPath),
                    apiKey: apiKey,
                    model: model,
                  );
          if (!mounted) return;
          setState(() => _scanning = false);
          await _finishAnalysis(
            merchant: aiResult.merchantName,
            total: aiResult.total,
            date: aiResult.date,
            textForRuleMatching: aiResult.merchantName ?? '',
          );
          return;
        } on GeminiApiException catch (e) {
          if (!mounted) return;
          showErrorSnackBar(
            context,
            'AI cloud non disponibile (${e.message}), uso il riconoscimento offline.',
          );
        }
      }

      // Fallback: OCR ML Kit + regex (nessuna key configurata, o Gemini non
      // ha risposto correttamente).
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText result;
      try {
        result = await recognizer.processImage(InputImage.fromFilePath(savedPath));
      } finally {
        await recognizer.close();
      }

      if (!mounted) return;
      _rawController.text = result.text;
      setState(() => _scanning = false);
      await _analyze();
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      showErrorSnackBar(context, 'Errore durante la scansione: $e');
    }
  }

  /// Copia [source] nella cartella "application support" (stessa scelta di
  /// app_database.dart, non soggetta a redirect OneDrive) così l'immagine
  /// sopravvive oltre la sessione corrente (image_picker e file_picker
  /// restituiscono spesso un path in una cache temporanea).
  Future<String> _persistImage(File source) async {
    final supportDir = await getApplicationSupportDirectory();
    final receiptsDir = Directory(p.join(supportDir.path, 'receipts'));
    await receiptsDir.create(recursive: true);
    final savedPath = p.join(receiptsDir.path, '${const Uuid().v4()}.jpg');
    await source.copy(savedPath);
    return savedPath;
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
                  Text('Analisi in corso...'),
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
