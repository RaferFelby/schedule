import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:celechron/page/option/option_controller.dart';
import 'package:celechron/utils/json_utils.dart';
import 'package:celechron/model/practice_score_item.dart';

import 'period.dart';
import 'grade.dart';
import 'semester.dart';
import 'todo.dart';
import 'package:celechron/utils/gpa_helper.dart';
import 'package:celechron/database/database_helper.dart';

const _degradedRefreshMarker = '<<<CELECHRON_DEGRADED>>>';

class Scholar {
  Scholar();

  // 构造用户对象
  DatabaseHelper? _db;

  set db(DatabaseHelper? db) {
    _db = db;
  }

  // 登录状态
  bool isLogan = false;
  DateTime lastUpdateTimeGrade = DateTime.parse("20010101");
  DateTime lastUpdateTimeCourse = DateTime.parse("20010101");
  DateTime lastUpdateTimeHomework = DateTime.parse("20010101");

  // 按学期整理好的学业信息，包括该学期的所有科目、考试、课表、均绩等
  List<Semester> semesters = <Semester>[];

  // 按课程号整理好的成绩单（方便算重修成绩）
  Map<String, List<Grade>> grades = {};

  // 保研 GPA, 四个数据依次为五分制、四分制（4.3 分制）、原始的四分制、百分制
  List<double> gpa = [0.0, 0.0, 0.0, 0.0];

  // 出国 GPA, 四个数据依次为五分制、四分制（4.3 分制）、原始的四分制、百分制
  List<double> aboardGpa = [0.0, 0.0, 0.0, 0.0];

  // 所获学分
  double credit = 0.0;

  // 主修成绩，两个数据依次为主修GPA，主修学分
  List<double> majorGpaAndCredit = [0.0, 0.0];

  // 特殊日期
  Map<DateTime, String> specialDates = {};

  // 作业（学在浙大）
  List<Todo> todos = [];

  // 素质拓展记点；Jf 是“记点”。
  double pt2 = 0.0; // 第二课堂记点
  double pt3 = 0.0; // 第三课堂记点
  double pt4 = 0.0; // 第四课堂记点
  bool isPracticeScoresGet = false; // 是否有可展示的二三四课堂记点
  List<PracticeScoreItem> practiceScoreItems = [];
  // 明细来源始终只描述 getSqjl，不与外层正式汇总混用。
  PracticeDataSource practiceDataSource = PracticeDataSource.unavailable;
  PracticeSummarySource practiceSummarySource =
      PracticeSummarySource.unavailable;
  DateTime? practiceUpdatedAt;
  DateTime? practiceDetailsUpdatedAt;
  bool practiceDetailsAvailable = false;
  bool practiceDetailsStale = false;
  bool practiceSummaryStale = false;
  bool? practiceMyPassed;
  bool? practiceLyPassed;

  /// 总记点只由第二、第三、第四课堂三个记点字段组成。
  double get practiceTotalJf => pt2 + pt3 + pt4;

  int get gradedCourseCount {
    return grades.values.fold(0, (p, e) => p + e.length);
  }

  List<Period> get periods {
    return semesters.fold(<Period>[], (p, e) => p + e.periods);
  }

  Semester get thisSemester {
    if (semesters.length > 1) {
      if (semesters[1]
          .periods
          .last
          .endTime
          .isAfter(DateTime.now().subtract(const Duration(days: 14)))) {
        return semesters[1];
      } else {
        return semesters[0];
      }
    } else {
      return semesters.isEmpty ? Semester('未刷新') : semesters.first;
    }
  }

  bool get isNearExamWeek {
    var thisSem = thisSemester;
    for (var exam in thisSem.exams) {
      var now = DateTime.now();
      if (now.isAfter(exam.time[0].subtract(const Duration(days: 3))) &&
          now.isBefore(exam.time[0].add(const Duration(days: 3)))) {
        return true;
      }
    }
    return false;
  }

