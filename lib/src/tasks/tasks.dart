import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_machine_scanner/src/app_bar/app_bar.dart';

// models.dart
class Equipment {
  final String name;
  final List<Checklist> checklists;

  Equipment(this.name, this.checklists);
}

class Checklist {
  final String period;
  final List<Task> tasks;
  bool isExpanded;

  Checklist(this.period, this.tasks, {this.isExpanded = false});
}

class Task {
  final String operation;
  final String node;
  final String? quantity;
  final String? material;

  Task({
    required this.operation,
    required this.node,
    this.quantity,
    this.material,
  });

  Map<String, dynamic> toJson() {
    return {
      'operation': operation,
      'node': node,
      'quantity': quantity,
      'material': material,
    };
  }
}

class EquipmentListScreen extends StatelessWidget {
  final List<Equipment> equipmentList;

  final bool isModal;

  static final machineIdToEquipment = {
    1: [5],
    2: [6],
    3: [2],
    4: [2],
    5: [3],
    6: [7, 8],
    7: [11],
    8: [10],
    // 9: [0, 1],
    9: [1],
  };

  static final equipmentListAll = [
    Equipment(
        'Пристаночная механизация линии POWERMAT 2500. Линия сортировки досок. Триммер, Сортировочный стол Ламели',
        [
          Checklist('Ежедневно', [
            Task(
              operation: 'Визуальный осмотр',
              node:
                  'Подшипниковые узлы приводного вала, тяговых цепей , приводных цепей',
              quantity: '6 гр.',
              material: 'Класс EP2 -2 NLGI',
            ),
            Task(
              operation:
                  'Проверить натяжение транспортной цепи, при необходимости отрегулировать',
              node: 'Кулачковый угловой транспортер',
              quantity: '',
              material: 'Промышленные масла',
            ),
          ]),
          Checklist('Еженедельно', [
            Task(
              operation: 'Осмотр на наличие конденсата (слить)',
              node: 'Блок подготовки сжатого воздуха',
              quantity: '',
              material: '',
            ),
            Task(
              operation:
                  'Постоянный контроль пильных полотен и защитных устройств',
              node: 'Многопильный торцовочный станок',
              quantity: '',
              material: '',
            ),
            Task(
              operation:
                  'Проверить натяжение ленты, при необходимости дополнительно натянуть',
              node: 'Продольно ленточный конвеер, поперечный конвеер.',
              quantity: '',
              material: '',
            ),
            Task(
              operation:
                  'Проверить натяжение транспортной цепи, при необходимости отрегулировать',
              node: 'Цепной поперечный транспортер',
              quantity: '',
              material: 'Промышленные масла',
            ),
          ]),
          Checklist('1 раз в месяц', [
            Task(
              operation: 'Осмотр на наличие протечек',
              node: 'Гидроцилиндр, шланги',
              quantity: '',
              material: '',
            ),
          ]),
          Checklist('1 раз 3 мес', [
            Task(
              operation: 'Cмазка протяжка креплений',
              node:
                  'Подшипниковые узлы приводного вала, тяговых цепей , приводных цепей',
              quantity: '6 гр.',
              material: 'Класс EP2 -2 NLGI',
            ),
            Task(
              operation: 'Визуальный осмотр',
              node:
                  'Редуктора привода тяговых цепей, роликов, транспортеров, ленточных конвееров',
              quantity: '',
              material: 'CLP 220',
            ),
            Task(
              operation: 'Проверка уровня масла (доливка)',
              node:
                  'Редуктора привода тяговых цепей, роликов, транспортеров, ленточных конвееров',
              quantity: '',
              material: 'CLP 220',
            ),
            Task(
              operation: 'Визуальный осмотр',
              node: 'Линейные подшипники направляющие',
              quantity: '6 гр.',
              material: 'Класс EP 0',
            ),
            Task(
              operation: 'Смазка протяжка креплений',
              node: 'Линейные подшипники направляющие',
              quantity: '6 гр.',
              material: 'Класс EP 0',
            ),
            Task(
              operation: 'Очистить и смазать',
              node: 'Кулачковый угловой транспортер',
              quantity: '',
              material: 'Промышленные масла',
            ),
            Task(
              operation: 'Очистить и смазать',
              node: 'Цепной поперечный транспортер',
              quantity: '',
              material: 'Промышленные масла',
            ),
          ]),
          Checklist('1 раз 6 меc', [
            Task(
              operation: 'Замена фильтра маслостанции',
              node: 'Маслостанция подьемного стола',
              quantity: '1 шт.',
              material: 'Масло HLP 46',
            ),
          ]),
          Checklist('1 раз в год', [
            Task(
              operation: 'Замена работчей жидкости',
              node: 'Маслостанция подьемного стола',
              quantity: '1 шт.',
              material: 'Масло HLP 46',
            ),
          ]),
        ]),
    Equipment('POWERMAT 2500', [
      Checklist('Еженедельно', [
        Task(
          operation: 'Проверить натяжение ремней, следить за чистотой',
          node: 'Зубчатый ремень',
          quantity: '',
          material: '',
        ),
        Task(
          operation:
              'Осмотр сильфоновов на наличие трещин. Если имеются трещины заменить',
          node: 'Сильфоны горизонтального шпинделя регулятора высоты',
          quantity: '',
          material: '',
        ),
        Task(
          operation:
              'Прверить крепёжные винты на прочность затяжки. При необходимости подтянуть',
          node: 'Подающие вальцы и подвижные плиты стола',
          quantity: '',
          material: '',
        ),
        Task(
          operation:
              'Прверить на наличие утечки. Проверить уровень масла при необходимости долить',
          node: 'Гидроагрегат для гидрозажима',
          quantity: '',
          material: 'Масло HLP 46',
        ),
        Task(
          operation: 'Визуальный осмотр, протяжка креплений',
          node: 'Пневмоцилиндры',
          quantity: '',
          material: '',
        ),
      ]),
      Checklist('Ежемесячно', [
        Task(
          operation: 'Очистить и смазать продольную направляющую',
          node: 'Джойнтер',
          quantity: '',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Осмотр и смазка: линейный напрвляющая прижимных роликов',
          node: 'Пильный шпиндель',
          quantity: '6 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Прверить плавность хода радиального регулятора',
          node: 'Газовый пневмоцилиндр у кронштейна двигателя',
          quantity: '',
          material: '',
        ),
      ]),
      Checklist('1 раз 3 мес', [
        Task(
          operation:
              'Осмотр и смазка: Загрузочный стол. Горизонтальный шпиндель .Вертикальный шпиндель. Пильный шпиндель',
          node: 'Установочные винты',
          quantity: '',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Осмотр и смазка: Левый шпиндель. Верхний шпиндель',
          node: 'Прижимное устройство',
          quantity: '6 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
      ]),
      Checklist('1 раз в год', [
        Task(
          operation: 'Замена масла',
          node: 'Гидроагрегат для гидрозажима',
          quantity: '',
          material: 'Масло HLP 46',
        ),
      ]),
      Checklist('1 раз в 2 года', [
        Task(
          operation: 'Замена масла',
          node: 'Редуктор (подача)',
          quantity: '1500 - 7000 см2',
          material: 'CLP 220',
        ),
        Task(
          operation: 'Замена масла',
          node: 'Гидравлический агрегат',
          quantity: '1000 см2',
          material: 'Масло HLP 46',
        ),
      ]),
    ]),
    Equipment('OPTICUT 200', [
      Checklist('Ежемесячно', [
        Task(
          operation:
              'Конторль натяжки ремней. Проверить, движется ли ремень равномероно и ровные ли него края',
          node: 'Ременые передачи',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Очистить, инспектировать. Смазка кисточкой',
          node: 'Напряавляющие ходовые винты',
          quantity: '',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Очистить, инспектировать. Смазка',
          node: 'Опора полотна пилы',
          quantity: '4 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Очистить, инспектировать. Смазка',
          node: 'Направляющие подачи, линейные подшипники',
          quantity: '6 гр.',
          material: 'Класс EP 0',
        ),
        Task(
          operation: 'Очистить, инспектировать. Смазка',
          node: 'Выбрасыватель',
          quantity: '4 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'По потребности долить масло',
          node: 'Пневматический узел',
          quantity: '',
          material: 'ISO VG 32',
        ),
        Task(
          operation: 'Очистить, инспектировать. Смазка',
          node: 'Шарнирная головка',
          quantity: '4 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
      ]),
      Checklist('1 раз 6 меc', [
        Task(
          operation: 'Проверка уровня масла',
          node: 'Редуктора привода ленточных конвееров',
          quantity: 'По потребности 0.7-1.6 литра.',
          material: 'CLP 220',
        ),
      ]),
      Checklist('1 раз в год', [
        Task(
          operation: 'Смена масла',
          node: 'Редуктора привода ленточных конвееров',
          quantity: 'По потребности 0.7-1.6 литра.',
          material: 'CLP 220',
        ),
      ]),
    ]),
    Equipment('Grecon HS 120', [
      Checklist('Ежедневно', [
        Task(
          operation: 'Доливка масла',
          node: 'Капельная смазка',
          quantity: '',
          material: 'Промышленные масла',
        ),
        Task(
          operation: 'Проверка, слив конденсата',
          node: 'Блок подготовки пневмосистемы, водоотделитель',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Проверка, натяжка',
          node: 'Леточный траспортер',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Проверка, замена',
          node: 'Упругие пластины',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Проверка уровня, долить',
          node: 'Противозадирное средство для опрных планок станины цепи',
          quantity: '',
          material: 'WAXILIT',
        ),
        Task(
          operation: 'Проверка, натяжка',
          node: 'Цепи захватами',
          quantity: '',
          material: '',
        ),
      ]),
      Checklist('Еженедельно', [
        Task(
          operation: 'Проверка прочности затяжки',
          node: 'Крепёжный элимент',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Проверка натяжки',
          node: 'Ремни привода шпинделя фрезы',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Смазка',
          node: 'Поворотно-направляющий пресс',
          quantity: '4 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Очистка',
          node: 'Ревизия заливного вентиляционного фильтра гидостанции',
          quantity: '',
          material: '',
        ),
        Task(
          operation:
              'Прверить на наличие утечки. Проверить уровень масла, при необходимости долить',
          node: 'Гидростанция пресса',
          quantity: 'Обьем шильда редуктора',
          material: 'Масло HLP 46',
        ),
      ]),
      Checklist('Ежемесячно', [
        Task(
          operation: 'Проверка',
          node: 'Пневматика , клапана пневмосистемы',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Проверка, натежение приводного ремня',
          node: 'Щеточный узел',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Смазка, проверка натяжки',
          node: 'Приводные цепи',
          quantity: '',
          material: 'Промышленные масла',
        ),
        Task(
          operation: 'Инспектировать. Очистка чистящей жидкостью',
          node: 'Пневматика, глушители шума',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Смазка',
          node:
              'Устройство перестановки верхнего прижима, 1-2 сторона фрезерования',
          quantity: '4 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Смазка',
          node: 'Направляющая каретки для натяжения цепи',
          quantity: '4 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Смазка',
          node: 'Направлщая каретки установочного шпинделя',
          quantity: '4 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Смазка',
          node: 'Установачный шпиндель',
          quantity: '4 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
      ]),
      Checklist('1 раз 6 меc', [
        Task(
          operation: 'Смазка',
          node: 'Супорт фрезы 1 и 2',
          quantity: '4 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Смазка',
          node: 'Напрявляющая корпуса подрезателя',
          quantity: '4 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Смазка',
          node: 'Приводные звездочки толкателей',
          quantity: '6 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Смазка',
          node: 'Подшипник опирания привода',
          quantity: '6 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
      ]),
      Checklist('1 раз в год', [
        Task(
          operation: 'Замена масла',
          node: 'Гидростанция пресса',
          quantity: 'Обьем шильда редуктора',
          material: 'Масло HLP 46',
        ),
        Task(
          operation: 'Замена',
          node: 'Фильтр напорной линии',
          quantity: '',
          material: '',
        ),
      ]),
      Checklist('1 раз в 2 года', [
        Task(
          operation: 'Замена масла',
          node: 'Приводные редуктора и барабанные двигателя',
          quantity: 'Обьем шильда редуктора',
          material: 'CLP 220',
        ),
      ]),
    ]),
    // Equipment('Profi Press 2500', [
    //   Checklist('Еженедельно', [
    //     Task(
    //       operation: 'Смазка, очистить старые смазочные вещества и смазки',
    //       node: 'Смазка пресса',
    //       quantity: '2 гр.',
    //       material: 'Класс EP2 -2 NLGI',
    //     ),
    //     Task(
    //       operation: 'Инспектировать',
    //       node: 'Гидростанция пресса',
    //       quantity: 'Обьем гидробака',
    //       material: 'Масло HLP 46',
    //     ),
    //     Task(
    //       operation: 'Инспектировать смазка кисточкой',
    //       node: 'Приводные и транспортерные цепи',
    //       quantity: '',
    //       material: 'Промышленные масла',
    //     ),
    //     Task(
    //       operation: 'Смазка ЕР 0',
    //       node: 'Линейные подшипники направляющие',
    //       quantity: '2 гр.',
    //       material: 'Класс EP 0',
    //     ),
    //     Task(
    //       operation: 'Смазка, очистить старые смазочные вещества и смазки',
    //       node: 'Шпиндель с трапецивидной резьбой , направляющие скольжения',
    //       quantity: '6 гр.',
    //       material: 'Класс EP2 -2 NLGI',
    //     ),
    //   ]),
    //   Checklist('Ежемесячно', [
    //     Task(
    //       operation: 'Смазка, очистить старые смазочные вещества и смазки',
    //       node: 'Загрузочный толкатель',
    //       quantity: '2 гр.',
    //       material: 'Класс EP 0',
    //     ),
    //     Task(
    //       operation: 'Очистка веторшью',
    //       node: 'Линейные подшипники направляющие',
    //       quantity: '2 гр.',
    //       material: 'Класс EP 0',
    //     ),
    //   ]),
    //   Checklist('1 раз 6 меc', [
    //     Task(
    //       operation: 'Инспектировать',
    //       node: 'Мотор редуктор',
    //       quantity: 'Обьем шильда редуктора',
    //       material: 'CLP 220',
    //     ),
    //   ]),
    //   Checklist('1 раз в год', [
    //     Task(
    //       operation: 'Замена масла',
    //       node: 'Гидростанция пресса',
    //       quantity: 'Обьем гидробака',
    //       material: 'Масло HLP 46',
    //     ),
    //     Task(
    //       operation: 'Замена масла',
    //       node: 'Мотор редуктор',
    //       quantity: 'Обьем шильда редуктора',
    //       material: 'CLP 220',
    //     ),
    //   ]),
    // ]),
    Equipment('Profi Press 5500. Установлен таймер технического обслуживания', [
      Checklist('Еженедельно', [
        Task(
          operation: 'Смазка',
          node:
              'Шибер вертикального шпинделя и горизонтального шибера, гайка , шибер подающей балки, вал шпинделя',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Смазка, очистить старые смазочные вещества и смазки',
          node: 'Смазка пресса',
          quantity: '2 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Инспектировать',
          node: 'Гидростанция пресса',
          quantity: 'Обьем гидробака',
          material: 'Масло HLP 46',
        ),
        Task(
          operation: 'Инспектировать смазка кисточкой',
          node: 'Приводные и транспортерные цепи',
          quantity: '',
          material: 'Промышленные масла',
        ),
        Task(
          operation: 'Смазка ЕР 0',
          node: 'Линейные подшипники направляющие',
          quantity: '2 гр.',
          material: 'Класс EP 0',
        ),
        Task(
          operation: 'Смазка',
          node: 'Фрезерный шпиндель с тавотницей',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Чистка, смазка',
          node: 'Джонтер',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Чистка, смазка',
          node: 'Фрезерный шпиндель, кольца',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
      ]),
      Checklist('1 раз в 2 нед', [
        Task(
          operation: 'Смазка, проверка целостности звеньев',
          node: 'Рабочие цепи',
          quantity: '',
          material: 'wurth hhs 2000',
        ),
      ]),
      Checklist('Ежемесячно', [
        Task(
          operation: 'Смазка, очистить старые смазочные вещества и смазки',
          node: 'Загрузочный толкатель',
          quantity: '2 гр.',
          material: 'Класс EP 0',
        ),
        Task(
          operation: 'Проверка уровня масла',
          node: 'Гидростанция пресса',
          quantity: 'Обьем гидробака',
          material: 'Масло Shell Tellus 46',
        ),
        Task(
          operation: 'Смазка',
          node:
              'Шибер шпинделя, гайка шибер подающей балки, направляющие и зубья шестерни, подг. стол',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Смазка',
          node:
              'Правый шпиндель, подвижный, регулировка головки шпинделя, поверхность зубьев, червячное колесо',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Смазка',
          node: 'Колено карданного вала',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Смазка',
          node: 'Подача - регулировочный редуктор',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Смазка',
          node:
              'Загрузочный стол и направляющая линейка, поджим к верху шпинделя',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Смазка',
          node: 'Посадочный вал шпинделя',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Очистка веторшью',
          node: 'Линейные подшипники направляющие',
          quantity: '2 гр.',
          material: 'Класс EP 0',
        ),
      ]),
      Checklist('1 раз 6 меc', [
        Task(
          operation: 'Инспектировать',
          node: 'Редуктор',
          quantity: '',
          material: 'Shell OMALLA 220',
        ),
        Task(
          operation: 'Осмотр, проверка натяжения, при необходимости замена',
          node: 'Ремни',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Инспектировать',
          node: 'Червячный редуктор',
          quantity: '',
          material: 'Shell OMALLA 220',
        ),
        Task(
          operation: 'Инспектировать',
          node: 'Мотор-редуктор',
          quantity: 'Обьем шильда редуктора',
          material: 'CLP 220',
        ),
      ]),
      Checklist('1 раз в год', [
        Task(
          operation: 'Замена',
          node: 'Гидростанция пресса',
          quantity: 'Обьем гидробака',
          material: 'Масло Shell Tellus 46',
        ),
        Task(
          operation: 'Замена масла',
          node: 'Редуктор',
          quantity: '',
          material: 'Shell OMALLA 220',
        ),
        Task(
          operation: 'Замена масла',
          node: 'Червячный редуктор',
          quantity: '',
          material: 'Shell OMALLA 220',
        ),
        Task(
          operation: 'Замена масла',
          node: 'Гидростанция пресса',
          quantity: 'Обьем гидробака',
          material: 'Масло HLP 46',
        ),
        Task(
          operation: 'Замена масла',
          node: 'Мотор-редуктор',
          quantity: 'Обьем шильда редуктора',
          material: 'CLP 220',
        ),
      ]),
    ]),
    Equipment('Пристаночный цепной транспортёр подачи в Hydromat 1000', [
      Checklist('Еженедельно', [
        Task(
          operation: 'Инспектировать',
          node: 'Гидростанция разгонного блока',
          quantity: 'Обьем гидробака',
          material: '',
        ),
      ]),
      Checklist('1 раз в 2 нед', [
        Task(
          operation: 'Инспектировать смазка',
          node: 'Приводные тяговые цепи',
          quantity: 'Промышленные масла',
          material: '',
        ),
        Task(
          operation: 'Инспектировать смазка',
          node: 'Рабочие ролики',
          quantity: 'Промышленные масла',
          material: '',
        ),
      ]),
      Checklist('1 раз 6 меc', [
        Task(
          operation: 'Смазка, протяжка креплений',
          node: 'Подшипниковые узлы приводного вала',
          quantity: '3 гр.',
          material: 'Shell GADUS S-2',
        ),
      ]),
      Checklist('1 раз в год', [
        Task(
          operation: 'Замена масла',
          node: 'Гидростанция разгонного блока',
          quantity: '',
          material: 'Масло HLP 46',
        ),
      ]),
    ]),
    Equipment('Линия HOMAG. Базовые станки FPR 620 Обрезные станции', [
      Checklist('1 раз 3 мес', [
        Task(
          operation: 'Контроль уровня масла',
          node: 'Привод цепного транспортера редуктора',
          quantity: 'Обьем шильда редуктора',
          material: 'Shell OMALLA 220',
        ),
      ]),
      Checklist('1 раз в год', [
        Task(
          operation: 'Замена масла',
          node: 'Привод цепного транспортера редуктора',
          quantity: 'Обьем шильда редуктора',
          material: 'Shell OMALLA 220',
        ),
      ]),
      Checklist('Автоматический счетчик обслуживания', [
        Task(
          operation: 'Чистка, смазка',
          node: 'Цепной транспортер',
          quantity: '2 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation:
              'Чистка, смазка. Проверить натяжение ремня и натяжной винт',
          node: 'Верхнее прижимное устройство',
          quantity: '4 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Читска, смазка. Проверка редуктора',
          node: 'Устройство регулирования ширины',
          quantity: '4 гр.',
          material: 'Shell GADUS S-2',
        ),
        Task(
          operation: 'Очистить приводной вал тряпкой и слегка смазать маслом',
          node: 'Приводной вал',
          quantity: '',
          material: 'Промышленные масла',
        ),
        Task(
          operation:
              'Очистить войлок позади стопорного кольца, пропитать маслом',
          node: 'Подвижная втулка',
          quantity: '',
          material: 'Промышленные масла',
        ),
        Task(
          operation: 'Осмотр, слив конденсата',
          node: 'Пневмоблок подготовки сжатого воздуха',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Инспектировать, замена масла',
          node: 'Редукторный двигатель',
          quantity: 'Обьем шильда редуктора',
          material: 'CLP 220',
        ),
        Task(
          operation:
              'Проверить отсуствие зазора (не должна входить контрольная полоса толщиной 0.05 мм). Очистка',
          node: 'Направляющие в форме ласточкина хвоста',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Смазка , очистка',
          node: 'Шпиндель и подвижные части',
          quantity: '3 гр.',
          material: 'Класс EP2 -2 NLGI',
        ),
        Task(
          operation: 'Проверьте и отрегулируйте скребки и контактный ролик',
          node: 'Фрезерование',
          quantity: '',
          material: '',
        ),
      ]),
    ]),
    Equipment('Линия HOMAG. Шлифовальные станки SWT 735 /935', [
      Checklist('Еженедельно', [
        Task(
          operation:
              'Контроль натежения. Регулировка натяжения, если необходимо',
          node: 'Приводные ручейковые ремни шлифовальных валов',
          quantity: '',
          material: '',
        ),
        Task(
          operation:
              'Контроль натежения. Регулировка натяжения, если необходимо',
          node: 'Приводные зубчатые ремни, регулировка по высоте машин',
          quantity: '',
          material: '',
        ),
        Task(
          operation:
              'Контроль натежения. Регулировка натяжения, если необходимо',
          node: 'Приводные ремни вакумного вентилятора',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Инспектировать',
          node: 'Гидростанции подьемных лифтов столов',
          quantity: 'Обьем гидробака',
          material: 'Масло HLP 46',
        ),
      ]),
      Checklist('1 раз 3 мес', [
        Task(
          operation: 'Контроль уровня масла',
          node: 'Привод транспортерной ленты редуктора',
          quantity: 'Обьем шильда редуктора',
          material: 'Shell OMALLA 220',
        ),
      ]),
      Checklist('1 раз в год', [
        Task(
          operation: 'Замена масла',
          node: 'Привод транспортерной ленты редуктора',
          quantity: 'Обьем шильда редуктора',
          material: 'Shell OMALLA 220',
        ),
        Task(
          operation: 'Замена масла',
          node: 'Гидростанции подьемных лифтов столов',
          quantity: 'Обьем гидробака',
          material: 'Масло HLP 46',
        ),
      ]),
      Checklist('Автоматический счетчик обслуживания', [
        Task(
          operation: 'Осмотр, слив конденсата',
          node: 'Пневмоблок подготовки сжатого воздуха',
          quantity: '',
          material: '',
        ),
      ]),
    ]),
    // Equipment('Участок Аспирации MOLDOW', [
    //   Checklist('Еженедельно', [
    //     Task(
    //       operation: 'Осмотр',
    //       node: 'Цепь Скребками',
    //       quantity: '',
    //       material: '',
    //     ),
    //   ]),
    //   Checklist('1 раз 3 мес', [
    //     Task(
    //       operation: 'Осмотр',
    //       node: 'Опорные колеса и звездочки',
    //       quantity: '',
    //       material: '',
    //     ),
    //     Task(
    //       operation: 'Осмотр',
    //       node: 'Опорные звездочки',
    //       quantity: '',
    //       material: '',
    //     ),
    //     Task(
    //       operation:
    //           'Контроль натежения. Регулирование натяжение, если необходимо',
    //       node: 'Ременной привод',
    //       quantity: '',
    //       material: '',
    //     ),
    //     Task(
    //       operation: 'Смазка, очистить старые смазочные вещества.',
    //       node: 'Подшипники шлюзового дозатора',
    //       quantity: '3 гр.',
    //       material: 'Класс EP2 -2 NLGI',
    //     ),
    //     Task(
    //       operation: 'Смазка, очистить старые смазочные вещества.',
    //       node: 'Пошипники шнековый конвеер',
    //       quantity: '3 гр.',
    //       material: 'Класс EP2 -2 NLGI',
    //     ),
    //     Task(
    //       operation: 'Осмотр',
    //       node: 'Двухрядная цепь',
    //       quantity: '',
    //       material: '',
    //     ),
    //   ]),
    //   Checklist('1 раз 6 меc', [
    //     Task(
    //       operation: 'Осмотр',
    //       node: 'Рельсы',
    //       quantity: '',
    //       material: '',
    //     ),
    //     Task(
    //       operation: 'Осмотр',
    //       node: 'Износные пластины',
    //       quantity: '',
    //       material: '',
    //     ),
    //     Task(
    //       operation: 'Осмотр',
    //       node: 'Скребки',
    //       quantity: '',
    //       material: '',
    //     ),
    //     Task(
    //       operation: 'Смазка, очистка старые смазочные вещества.',
    //       node: 'Подшипники приводной станции',
    //       quantity: '3 гр.',
    //       material: 'Класс EP2 -2 NLGI',
    //     ),
    //     Task(
    //       operation: 'Осмотр',
    //       node: 'Шестерня',
    //       quantity: '',
    //       material: '',
    //     ),
    //     Task(
    //       operation: 'Осмотр',
    //       node: 'Муфта',
    //       quantity: '',
    //       material: '',
    //     ),
    //     Task(
    //       operation: 'Инспектировать',
    //       node: 'Редуктора',
    //       quantity: 'Обьем шильда редуктора',
    //       material: 'CLP 220',
    //     ),
    //   ]),
    //   Checklist('1 раз в год', [
    //     Task(
    //       operation: 'Замена масла',
    //       node: 'Редуктора',
    //       quantity: 'Обьем шильда редуктора',
    //       material: 'CLP 220',
    //     ),
    //   ]),
    // ]),
    Equipment('SELCO Форматно-раскороечный станок', [
      Checklist('1 раз 3 мес', [
        Task(
          operation: 'Очистка сжатым воздухом',
          node: 'Зубчатая рейка прижимной балки',
          quantity: '',
          material: '',
        ),
      ]),
      Checklist('1 раз 6 меc', [
        Task(
          operation: 'Очистка сжатым воздухом',
          node: 'Горизонтальная направляющая каретки пил',
          quantity: '',
          material: '',
        ),
        Task(
          operation: 'Очистка сжатым воздухом',
          node: 'Зубчатая рейка пильной каретки',
          quantity: '',
          material: '',
        ),
      ]),
      Checklist('Автоматический счетчик обслуживание', [
        Task(
          operation: 'Смазка',
          node: 'Линейные подшипники направляющих прижимов',
          quantity: '2 гр',
          material: 'Класс EP 0',
        ),
        Task(
          operation: 'Смазка',
          node:
              'Линейные подшипники двойного толкателя Twin Pusher (опция для SELCO WN 250)',
          quantity: '2 гр',
          material: 'Класс EP 0',
        ),
        Task(
          operation:
              'Контроль натежения. Регулирование натяжения, если необходимо',
          node: 'Ремни пильных дисков',
          quantity: '',
          material: '',
        ),
      ]),
    ]),
    Equipment('11 Термоупаковка KALLFASS', [
      Checklist('Еженедельно', [
        Task(
          operation: 'Смазать высокотемпературным маслом',
          node: 'Цепь конвейера',
          quantity: '',
          material: '',
        ),
      ]),
      Checklist('1 раз в 2 нед', [
        Task(
          operation: 'Регулярная проверка',
          node: 'Болтовые соединения',
          quantity: '',
          material: '',
        ),
      ]),
    ]),
  ];

  const EquipmentListScreen(
      {super.key, required this.equipmentList, this.isModal = false});

  @override
  Widget build(BuildContext context) {
    Widget list = ListView.builder(
      itemCount: equipmentList.length,
      itemBuilder: (context, index) {
        final equipment = equipmentList[index];
        return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              title: Text(
                equipment.name,
                style: const TextStyle(
                    // color: Colors.blue,
                    // fontWeight: FontWeight.bold,
                    ),
              ),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () => GoRouter.of(context).go('/details/$index'),
            ));
      },
    );

    if (isModal) {
      return list;
    }

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: list,
    );
  }
}

// equipment_detail_screen.dart
// import 'package:flutter/material.dart';
// import 'models.dart';

final Map<String, Color> periodColors = {
  'Ежедневно': Colors.red,
  'Еженедельно': Colors.yellow,
  "1 раз в 2 нед": Colors.pink,
  "Ежемесячно": Colors.teal,
  '1 раз в месяц': Colors.teal,
  '1 раз 3 мес': Colors.blueGrey,
  '1 раз 6 мес': Colors.blue,
  '1 раз 6 меc': Colors.blue,
  '1 раз в год': Colors.green,
  '1 раз в 2 года': Colors.grey,
  'Автоматический счетчик обслуживания': Colors.teal,
  'Автоматический счетчик обслуживание': Colors.teal,
};

class EquipmentDetailScreen extends StatefulWidget {
  final Equipment equipment;
  final bool isModal;
  final void Function(Task)? onTaskTap;

  const EquipmentDetailScreen(
      {super.key,
      required this.equipment,
      this.isModal = false,
      this.onTaskTap = null});

  @override
  State<EquipmentDetailScreen> createState() => _EquipmentDetailScreenState();
}

class _EquipmentDetailScreenState extends State<EquipmentDetailScreen> {
  @override
  Widget build(BuildContext context) {
    Widget list = ListView.builder(
      itemCount: widget.equipment.checklists.length,
      itemBuilder: (context, index) {
        final checklist = widget.equipment.checklists[index];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: periodColors[checklist.period],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
              ),
              ExpansionTile(
                shape: const Border(),
                title: Text(
                  checklist.period + ' (${checklist.tasks.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                trailing: Icon(
                  checklist.isExpanded ? Icons.remove : Icons.add,
                  size: 28,
                ),
                childrenPadding:
                    const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                children: checklist.tasks.map((task) {
                  return _buildTaskItem(task);
                }).toList(),
                onExpansionChanged: (expanded) {
                  setState(() {
                    checklist.isExpanded = expanded;
                  });
                },
              ),
            ],
          ),
        );
      },
    );

    Widget body = Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 30),
          child: Text(
            widget.equipment.name,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        Expanded(child: list)
      ],
    );

    if (widget.isModal) {
      // return body;
      final mediaQuery = MediaQuery.of(context);
      final height = mediaQuery.size.height * 0.9;
      return Container(
        padding: EdgeInsets.symmetric(vertical: 10),
        height: height,
        child: Column(
          children: [
            SizedBox(
              height: 10,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  child: Icon(
                    Icons.close,
                    size: 32,
                  ),
                  onTap: () => Navigator.of(context).pop(),
                ),
                SizedBox(width: 20)
              ],
            ),
            SizedBox(
              height: 10,
            ),
            Expanded(child: body)
          ],
        ),
        margin: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            )
          ],
        ),
      );
    }

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: body,
    );
  }

  Widget _buildTaskItem(Task task) {
    Widget col = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Операция
        Text(
          task.operation,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.blue,
          ),
        ),

        const SizedBox(height: 8),

        // Узел
        Text(
          task.node,
          style: const TextStyle(
            fontSize: 15,
          ),
        ),
        SizedBox(
          width: MediaQuery.of(context).size.width,
        ),
        // Дополнительная информация (если есть)
        if ((task.quantity != null && task.quantity!.length > 0) ||
            (task.material != null && task.material!.length > 0))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.quantity != null && task.quantity!.length > 0)
                  _buildDetailRow('Количество:', task.quantity!),
                if (task.material != null && task.material!.length > 0)
                  _buildDetailRow('Материал:', task.material!),
              ],
            ),
          ),
      ],
    );
    if (widget.isModal) {
      return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(10),
            // border: Border.all(color: Colors.grey[200]!),
          ),
          child: InkWell(
            child: col,
            onTap: () {
              if (widget.onTaskTap != null) {
                widget.onTaskTap!(task);
              }
            },
          ));
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        // border: Border.all(color: Colors.grey[200]!),
      ),
      child: col,
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// main.dart
// import 'package:flutter/material.dart';
// import 'package:go_router/go_router.dart';
// import 'equipment_list_screen.dart';
// import 'equipment_detail_screen.dart';
// import 'models.dart';
