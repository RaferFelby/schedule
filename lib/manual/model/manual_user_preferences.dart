import 'package:flutter/material.dart' show Brightness;

/// iOS-local appearance and planning preferences, independent of legacy Hive.
final class ManualUserPreferences {
  const ManualUserPreferences({
    this.theme = 'system',
    this.workMinutes = 25,
    this.restMinutes = 5,
    this.availableWindows = const [
      <int>[480, 1320]
    ],
  });

  final String theme;
  final int workMinutes;
  final int restMinutes;
  final List<List<int>> availableWindows;

  Brightness? get brightness => switch (theme) {
        'light' => Brightness.light,
        'dark' => Brightness.dark,
        _ => null,
      };

  ManualUserPreferences copyWith({
    String? theme,
    int? workMinutes,
    int? restMinutes,
    List<List<int>>? availableWindows,
  }) =>
      ManualUserPreferences(
        theme: theme ?? this.theme,
        workMinutes: workMinutes ?? this.workMinutes,
        restMinutes: restMinutes ?? this.restMinutes,
        availableWindows: availableWindows ?? this.availableWindows,
      );

  Map<String, Object?> toJson() => {
        'theme': theme,
        'workMinutes': workMinutes,
        'restMinutes': restMinutes,
        'availableWindows': availableWindows
            .map((window) =>
                {'startMinutes': window[0], 'endMinutes': window[1]})
            .toList(growable: false),
      };

  factory ManualUserPreferences.fromJson(Object? raw) {
    if (raw is! Map) return const ManualUserPreferences();
    final theme = raw['theme'];
    final work = raw['workMinutes'];
    final rest = raw['restMinutes'];
    final windows = raw['availableWindows'];
    if (theme is! String ||
        !const ['system', 'light', 'dark'].contains(theme) ||
        work is! int ||
        work < 5 ||
        work > 1440 ||
        rest is! int ||
        rest < 0 ||
        rest > 1440 ||
        windows is! List) {
      throw const FormatException('本地设置格式无效');
    }
    final parsed = <List<int>>[];
    for (final item in windows) {
      if (item is! Map ||
          item['startMinutes'] is! int ||
          item['endMinutes'] is! int) {
        throw const FormatException('可用时段格式无效');
      }
      final start = item['startMinutes'] as int;
      final end = item['endMinutes'] as int;
      if (start < 0 || end > 1440 || end <= start) {
        throw const FormatException('可用时段范围无效');
      }
      parsed.add([start, end]);
    }
    parsed.sort((a, b) => a[0].compareTo(b[0]));
    for (var i = 1; i < parsed.length; i++) {
      if (parsed[i][0] < parsed[i - 1][1]) {
        throw const FormatException('可用时段不能重叠');
      }
    }
    return ManualUserPreferences(
      theme: theme,
      workMinutes: work,
      restMinutes: rest,
      availableWindows: List.unmodifiable(parsed.map(List<int>.unmodifiable)),
    );
  }

  factory ManualUserPreferences.fromLegacy(Map<String, Object?> values) {
    const defaults = ManualUserPreferences();
    final brightness = values['brightnessMode'];
    final theme = brightness is int && brightness >= 0 && brightness <= 2
        ? const ['system', 'light', 'dark'][brightness]
        : defaults.theme;
    final work = values['workTime'];
    final rest = values['restTime'];
    final windows = values['allowTime'];
    int durationMinutes(Object? value, int fallback,
        {required bool allowZero}) {
      if (value is! Duration) return fallback;
      const maxMinutes = 1440;
      final minutes = value.inMinutes;
      if (value.inSeconds != minutes * 60 ||
          minutes > maxMinutes ||
          (allowZero ? minutes < 0 : minutes < 5)) {
        return fallback;
      }
      return minutes;
    }

    var parsedWindows = defaults.availableWindows;
    if (windows is Map &&
        windows.keys.every((key) => key is DateTime) &&
        windows.values.every((value) => value is DateTime)) {
      final converted = <List<int>>[];
      for (final entry in windows.entries) {
        final start = entry.key as DateTime;
        final end = entry.value as DateTime;
        final startMinute = start.hour * 60 + start.minute;
        var endMinute = end.hour * 60 + end.minute;
        if (endMinute == 0 && end.day != start.day) {
          endMinute = 1440;
        }
        if (startMinute < endMinute) converted.add([startMinute, endMinute]);
      }
      converted.sort((a, b) => a[0].compareTo(b[0]));
      var valid = converted.isNotEmpty;
      for (var i = 1; i < converted.length; i++) {
        if (converted[i][0] < converted[i - 1][1]) {
          valid = false;
        }
      }
      if (valid) {
        parsedWindows =
            List.unmodifiable(converted.map(List<int>.unmodifiable));
      }
    }
    return ManualUserPreferences(
      theme: theme,
      workMinutes:
          durationMinutes(work, defaults.workMinutes, allowZero: false),
      restMinutes: durationMinutes(rest, defaults.restMinutes, allowZero: true),
      availableWindows: parsedWindows,
    );
  }
}
