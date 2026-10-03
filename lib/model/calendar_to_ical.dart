import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/manual/service/ical_period_encoder.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// iCal日历格式转换器
/// 将课程信息转换为iCal格式，支持导入到各种日历应用
///
/// 主要功能:
/// - iCal生成: [generateIcal], [generateIcalFromScholar], [generateIcalFromSemester]
/// - 文件导出: [exportIcsFile], [exportSpecificSemester], [exportAllSemesters]
/// - 学期管理: [getAvailableSemesters]
/// - UI交互: [showExportDialog], [_showSemesterSelectionDialog]
/// - 统计功能: [getCalendarStatistics]
///
/// 通用 Period 编码委托给不读取 Scholar 或 UI 的 IcalPeriodEncoder。
/// 本类其余入口保留旧 Scholar 导出及用户分享界面。
/// - [_showAlert]: 显示提示弹窗
/// - [_isIPad]: 判断是否为 iPad
/// - [_calculateSharePositionOrigin]: 计算分享位置（iPad必需）

class CalendarToIcal {
  /// iCal日期格式常量
  static const String dateLayoutUTC = "yyyyMMddTHHmmssZ";

  /// 生成完整的iCal日历文件
  static String generateIcal({
    required List<Period> periods,
    String calendarName = "浙大课程表",
    bool includeExams = true,
  }) =>
      IcalPeriodEncoder.generate(
        periods: periods,
        calendarName: calendarName,
        includeExams: includeExams,
      );

