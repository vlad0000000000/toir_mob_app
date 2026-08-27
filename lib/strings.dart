class Strings {
  static final locale = 'ru';

  static get back {
    return {'ru': 'Назад'}[Strings.locale];
  }

  static get cancel {
    return {'ru': 'Отмена'}[Strings.locale];
  }

  static get qrDetectFailTitle {
    return {'ru': 'Станок не найден'}[Strings.locale];
  }

  static get qrDetectFailDesc {
    return {'ru': 'Проверьте QR код актива'}[Strings.locale];
  }

  static get loginFailTitle {
    return {'ru': 'Не удалось войти'}[Strings.locale];
  }

  static get loginFailDesc {
    return {'ru': 'Проверьте логин и пароль'}[Strings.locale];
  }

  static get walkerOnlyTitle {
    return {'ru': 'Доступ запрещен'}[Strings.locale];
  }

  static get walkerOnlyDesc {
    return {'ru': 'Только обходчик может авторизироваться'}[Strings.locale];
  }

  static get noConnectionTitle {
    return {'ru': 'Нет соединения'}[Strings.locale];
  }

  static get noConnectionDesc {
    return {
      'ru':
          'Не удалось подключиться к серверу. Проверьте подключение к интернету'
    }[Strings.locale];
  }

  static get invalidCredentialsTitle {
    return {'ru': 'Неверные учетные данные'}[Strings.locale];
  }

  static get invalidCredentialsDesc {
    return {'ru': 'Неверный логин или пароль'}[Strings.locale];
  }

  static get understand {
    return {'ru': 'Понятно'}[Strings.locale];
  }

  static get addImage {
    return {'ru': 'Добавить изображение'}[Strings.locale];
  }

  static get checkDescription {
    return {'ru': 'Комментарий'}[Strings.locale];
  }

  static get problemDescription {
    return {'ru': 'Описание проблемы'}[Strings.locale];
  }

  static get finishCheck {
    return {'ru': 'Завершить осмотр'}[Strings.locale];
  }

  static get send {
    return {'ru': 'Отправить'}[Strings.locale];
  }

  static get no {
    return {'ru': 'Нет'}[Strings.locale];
  }

  static get yes {
    return {'ru': 'Да'}[Strings.locale];
  }

  static get areYouSure {
    return {'ru': 'Вы уверены?'}[Strings.locale];
  }

  static get qrResultScreenTitle {
    return {'ru': 'Завершить осмотр'}[Strings.locale];
  }

  static get inputPassword {
    return {'ru': 'Пароль'}[Strings.locale];
  }

  static get inputLogin {
    return {'ru': 'Логин'}[Strings.locale];
  }

  static get logout {
    return {'ru': 'Выйти'}[Strings.locale];
  }

  static get login {
    return {'ru': 'Войти'}[Strings.locale];
  }

  static get passwordHelp {
    return {'ru': 'Пожалуйста, введите ваш пароль'}[Strings.locale];
  }

  static get loginHelp {
    return {'ru': 'Пожалуйста, введите ваш логин'}[Strings.locale];
  }

  static get scanner {
    return {'ru': 'Сканер'}[Strings.locale];
  }

  static get tasks {
    return {'ru': 'Задачи'}[Strings.locale];
  }

  static get sync {
    return {'ru': 'Синхронизировать'}[Strings.locale];
  }

  static get uploadScans {
    return {'ru': 'Синхронизировать осмотры'}[Strings.locale];
  }

  static get syncData {
    return {'ru': 'Синхронизировать данные'}[Strings.locale];
  }

  static get priority {
    return {'ru': 'Приоритет'}[Strings.locale];
  }

  static get low {
    return {'ru': 'Низкий'}[Strings.locale];
  }

  static get medium {
    return {'ru': 'Средний'}[Strings.locale];
  }

  static get high {
    return {'ru': 'Высокий'}[Strings.locale];
  }
}

/// Строки интерфейса ремонтов — общий файл строк (п. 4.6.3 отчёта).
///
/// Отдельный класс, а не продолжение [Strings]: у той исторический стиль —
/// геттеры без типа, отдающие `String?` из карты локалей. Для новых экранов
/// это неудобно (каждое обращение требовало бы `!`), а строки с подстановкой
/// в такой стиль не укладываются вовсе. Здесь — типизированные константы и
/// функции для параметризованных строк.
class RepairStrings {
  RepairStrings._();

