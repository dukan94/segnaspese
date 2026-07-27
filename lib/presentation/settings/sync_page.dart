import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../data/services/sync_service.dart';

/// Impostazioni di sincronizzazione multi-dispositivo (Milestone M7):
/// l'utente incolla URL e auth token del proprio database Turso una tantum,
/// poi può forzare una sync manuale o lasciare che parta da sola all'avvio
/// e periodicamente mentre l'app è aperta (v. main.dart).
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final service = ref.read(syncServiceProvider);
    if (await service.isConfigured()) {
      // Le credenziali sono in flutter_secure_storage e non vengono rilette
      // in chiaro qui: l'utente le reinserisce solo se vuole sostituirle.
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_urlController.text.trim().isEmpty || _tokenController.text.trim().isEmpty) {
      showErrorSnackBar(context, 'Inserisci sia l\'URL che l\'auth token');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(syncServiceProvider).configure(
            tursoUrl: _urlController.text.trim(),
            authToken: _tokenController.text.trim(),
          );
      await ref.read(syncServiceProvider).syncNow();
      // Chiude il contesto di autofill: su Android è il segnale che fa
      // comparire il prompt "Salva in Proton Pass" (o altro password manager)
      // per queste credenziali, se non erano già salvate.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      showSuccessSnackBar(context, 'Configurazione salvata, sync avviata');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Errore durante la configurazione: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      await ref.read(syncServiceProvider).syncNow();
      if (!mounted) return;
      showSuccessSnackBar(context, 'Sincronizzazione completata');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Errore durante la sync: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sync multi-dispositivo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Collega un database Turso per sincronizzare le operazioni tra '
            'più dispositivi. URL e auth token si trovano nella dashboard '
            'Turso o con "turso db show" / "turso db tokens create".',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _StatusBanner(status: status),
          const SizedBox(height: 24),
          // AutofillGroup + autofillHints: permette a un password manager
          // (es. Proton Pass) installato come servizio di autofill Android di
          // proporre di compilare questi campi da una voce salvata, invece di
          // dover copiare/incollare a mano URL e token ogni volta.
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autofillHints: const [AutofillHints.url],
                  decoration: const InputDecoration(
                    labelText: 'URL database Turso',
                    hintText: 'libsql://nome-db-org.turso.io',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Auth token',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureToken
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salva e sincronizza'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _syncNow,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(_busy ? 'Sincronizzazione...' : 'Sincronizza ora'),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final AsyncValue<SyncStatus> status;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = status.when(
      data: (s) => switch (s) {
        SyncStatus.offline => (Icons.cloud_off_outlined, 'Non configurato / offline', Colors.grey),
        SyncStatus.syncing => (Icons.sync, 'Sincronizzazione in corso...', Colors.blue),
        SyncStatus.synced => (Icons.cloud_done_outlined, 'Sincronizzato', Colors.green),
        SyncStatus.error => (Icons.error_outline, 'Errore di sincronizzazione', Colors.red),
      },
      loading: () => (Icons.cloud_outlined, 'Stato sconosciuto', Colors.grey),
      error: (_, __) => (Icons.error_outline, 'Errore di sincronizzazione', Colors.red),
    );

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
      ),
    );
  }
}
