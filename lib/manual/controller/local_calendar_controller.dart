import 'package:celechron/model/period.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';

/// Calendar state for the local academic profile, independent of legacy Scholar.
final class LocalCalendarController extends GetxController {
  LocalCalendarController({List<Period> periods = const []})
      : _periods = List.of(periods);

  List<Period> _periods;
  final selectedDay = DateTime.now().obs;
  final focusedDay = DateTime.now().obs;
  final calendarFormat = CalendarFormat.month.obs;
  final events = <DateTime, List<Period>>{}.obs;

  @override
  void onInit() {
    refreshEvents();
    super.onInit();
  }

  void refreshEvents() {
    events.clear();
    for (final period in _periods) {
      final day = chopDate(period.startTime);
      events.putIfAbsent(day, () => <Period>[]).add(period);
    }
    for (final dayEvents in events.values) {
      dayEvents.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
  }

  void replacePeriods(List<Period> periods) {
    _periods = List.of(periods);
    refreshEvents();
  }

  DateTime chopDate(DateTime day) => DateTime(day.year, day.month, day.day);

  List<Period> getEventsForDay(DateTime day) =>
      (events[chopDate(day)] ?? const <Period>[])
          .map((period) => period.copyWith())
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  String dayDescription(DateTime day) => '本地课程';

  String getCurrentSemesterDisplayName() => '无学期信息';
}