  // Общее
  static const String cancel = 'Отмена';
  static const String delete = 'Удалить';
  static const String send = 'Отправить';
  static const String done = 'Готово';
  static const String clearSearch = 'Очистить поиск';
  static const String nothingFound = 'Ничего не найдено';
  static const String noConnection = 'Нет связи с сервером';
  static const String equipmentUnknown = 'Оборудование не указано';

  // Статусы
  static const String statusOpen = 'Открыт';
  static const String statusUnderReview = 'На рассмотрении';
  static const String statusClosed = 'Закрыт';
  static const String statusFree = 'Свободен';

  // Список ремонтов
  static const String groupFree = 'СВОБОДНЫЕ — МОЖНО ВЗЯТЬ В РАБОТУ';
  static const String groupMine = 'МОИ РЕМОНТЫ';
  static const String listEmptyTitle = 'Ремонтов нет';
  static const String listEmptyHint =
      'Здесь появятся ремонты, за которые вы отвечаете.';
  static const String listEmptyClosedHint = 'Закрытых ремонтов пока не было.';
  static const String closedLoadFailed = 'Не удалось загрузить закрытые '
      'ремонты. Проверьте соединение и потяните вниз.';
  static const String listOfflineHint =
      'Показаны данные с последней синхронизации.';

  // Черновики офлайн-очереди
  static const String draftPill = 'Не отправлено';
  static const String draftWaiting =
      'Без связи с сервером ремонт не отправить — уйдёт сам, как только она '
      'появится. Данные можно скопировать и передать администратору.';

  /// По оборудованию уже лежит неотправленный черновик. Показывается и в
  /// карточке скана (при попытке завести ремонт), и в самой форме создания —
  /// текст один, поэтому и константа одна.
  static const String understand = 'Понятно';

  /// Оборудование занято ремонтом другого сотрудника. Такой ремонт приложение
  /// не кэширует — о нём известно только по серверному `has_open_repair`,
  /// поэтому ни номера, ни перехода в карточку предложить нельзя.
  /// Запасная подпись состояния «В ремонте» — если справочник состояний ещё
  /// не загрузился и подставить название оттуда неоткуда.
  static const String equipmentInRepair = 'В ремонте';

  static const String busyByOtherTitle = 'Оборудование в ремонте';
  static const String busyByOtherBody =
      'По этому оборудованию открыт ремонт другого сотрудника. Состояние '
      'изменится само, когда ремонт закроют.';

  static const String draftAlreadyQueuedTitle = 'Ремонт уже создан';
  static const String draftAlreadyQueuedBody =
      'Ремонт по этому оборудованию сохранён на устройстве и отправится, '
      'когда появится связь. Второй заводить не нужно.';

  static const String draftDeleteTitle = 'Удалить черновик?';

  static String draftDeleteBody(String equipmentName) =>
      'Ремонт по оборудованию «$equipmentName» не будет создан.';

  /// Черновик, чей ремонт сервер уже принял: не доехали только снимки и
  /// заполненный расход. Говорить «ремонт не будет создан» здесь нельзя —
  /// он создан, и оборудование уже числится в ремонте.
  static const String draftDeleteCreatedTitle = 'Удалить неотправленное?';

  static String draftDeleteCreatedBody(String equipmentName) =>
      'Ремонт по оборудованию «$equipmentName» уже создан на сервере — '
      'удалятся только неотправленные фотографии и расход ЗИП.';

  static const String draftDeleteCreatedNote =
      'Сам ремонт останется открытым, а оборудование — в состоянии «В '
      'ремонте». Закрыть или отменить его может только администратор.';

  /// Последствие удаления — отдельной плашкой в диалоге подтверждения.
  static const String deleteIrreversible =
      'Восстановить данные будет нельзя. Если они ещё нужны — сначала '
      'скопируйте их.';

  // Истёкшая сессия
  static const String authExpiredTitle = 'Сессия истекла';
  static const String authExpiredBody =
      'Неотправленное сохранено на устройстве. Войдите заново — отправка '
      'продолжится сама.';
  static const String authExpiredAction = 'Войти заново';

