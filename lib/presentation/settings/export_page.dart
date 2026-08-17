import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/category_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../data/mappers/transaction_mapper.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/services/transaction_export_service.dart';
import '../shared_widgets/content_width_limiter.dart';

/// Export delle operazioni di un anno in CSV (Milestone M6).
///
/// Il file usa le stesse colonne dell'import (più alcune informative), quindi
/// è ri-importabile senza perdite. Su desktop apre una finestra "Salva con
/// nome"; su mobile il file viene salvato tramite il selettore di sistema.
class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  late int _year = DateTime.now().year;
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final txns = await ref.read(yearTransactionsProvider(_year).future);
      if (txns.isEmpty) {
        if (!mounted) return;
        setState(() => _busy = false);
        showErrorSnackBar(context, 'Nessuna operazione per il $_year');
        return;
      }

      // Nomi categorie/sottocategorie per le colonne leggibili + compatibili
      // con l'import (l'import abbina la sottocategoria per nome).
      final cats = ref.read(allCategoriesProvider).valueOrNull ?? const [];
      final categoryNameById = {for (final c in cats) c.id: c.name};

      final expSubs = await ref.read(
          subCategoriesForTypeProvider(TransactionType.expense.toDrift())
              .future);
      final incSubs = await ref.read(
          subCategoriesForTypeProvider(TransactionType.income.toDrift())
              .future);
      final subCategoryNameById = <int, String>{
        for (final s in [...expSubs, ...incSubs])
          s.subCategory.id: s.subCategory.name,
      };

      final csv = const TransactionCsvExporter().buildCsv(
        transactions: txns,
        categoryNameById: categoryNameById,
        subCategoryNameById: subCategoryNameById,
      );

      // UTF-8 con BOM: così Excel apre il CSV con le lettere accentate corrette.
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];

      // file_picker 12.x (M24): saveFile() torna un Uri? (non più String?).
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Salva export operazioni $_year',
        fileName: 'operazioni_$_year.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(bytes),
      );

      if (!mounted) return;
      if (uri == null) {
        setState(() => _busy = false); // annullato dall'utente
        return;
      }

      // Su desktop saveFile restituisce solo il percorso: scriviamo noi il
      // file. Su mobile il plugin lo salva già usando i bytes passati.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(uri.toFilePath()).writeAsBytes(bytes, flush: true);
      }

      if (!mounted) return;
      setState(() => _busy = false);
      showSuccessSnackBar(context, 'Esportate ${txns.length} operazioni');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, 'Errore durante l\'export: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Esporta operazioni')),
      body: ContentWidthLimiter(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Esporta in CSV tutte le operazioni di un anno. Il file usa lo '
              'stesso formato dell\'import, quindi puoi ri-importarlo o aprirlo '
              'in Excel.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Anno'),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed:
                              _busy ? null : () => setState(() => _year--),
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Anno precedente',
                        ),
                        Text('$_year', style: theme.textTheme.titleLarge),
                        IconButton(
                          onPressed:
                              _busy ? null : () => setState(() => _year++),
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Anno successivo',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(_busy ? 'Esportazione...' : 'Esporta CSV del $_year'),
            ),
          ],
        ),
      ),
    );
  }
}
