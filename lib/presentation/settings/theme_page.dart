import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/theme_providers.dart';
import '../../core/theme/app_theme.dart';

/// Scelta del tema (Milestone M8): modalità chiaro/scuro/sistema e, per lo
/// scuro, una delle 4 varianti cromatiche disponibili (v. [DarkThemeVariant]).
class ThemePage extends ConsumerWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final variant = ref.watch(darkVariantProvider).valueOrNull ?? DarkThemeVariant.boscoNotturno;
    final setMode = ref.read(setThemeModeProvider);
    final setVariant = ref.read(setDarkVariantProvider);
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
          const SizedBox(height: 24),
          Text('Variante scura', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Si applica quando il tema scuro è attivo (anche seguendo il sistema).',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<DarkThemeVariant>(
              groupValue: variant,
              onChanged: (v) => setVariant(v!),
              child: Column(
                children: [
                  for (final v in DarkThemeVariant.values)
                    RadioListTile<DarkThemeVariant>(
                      secondary: CircleAvatar(backgroundColor: v.seedColor),
                      title: Text(v.label),
                      value: v,
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