  // Форма создания
  static const String createTitle = 'Новый ремонт';
  static const String createOfflineHint =
      'Ремонт сохранится на устройстве и отправится, когда связь появится.';
  static const String createEquipmentLocked =
      'Выбрано автоматически при переводе в ремонт';
  static const String labelResponsible = 'ОТВЕТСТВЕННЫЙ';
  static const String responsibleSelf = 'Вы';
  static const String responsibleHint = 'Ремонт оформляется на вас';
  static const String labelNorm = 'НОРМА РАСХОДА ЗИП';
  static const String normNotSet = 'Не задана';
  static const String normHint =
      'Если выбрать норму, плановые количества ЗИП подставятся в ремонт';
  static const String labelStartedAt = 'ДАТА И ВРЕМЯ НАЧАЛА';
  static const String labelComment = 'КОММЕНТАРИЙ';
  static const String commentHint = 'Опишите планируемые работы…';
  static const String createSubmit = 'Создать ремонт';
  static const String createSubmitting = 'Создаём…';
  static const String createFooter =
      'Оборудование перейдёт в состояние «В ремонте»';
  static const String normSheetTitle = 'Норма расхода ЗИП';
  static const String normLoadFailed =
      'Не удалось загрузить нормы расхода. Проверьте соединение.';
  static const String normsEmpty = 'Для этого оборудования нет норм расхода';
  static const String timeSheetTitle = 'Время начала';

  /// Подпись над календарём — в том же виде, что «С даты» и «По дату» в
  /// фильтре периода: строчными, а не капсом секционной подписи формы.
  static const String labelStartedAtField = 'Дата начала';

  static String responsibleYou(String name) => '$name (вы)';

  // Окно выбора ЗИП
  static const String pickerTitle = 'Выбор ЗИП';
  static const String pickerHint = 'Поиск по названию или артикулу';
  static const String pickerAdded = 'Добавлено';
  static const String pickerCatalogEmpty = 'Справочник ЗИП ещё не загружен.';
  static const String pickerRefine = 'Попробуйте изменить запрос.';

  static String pickerAsOf(String freshness) =>
      'Поиск по сохранённому справочнику, остатки $freshness';
}

/// Строки карточки ремонта — продолжение [RepairStrings]; отдельный класс
/// только чтобы список констант оставался обозримым.
class RepairCardStrings {
  RepairCardStrings._();

  // Карточка
  static const String title = 'Ремонт';
  static const String loadFailedTitle = 'Не удалось загрузить ремонт';
  static const String loadFailedHint = 'Проверьте соединение и потяните вниз.';
  static const String staleDataBanner =
      'Показаны сохранённые данные — подробности не загрузились. Потяните '
      'вниз, чтобы повторить.';
  static const String lockedClosed =
      'Ремонт закрыт — редактирование недоступно';

  /// Формулировка из п. 4.3.14 отчёта: обходчику важно не «нельзя править», а
  /// что ремонт ушёл дальше по процессу и его смотрит человек.
  static const String lockedUnderReview =
      'Ремонт отправлен на рассмотрение, данные проверит администратор';
  static const String labelDetails = 'ДЕТАЛИ РЕМОНТА';
  static const String labelComment = 'КОММЕНТАРИЙ';
  static const String labelPhotos = 'ФОТО';
  static const String labelUnsent = 'НЕ ОТПРАВЛЕНО';

  /// Показывается, если причина отказа почему-то не сохранилась: сам факт
  /// отказа известен по пометке, а текста нет.
  static const String unsentRejectedFallback =
      'Сервер не принял данные. Попробуйте отправить ещё раз или скопируйте '
      'их и передайте администратору.';

  /// Черновик отправлен обходчиком и ждёт связи — править его больше нельзя,
  /// пока отправка не отменена.
  static const String unsentSubmitted =
      'Отправлено на рассмотрение — уйдёт, как только появится связь. Чтобы '
      'снова править, отмените отправку.';
  static const String cancelSubmit = 'Отменить отправку';
  static const String commentHint = 'Что было сделано во время ремонта';
  static const String claim = 'Взять в работу';
  static const String save = 'Сохранить';
  static const String submit = 'Отправить';

  static String titleWithId(int id) => 'Ремонт №$id';

  // Реквизиты
  static const String fieldResponsible = 'Ответственный';

