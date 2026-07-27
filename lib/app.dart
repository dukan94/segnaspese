import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/sync_providers.dart';
import 'core/di/theme_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

/// Widget radice dell'app: Material 3, tema chiaro/scuro scelto dall'utente
/// in Impostazioni > Tema (default "segui sistema"), routing dichiarativo
/// con go_router.
///
/// Localizzazione forzata in italiano: senza `localizationsDelegates` /
/// `supportedLocales`, i widget di sistema (DatePicker, ecc.) usano
/// l'inglese di default, con settimana che parte da domenica.
class FinanceApp extends ConsumerStatefulWidget {
  const FinanceApp({super.key});

  @override
  ConsumerState<FinanceApp> createState() => _FinanceAppState();
}

class _FinanceAppState extends ConsumerState<FinanceApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Oltre alla sync all'avvio e ogni 5 minuti (v. main.dart), sincronizza
  /// anche quando l'app va in background/si chiude e quando torna in primo
  /// piano: senza questo, dati inseriti poco prima di chiudere l'app (es. un
  /// budget appena impostato) potevano restare solo locali, mai arrivati su
  /// Turso, e quindi "persi" agli occhi degli altri dispositivi.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.resumed) {
      ref.read(syncServiceProvider).syncNow().catchError((Object e, StackTrace st) {
        debugPrint('Sync Turso fallita (lifecycle $state): $e\n$st');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // .valueOrNull come fallback di rendering è corretto qui (l'app deve
    // comunque mostrare un tema anche se la lettura fallisce), ma va
    // loggato: altrimenti un errore reale si confonde silenziosamente con
    // "nessuna preferenza salvata" (lo stesso difetto del bug tema già
    // risolto, qui per qualunque altra causa d'errore dello stream).
    final themeModeAsync = ref.watch(themeModeProvider);
    if (themeModeAsync.hasError) {
      debugPrint('Errore lettura tema: ${themeModeAsync.error}');
    }
    final themeMode = themeModeAsync.valueOrNull ?? ThemeMode.system;

    final darkVariantAsync = ref.watch(darkVariantProvider);
    if (darkVariantAsync.hasError) {
      debugPrint('Errore lettura variante scura: ${darkVariantAsync.error}');
    }
    final darkVariant = darkVariantAsync.valueOrNull ?? DarkThemeVariant.boscoNotturno;

    return MaterialApp.router(
      title: 'Finanze',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.darkVariant(darkVariant),
      themeMode: themeMode,
      locale: const Locale('it'),
      supportedLocales: const [Locale('it')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: appRouter,
    );
  }
}
