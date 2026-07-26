/// Tipo di movimento, usato in tutto il layer di dominio.
enum TransactionType { income, expense }

/// Rappresentazione di dominio di un movimento (entrata o uscita).
///
/// Non dipende da Drift né da Flutter: è l'oggetto che circola tra
/// UseCase, Repository (interfacce) e Presentation.
class TransactionEntity {
  final int? id;
  final DateTime date;
  final double amount;
  final TransactionType type;
  final int categoryId;
  final int? subCategoryId;
  final int? merchantId;
  final String? note;
  final String? receiptImagePath;
  final int? recurringId;

  /// Se questa transazione è un rimborso collegato a una spesa esistente,
  /// è l'id di quella spesa. null = rimborso non collegato o spesa normale.
  final int? refundOfId;

  /// Spesa/entrata "una tantum" (straordinaria).
  final bool isExtraordinary;

  /// Rimborso ricevuto su una spesa (sottrae dalla propria categoria di spesa).
  final bool isRefund;

  const TransactionEntity({
    this.id,
    required this.date,
    required this.amount,
    required this.type,
    required this.categoryId,
    this.subCategoryId,
    this.merchantId,
    this.note,
    this.receiptImagePath,
    this.recurringId,
    this.refundOfId,
    this.isExtraordinary = false,
    this.isRefund = false,
  });

  /// Importo con segno, utile per i calcoli di saldo: positivo per le entrate,
  /// negativo per le uscite, ma positivo per i rimborsi (soldi che rientrano).
  double get signedAmount {
    if (type == TransactionType.income) return amount;
    return isRefund ? amount : -amount;
  }

  /// Contributo alla spesa della propria categoria: normale = +importo,
  /// rimborso = −importo (netta la spesa). Da usare solo sulle uscite.
  double get netExpense => isRefund ? -amount : amount;

  TransactionEntity copyWith({
    int? id,
    DateTime? date,
    double? amount,
    TransactionType? type,
    int? categoryId,
    int? subCategoryId,
    int? merchantId,
    String? note,
    String? receiptImagePath,
    int? recurringId,
    int? refundOfId,
    bool? isExtraordinary,
    bool? isRefund,
  }) {
    return TransactionEntity(
      id: id ?? this.id,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      subCategoryId: subCategoryId ?? this.subCategoryId,
      merchantId: merchantId ?? this.merchantId,
      note: note ?? this.note,
      receiptImagePath: receiptImagePath ?? this.receiptImagePath,
      recurringId: recurringId ?? this.recurringId,
      refundOfId: refundOfId ?? this.refundOfId,
      isExtraordinary: isExtraordinary ?? this.isExtraordinary,
      isRefund: isRefund ?? this.isRefund,
    );
  }
}
