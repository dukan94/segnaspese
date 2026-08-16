import 'package:finance_app/domain/entities/transaction_entity.dart';
import 'package:finance_app/domain/usecases/transaction/build_split_refund.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const buildSplitRefund = BuildSplitRefund();
  final today = DateTime(2026, 8, 16);

  final expense = TransactionEntity(
    id: 1,
    date: DateTime(2026, 8, 10),
    amount: 50,
    type: TransactionType.expense,
    categoryId: 3,
    subCategoryId: 7,
  );

  test('divide l\'importo per il divisore ed eredita categoria/sottocategoria', () {
    final refund = buildSplitRefund(
      expense: expense,
      divisor: 2,
      today: today,
      note: 'Nicola',
    );

    expect(refund.amount, 25.0);
    expect(refund.categoryId, expense.categoryId);
    expect(refund.subCategoryId, expense.subCategoryId);
    expect(refund.type, TransactionType.expense);
    expect(refund.isRefund, isTrue);
    expect(refund.refundOfId, expense.id);
    expect(refund.date, today);
    expect(refund.note, 'Nicola');
  });

  test('arrotonda a 2 decimali una divisione non esatta', () {
    final refund = buildSplitRefund(
      expense: expense.copyWith(amount: 50),
      divisor: 3,
      today: today,
    );

    expect(refund.amount, 16.67);
  });

  test('nota vuota o solo spazi diventa null', () {
    final refund = buildSplitRefund(
      expense: expense,
      divisor: 2,
      today: today,
      note: '   ',
    );

    expect(refund.note, isNull);
  });

  test('nota assente resta null', () {
    final refund = buildSplitRefund(expense: expense, divisor: 2, today: today);

    expect(refund.note, isNull);
  });

  test('nota con spazi ai bordi viene tolta', () {
    final refund = buildSplitRefund(
      expense: expense,
      divisor: 2,
      today: today,
      note: '  Nicola  ',
    );

    expect(refund.note, 'Nicola');
  });

  test('divisore 1 non è ammesso (rimborso pieno, coperto dal flusso manuale)', () {
    expect(
      () => buildSplitRefund(expense: expense, divisor: 1, today: today),
      throwsArgumentError,
    );
  });

  test('divisore 0 o negativo non è ammesso', () {
    expect(
      () => buildSplitRefund(expense: expense, divisor: 0, today: today),
      throwsArgumentError,
    );
    expect(
      () => buildSplitRefund(expense: expense, divisor: -2, today: today),
      throwsArgumentError,
    );
  });

  test('una spesa senza id (non salvata) non è ammessa', () {
    final noId = TransactionEntity(
      date: DateTime(2026, 8, 10),
      amount: 50,
      type: TransactionType.expense,
      categoryId: 3,
    );
    expect(
      () => buildSplitRefund(expense: noId, divisor: 2, today: today),
      throwsArgumentError,
    );
  });

  test('un rimborso già esistente non può essere rimborsato a sua volta', () {
    final alreadyRefund = expense.copyWith(isRefund: true);
    expect(
      () => buildSplitRefund(expense: alreadyRefund, divisor: 2, today: today),
      throwsArgumentError,
    );
  });

  test('un\'entrata non può essere "rimborsata"', () {
    final income = expense.copyWith(type: TransactionType.income);
    expect(
      () => buildSplitRefund(expense: income, divisor: 2, today: today),
      throwsArgumentError,
    );
  });
}
