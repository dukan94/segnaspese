import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/google_sheets_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../data/services/google_sheets_service.dart';

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
    super.dispose();
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
        ],
      ),
    );
  }
}
