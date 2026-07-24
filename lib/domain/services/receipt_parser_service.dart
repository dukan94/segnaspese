/// Risultato dell'analisi del testo di uno scontrino.
class ParsedReceipt {
  const ParsedReceipt({
    required this.rawText,
    this.merchantName,
    this.total,
  });

  /// Testo grezzo di partenza (OCR su mobile, incollato a mano su desktop).
  final String rawText;

  /// Nome del negozio individuato (euristica), null se non riconosciuto.
  final String? merchantName;

  /// Totale individuato, null se non riconosciuto.
  final double? total;

  bool get hasAnyData => merchantName != null || total != null;
}

/// Estrae negozio e totale dal testo di uno scontrino.
///
/// Logica pura (nessuna dipendenza da Flutter/OCR): la stessa funzione serve
/// sia al testo prodotto dall'OCR su mobile sia al testo incollato a mano nei
/// test su desktop. È volutamente euristica e tollerante: in caso di dubbio
/// l'utente corregge nella schermata di conferma.
class ReceiptParserService {
  const ReceiptParserService();

  /// Numeri in formato monetario CON due decimali: "42,80", "1.234,56",
  /// "12.34". Usato nel ripiego, per non catturare quantità o codici interi.
  static final RegExp _amount = RegExp(r'\d+(?:[.,]\d{3})*[.,]\d{2}');

  /// Numeri monetari con decimali OPZIONALI: "42,80", "1.299,00", ma anche
  /// "10" o "8". Usato solo sulle righe del totale, dove il numero è per forza
  /// l'importo (così un totale scritto senza decimali viene comunque letto).
  static final RegExp _money = RegExp(r'\d+(?:[.\s]\d{3})*(?:[.,]\d{2})?');

  ParsedReceipt parse(String rawText) {
    return ParsedReceipt(
      rawText: rawText,
      merchantName: extractMerchant(rawText),
      total: extractTotal(rawText),
    );
  }

  /// Totale: privilegia le righe con parole chiave ("totale", "importo"...),
  /// escludendo subtotali/parziali/IVA. Se non trova nulla, ripiega
  /// sull'importo monetario più alto presente nel testo.
  double? extractTotal(String text) {
    final lines = text.split('\n');
    final keyword =
        RegExp(r'total|importo|tot\.?\b|da pagare', caseSensitive: false);
    // Righe con parole chiave ma che NON sono il totale in denaro
    // (subtotali, IVA, conteggio articoli, punti fedeltà, pagamento...).
    final exclude = RegExp(
      r'subtot|parzial|iva|resto|contant|carta|articol|pezz|punti|sconto|numero',
      caseSensitive: false,
    );

    double? fromKeyword;
    for (final line in lines) {
      if (keyword.hasMatch(line) && !exclude.hasMatch(line)) {
        final amt = _lastMoneyIn(line);
        // L'ultima riga-chiave con un importo vince: sugli scontrini il
        // "TOTALE" definitivo è di norma verso il fondo.
        if (amt != null) fromKeyword = amt;
      }
    }
    if (fromKeyword != null) return fromKeyword;

    double? max;
    for (final match in _amount.allMatches(text)) {
      final value = _parseAmount(match.group(0)!);
      if (value != null && (max == null || value > max)) max = value;
    }
    return max;
  }

  /// Nome negozio: prima riga "significativa" in cima allo scontrino,
  /// saltando date, indirizzi, partita IVA e righe quasi solo numeriche.
  String? extractMerchant(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final skip = RegExp(
      r'(^(via|v\.le|viale|p\.?zza|piazza|corso|c\.so|str\.?|strada)\b)'
      r'|(p\.?\s*iva)|(partita iva)|(cod\.?\s*fisc)|scontrino|documento'
      r'|ricevuta|(\btel\.?\b)|(\bn\.?\s*\d)',
      caseSensitive: false,
    );
    final dateLike = RegExp(r'\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}');
    final letters = RegExp(r'[A-Za-zÀ-ÿ]');

    for (final line in lines.take(6)) {
      if (letters.allMatches(line).length < 2) continue;
      if (dateLike.hasMatch(line)) continue;
      if (skip.hasMatch(line)) continue;
      return line;
    }

    // Fallback: prima riga che contiene una parola di almeno 2 lettere.
    for (final line in lines) {
      if (RegExp(r'[A-Za-zÀ-ÿ]{2,}').hasMatch(line)) return line;
    }
    return null;
  }

  /// Ultimo importo su una riga del totale, accettando anche gli interi
  /// (v. [_money]).
  double? _lastMoneyIn(String line) {
    double? last;
    for (final match in _money.allMatches(line)) {
      final value = _parseAmount(match.group(0)!);
      if (value != null) last = value;
    }
    return last;
  }

  /// Converte un token monetario in double, deducendo il separatore decimale
  /// (l'ultimo tra '.' e ',') e rimuovendo quello delle migliaia.
  double? _parseAmount(String token) {
    var s = token.replaceAll(RegExp(r'\s'), '');
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    final decimalSep = lastComma > lastDot ? ',' : '.';
    final thousandsSep = decimalSep == ',' ? '.' : ',';
    s = s.replaceAll(thousandsSep, '').replaceAll(decimalSep, '.');
    return double.tryParse(s);
  }
}
