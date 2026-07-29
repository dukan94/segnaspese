import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/theme_providers.dart';

/// Scelta del tema (Milestone M8): modalità chiaro/scuro/sistema. Un'unica
/// identità cromatica per entrambe le modalità (v. AppTheme), niente più
/// varianti da scegliere.
class ThemePage extends ConsumerWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modeAsync = ref.watch(themeModeProvider);
    if (modeAsync.hasError) debugPrint('Errore lettura tema: ${modeAsync.error}');
    final mode = modeAsync.valueOrNull ?? ThemeMode.system;
    final setMode = ref.read(setThemeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tema')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Modalità', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: mode,
              onChanged: (v) => setMode(v!),
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text('Segui sistema'),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('Chiaro'),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('Scuro'),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