  /// Должность, на которую назначен ремонт. Отдельным полем, как в админке:
  /// у ремонта могут быть одновременно и исполнитель, и должность (при
  /// «Взять в работу» сервер должность сохраняет), и склеивать их в одну
  /// строку значило бы прятать одно за другим.
  static const String fieldResponsibleRole = 'Ответственная должность';
  static const String fieldStartedAt = 'Дата начала';
  static const String fieldNorm = 'Норма расхода';
  static const String fieldDuration = 'Длительность';

  /// Момент, когда обходчик закончил работу и отправил ремонт на
  /// рассмотрение. На сервере это `under_review_at`, но для обходчика это
  /// именно окончание его работ — так поле и подписано.
  static const String fieldFinishedAt = 'Дата окончания';
  static const String normNotSet = 'Не задана';
  static const String responsibleNone = 'Не назначен';
  static const String responsibleRoleNone = 'Не назначена';

  // Результаты действий
  static const String submitted = 'Ремонт отправлен на рассмотрение';
  static const String saved = 'Изменения сохранены';
  static const String queuedSubmit =
      'Нет связи. Отправим на рассмотрение, когда она появится';
  static const String queuedSave =
      'Нет связи. Изменения сохранены на устройстве';
  static const String claimNeedsConnection =
      'Чтобы взять ремонт в работу, нужна связь с сервером';
  static const String claimed = 'Ремонт взят в работу';
  static const String normAlreadyFilled = 'Все позиции нормы уже добавлены';
  static const String photoAdded = 'Фото добавлено';
  static const String photoQueued =
      'Нет связи. Фото сохранено и отправится позже';

  // Полоса неотправленного
  static const String unsentSubmitBody =
      'Ремонт уйдёт на рассмотрение, как только появится связь.';
  static const String unsentSaveBody =
      'Сохранены на устройстве и отправятся, как только появится связь.';
  static const String draftWillSubmit =
      'Ремонт создастся и сразу уйдёт на рассмотрение, как только появится '
      'связь.';

  // Фото
  static const String photoTakeShot = 'Сделать фото';
  static const String photoFromGallery = 'Выбрать из галереи';
  static const String photoAdd = 'Добавить фото';
  static const String photosEmpty = 'Фотографии не приложены.';
  static const String close = 'Закрыть';

  // Фактический расход
  static const String consumptionTitle = 'Фактический расход ЗИП';
  static const String consumptionTooltip =
      'Указывать необязательно. Но если хотите, чтобы остатки ЗИП списались '
      'со склада автоматически, — укажите верные значения.';
  static const String consumptionWriteOffNote =
      'Указанные количества спишутся со склада, когда администратор закроет '
      'ремонт.';
  static const String consumptionEmptyNote =
      'Расход не указан — списания со склада не будет.';
  static const String addPosition = 'Добавить позицию';
  static const String fillFromNorm = 'Заполнить из нормы';
  static const String removePosition = 'Убрать позицию';

  static String positions(int count) => 'Позиций: $count';

  static String positionsWithOverNorm(int count, int overNorm) =>
      'Позиций: $count · превышений нормы: $overNorm';

  static String norm(String quantity) => 'Норма $quantity';

  static String shortage(String available) =>
      'На складе $available — при закрытии потребуется пополнение';

  static const String outOfStock =
      'Нет на складе — списывать будет нечего, потребуется пополнение';

  // Окно завершения
  static const String finishBodyPrefix = 'Ремонт перейдёт в статус ';
  static const String finishStatusUnderReview = '«На рассмотрении»';
  static const String finishBodySuffix =
      'Отредактировать расход после этого можно только через администратора. '
      'Остатки ЗИП спишутся при закрытии ремонта.';
  static const String finishNoConsumption =
      'Фактический расход не указан — списания ЗИП не будет.';
  static const String finishOffline =
      'Данные сохранены на устройстве и будут отправлены автоматически при '
      'появлении связи.';
  static const String finishAndSave = 'Завершить и сохранить';
  static const String finishCaptionPositions = 'позиции расхода';
  static const String finishCaptionOverNorm = 'превышение нормы';

  static String finishTitle(int repairId) => 'Завершить ремонт №$repairId?';

  static String countOf(int count, int total) => '$count из $total';
}

/// Строки неотправленного в карточке ремонта: причина, по которой ремонт не
/// уехал, и два действия под ней.
///
/// Раньше это был отдельный экран разрешения конфликта. Он показывал
/// комментарий и расход второй раз, поверх той же карточки, а заголовок
/// «Изменения отклонены» настоящую причину не называл. Экран убран, блок
/// переехал вниз формы — часть строк вместе с ним не понадобилась.
class ConflictStrings {
  ConflictStrings._();

