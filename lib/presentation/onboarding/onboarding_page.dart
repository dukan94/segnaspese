import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/onboarding_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../shared_widgets/content_width_limiter.dart';

/// Wizard di primo avvio (M49): mostrato SOLO su un'installazione davvero
/// vuota (v. `resolveNeedsOnboarding`, chiamata in `main.dart` prima di
/// costruire il router) — mai a un dispositivo/utente già in uso. Tre
/// schermate (Benvenuto → Sync Turso, opzionale → Fine), lo step corrente è
/// salvato in Settings (`onboardingStepProvider`): se l'utente esce
/// dall'app per creare il database Turso sul browser e il processo viene
/// ucciso nel frattempo, al ritorno riprende esattamente dalla stessa
/// schermata invece di ripartire da "Benvenuto".
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(onboardingStepProvider).valueOrNull ??
        onboardingStepWelcome;
    return switch (step) {
      onboardingStepTurso => const _TursoStep(),
      onboardingStepDone => const _DoneStep(),
      _ => const _WelcomeStep(),
    };
  }
}

class _WelcomeStep extends ConsumerWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // Niente titolo: l'AppBar serve solo a dare una freccia Indietro
      // automatica quando si può tornare a una schermata precedente (es.
      // avviato per test da Admin, M49) — su un vero primo avvio non c'è
      // nulla su cui tornare (`/onboarding` è la route iniziale), quindi
      // Flutter non la mostra da sola.
      appBar: AppBar(),
      body: Center(
        child: ContentWidthLimiter(
          maxWidth: 480,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icona in un cerchio con sfondo tenue invece che nuda: stesso
                // "peso" visivo di un logo, look più curato di una semplice
                // icona Material fluttuante (richiesto da Mario, M49).
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'Benvenuto in Tally',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  'Tieni sotto controllo le tue spese: categorizzazione '
                  'automatica, dashboard, budget e movimenti ricorrenti.',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Tutto resta salvato solo su questo dispositivo. Nel '
                  'prossimo passo potrai collegare un database gratuito: '
                  'serve solo se vuoi usare Tally su più dispositivi con gli '
                  'stessi dati — con uno solo puoi saltarlo tranquillamente.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                FilledButton(
                  onPressed: () =>
                      ref.read(setOnboardingStepProvider)(onboardingStepTurso),
                  child: const Text('Inizia'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TursoStep extends ConsumerStatefulWidget {
  const _TursoStep();

  @override
  ConsumerState<_TursoStep> createState() => _TursoStepState();
}

class _TursoStepState extends ConsumerState<_TursoStep> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _busy = false;

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    if (_urlController.text.trim().isEmpty ||
        _tokenController.text.trim().isEmpty) {
      showErrorSnackBar(context, 'Inserisci sia l\'URL che l\'auth token');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(syncServiceProvider).configure(
            tursoUrl: _urlController.text.trim(),
            authToken: _tokenController.text.trim(),
          );
      unawaited(ref.read(syncServiceProvider).syncNow());
      TextInput.finishAutofillContext();
      if (!mounted) return;
      ref.read(wizardTursoOutcomeProvider.notifier).state = true;
      await ref.read(setOnboardingStepProvider)(onboardingStepDone);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Errore durante la configurazione: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    ref.read(wizardTursoOutcomeProvider.notifier).state = false;
    await ref.read(setOnboardingStepProvider)(onboardingStepDone);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronizzazione'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              ref.read(setOnboardingStepProvider)(onboardingStepWelcome),
        ),
      ),
      body: ContentWidthLimiter(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Facoltativo: collega un tuo database Turso (gratuito) per '
              'usare Tally su più dispositivi con gli stessi dati. Puoi '
              'sempre farlo più tardi da Impostazioni → Configurazioni.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            const _TursoInstructions(),
            const SizedBox(height: 24),
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
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _saveAndContinue,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_busy ? 'Configurazione...' : 'Salva e continua'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _skip,
              child: const Text('Salta per ora'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Istruzioni passo-passo per creare un database Turso gratuito, con link
/// diretto (richiesto da Mario, M49): chi riceve l'app non ha nessun altro
/// contesto da cui partire, a differenza della pagina Sync in Impostazioni
/// (pensata per chi lo sta già usando su un altro dispositivo).
class _TursoInstructions extends StatelessWidget {
  const _TursoInstructions();

  static const _steps = [
    'Vai su turso.tech e crea un account gratuito',
    'Crea un nuovo database (pulsante "Create Database")',
    'Copia l\'URL del database ("libsql://...")',
    'Crea un token di accesso ("Create Token") e copialo',
    'Torna qui e incolla i due valori qui sotto',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Come ottenere URL e token', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (var i = 0; i < _steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${i + 1}. ${_steps[i]}'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://turso.tech'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Apri turso.tech'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneStep extends ConsumerWidget {
  const _DoneStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Esito di QUESTA sessione del wizard (v. wizardTursoOutcomeProvider),
    // non lo stato Turso già presente sul dispositivo: altrimenti "Salta
    // per ora" su un dispositivo che ha già Turso configurato da prima
    // (es. testando da Admin, M49) mostrerebbe comunque "configurata".
    final tursoConfigured = ref.watch(wizardTursoOutcomeProvider) ?? false;
    return Scaffold(
      appBar: AppBar(), // v. commento in _WelcomeStep
      body: Center(
        child: ContentWidthLimiter(
          maxWidth: 480,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  'Tutto pronto!',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  tursoConfigured
                      ? 'Sincronizzazione configurata. Puoi iniziare a usare Tally.'
                      : 'Puoi collegare la sincronizzazione in qualsiasi momento '
                          'da Impostazioni → Configurazioni.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () async {
                    await ref.read(completeOnboardingProvider)();
                    if (!context.mounted) return;
                    // Se il wizard è stato aperto per test da Admin (push,
                    // c'è una route su cui tornare), torna lì invece di
                    // andare comunque in Home — altrimenti il pulsante
                    // "Avvia wizard" (M49) non riporterebbe mai ad Admin
                    // come promesso, e servirebbe reinserire il PIN (audit,
                    // 2 set 2026). Su un vero primo avvio (`/onboarding` è
                    // la route iniziale, niente su cui tornare) resta
                    // `context.go('/home')` come prima.
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.go('/home');
                    }
                  },
                  child: const Text('Inizia a usare Tally'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
