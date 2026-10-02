import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

/// Riga transazione "piatta", senza isolamento grafico per riga (M57,
/// stile scelto da Mario dopo un confronto A/B, v. `progettazione_
/// finance_app.md`) — sostituisce sia la card dello Storico (M36) sia il
/// `ListTile` della Home: nessun riquadro/elevazione per riga, solo un
/// filo sottile (`Divider`) a separare una transazione dalla successiva,
/// come un estratto conto. Condiviso tra Storico e Home apposta per non
/// avere due design diversi per lo stesso concetto (incoerenza segnalata
/// da Mario).
///
/// Il verde di sfondo per le entrate (M30) non c'è più: in una lista
/// piatta un intero rettangolo colorato per riga tornerebbe a isolare
/// visivamente quella riga dalle altre, lo stesso effetto che questo
/// redesign vuole evitare — il segno (+/verde vs -/rosso) resta solo
/// sull'importo, come un estratto conto.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.meta,
    required this.date,
    required this.amount,
    required this.onTap,
    this.badge,
    this.trailingActions,
  });

  /// Emoji della categoria (o 💶 di ripiego).
  final String icon;

  /// Colore della categoria, sfondo del cerchietto icona.
  final int iconColor;

  /// Nota della transazione, o nome categoria se la nota è vuota.
  final String title;

  /// Riga informativa sotto il titolo (sottocategoria/categoria + tag
  /// "Rimborso"/"Straordinaria" colorati) — costruita dal chiamante con
  /// [buildMetaLine], così ogni pagina decide quali informazioni includere
  /// senza che questo widget debba conoscerle tutte.
  final InlineSpan meta;

  /// Es. "21 ott", sotto l'importo.
  final String date;

  /// Importo con segno (v. `TransactionEntity.signedAmount`).
  final double amount;

  final VoidCallback onTap;

  /// Badge tondo opzionale accanto al titolo (es. "spesa già rimborsata",
  /// tappabile per vedere i rimborsi collegati) — stesso concetto di M30,
  /// solo a fianco del titolo invece che della Nota in una card.
  final Widget? badge;

  /// Azioni a destra (menu "⋮" in Storico, icone dirette in Home) — ogni
  /// pagina passa le proprie, questo widget non ne assume la forma.
  final Widget? trailingActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = amount >= 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Color(iconColor),
              child: Text(icon, style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        badge!,
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text.rich(
                    meta,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppFormatters.signedCurrency(amount),
                  style:
                      AppTheme.amountStyle(theme.textTheme.bodyMedium?.copyWith(
                    color: positive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  )),
                ),
                Text(
                  date,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            if (trailingActions != null) ...[
              const SizedBox(width: 2),
              trailingActions!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Filo sottile tra una riga e la successiva (M57) — stesso colore ovunque
/// sia usato `TransactionRow`, un solo punto da cambiare.
const transactionRowDivider = Divider(height: 1, thickness: 1);

/// Costruisce la riga informativa sotto il titolo: [leading] (sottocategoria
/// o nome categoria) in colore neutro, seguito dai tag colorati richiesti
/// — "Rimborso" nel colore primario del tema, "Straordinaria" nello stesso
/// giallo/ambra già usato per gli avvisi non critici (`AppTheme.
/// warningContainer`). Un'unica implementazione condivisa invece di
/// duplicare la logica di colore tra Storico e Home.
InlineSpan buildMetaLine(
  BuildContext context, {
  String? leading,
  bool isRefund = false,
  bool isExtraordinary = false,
}) {
  final theme = Theme.of(context);
  final parts = <InlineSpan>[];

  void addSeparatorIfNeeded() {
    if (parts.isNotEmpty) {
      parts.add(const TextSpan(text: ' · '));
    }
  }

  if (leading != null && leading.isNotEmpty) {
    parts.add(TextSpan(text: leading));
  }
  if (isRefund) {
    addSeparatorIfNeeded();
    parts.add(TextSpan(
      text: 'Rimborso',
      style: TextStyle(
          color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
    ));
  }
  if (isExtraordinary) {
    addSeparatorIfNeeded();
    parts.add(TextSpan(
      text: 'Straordinaria',
      style: TextStyle(
          color: AppTheme.onWarningContainer(context),
          fontWeight: FontWeight.w500),
    ));
  }

  return TextSpan(children: parts);
}
