import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class FinanceApp extends ConsumerWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final darkVariant = ref.watch(darkVariantProvider).valueOrNull ?? DarkThemeVariant.boscoNotturno;

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
