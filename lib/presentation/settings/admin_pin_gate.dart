import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/admin_pin_providers.dart';
import 'admin_page.dart';

/// Gate d'accesso al pannello Admin (M48): un solo PIN per l'INTERA
/// sezione, non uno diverso per bottone — stesso principio "solo
/// l'essenziale" già seguito altrove in questo progetto. Locale al
/// dispositivo (v. `AdminPinStore`): nessun canale per cui il PIN o le
/// azioni fatte su QUESTO dispositivo possano mai toccare il database di
/// un altro utente (isolamento già garantito da database Turso separati
/// per persona, non da questo gate).
///
/// Al primo accesso (nessun PIN ancora impostato) obbliga a impostarne uno
/// prima di procedere — nessun "salta per ora": un gate che si può
/// ignorare non protegge nulla. Ogni accesso successivo richiede il PIN;
/// resta sbloccato solo per la durata di questa "sessione" (finché non si
/// esce da Admin), non c'è un "ricordami".
class AdminPinGate extends ConsumerStatefulWidget {
  const AdminPinGate({super.key});

  @override
  ConsumerState<AdminPinGate> createState() => _AdminPinGateState();
}

class _AdminPinGateState extends ConsumerState<AdminPinGate> {
  bool _loading = true;
  bool _pinAlreadySet = false;
  bool _unlocked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkPinSet();
  }

  Future<void> _checkPinSet() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final isSet = await ref.read(adminPinStoreProvider).isSet();
      if (!mounted) return;
      setState(() {
        _pinAlreadySet = isSet;
        _loading = false;
      });
    } catch (e) {
      // Senza questo catch, un errore qui (es. il keystore di sistema non
      // risponde) lasciava _loading a true per sempre: spinner infinito,
      // Admin diventava irraggiungibile senza nessun messaggio (audit, 2 set
      // 2026).
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossibile verificare il PIN: $e';
      });
    }
  }

  void _unlock() => setState(() => _unlocked = true);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return _PinErrorScreen(message: _error!, onRetry: _checkPinSet);
    }
    if (_unlocked) {
      return const AdminPage();
    }
    return _pinAlreadySet
        ? _EnterPinScreen(onUnlocked: _unlock)
        : _SetPinScreen(onSet: _unlock);
  }
}

/// Mostrata se anche solo verificare se un PIN è già impostato fallisce
/// (es. errore del secure storage di sistema) — mai un'app bloccata su uno
/// spinner infinito senza spiegazione.
class _PinErrorScreen extends StatelessWidget {
  const _PinErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 40, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(onPressed: onRetry, child: const Text('Riprova')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Primo accesso: nessun PIN impostato ancora, va creato prima di entrare.
class _SetPinScreen extends ConsumerStatefulWidget {
  const _SetPinScreen({required this.onSet});

  final VoidCallback onSet;

  @override
  ConsumerState<_SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends ConsumerState<_SetPinScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text;
    final confirm = _confirmController.text;
    if (pin.length < adminPinMinLength) {
      setState(() => _error = 'Il PIN deve avere almeno $adminPinMinLength cifre');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'I due PIN inseriti non coincidono');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref.read(adminPinStoreProvider).setPin(pin);
      if (!mounted) return;
      widget.onSet();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Errore durante il salvataggio del PIN: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 16),
                Text(
                  'Imposta un PIN per proteggere questa sezione',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Serve solo su questo dispositivo, per evitare che chi lo '
                  'usa acceda per sbaglio a strumenti come l\'eliminazione '
                  'definitiva.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(adminPinMaxLength),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Nuovo PIN',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(adminPinMaxLength),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Conferma PIN',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: const Text('Imposta PIN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// PIN già impostato: va inserito per sbloccare l'accesso.
class _EnterPinScreen extends ConsumerStatefulWidget {
  const _EnterPinScreen({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<_EnterPinScreen> createState() => _EnterPinScreenState();
}

class _EnterPinScreenState extends ConsumerState<_EnterPinScreen> {
  final _pinController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text;
    if (pin.isEmpty) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final correct = await ref.read(adminPinStoreProvider).verify(pin);
      if (!mounted) return;
      if (correct) {
        widget.onUnlocked();
        return;
      }
      _pinController.clear();
      setState(() {
        _error = 'PIN errato';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Errore durante la verifica del PIN: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 16),
                Text(
                  'Inserisci il PIN',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(adminPinMaxLength),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: const Text('Sblocca'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
