import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Новый `Idempotency-Key`: 128 случайных бит, hex — так же, как ключ события
/// осмотра (`Scan.newEventId`). Сервер принимает от 1 до 255 печатных
/// символов (бэкенд `81f644c`, `reserve_mutation`).
String newIdempotencyKey([Random? random]) {
  final source = random ?? Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Ключ последнего шага черновика ремонта — `PATCH` комментария, расхода и
/// отправки на проверку уже созданного ремонта.
///
/// Выводится из [localId] черновика и отпечатка тела, а не хранится: тело
/// этого шага собирается из полей черновика, и пока они те же, повтор после
/// потерянного ответа уходит тем же ключом — сервер не применит его дважды.
/// Поменял обходчик черновик — другое тело, другой ключ, и сервер не
/// отклонит его как «ключ с чужим телом». Черновик после шага удаляется,
/// так что ключ одного тела второй раз не понадобится.
String repairFinishKey(String localId, String body) =>
    '$localId:finish:${md5.convert(utf8.encode(body))}';
