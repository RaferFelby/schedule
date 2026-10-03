import 'package:celechron/utils/json_utils.dart';
import 'package:celechron/manual/model/grading_policy.dart';

class Grade {
  String id; // 课程号
  String name; // 课程名
  double credit; // 学分
  String original; // 原始成绩
  double fivePoint; // 五分制成绩
  late double fourPoint; // 四分制成绩（4.3 满分）
  late double fourPointLegacy; // 原始的四分制成绩
  late int hundredPoint; // 百分制成绩
  bool major = false; // 计入主修
  bool? isOnline = false; // grs成绩使用这个字段标志是不是线上上课(hack)
  // 计入GPA（弃修、待录、缓考、二级制的不计）
  late bool gpaIncluded;
  // 计入学分（弃修、待录、缓考的不计）
  late bool creditIncluded;

  // 获得的学分（挂科、不计学分的不计）
  double get earnedCredit =>
      (creditIncluded && (fivePoint != 0 || id.contains('xtwkc')))
          ? credit
          : 0.0;

  // only used for ugrs
  String get semesterId => id.length > 12 ? id.substring(1, 12) : "研究生请勿使用此函数";

  String get realId {
    var matchClass = RegExp(r'(\(.*\)-.*?)-.*').firstMatch(id);
    var key = matchClass?.group(1);
    key ??= id.length < 22 ? id : id.substring(0, 22);
    return key;
  }

  Grade.empty()
      : id = "",
        name = "",
        credit = 0.0,
        original = "",
        fivePoint = 0.0;

  // 从所有成绩查询处爬取，因此不含主修标记
  factory Grade(Map<String, dynamic> json) {
    final id = asString(json['xkkh']);
    if (id == null || id.isEmpty) {
      throw const FormatException('成绩缺少选课课号 xkkh');
    }
    final grade = Grade.empty()
      ..id = id
      ..name = (asString(json['kcmc']) ?? '未知课程')
          .replaceAll('(', '（')
          .replaceAll(')', '）')
      ..credit = asDouble(json['xf']) ?? 0.0
      ..original = asString(json['cj']) ?? ''
      ..fivePoint = asDouble(json['jd']) ?? 0.0;
    grade._completeDerivedFields();
    return grade;
  }

  void _completeDerivedFields() {
    hundredPoint = GradingMethodPolicy.importedLabelToHundredPoint(original);
    fourPoint =
        GradingMethodPolicy.importedFivePointToFourPointValue(fivePoint);
    fourPointLegacy = fivePoint > 4.0 ? 4.0 : fivePoint;
    creditIncluded = original != "弃修" &&
        original != "待录" &&
        original != "缓考" &&
        original != "无效";
    gpaIncluded = creditIncluded &&
        original != "合格" &&
        original != "不合格" &&
        !id.contains('xtwkc');
  }

  // 从主修成绩查询处爬取，因此打上主修标记
  factory Grade.fromMajor(Map<String, dynamic> json) {
    final grade = Grade(json)..major = true;
    return grade;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'credit': credit,
        'original': original,
        'fivePoint': fivePoint,
        'fourPoint': fourPoint,
        'fourPointLegacy': fourPointLegacy,
        'hundredPoint': hundredPoint,
        'gpaIncluded': gpaIncluded,
        'creditIncluded': creditIncluded,
      };

  Grade.fromJson(Map<String, dynamic> json)
      : id = asString(json['id']) ?? '',
        name = asString(json['name']) ?? '未知课程',
        credit = asDouble(json['credit']) ?? 0.0,
        original = asString(json['original']) ?? '',
        fivePoint = asDouble(json['fivePoint']) ?? 0.0,
        fourPoint = asDouble(json['fourPoint']) ?? 0.0,
        fourPointLegacy = asDouble(json['fourPointLegacy']) ?? 0.0,
        hundredPoint = asInt(json['hundredPoint']) ?? 0,
        gpaIncluded = asBool(json['gpaIncluded']) ?? false,
        creditIncluded = asBool(json['creditIncluded']) ?? false;
}
