import 'dart:io';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/service/ical_period_encoder.dart';
import 'package:celechron/manual/service/manual_calendar_period_adapter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Creates and shares an ICS file from the active local academic profile.
final class LocalCalendarIcsExporter {
  const LocalCalendarIcsExporter();

  Future<String> generate({
    required AcademicRepository repository,
    String calendarName = '本地课程表',
    bool includeExams = true,
  }) async {
    final periods = await ManualCalendarPeriodAdapter(repository).readPeriods();
    return IcalPeriodEncoder.generate(
      periods: periods,
      calendarName: calendarName,
      includeExams: includeExams,
    );
  }

  Future<void> exportFile(
    AcademicRepository repository, {
    BuildContext? context,
  }) async {
    try {
      final sharePositionOrigin = await _calculateSharePositionOrigin(context);
      final icalContent = await generate(repository: repository);
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'celechron_local_${DateTime.now().millisecondsSinceEpoch}.ics';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(icalContent);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: '本地课程表',
          text: '从 Celechron 导出的本地课程表文件。',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      _showAlert('成功', '本地课程表已导出，请选择保存位置或分享');
    } on Object catch (error) {
      _showAlert('错误', '导出失败: $error', isError: true);
    }
  }

  static void _showAlert(String title, String message, {bool isError = false}) {
    Get.dialog(
      CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: isError,
            onPressed: Get.back,
            child: const Text('确定'),
          ),
        ],
      ),
      barrierDismissible: true,
    );
  }

  static Future<Rect?> _calculateSharePositionOrigin(
    BuildContext? context,
  ) async {
    if (context == null || !Platform.isIOS) return null;
    final iosInfo = await DeviceInfoPlugin().iosInfo;
    if (!iosInfo.model.toLowerCase().contains('ipad') || !context.mounted) {
      return null;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}
