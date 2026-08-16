import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Tema centralizzato dell'app: Material 3, un'unica identità cromatica
/// (stesso seed per chiaro e scuro, v. progettazione sezione Design) che
/// riprende l'icona dell'app — carrello ambra/arancio su sfondo crema.
/// Prima del rebranding il tema scuro aveva 4 varianti selezionabili
/// indipendenti dal chiaro: rimosse per avere un'identità unica e coerente
/// con l'icona invece che scollegata da essa.
class AppTheme {
  AppTheme._();

  /// Stesso arancione/marrone del segno nell'icona dell'app: seed sia per il
  /// tema chiaro che per lo scuro, così le due modalità restano la stessa
  /// identità invece di due palette indipendenti.
  static const _brandSeedColor = Color(0xFFC46C2A);

  /// Stesso crema di sfondo dell'icona. Il tema scuro non ha un equivalente
  /// esplicito: lì la scala di superficie generata da Material 3 dal seed
  /// (bruno caldo scuro) è già coerente, non serve fissarla a mano come qui.
  static const _brandCream = Color(0xFFFAF0E0);

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

  static ThemeData get light {
    // "medium contrast" M3 (testo più leggibile) come base per secondary/
    // tertiary/error, ma la scala di superficie e il primary generati dal
    // seed derivano verso un bruno scuro poco somigliante all'icona: qui
    // sotto vengono fissati a mano sul crema/arancio reali dell'icona.
    final base = ColorScheme.fromSeed(
      seedColor: _brandSeedColor,
      brightness: Brightness.light,
      contrastLevel: 0.5,
    );
    final colorScheme = base.copyWith(
      primary: _brandSeedColor,
      onPrimary: const Color(0xFFFFF8EE),
      primaryContainer: const Color(0xFFF0C79B),
      onPrimaryContainer: const Color(0xFF3A2410),
      surface: _brandCream,
      surfaceContainerLowest: const Color(0xFFFFFBF3),
      surfaceContainerLow: const Color(0xFFF5E8D3),
      surfaceContainer: const Color(0xFFF0DFC4),
      surfaceContainerHigh: const Color(0xFFEAD6B4),
      surfaceContainerHighest: const Color(0xFFE3CCA0),
      onSurface: const Color(0xFF2E2018),
      onSurfaceVariant: const Color(0xFF6B5C4A),
      outline: const Color(0xFFB8A68C),
    );
    return _buildTheme(colorScheme);
  }

  static ThemeData get dark => _buildTheme(
        ColorScheme.fromSeed(
          seedColor: _brandSeedColor,
          brightness: Brightness.dark,
        ),
      );

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // Componenti Material standard più compatti su desktop (Windows),
      // invariati su Android — richiesto da Mario (16 ago 2026, "elementi
      // troppo da touch" usando l'app da PC). Un solo cambio qui, nessuna
      // palette/dimensione da mantenere a mano altrove.
      visualDensity: VisualDensity.adaptivePlatformDensity,
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
