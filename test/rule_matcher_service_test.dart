import 'package:finance_app/domain/entities/merchant_rule_entity.dart';
import 'package:finance_app/domain/services/rule_matcher_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const matcher = RuleMatcherService();

  const esselunga = MerchantRuleEntity(
    id: 1,
    pattern: r'ESSEL.*',
    categoryId: 10,
    subCategoryId: 100,
    priority: 0,
  );
  const generic = MerchantRuleEntity(
    id: 2,
    pattern: r'.*',
    categoryId: 99,
    priority: 0,
  );
  const highPriority = MerchantRuleEntity(
    id: 3,
    pattern: r'ESSEL.*',
    categoryId: 42,
    priority: 10,
  );

  test('trova la regola con pattern corrispondente (case-insensitive)', () {
    final match = matcher.match('scontrino esselunga spa', [esselunga]);
    expect(match?.categoryId, 10);
  });

  test('a parità di match vince la priorità più alta', () {
    final match = matcher.match('ESSELUNGA', [esselunga, highPriority]);
    expect(match?.categoryId, 42);
  });

  test('nessuna corrispondenza → null', () {
    final match = matcher.match('PANIFICIO ROSSI', [esselunga]);
    expect(match, isNull);
  });

  test('un pattern regex non valido non fa fallire il matching', () {
    const invalid = MerchantRuleEntity(
      id: 4,
      pattern: r'[invalid(regex',
      categoryId: 1,
      priority: 100,
    );
    final match = matcher.match('ESSELUNGA', [invalid, esselunga]);
    expect(match?.categoryId, 10);
  });

  test('testo vuoto → null', () {
    expect(matcher.match('', [generic]), isNull);
  });
}