  Future<bool> logout() async {
    semesters = [];
    grades = {};
    gpa = [0.0, 0.0, 0.0, 0.0];
    aboardGpa = [0.0, 0.0, 0.0, 0.0];
    credit = 0.0;
    majorGpaAndCredit = [0.0, 0.0];
    pt2 = 0.0;
    pt3 = 0.0;
    pt4 = 0.0;
    isPracticeScoresGet = false;
    practiceScoreItems = [];
    practiceDataSource = PracticeDataSource.unavailable;
    practiceSummarySource = PracticeSummarySource.unavailable;
    practiceUpdatedAt = null;
    practiceDetailsUpdatedAt = null;
    practiceDetailsAvailable = false;
    practiceDetailsStale = false;
    practiceSummaryStale = false;
    practiceMyPassed = null;
    practiceLyPassed = null;
    isLogan = false;
    lastUpdateTimeGrade = DateTime.parse("20010101");
    lastUpdateTimeCourse = DateTime.parse("20010101");
    lastUpdateTimeHomework = DateTime.parse("20010101");
    await _db?.removeScholar();
    await _db?.removeAllCachedWebPage();
    return true;
  }

  void setScholar(
      List<String?> errorMessage,
      List<Semester> tempSemesters,
      Map<String, List<Grade>> tempGrades,
      List<double> tempMajorGpaAndCredit,
      Map<DateTime, String> tempSpecialDates,
      List<Todo> tempTodos,
      PracticeScoreSnapshot? tempPracticeSnapshot) {
    // 各模块独立降级：某一来源失败时保留该模块旧数据，不阻断其它成功结果。
    var errorItems = ["成绩", "主修", "课表", "作业", "实践"];
    var errorResult = [false, false, false, false, false];

    for (int i = 0; i < errorItems.length; i++) {
      for (var e in errorMessage) {
        if (e != null &&
            !e.startsWith(_degradedRefreshMarker) &&
            e.contains(errorItems[i])) {
          errorResult[i] = true;
          break;
        }
      }
    }

    if (tempSpecialDates.isNotEmpty) {
      specialDates = tempSpecialDates;
    }
    if (errorResult[0] == false && tempGrades.isNotEmpty) {
      grades = tempGrades;
    }
    if (errorResult[1] == false && tempMajorGpaAndCredit.isNotEmpty) {
      majorGpaAndCredit = tempMajorGpaAndCredit;
    }
    if (errorResult[2] == false && tempSemesters.isNotEmpty) {
      semesters = tempSemesters;
    } else if (tempSemesters.isNotEmpty) {
      // 降级刷新只合并可用片段，避免不完整新对象覆盖已有课表明细。
      for (final incoming in tempSemesters) {
        final existingIndex =
            semesters.indexWhere((semester) => semester.name == incoming.name);
        if (existingIndex < 0) {
          semesters.add(incoming);
        } else {
          semesters[existingIndex].mergePartialFrom(incoming);
        }
      }
      semesters.sort((a, b) => b.name.compareTo(a.name));
    }
    if (errorResult[3] == false) {
      todos = tempTodos;
    }
    if (tempPracticeSnapshot != null) {
      // 详情仍只采用 getSqjl；汇总独立采用 getMyInfo 的三级回退结果。
      final snapshot = tempPracticeSnapshot;
      if (snapshot.detailsAvailable) {
        practiceScoreItems = List<PracticeScoreItem>.from(snapshot.items);
        practiceDataSource = snapshot.source;
        practiceDetailsUpdatedAt = snapshot.updatedAt;
        practiceDetailsAvailable = true;
        practiceDetailsStale = snapshot.stale;
      } else if (snapshot.source == PracticeDataSource.unavailable) {
        // getSqjl 失败不能清空上一次成功明细。
        practiceDetailsAvailable = practiceScoreItems.isNotEmpty;
        practiceDetailsStale = true;
      }

      final summary = snapshot.summary;
      if (summary != null) {
        isPracticeScoresGet = true;
        practiceSummarySource = summary.source;
        practiceUpdatedAt = summary.updatedAt;
        practiceSummaryStale = summary.stale;
        practiceMyPassed = summary.myPassed;
        practiceLyPassed = summary.lyPassed;
        pt2 = summary.dektJf;
        pt3 = summary.dsktJf;
        pt4 = summary.dsiktJf;
      }
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'semesters': semesters,
      'grades': grades,
      'gpa': gpa,
      'aboardGpa': aboardGpa,
      'credit': credit,
      'majorGpaAndCredit': majorGpaAndCredit,
      'specialDates':
          specialDates.map((k, v) => MapEntry(k.toIso8601String(), v)),
      'lastUpdateTimeGrade': lastUpdateTimeGrade.toIso8601String(),
      'lastUpdateTimeCourse': lastUpdateTimeCourse.toIso8601String(),
      'lastUpdateTimeHomework': lastUpdateTimeHomework.toIso8601String(),
      'todos': todos,
      'pt2': pt2,
      'pt3': pt3,
      'pt4': pt4,
      'isPracticeScoresGet': isPracticeScoresGet,
      'practiceScoreItems':
          practiceScoreItems.map((item) => item.toJson()).toList(),
      'practiceDataSource': practiceDataSource.name,
      'practiceSummarySource': practiceSummarySource.name,
      'practiceUpdatedAt': practiceUpdatedAt?.toIso8601String(),
      'practiceDetailsUpdatedAt': practiceDetailsUpdatedAt?.toIso8601String(),
      'practiceDetailsAvailable': practiceDetailsAvailable,
      'practiceDetailsStale': practiceDetailsStale,
      'practiceSummaryStale': practiceSummaryStale,
      'practiceMyPassed': practiceMyPassed,
      'practiceLyPassed': practiceLyPassed,
    };
  }

