import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/subscription_blocks.dart';

/// Блокировка офлайн-входа по компании: на одном телефоне несколько
/// обходчиков одной компании, и закрыть вход нужно всем им.
void main() {
  late Map<String, String> store;
  late SubscriptionBlocks blocks;
  late DateTime clock;

  setUp(() {
    store = {};
    clock = DateTime(2026, 10, 20, 9);
    blocks = SubscriptionBlocks(
      read: (key) => store[key],
      write: (key, value) async => store[key] = value,
      delete: (key) async => store.remove(key),
      keys: () => store.keys,
      now: () => clock,
    );
  });

  void later() => clock = clock.add(const Duration(minutes: 1));

  test('блокировка компании закрывает офлайн-вход всем её обходчикам',
      () async {
    await blocks.rememberCompany('ivanov', '38');
    await blocks.rememberCompany('petrov', '38');

    await blocks.block('ivanov', 'subscription_expired');

    expect(blocks.isBlocked('ivanov'), 'subscription_expired');
    expect(blocks.isBlocked('petrov'), 'subscription_expired');
  });

  test('сотрудника другой известной компании не задевает', () async {
    await blocks.rememberCompany('ivanov', '38');
    await blocks.rememberCompany('sidorov', '41');

    await blocks.block('ivanov', 'subscription_expired');

    expect(blocks.isBlocked('sidorov'), isNull);
  });

  test('компания логина неизвестна — любая блокировка закрывает вход',
      () async {
    // Входил до появления связи «логин → компания»: мог быть из той же.
    await blocks.rememberCompany('ivanov', '38');
    await blocks.block('ivanov', 'company_deactivated');

    expect(blocks.isBlocked('old_user'), 'company_deactivated');
  });

  test('блокировка логина с неизвестной компанией закрывает всех', () async {
    await blocks.rememberCompany('sidorov', '41');

    await blocks.block('old_user', 'subscription_expired');

    expect(blocks.isBlocked('old_user'), 'subscription_expired');
    expect(blocks.isBlocked('sidorov'), 'subscription_expired');
  });

  test('онлайн-вход снимает блокировку всей компании', () async {
    await blocks.rememberCompany('ivanov', '38');
    await blocks.rememberCompany('petrov', '38');
    await blocks.block('ivanov', 'subscription_expired');

    // Тариф продлили, Петров вошёл онлайн.
    await blocks.clearCompany('petrov', '38');

    expect(blocks.isBlocked('ivanov'), isNull);
    expect(blocks.isBlocked('petrov'), isNull);
  });

  test('онлайн-вход снимает и блокировку, записанную до связи с компанией',
      () async {
    await blocks.block('old_user', 'subscription_expired');

    await blocks.rememberCompany('old_user', '38');
    await blocks.clearCompany('old_user', '38');

    expect(blocks.isBlocked('old_user'), isNull);
    expect(store, isNot(contains('subscription_blocked:old_user')));
  });

  test(
      'старая блокировка с неизвестной компанией не держит после '
      'подтверждения доступа своей компании', () async {
    // А входил до появления связи с компанией, его заблокировали.
    await blocks.block('old_user', 'subscription_expired');
    later();
    // Тариф продлили, Б вошёл онлайн — сервер подтвердил доступ его
    // компании. Блокировка А записана раньше: была той же компании — её
    // перекрыло подтверждение; была другой — к Б не относится.
    await blocks.rememberCompany('sidorov', '41');
    await blocks.clearCompany('sidorov', '41');

    expect(blocks.isBlocked('sidorov'), isNull);
    // Сам А по-прежнему не войдёт офлайн: его компания неизвестна.
    expect(blocks.isBlocked('old_user'), 'subscription_expired');
  });

  test('блокировка свежее подтверждения — держит', () async {
    await blocks.rememberCompany('sidorov', '41');
    await blocks.clearCompany('sidorov', '41');
    later();

    await blocks.block('old_user', 'subscription_expired');

    expect(blocks.isBlocked('sidorov'), 'subscription_expired');
  });

  test('без блокировок вход открыт', () {
    expect(blocks.isBlocked('anyone'), isNull);
  });
}
