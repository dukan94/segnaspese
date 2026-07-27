import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Le 4 varianti disponibili per il tema scuro (scelte dall'utente in
/// Impostazioni > Tema): ognuna ha una propria identità cromatica, non solo
/// una declinazione scura dello stesso verde del tema chiaro.
enum DarkThemeVariant {
  boscoNotturno('Bosco notturno', Color(0xFF4CAF7D)),
  inchiostroEOttone('Inchiostro e ottone', Color(0xFFC99B4A)),
  grafiteETerracotta('Grafite e terracotta', Color(0xFFD9764A)),
  prugnaProfonda('Prugna profonda', Color(0xFFB98BC9));

  const DarkThemeVariant(this.label, this.seedColor);

  final String label;
  final Color seedColor;
}

/// Tema centralizzato dell'app: Material 3, seed color per tema (v.
/// progettazione, sezione Design). Il tema chiaro ha un contrasto testo
/// alzato rispetto al default M3 (richiesto dall'utente); il tema scuro ha
/// 4 varianti selezionabili (v. [DarkThemeVariant]), ognuna con un proprio
/// colore-chiave invece di essere una semplice inversione del verde chiaro.
class AppTheme {
  AppTheme._();

  static const _lightSeedColor = Color(0xFF2E7D5B); // verde: coerente col tema "finanze"

  /// Font dedicato agli importi in denaro mostrati in evidenza (saldo,
  /// liste, grafici). Richiesto "Aptos Display", non liberamente
  /// ridistribuibile (font proprietario Microsoft): Public Sans è
  /// l'alternativa scelta, licenza OFL (v. assets/fonts/PublicSans-LICENSE.md),
  /// stile analogo e ottime cifre tabulari per allineare le colonne di importi.
  static TextStyle amountStyle([TextStyle? base]) {
    return (base ?? const TextStyle()).merge(
      const TextStyle(
        fontFamily: 'PublicSans',
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  /// Coppia di colori per avvisi non critici (es. "nessun budget impostato").
  /// Material 3 non ha un ruolo semantico "warning" nel ColorScheme generato
  /// dal seed (solo error/primary/secondary/tertiary): un giallo/ambra fisso,
  /// indipendente dal seed e dalla variante scura attiva, comunica meglio
  /// "attenzione" rispetto a una Card che si confonde con lo sfondo.
  static Color warningContainer(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF4D3D00)
        : const Color(0xFFFFF3C0);
  }

  static Color onWarningContainer(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFE485)
        : const Color(0xFF6B4E00);
  }

  static ThemeData get light => _buildTheme(
        brightness: Brightness.light,
        seedColor: _lightSeedColor,
        contrastLevel: 0.5, // "medium contrast" M3: testo più leggibile, stessa identità
      );

  static ThemeData darkVariant(DarkThemeVariant variant) => _buildTheme(
        brightness: Brightness.dark,
        seedColor: variant.seedColor,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color seedColor,
    double contrastLevel = 0.0,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      contrastLevel: contrastLevel,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      // Animazioni leggere e coerenti tra le pagine (v. progettazione).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