  /// 显示提示弹窗
  static void _showAlert(String title, String message, {bool isError = false}) {
    Get.dialog(
      CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Get.back(),
          ),
        ],
      ),
      barrierDismissible: true,
    );
  }

  /// 判断是否为 iPad
  static Future<bool> _isIPad() async {
    if (!Platform.isIOS) return false;
    final deviceInfo = DeviceInfoPlugin();
    final iosInfo = await deviceInfo.iosInfo;
    return iosInfo.model.toLowerCase().contains('ipad');
  }

  /// 计算分享位置（iPad 必需）
  static Future<Rect?> _calculateSharePositionOrigin(
      BuildContext? context) async {
    if (context == null) return null;
    if (!(await _isIPad())) return null;
    // 检查 context 是否仍然有效（避免在 async gap 后使用无效的 context）
    if (!context.mounted) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  /// 从Scholar对象生成iCal
  static String generateIcalFromScholar({
    required Scholar scholar,
    String? semesterName,
    String calendarName = "浙大课程表",
    bool includeExams = true,
    bool includeAllSemesters = false,
  }) {
    List<Period> periods = [];

    if (includeAllSemesters) {
      // 包含所有学期
      periods = scholar.periods;
    } else if (semesterName != null) {
      // 指定学期
      final semester = scholar.semesters.firstWhere(
        (s) => s.name == semesterName,
        orElse: () => scholar.thisSemester,
      );
      periods = semester.periods;
    } else {
      // 当前学期
      periods = scholar.thisSemester.periods;
    }

    return generateIcal(
      periods: periods,
      calendarName: calendarName,
      includeExams: includeExams,
    );
  }

  /// 从指定学期生成iCal
  static String generateIcalFromSemester({
    required Semester semester,
    String? calendarName,
    bool includeExams = true,
  }) {
    final name = calendarName ?? '${semester.name} 课程表';
    return generateIcal(
      periods: semester.periods,
      calendarName: name,
      includeExams: includeExams,
    );
  }

  /// 导出ICS课程表文件
  static Future<void> exportIcsFile(
    Scholar scholar, {
    BuildContext? context,
  }) async {
    try {
      if (!scholar.isLogan) {
        _showAlert('提示', '请先登录后再导出课程表');
        return;
      }

      // 在异步操作前计算分享位置，避免跨异步间隙使用 BuildContext
      final sharePositionOrigin = await _calculateSharePositionOrigin(context);

      // 生成iCal内容
      final icalContent = generateIcalFromScholar(
        scholar: scholar,
        calendarName: "浙大课程表-${scholar.thisSemester.name}",
        includeExams: true,
      );

      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'celechron_schedule_${DateTime.now().millisecondsSinceEpoch}.ics';
      final tempFile = File('${directory.path}/$fileName');

      // 写入临时文件
      await tempFile.writeAsString(icalContent);

      // 使用系统分享功能
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          subject: '浙大课程表',
          text: '从 Celechron 导出的课程表文件，可导入到其他日历应用中使用。',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      _showAlert('成功', '课程表已导出，请选择保存位置或分享');
    } catch (e) {
      _showAlert('错误', '导出失败: $e', isError: true);
    }
  }

  /// 导出指定学期
  static Future<void> exportSpecificSemester(
    Scholar scholar,
    String semesterName, {
    BuildContext? context,
  }) async {
    try {
      // 在异步操作前计算分享位置，避免跨异步间隙使用 BuildContext
      final sharePositionOrigin = await _calculateSharePositionOrigin(context);

      final icalContent = generateIcalFromScholar(
        scholar: scholar,
        semesterName: semesterName,
        calendarName: "浙大课程表-$semesterName",
        includeExams: true,
      );

      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'celechron_${semesterName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.ics';
      final tempFile = File('${directory.path}/$fileName');

      await tempFile.writeAsString(icalContent);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          subject: '浙大课程表-$semesterName',
          text: '从 Celechron 导出的 $semesterName 课程表文件。',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      _showAlert('成功', '$semesterName 课程表已导出');
    } catch (e) {
      _showAlert('错误', '导出失败: $e', isError: true);
    }
  }

  /// 导出所有学期
  static Future<void> exportAllSemesters(
    Scholar scholar, {
    BuildContext? context,
  }) async {
    try {
      // 在异步操作前计算分享位置，避免跨异步间隙使用 BuildContext
      final sharePositionOrigin = await _calculateSharePositionOrigin(context);

      final icalContent = generateIcalFromScholar(
        scholar: scholar,
        calendarName: "课程表-完整版",
        includeExams: true,
        includeAllSemesters: true,
      );

      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'celechron_all_semesters_${DateTime.now().millisecondsSinceEpoch}.ics';
      final tempFile = File('${directory.path}/$fileName');

      await tempFile.writeAsString(icalContent);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          subject: '浙大课程表-完整版',
          text: '从 Celechron 导出的完整课程表文件，包含所有学期。',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      _showAlert('成功', '完整课程表已导出');
    } catch (e) {
      _showAlert('错误', '导出失败: $e', isError: true);
    }
  }

  /// 获取可用的学期列表
  static List<String> getAvailableSemesters(Scholar scholar) {
    return scholar.semesters.map((s) => s.name).toList();
  }

  /// 显示导出课程表对话框
  static void showExportDialog(BuildContext context, Scholar scholar) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext popupContext) => CupertinoActionSheet(
        title: const Text('导出课程表'),
        message: const Text('选择导出方式'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(popupContext);
              exportIcsFile(scholar, context: popupContext);
            },
            child: const Text('导出当前学期'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(popupContext);
              _showSemesterSelectionDialog(context, scholar);
            },
            child: const Text('选择学期导出'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(popupContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 显示学期选择对话框（UI界面）
  static void _showSemesterSelectionDialog(
      BuildContext context, Scholar scholar) {
    final semesters = getAvailableSemesters(scholar);

    if (semesters.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (BuildContext dialogContext) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('没有可导出的课程表数据'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ],
        ),
      );
      return;
    }

    /// 显示学期选择对话框 （UI界面）
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext popupContext) => CupertinoActionSheet(
        title: const Text('选择学期'),
        message: const Text('选择要导出的学期'),
        actions: [
          ...semesters.map((semester) => CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(popupContext);
                  exportSpecificSemester(scholar, semester,
                      context: popupContext);
                },
                child: Text(semester),
              )),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(popupContext);
              exportAllSemesters(scholar, context: popupContext);
            },
            child: const Text('导出所有学期'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(popupContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 生成课程统计信息
  static Map<String, dynamic> getCalendarStatistics(List<Period> periods) {
    final stats = <String, dynamic>{};

    // 按类型统计
    final typeCount = <PeriodType, int>{};
    for (final period in periods) {
      typeCount[period.type] = (typeCount[period.type] ?? 0) + 1;
    }

    stats['totalEvents'] = periods.length;
    stats['courseCount'] = typeCount[PeriodType.classes] ?? 0;
    stats['examCount'] = typeCount[PeriodType.test] ?? 0;
    stats['userEventCount'] = typeCount[PeriodType.user] ?? 0;
    stats['flowCount'] = typeCount[PeriodType.flow] ?? 0;

    // 时间范围
    if (periods.isNotEmpty) {
      final sortedPeriods = List<Period>.from(periods)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      stats['startDate'] = sortedPeriods.first.startTime;
      stats['endDate'] = sortedPeriods.last.endTime;
    }

    return stats;
  }
}
