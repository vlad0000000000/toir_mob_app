/// Парсер сырых строк SSE-стрима. Хранит состояние текущего event/data;
/// при пустой строке (конец события) вызывает переданный [onEvent].
///
/// Используется и в основном изоляте ([NotificationsService]), и в
/// фоновом ([NotificationsTaskHandler]) — раньше был продублирован.
class SseLineParser {
  String? _currentEvent;
  final StringBuffer _currentData = StringBuffer();

  /// Сбрасывает состояние парсера (например, при reconnect).
  void reset() {
    _currentEvent = null;
    _currentData.clear();
  }

  /// Обрабатывает одну строку из SSE-стрима. При завершении события
  /// (пустая строка) вызывает `onEvent(event, dataAccumulated)`.
  void handleLine(
      String line, void Function(String event, String data) onEvent) {
    if (line.isEmpty) {
      if (_currentEvent != null) {
        onEvent(_currentEvent!, _currentData.toString());
      }
      _currentEvent = null;
      _currentData.clear();
      return;
    }
    if (line.startsWith(':')) return;
    if (line.startsWith('event:')) {
      _currentEvent = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (_currentData.isNotEmpty) _currentData.write('\n');
      _currentData.write(line.substring(5).trim());
    }
  }
}
