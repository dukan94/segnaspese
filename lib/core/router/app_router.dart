import 'package:go_router/go_router.dart';

import '../../presentation/home/home_page.dart';
import '../../presentation/history/history_page.dart';
import '../../presentation/transaction/add_transaction_page.dart';
import '../../presentation/receipt/receipt_scan_page.dart';
import '../../presentation/dashboard/dashboard_page.dart';
import '../../presentation/recurring/recurring_list_page.dart';
import '../../presentation/budget/budget_page.dart';
import '../../presentation/budget/budget_month_page.dart';
import '../../presentation/settings/settings_page.dart';
import '../../presentation/settings/categories_manage_page.dart';
import '../../presentation/settings/merchant_rules_page.dart';
import '../../presentation/settings/import_page.dart';
import '../../presentation/shared_widgets/root_scaffold.dart';

/// Configurazione di navigazione dell'app.
///
/// Bottom navigation a 5 voci (Home | Dashboard | Ricorrenze | Budget |
/// Impostazioni), come da wireframe approvato. Le schermate di dettaglio
/// (Nuova Operazione, Scansione Scontrino, ecc.) verranno aggiunte come
/// route push nelle milestone M1-M3.
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
              path: '/history',
              builder: (context, state) => const HistoryPage(),
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
              path: '/recurring',
              builder: (context, state) => const RecurringListPage(),
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
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