  Future<void> recalculateGpa() async {
    grades =
        grades.values.expand((e) => e).fold(<String, List<Grade>>{}, (p, e) {
      // 体育课
      var matchClass = RegExp(r'(\(.*\)-(.*?))-.*').firstMatch(e.id);
      var key = matchClass?.group(2) ?? e.id.substring(14, 22);
      if (key.startsWith('PPAE') || key.startsWith('401')) {
        key = matchClass?.group(1) ?? e.id.substring(0, 22);
      }
      var courseIdMappingList =
          Get.find<OptionController>(tag: 'optionController')
              .courseIdMappingList;
      var courseIdMappingMap = {
        for (var e in courseIdMappingList) e.id1: e.id2
      };
      if (courseIdMappingMap.containsKey(key)) {
        key = courseIdMappingMap[key]!;
      }
      p.putIfAbsent(key, () => <Grade>[]).add(e);
      return p;
    });

    // 保研成绩，只取第一次
    var netGrades = grades.values.map((e) => e.first);
    if (netGrades.isNotEmpty) {
      gpa = GpaHelper.calculateGpa(netGrades).item1;
    }
    // 出国成绩，取最高的一次
    var aboardNetGrades = grades.values.map((e) {
      e.sort((a, b) => a.hundredPoint.compareTo(b.hundredPoint));
      return e.last;
    });
    if (aboardNetGrades.isNotEmpty) {
      var result = GpaHelper.calculateGpa(aboardNetGrades);
      aboardGpa = result.item1;
      // 所获学分，不包括挂科的。
      credit = result.item2;
    } else {
      credit = 0.0;
    }

    await _db?.setScholar(this);
  }

