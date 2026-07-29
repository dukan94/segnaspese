import 'package:async/async.dart';
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> insertCategory(String name) {
    return db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: name,
            icon: '🏷️',
            type: TransactionKind.expense,
            color: 0xFF000000,
          ),
        );
  }

  test('senza ordine salvato, le categorie restano nell\'ordine di inserimento (per id)', () async {
    await insertCategory('Casa');
    await insertCategory('Auto');
    await insertCategory('Spesa');

    final result = await db.categoryDao.watchByType(TransactionKind.expense).first;

    expect(result.map((c) => c.name).toList(), ['Casa', 'Auto', 'Spesa']);
  });

  test('reorderCategories applica l\'ordine manuale salvato', () async {
    final casa = await insertCategory('Casa');
    final auto = await insertCategory('Auto');
    final spesa = await insertCategory('Spesa');

    await db.categoryDao.reorderCategories(TransactionKind.expense, [spesa, casa, auto]);

    final result = await db.categoryDao.watchByType(TransactionKind.expense).first;
    expect(result.map((c) => c.name).toList(), ['Spesa', 'Casa', 'Auto']);
  });

  test('una categoria creata dopo il salvataggio dell\'ordine viene accodata alla fine', () async {
    final casa = await insertCategory('Casa');
    final auto = await insertCategory('Auto');
    await db.categoryDao.reorderCategories(TransactionKind.expense, [auto, casa]);

    await insertCategory('Svago'); // non presente nell'ordine salvato

    final result = await db.categoryDao.watchByType(TransactionKind.expense).first;
    expect(result.map((c) => c.name).toList(), ['Auto', 'Casa', 'Svago']);
  });

  test('un id nell\'ordine salvato che non esiste più viene ignorato senza errori', () async {
    final casa = await insertCategory('Casa');
    const idFantasma = 9999;
    await db.categoryDao.reorderCategories(TransactionKind.expense, [idFantasma, casa]);

    final result = await db.categoryDao.watchByType(TransactionKind.expense).first;
    expect(result.map((c) => c.name).toList(), ['Casa']);
  });

  test('softDeleteCategory cancella in cascata anche le sue sottocategorie', () async {
    final casaId = await insertCategory('Casa');
    final bolletteId = await db.into(db.subCategories).insert(
          SubCategoriesCompanion.insert(categoryId: casaId, name: 'Bollette'),
        );
    final affittoId = await db.into(db.subCategories).insert(
          SubCategoriesCompanion.insert(categoryId: casaId, name: 'Affitto'),
        );

    await db.categoryDao.softDeleteCategory(casaId);

    final category = await (db.select(db.categories)..where((c) => c.id.equals(casaId))).getSingle();
    expect(category.isDeleted, isTrue);

    final subCategories = await (db.select(db.subCategories)
          ..where((s) => s.id.isIn([bolletteId, affittoId])))
        .get();
    expect(subCategories.every((s) => s.isDeleted), isTrue);
  });

  test('softDeleteCategory non tocca le sottocategorie di un\'altra categoria', () async {
    final casaId = await insertCategory('Casa');
    final autoId = await insertCategory('Auto');
    final carburanteId = await db.into(db.subCategories).insert(
          SubCategoriesCompanion.insert(categoryId: autoId, name: 'Carburante'),
        );

    await db.categoryDao.softDeleteCategory(casaId);

    final carburante = await (db.select(db.subCategories)..where((s) => s.id.equals(carburanteId))).getSingle();
    expect(carburante.isDeleted, isFalse);
  });

  group('reattività del riordino su uno stream già in ascolto (senza riavviare l\'app)', () {
    // Prima del fix, questi stream erano costruiti solo sulla query di
    // categorie/sottocategorie: Drift li riemette in base alle sole tabelle
    // che quella query tocca, quindi una scrittura che cambia SOLO l'ordine
    // salvato (tabella Settings) non li faceva ripartire — l'ordine nuovo si
    // vedeva solo dopo un riavvio dell'app (bug segnalato dall'utente).

    test('watchByType riemette con il nuovo ordine appena si chiama reorderCategories', () async {
      final casa = await insertCategory('Casa');
      final auto = await insertCategory('Auto');
      final queue = StreamQueue(db.categoryDao.watchByType(TransactionKind.expense));

      final first = await queue.next;
      expect(first.map((c) => c.name).toList(), ['Casa', 'Auto']);

      await db.categoryDao.reorderCategories(TransactionKind.expense, [auto, casa]);

      final second = await queue.next;
      expect(second.map((c) => c.name).toList(), ['Auto', 'Casa']);

      await queue.cancel();
    });

    test('watchSubCategories riemette con il nuovo ordine appena si chiama reorderSubCategories', () async {
      final casaId = await insertCategory('Casa');
      final bollette = await db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(categoryId: casaId, name: 'Bollette'),
          );
      final affitto = await db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(categoryId: casaId, name: 'Affitto'),
          );
      final queue = StreamQueue(db.categoryDao.watchSubCategories(casaId));

      final first = await queue.next;
      expect(first.map((s) => s.name).toList(), ['Bollette', 'Affitto']);

      await db.categoryDao.reorderSubCategories(casaId, [affitto, bollette]);

      final second = await queue.next;
      expect(second.map((s) => s.name).toList(), ['Affitto', 'Bollette']);

      await queue.cancel();
    });

    test('watchSubCategoriesForType riemette con il nuovo ordine (categorie e sottocategorie) senza ricreare la subscription', () async {
      final casaId = await insertCategory('Casa');
      final autoId = await insertCategory('Auto');
      final bollette = await db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(categoryId: casaId, name: 'Bollette'),
          );
      final affitto = await db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(categoryId: casaId, name: 'Affitto'),
          );
      final queue = StreamQueue(db.categoryDao.watchSubCategoriesForType(TransactionKind.expense));

      final first = await queue.next;
      expect(first.map((i) => '${i.category.name}/${i.subCategory.name}').toList(),
          ['Casa/Bollette', 'Casa/Affitto']);

      // Riordina prima le categorie (Auto prima di Casa): tocca solo
      // Settings, nessuna riga di Categories/SubCategories.
      await db.categoryDao.reorderCategories(TransactionKind.expense, [autoId, casaId]);
      final second = await queue.next;
      expect(second.map((i) => '${i.category.name}/${i.subCategory.name}').toList(),
          ['Casa/Bollette', 'Casa/Affitto'],
          reason: 'categoria riordinata, sottocategorie di Casa ancora nell\'ordine originale');

      // Poi le sottocategorie di Casa (Affitto prima di Bollette): stessa
      // storia, solo Settings.
      await db.categoryDao.reorderSubCategories(casaId, [affitto, bollette]);
      final third = await queue.next;
      expect(third.map((i) => '${i.category.name}/${i.subCategory.name}').toList(),
          ['Casa/Affitto', 'Casa/Bollette']);

      await queue.cancel();
    });
  });
}
