import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/announcement.dart';
import 'package:qr_scan_industry/src/model/notification.dart';
import 'package:qr_scan_industry/src/notifications/feed_order.dart';

/// «Уведомления»: объявления идут в одном ряду с уведомлениями по времени,
/// новые сверху, без подъёма важных (решение 19.11).
void main() {
  final base = DateTime.utc(2026, 11, 19, 12);

  Announcement announcement(String uuid, int minutes,
          {String importance = 'normal'}) =>
      Announcement(
        uuid: uuid,
        title: uuid,
        body: '',
        importance: importance,
        visibleFrom: base.add(Duration(minutes: minutes)),
      );

  AppNotification notification(String uuid, int minutes) => AppNotification(
        uuid: uuid,
        notificationType: 'repair_assigned',
        title: uuid,
        description: '',
        status: 'new',
        isRead: false,
        readAt: null,
        createdAt: base.add(Duration(minutes: minutes)),
        updatedAt: null,
        priority: null,
        priorityDisplay: null,
        equipmentUuid: null,
        equipmentName: null,
        inspectionUuid: null,
        responsibleUserUuid: null,
        responsibleUserFullname: null,
        targetScope: null,
        canOpenTarget: true,
        payload: const {},
      );

  String key(FeedItem item) =>
      item.announcement?.uuid ?? item.notification!.uuid;

  test('по времени, новые сверху — объявления вперемешку с уведомлениями', () {
    final feed = mergeFeed(
      [announcement('a-old', 1), announcement('a-new', 30)],
      [notification('n-mid', 10), notification('n-newest', 40)],
    );
    expect(feed.map(key), ['n-newest', 'a-new', 'n-mid', 'a-old']);
  });

  test('важное не поднимается выше более свежего', () {
    final feed = mergeFeed(
      [announcement('important', 1, importance: 'important')],
      [notification('fresh', 5)],
    );
    expect(feed.map(key), ['fresh', 'important']);
  });

  test('одинаковое время — порядок по uuid, не прыгает', () {
    final feed = mergeFeed(
      [announcement('b', 5)],
      [notification('a', 5), notification('c', 5)],
    );
    expect(feed.map(key), ['a', 'b', 'c']);
  });

  test('объявление без даты начала — в конце', () {
    final feed = mergeFeed(
      [const Announcement(uuid: 'undated', title: 't', body: '')],
      [notification('n', 0)],
    );
    expect(feed.map(key), ['n', 'undated']);
  });
}