  Scholar.fromJson(Map<String, dynamic> json) {

    semesters = [];
    for (final rawSemester in asDynamicList(json['semesters']) ?? const []) {
      final semesterMap = asStringMap(rawSemester);
      if (semesterMap == null) continue;
      try {
        semesters.add(Semester.fromJson(semesterMap));
      } on Object catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('跳过损坏的本地学期数据：${error.runtimeType}: $error\n$stackTrace');
        }
      }
    }

    grades = {};
    final rawGrades = asStringMap(json['grades']) ?? const {};
    for (final entry in rawGrades.entries) {
      final parsedGrades = <Grade>[];
      for (final rawGrade in asDynamicList(entry.value) ?? const []) {
        final gradeMap = asStringMap(rawGrade);
        if (gradeMap == null) continue;
        try {
          final grade = Grade.fromJson(gradeMap);
          if (grade.id.isNotEmpty) parsedGrades.add(grade);
        } on Object catch (error, stackTrace) {
          if (kDebugMode) {
            debugPrint('跳过损坏的本地成绩数据：${error.runtimeType}: $error\n$stackTrace');
          }
        }
      }
      if (parsedGrades.isNotEmpty) grades[entry.key] = parsedGrades;
    }

    List<double> numberList(Object? value, int expectedLength) {
      final parsed = (asDynamicList(value) ?? const [])
          .map(asDouble)
          .whereType<double>()
          .toList();
      if (expectedLength == 4 && parsed.length == 3) {
        parsed.insert(2, 0.0);
      }
      return parsed.length == expectedLength
          ? parsed
          : List<double>.filled(expectedLength, 0.0);
    }

    gpa = numberList(json['gpa'], 4);
    aboardGpa = numberList(json['aboardGpa'], 4);
    credit = asDouble(json['credit']) ?? 0.0;
    majorGpaAndCredit = numberList(json['majorGpaAndCredit'], 2);

    specialDates = {};
    for (final entry
        in (asStringMap(json['specialDates']) ?? const {}).entries) {
      final date = asDateTime(entry.key);
      final description = asString(entry.value);
      if (date != null && description != null) {
        specialDates[date] = description;
      }
    }
    lastUpdateTimeGrade =
        asDateTime(json['lastUpdateTimeGrade']) ?? DateTime(2001);
    lastUpdateTimeCourse =
        asDateTime(json['lastUpdateTimeCourse']) ?? DateTime(2001);
    lastUpdateTimeHomework =
        asDateTime(json['lastUpdateTimeHomework']) ?? DateTime(2001);

    todos = [];
    for (final rawTodo in asDynamicList(json['todos']) ?? const []) {
      final todoMap = asStringMap(rawTodo);
      if (todoMap == null) continue;
      try {
        final todo = Todo.fromJson(todoMap);
        if (todo.id.isNotEmpty) todos.add(todo);
      } on Object catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('跳过损坏的本地作业数据：${error.runtimeType}: $error\n$stackTrace');
        }
      }
    }
    pt2 = asDouble(json['pt2']) ?? 0.0;
    pt3 = asDouble(json['pt3']) ?? 0.0;
    pt4 = asDouble(json['pt4']) ?? 0.0;
    isPracticeScoresGet = asBool(json['isPracticeScoresGet']) ?? false;
    // 字段是否存在用于区分旧版缓存与“新版缓存但项目为空”。
    final hasPracticeItemsField = json.containsKey('practiceScoreItems');
    practiceScoreItems = [];
    for (final rawItem
        in asDynamicList(json['practiceScoreItems']) ?? const []) {
      final itemMap = asStringMap(rawItem);
      if (itemMap == null) continue;
      try {
        final item = PracticeScoreItem.fromJson(itemMap);
        if (!item.deleted) practiceScoreItems.add(item);
      } on Object catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('跳过损坏的本地实践项目数据：${error.runtimeType}: $error\n$stackTrace');
        }
      }
    }
    practiceDataSource = PracticeDataSource.fromJson(
      json['practiceDataSource'],
    );
    final hasPracticeSummarySource = json.containsKey('practiceSummarySource');
    practiceSummarySource = PracticeSummarySource.fromJson(
      json['practiceSummarySource'],
    );
    practiceUpdatedAt = asDateTime(json['practiceUpdatedAt'])?.toLocal();
    practiceDetailsUpdatedAt =
        asDateTime(json['practiceDetailsUpdatedAt'])?.toLocal() ??
            practiceUpdatedAt;
    practiceDetailsAvailable = asBool(json['practiceDetailsAvailable']) ??
        (hasPracticeItemsField && practiceScoreItems.isNotEmpty);
    practiceDetailsStale = asBool(json['practiceDetailsStale']) ?? false;
    practiceSummaryStale =
        asBool(json['practiceSummaryStale']) ?? hasPracticeSummarySource;
    practiceMyPassed = asBool(json['practiceMyPassed']);
    practiceLyPassed = asBool(json['practiceLyPassed']);
    if (!json.containsKey('practiceDataSource') && isPracticeScoresGet) {
      // 旧版本只保存教务网汇总，因此恢复为无明细且过期的兼容来源。
      practiceDataSource = PracticeDataSource.zdbkCache;
      practiceDetailsAvailable = false;
      practiceDetailsStale = true;
    }
    if (!hasPracticeSummarySource &&
        hasPracticeItemsField &&
        practiceDetailsAvailable) {
      // 旧版有明细时，其外层总分原本就是 getSqjl 项目合计。
      final totals = PracticeScoreItem.approvedTotals(practiceScoreItems);
      pt2 = totals[1] ?? 0;
      pt3 = totals[2] ?? 0;
      pt4 = totals[3] ?? 0;
      practiceSummarySource = PracticeSummarySource.calculatedFromSqjl;
      practiceSummaryStale = true;
    } else if (!hasPracticeSummarySource && isPracticeScoresGet) {
      practiceSummarySource = PracticeSummarySource.legacyPersisted;
      practiceSummaryStale = true;
    } else if (practiceSummarySource == PracticeSummarySource.networkMyInfo) {
      // 从 Scholar 持久化恢复后已不是本次网络结果，按缓存语义展示。
      practiceSummarySource = PracticeSummarySource.cachedMyInfo;
      practiceSummaryStale = true;
    }
    isLogan = true;
  }
}
