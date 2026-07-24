import 'package:intl/intl.dart';

/// Formattatori condivisi da tutta la Presentation (valuta/data), per
/// evitare di istanziare `NumberFormat`/`DateFormat` sparsi nei widget.
class AppFormatters {
  AppFormatters._();

  static final _currency = NumberFormat.currency(
    locale: 'it_IT',
    symbol: '€',
    decimalDigits: 2,
  );

  static final _shortDate = DateFormat('d MMM yyyy', 'it_IT');
  static final _dayMonth = DateFormat('d MMM', 'it_IT');
  static final _monthName = DateFormat('MMMM', 'it_IT');
  static final _monthYear = DateFormat('MMMM yyyy', 'it_IT');

  /// Es. "1.450,00 €". Il segno (+/-) va gestito dal chiamante in base al
  /// tipo di movimento, se necessario (v. [TransactionEntity.signedAmount]).
  static String currency(double amount) => _currency.format(amount);

  /// Es. "+1.450,00 €" / "-42,80 €", utile per liste di transazioni.
  static String signedCurrency(double amount) {
    final formatted = _currency.format(amount.abs());
    return amount < 0 ? '-$formatted' : '+$formatted';
  }

  /// Es. "23 lug 2026".
  static String shortDate(DateTime date) => _shortDate.format(date);

  /// Es. "23 lug", usato dove l'anno è ridondante (liste recenti).
  static String dayMonth(DateTime date) => _dayMonth.format(date);

  /// Nome del mese, es. "luglio". Accetta anno/mese così da poterlo usare con
  /// gli indici della vista Budget.
  static String monthName(int year, int month) =>
      _monthName.format(DateTime(year, month));

  /// Es. "luglio 2026".
  static String monthYear(int year, int month) =>
      _monthYear.format(DateTime(year, month));
}
