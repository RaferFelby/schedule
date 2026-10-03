/// Legacy version-cache projection.
///
/// Version checks were retired. Keep this Hive payload readable so upgrades can
/// open and migrate the historical `dbFuse` box without changing its type ID.
class Fuse {
  late DateTime lastUpdateTime;

  final bool isBeta = false;
  final version = [1, 3, 0];
  final build = 1;
  bool hasNewVersion = false;

  String get displayVersion => version.join('.') + (isBeta ? ' beta' : '');

  Fuse() {
    lastUpdateTime = DateTime(2001, 1, 1);
  }

  Map<String, dynamic> toJson() => {
        'lastUpdateTime': lastUpdateTime.toIso8601String(),
      };

  Fuse.fromJson(Map<String, dynamic> json) {
    lastUpdateTime = DateTime.parse(json['lastUpdateTime']);
  }
}
