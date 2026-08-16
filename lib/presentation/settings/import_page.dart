import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/category_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../data/local/database/daos/category_dao.dart';
import '../../data/mappers/transaction_mapper.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/services/csv_transaction_parser.dart';

/// Import operazioni da CSV (prima slice di M6).
///
/// L'utente esporta il foglio da Excel in CSV; l'app abbina le sottocategorie
/// per nome (ignorando emoji), mostra un'anteprima con righe pronte e righe da
/// saltare (con motivo), e importa dopo conferma.
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ResolvedRow {
  _ResolvedRow(this.row, this.entity, this.problem);

  final CsvTransactionRow row;

  /// Transazione pronta da inserire (null se la riga va saltata).
  final TransactionEntity? entity;
  final String? problem;

  bool get ok => problem == null && entity != null;
}

class _ImportPageState extends ConsumerState<ImportPage> {
  static const _parser = CsvTransactionParser();

  String? _fileName;
  List<_ResolvedRow> _rows = [];
  List<String> _missingColumns = [];
  bool _busy = false;

  int get _okCount => _rows.where((r) => r.ok).length;
  int get _skipCount => _rows.where((r) => !r.ok).length;

  /// Prova UTF-8; se il file usa un'altra codifica (es. Windows-1252 dell'export
  /// Excel), ripiega su Latin-1 così le lettere accentate non si corrompono.
  String _decodeBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  Future<void> _pickAndAnalyze() async {
    setState(() => _busy = true);
    try {
      // file_picker 12.x (M24): pickFiles() non è più su FilePicker.platform
      // (rimosso), e allowMultiple/withData sono deprecati a favore di
      // pickFile() (singolare, un solo file) + PlatformFile.readAsBytes()
      // (lettura lazy, sostituisce la vecchia proprietà .bytes rimossa).
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
      );
      if (file == null) {
        setState(() => _busy = false);
        return;
      }
      final bytes = await file.readAsBytes();
      var content = _decodeBytes(bytes);
      content = content.replaceFirst('﻿', ''); // rimuove BOM se presente

      final parsed = _parser.parse(content);

      // Mappa combinata nome-normalizzato → sottocategoria+categoria. Il tipo
      // (entrata/uscita) lo determina la categoria abbinata; un importo
      // negativo su una categoria di spesa è un rimborso.
      final expenseSubs = await ref
          .read(subCategoriesForTypeProvider(TransactionType.expense.toDrift()).future);
      final incomeSubs = await ref
          .read(subCategoriesForTypeProvider(TransactionType.income.toDrift()).future);

      final combined = <String, SubCategoryWithCategory>{};
      for (final s in [...expenseSubs, ...incomeSubs]) {
        combined.putIfAbsent(
            CsvTransactionParser.normalizeName(s.subCategory.name), () => s);
      }

      final resolved = parsed.rows.map((row) {
        if (!row.isValid) return _ResolvedRow(row, null, row.error);
        final match =
            combined[CsvTransactionParser.normalizeName(row.subCategoryName)];
        if (match == null) {
          return _ResolvedRow(
              row, null, 'Sottocategoria "${row.subCategoryName}" non trovata');
        }
        final type = match.category.type.toDomain();
        final signed = row.signedAmount!;
        final isRefund = type == TransactionType.expense && signed < 0;
        final entity = TransactionEntity(
          date: row.date!,
          amount: signed.abs(),
          type: type,
          categoryId: match.category.id,
          subCategoryId: match.subCategory.id,
          note: row.note,
          isExtraordinary: row.isExtraordinary,
          isRefund: isRefund,
        );
        return _ResolvedRow(row, entity, null);
      }).toList();

      setState(() {
        _fileName = file.name;
        _rows = resolved;
        _missingColumns = parsed.missingColumns;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, 'Errore lettura file: $e');
    }
  }

  Future<void> _import() async {
    final toImport = _rows.where((r) => r.ok).toList();
    if (toImport.isEmpty) return;
    setState(() => _busy = true);
    final repo = ref.read(transactionRepositoryProvider);
    final count = toImport.length;
    try {
      // Import atomico: o vengono salvate tutte le operazioni, o nessuna
      // (nessun import parziale in caso di errore a metà).
      await repo.addAll(toImport.map((r) => r.entity!).toList());
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
    final analyzed = _fileName != null;
    final unmatchedNames = _rows
        .where((r) => r.row.isValid && r.entity == null)
        .map((r) => r.row.subCategoryName)
        .toSet()
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Importa da CSV')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _FormatHint(),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _pickAndAnalyze,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(analyzed ? 'Scegli un altro file' : 'Scegli file CSV'),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_missingColumns.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Intestazione non valida. Colonne obbligatorie mancanti: '
                    '${_missingColumns.join(", ")}.',
                  ),
                ),
              ),
            ),
          if (analyzed && _missingColumns.isEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fileName!,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: Colors.green.shade600, size: 18),
                        const SizedBox(width: 6),
                        Text('$_okCount pronte all\'import'),
                      ],
                    ),
                    if (_skipCount > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.remove_circle_outline,
                              color: Theme.of(context).colorScheme.error, size: 18),
                          const SizedBox(width: 6),
                          Text('$_skipCount da saltare'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (unmatchedNames.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sottocategorie non riconosciute',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      const Text(
                          'Rinominale nel CSV come nell\'app (o creale in Categorie), poi rilancia:'),
                      const SizedBox(height: 8),
                      for (final name in unmatchedNames)
                        Text('• $name',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_busy || _okCount == 0) ? null : _import,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Importa $_okCount operazioni'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FormatHint extends StatelessWidget {
  const _FormatHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Formato atteso', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Colonne (in qualsiasi ordine): Data (gg/mm/aaaa), Quanto, '
              'Sub Categoria, e opzionali Note e "Tipologia Spesa" (scrivi '
              '"Straordinaria" dove serve). Il tipo (entrata/uscita) è dedotto '
              'dalla sottocategoria, che deve avere lo stesso nome dell\'app '
              '(le emoji sono ignorate). Un importo negativo su una '
              'sottocategoria di spesa è considerato un rimborso.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
