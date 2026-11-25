import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/announcement.dart';
import 'package:qr_scan_industry/src/notifications/announcement_card.dart';
import 'package:qr_scan_industry/strings.dart';

/// Объявление в «Уведомлениях» — карточка того же вида, что уведомление
/// (решение 19.11): подпись типа, заголовок, пилюли, срок показа; нажатие
/// открывает окно снизу с полным текстом.
void main() {
  final until = DateTime.now().add(const Duration(days: 3));

  Announcement announcement({
    String kind = 'custom',
    String importance = 'important',
    String? version,
    String? url,
    DateTime? readAt,
    DateTime? visibleUntil,
  }) =>
      Announcement(
        uuid: 'a-1',
        title: 'Плановые работы',
        body: 'Сервер будет недоступен с 22:00 до 23:00. ' * 3,
        importance: importance,
        kind: kind,
        visibleFrom: DateTime.now().subtract(const Duration(hours: 1)),
        visibleUntil: visibleUntil ?? until,
        targetVersion: version,
        updateUrl: url,
        readAt: readAt,
      );

  Future<void> pump(WidgetTester tester, Announcement a) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [AnnouncementCard(announcement: a)]),
          ),
        ),
      );

  testWidgets('карточка — как уведомление: тип, заголовок, пилюли, срок',
      (tester) async {
    await pump(tester, announcement());

    expect(find.text('ОБЪЯВЛЕНИЕ'), findsOneWidget);
    expect(find.text('Плановые работы'), findsOneWidget);
    expect(find.text(AnnouncementStrings.statusActive), findsOneWidget);
    expect(find.text(AnnouncementStrings.important), findsOneWidget);
    expect(find.textContaining('Показывается до'), findsOneWidget);
  });

  testWidgets('объявление о новой версии — своя подпись и версия',
      (tester) async {
    await pump(
      tester,
      announcement(kind: 'release', importance: 'normal', version: '1.1.0'),
    );

    expect(find.text('ОБНОВЛЕНИЕ ПРИЛОЖЕНИЯ'), findsOneWidget);
    expect(find.text('Версия 1.1.0'), findsOneWidget);
    expect(find.text(AnnouncementStrings.important), findsNothing);
  });

  testWidgets('показ закончился — «Завершено»', (tester) async {
    await pump(
      tester,
      announcement(
        readAt: DateTime.now(),
        visibleUntil: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );

    expect(find.text(AnnouncementStrings.statusExpired), findsOneWidget);
  });

  testWidgets('нажатие — окно снизу с полным текстом и кнопкой RuStore',
      (tester) async {
    // Прочитанное: окно открывается без отметки на сервере.
    await pump(
      tester,
      announcement(
        kind: 'release',
        version: '1.1.0',
        url: 'https://www.rustore.ru/catalog/app/pakgroup.qr.scanner.prod',
        readAt: DateTime.now(),
      ),
    );

    await tester.tap(find.byType(AnnouncementCard));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text(MobileSupportStrings.update), findsOneWidget);
    expect(find.textContaining('Показывается с'), findsOneWidget);
  });

  test('активно до конца показа', () {
    final now = DateTime.utc(2026, 11, 19, 12);
    expect(
      isAnnouncementActive(
        announcement(visibleUntil: now.add(const Duration(minutes: 1))),
        now,
      ),
      isTrue,
    );
    expect(
      isAnnouncementActive(announcement(visibleUntil: now), now),
      isFalse,
    );
  });
}
