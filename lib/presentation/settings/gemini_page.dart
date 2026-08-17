import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/di/gemini_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../shared_widgets/content_width_limiter.dart';

enum _GeminiTestStatus { unknown, testing, valid, invalid }

/// Configurazione dell'AI cloud gratuita (Google Gemini) usata in
/// "Scansiona scontrino" per leggere l'immagine direttamente, invece
/// dell'OCR (ML Kit) + regex, con fallback automatico su quest'ultimo se la
/// key non è configurata o la chiamata fallisce.
class GeminiPage extends ConsumerStatefulWidget {
  const GeminiPage({super.key});

  @override
  ConsumerState<GeminiPage> createState() => _GeminiPageState();
}

class _GeminiPageState extends ConsumerState<GeminiPage> {
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _obscureKey = true;
  bool _busy = false;
  bool _modelLoaded = false;
  bool _alreadyConfigured = false;
  _GeminiTestStatus _testStatus = _GeminiTestStatus.unknown;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final configured = await ref.read(geminiApiKeyStoreProvider).isConfigured();
    if (!mounted) return;
    setState(() => _alreadyConfigured = configured);
  }

  void _fillModelOnce(String model) {
    if (_modelLoaded) return;
    _modelLoaded = true;
    _modelController.text = model;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();
    if (apiKey.isEmpty && !_alreadyConfigured) {
      showErrorSnackBar(context, 'Inserisci la API key Gemini');
      return;
    }
    if (model.isEmpty) {
      showErrorSnackBar(context, 'Inserisci il nome del modello');
      return;
    }
    setState(() => _busy = true);
    try {
      if (apiKey.isNotEmpty) {
        await ref.read(geminiApiKeyStoreProvider).write(apiKey);
      }
      await ref.read(setGeminiModelProvider)(model);
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
    // Usa la key appena digitata se presente, altrimenti quella già salvata.
    var apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      apiKey = await ref.read(geminiApiKeyStoreProvider).read() ?? '';
    }
    if (!mounted) return;
    if (apiKey.isEmpty) {
      showErrorSnackBar(context, 'Inserisci prima una API key');
      return;
    }
    setState(() => _testStatus = _GeminiTestStatus.testing);
    try {
      final response = await http
          .get(Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      jsonDecode(response.body); // valida solo che sia JSON ben formato
      if (!mounted) return;
      setState(() => _testStatus = _GeminiTestStatus.valid);
      showSuccessSnackBar(context, 'API key valida');
    } catch (e) {
      if (!mounted) return;
      setState(() => _testStatus = _GeminiTestStatus.invalid);
      showErrorSnackBar(context, 'API key non valida o non raggiungibile: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelAsync = ref.watch(geminiModelProvider);
    if (modelAsync.hasValue) _fillModelOnce(modelAsync.value!);

    return Scaffold(
      appBar: AppBar(title: const Text('AI per scontrini (Gemini)')),
      body: ContentWidthLimiter(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '"Scansiona scontrino" può leggere la foto direttamente con '
              'Google Gemini (gratuito, richiede una API key personale) '
              'invece del solo riconoscimento testo offline. Se la key non è '
              'configurata o la richiesta fallisce, si ricade automaticamente '
              'sul riconoscimento offline. Ottieni una API key gratuita su '
              'aistudio.google.com/apikey.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _StatusBanner(
              testStatus: _testStatus,
              alreadyConfigured: _alreadyConfigured,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API key Gemini',
                hintText: _alreadyConfigured
                    ? 'Già configurata — lascia vuoto per non cambiarla'
                    : null,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Modello',
                hintText: 'gemini-2.5-flash',
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
              onPressed: _testStatus == _GeminiTestStatus.testing
                  ? null
                  : _testConnection,
              icon: _testStatus == _GeminiTestStatus.testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering_outlined),
              label: const Text('Testa connessione'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner(
      {required this.testStatus, required this.alreadyConfigured});

  final _GeminiTestStatus testStatus;
  final bool alreadyConfigured;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (testStatus) {
      _GeminiTestStatus.testing => (
          Icons.sync,
          'Verifica in corso...',
          Colors.blue,
        ),
      _GeminiTestStatus.valid => (
          Icons.check_circle_outline,
          'API key valida',
          Colors.green,
        ),
      _GeminiTestStatus.invalid => (
          Icons.error_outline,
          'API key non valida',
          Colors.red,
        ),
      _GeminiTestStatus.unknown => alreadyConfigured
          ? (Icons.check_circle_outline, 'Configurata', Colors.green)
          : (Icons.cloud_off_outlined, 'Non configurata', Colors.grey),
    };

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
      ),
    );
  }
}