  static const String copied = 'Данные скопированы';
  static const String badgeDraft = 'Черновик';

  static const String deleteTitle = 'Удалить мои данные?';
  static const String copyToClipboard = 'Скопировать данные в буфер обмена';
  static const String retry = 'Повторить отправку';

  /// Перенос в уже существующий ремонт — единственный способ не потерять
  /// введённое, когда оборудование занял ремонт самого обходчика.
  static String transferTo(int id) => 'Перенести в ремонт №$id';

  // Текст для буфера обмена. Подписи развёрнутые: сообщение читает не
  // обходчик, а администратор, у которого приложения перед глазами нет.
  static const String clipboardNewRepair = 'Новый ремонт';
  static const String clipboardEquipment = 'Оборудование:';
  static const String clipboardTypeModel = 'Тип/модель:';
  static const String clipboardStatus = 'Статус:';
  static const String clipboardNormItems = 'Состав нормы:';
  static const String clipboardComment = 'Комментарий:';
  static const String clipboardConsumption = 'Фактический расход ЗИП:';
  static const String clipboardStartedAt = 'Дата начала:';
}

/// Строки раздела ЗИП: справочник, фильтры и карточка позиции.
class SparePartStrings {
  SparePartStrings._();

  // Справочник
  static const String searchHint = 'Название или артикул';
  static const String clearSearch = 'Очистить поиск';
  static const String catalogEmptyTitle = 'Справочник ЗИП пуст';
  static const String catalogEmptyHint =
      'Справочник ещё не загружен. Потяните вниз, чтобы синхронизировать.';
  static const String nothingFound = 'Ничего не найдено';
  static const String refineHint = 'Измените запрос или сбросьте фильтры.';

  static String stockAsOf(String freshness) => 'Остатки $freshness';

  static const String freshnessJustNow = 'обновлены только что';

  static String freshnessMinutes(int minutes) =>
      'обновлены $minutes ${_minutesWord(minutes)} назад';

  static String freshnessToday(String time) => 'на сегодня $time';

  static String freshnessOn(String date, String time) => 'на $date $time';

  /// Склонение: «1 минуту», «2 минуты», «5 минут».
  static String _minutesWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'минуту';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'минуты';
    }
    return 'минут';
  }

  // Фильтры
  static const String filtersTitle = 'Фильтры';
  static const String reset = 'Сбросить';
  static const String labelWarehouse = 'СКЛАД';
  static const String labelGroup = 'ГРУППА НОМЕНКЛАТУРЫ';
  static const String labelAvailability = 'НАЛИЧИЕ';
  static const String toggleAll = 'Все';
  static const String toggleInStock = 'В наличии';
  static const String noFacetsInStock =
      'В наличии нет позиций со складом или группой номенклатуры.';
  static const String noFacets =
      'В справочнике нет позиций со складом или группой номенклатуры — '
      'фильтровать нечего.';

  static String showResults(String positions) => 'Показать $positions';

  static String more(int count) => 'Ещё $count';

  // Строка справочника
  static String article(String code) => 'Арт. $code · ';

  static String inStock(String quantity) => 'На складе: $quantity';

  // Карточка позиции
  static const String cardTitle = 'Позиция ЗИП';
  static const String notFoundTitle = 'Позиция не найдена';
  static const String notFoundHint =
      'Обновите справочник ЗИП и попробуйте снова.';
  static const String retry = 'Повторить';
  static const String currentStock = 'ТЕКУЩИЙ ОСТАТОК';
  static const String availabilityIn = 'В наличии';
  static const String availabilityBelowMinimum = 'Ниже минимума';
  static const String availabilityOut = 'Нет в наличии';
  static const String fieldWarehouse = 'Склад';
  static const String fieldGroup = 'Группа';
  static const String fieldArticle = 'Артикул';
  static const String fieldAccount = 'Счёт учёта';

  static String minimum(String value) => 'минимум $value';

  static String stockNorm(String value) => 'норма $value';

  // История движений
  static const String historyTitle = 'История движений';
  static const String historySearchHint = 'Поиск по задаче или ремонту';
  static const String historyUnavailableTitle = 'История недоступна';
  static const String historyEmptyTitle = 'Движений не было';
  static const String historyEmptyHint =
      'По этой позиции ещё не было ни приходов, ни списаний.';
  static const String resetFilters = 'Сбросить фильтры';
  static const String categoryAll = 'Все';
  static const String period = 'Период';
  static const String periodFrom = 'С даты';
  static const String periodTo = 'По дату';
  static const String periodAny = 'Любая';
  static const String done = 'Готово';
  static const String refreshFailed =
      'Не удалось обновить остатки. Показаны прежние данные.';

  static String shownOf(int shown, int total) => '$shown из $total';
}

