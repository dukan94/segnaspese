import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../theme/app_theme.dart';
import 'database_provider.dart';

/// Chiavi nella tabella Settings (stesso pattern key-value già usato per
/// l'obiettivo di risparmio annuo e l'ordine drag & drop delle categorie).
const String _themeModeKey = 'theme_mode';
const String _darkVariantKey = 'dark_variant';

ThemeMode _parseThemeMode(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String _themeModeToValue(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}

/// Modalità tema scelta dall'utente (Sistema/Chiaro/Scuro), default Sistema.
final themeModeProvider = StreamProvider<ThemeMode>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)..where((s) => s.key.equals(_themeModeKey)))
      .watchSingleOrNull()
      .map((row) => _parseThemeMode(row?.value));
});

final setThemeModeProvider = Provider<Future<void> Function(ThemeMode)>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (mode) => db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: _themeModeKey,
          value: _themeModeToValue(mode),
          updatedAt: Value(DateTime.now()),
        ),
      );
});

/// Variante del tema scuro scelta dall'utente tra le 4 disponibili (v.
/// [DarkThemeVariant]), default "Bosco notturno".
final darkVariantProvider = StreamProvider<DarkThemeVariant>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)..where((s) => s.key.equals(_darkVariantKey)))
      .watchSingleOrNull()
      .map((row) => DarkThemeVariant.values.firstWhere(
            (v) => v.name == row?.value,
            orElse: () => DarkThemeVariant.boscoNotturno,
          ));
});

final setDarkVariantProvider = Provider<Future<void> Function(DarkThemeVariant)>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (variant) => db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: _darkVariantKey,
          value: variant.name,
          updatedAt: Value(DateTime.now()),
        ),
      );
});
