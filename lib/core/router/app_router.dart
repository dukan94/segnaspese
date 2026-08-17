import 'package:go_router/go_router.dart';

import '../../presentation/home/home_page.dart';
import '../../presentation/history/history_page.dart';
import '../../presentation/transaction/add_transaction_page.dart';
import '../../presentation/receipt/receipt_scan_page.dart';
import '../../presentation/dashboard/dashboard_page.dart';
import '../../presentation/recurring/recurring_list_page.dart';
import '../../presentation/recurring/recurring_edit_page.dart';
import '../../domain/entities/recurring_entity.dart';
import '../../presentation/budget/budget_page.dart';
import '../../presentation/budget/budget_month_page.dart';
import '../../presentation/altro/altro_page.dart';
import '../../presentation/settings/settings_page.dart';
import '../../presentation/settings/categories_manage_page.dart';
import '../../presentation/settings/merchant_rules_page.dart';
import '../../presentation/settings/import_page.dart';
import '../../presentation/settings/export_page.dart';
import '../../presentation/statement_import/statement_import_page.dart';
import '../../presentation/settings/sync_page.dart';
import '../../presentation/settings/theme_page.dart';
import '../../presentation/settings/gemini_page.dart';
import '../../presentation/settings/admin_page.dart';
import '../../presentation/shared_widgets/root_scaffold.dart';

/// Configurazione di navigazione dell'app.
///
/// Bottom navigation a 4 voci (Home | Dashboard | Budget | Altro). Le sezioni
/// secondarie (Storico, Ricorrenze, Impostazioni) non sono tab: sono
/// raggruppate sotto "Altro" e si aprono a schermo intero come route
/// top-level (con pulsante Indietro), fuori dallo StatefulShellRoute. In
/// questo modo i loro percorsi restano invariati (es. /settings/categories),
/// e la barra non supera le 5 voci consigliate da Material.
final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return RootScaffold(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomePage(),
              routes: [
                GoRoute(
                  path: 'add-transaction',
                  builder: (context, state) => const AddTransactionPage(),
                ),
                GoRoute(
                  path: 'scan-receipt',
                  builder: (context, state) => const ReceiptScanPage(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) => const DashboardPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/budget',
              builder: (context, state) => const BudgetPage(),
              routes: [
                GoRoute(
                  path: 'month/:year/:month',
                  builder: (context, state) => BudgetMonthPage(
                    year: int.parse(state.pathParameters['year']!),
                    month: int.parse(state.pathParameters['month']!),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/altro',
              builder: (context, state) => const AltroPage(),
            ),
          ],
        ),
      ],
    ),

    // --- Sezioni secondarie (fuori dallo shell): si aprono a schermo intero
    // sopra la barra, con pulsante Indietro automatico. ---
    GoRoute(
      path: '/history',
      // `extra` opzionale (String?): query di ricerca precompilata, usata dal
      // doppio click su categoria/sottocategoria in Dashboard (M34).
      builder: (context, state) =>
          HistoryPage(initialQuery: state.extra as String?),
    ),
    GoRoute(
      path: '/recurring',
      builder: (context, state) => const RecurringListPage(),
      routes: [
        GoRoute(
          path: 'new',
          builder: (context, state) => const RecurringEditPage(),
        ),
        GoRoute(
          path: 'edit',
          builder: (context, state) => RecurringEditPage(
            existing: state.extra as RecurringEntity?,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
      routes: [
        GoRoute(
          path: 'categories',
          builder: (context, state) => const CategoriesManagePage(),
        ),
        GoRoute(
          path: 'rules',
          builder: (context, state) => const MerchantRulesPage(),
        ),
        GoRoute(
          path: 'import',
          builder: (context, state) => const ImportPage(),
        ),
        GoRoute(
          path: 'statement-import',
          builder: (context, state) => const StatementImportPage(),
        ),
        GoRoute(
          path: 'export',
          builder: (context, state) => const ExportPage(),
        ),
        GoRoute(
          path: 'sync',
          builder: (context, state) => const SyncPage(),
        ),
        GoRoute(
          path: 'gemini',
          builder: (context, state) => const GeminiPage(),
        ),
        GoRoute(
          path: 'theme',
          builder: (context, state) => const ThemePage(),
        ),
        GoRoute(
          path: 'admin',
          builder: (context, state) => const AdminPage(),
        ),
      ],
    ),
  ],
);