/// Тексты раздела фактического расхода ЗИП на экране результата скана.
///
/// Отдельно от [RepairCardStrings]: сам блок общий с карточкой ремонта, но
/// момент списания разный — у ремонта склад уменьшает администратор при
/// закрытии, у осмотра это происходит сразу после отправки.
class InspectionConsumptionStrings {
  static const String writeOffNote =
      'Указанные количества спишутся со склада сразу после отправки осмотра.';
  static const String emptyNote =
      'Расход не указан — списания со склада не будет.';

  static const String confirmEmptyTitle = 'Расход ЗИП не заполнен';
  static const String confirmEmptyBody =
      'Задача закроется, но со склада ничего не спишется. Отправить осмотр '
      'без расхода?';
}

/// Тексты очереди отправки осмотров: причины отказа и полоса на главной.
class ScanQueueStrings {
  static const String errorAuthExpired =
      'Сессия истекла. Войдите в приложение заново.';
  static const String errorNoConnection =
      'Нет связи с сервером. Проверьте интернет и повторите.';
  static const String errorGeneric = 'Сервер не принял осмотр';

  /// Перевод `InsufficientStockError.detail` — сервер отдаёт его по-английски
  /// намеренно и локализацию оставляет клиенту.
  static const String errorInsufficientStock =
      'Недостаточно ЗИП на складе для списания';

  static const String rejectedTitle = 'Осмотры не отправлены';
  static const String rejectedAction = 'Разобраться';
  static const String rejectedUnknownEquipment = 'Оборудование не указано';

  static String rejectedCount(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return '$count осмотр отклонён сервером';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return '$count осмотра отклонено сервером';
    }
    return '$count осмотров отклонено сервером';
  }
}

/// Тексты экрана разрешения конфликта при отправке осмотра.
class ScanConflictStrings {
  static const String title = 'Осмотр не отправлен';
  static const String reasonLabel = 'ПРИЧИНА ОТКАЗА';
  static const String dataLabel = 'ВАШИ ДАННЫЕ';
  static const String shortageLabel = 'ЧЕГО НЕ ХВАТАЕТ НА СКЛАДЕ';
  static const String commentLabel = 'КОММЕНТАРИЙ';
  static const String consumptionLabel = 'ФАКТИЧЕСКИЙ РАСХОД ЗИП';
  static const String noComment = 'Без комментария';
  static const String noConsumption = 'Расход не указан';

  static const String askAdminTitle = 'Обратитесь к администратору';
  static const String askAdminBody =
      'Попросите пополнить остатки на складе. После этого вернитесь сюда и '
      'повторите отправку — осмотр всё это время хранится на устройстве.';
  static const String copy = 'Скопировать список';
  static const String copied = 'Список скопирован';

  static const String retry = 'Повторить отправку';
  static const String delete = 'Удалить осмотр';
  static const String deleteTitle = 'Удалить осмотр?';
  static const String deleteBody =
      'Данные осмотра будут потеряны безвозвратно, а закрытая им задача снова '
      'станет активной после синхронизации.';

  static const String genericHint =
      'Отправку можно повторить — например если причина уже устранена. Если '
      'нет, осмотр придётся удалить и снять заново.';

  /// Подпись над самим списком нехватки — отделяет его от обращения к
  /// администратору, которое стоит выше.
  static const String shortageListLabel = 'Не хватает';

  static String needShortage(String name, String required, String available) =>
      '$name — нужно $required, на складе $available';

  /// Позиция расхода. Знак «×» — тот же разделитель, что в норме расхода и в
  /// тексте для буфера обмена: список должен читаться одинаково везде.
  static String position(String name, String quantity) => '$name × $quantity';
}
