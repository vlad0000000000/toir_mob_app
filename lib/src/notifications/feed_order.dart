import '../model/announcement.dart';
import '../model/notification.dart';

/// Элемент общего списка «Уведомлений»: объявление или уведомление — ровно
/// одно из двух.
typedef FeedItem = ({
  Announcement? announcement,
  AppNotification? notification
});

/// Время элемента в ленте: у уведомления — когда создано, у объявления —
/// когда начался показ (тогда оно и «пришло»). Без даты — самое старое.
DateTime _feedTime(FeedItem item) =>
    item.notification?.createdAt ??
    item.announcement?.visibleFrom ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

String _feedKey(FeedItem item) =>
    item.notification?.uuid ?? item.announcement!.uuid;

/// Объявления и уведомления одним списком по времени, новые сверху (решение
/// 19.11): объявление встаёт туда же, куда встало бы уведомление, пришедшее
/// в ту же минуту, — без подъёма важных. Важность видна пилюлей на карточке.
///
/// Тай-брейк — по uuid, как у самих уведомлений (`_sortNotifications`):
/// иначе при одинаковом времени карточки менялись бы местами на каждом
/// перечитывании.
List<FeedItem> mergeFeed(
  List<Announcement> announcements,
  List<AppNotification> notifications,
) {
  final items = <FeedItem>[
    for (final a in announcements) (announcement: a, notification: null),
    for (final n in notifications) (announcement: null, notification: n),
  ];
  items.sort((a, b) {
    final byTime = _feedTime(b).compareTo(_feedTime(a));
    if (byTime != 0) return byTime;
    return _feedKey(a).compareTo(_feedKey(b));
  });
  return items;
}
