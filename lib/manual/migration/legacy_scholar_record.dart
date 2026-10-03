import 'dart:convert';

import 'package:hive/hive.dart';

/// Neutral projection of the old Hive typeId 5 JSON value. It intentionally
/// does not construct the application's Scholar/authentication aggregate.
final class LegacyScholarRecord {
  const LegacyScholarRecord(this.fields);

  final Map<String, Object?> fields;
}

final class LegacyScholarRecordAdapter
    extends TypeAdapter<LegacyScholarRecord> {
  @override
  int get typeId => 5;

  @override
  LegacyScholarRecord read(BinaryReader reader) {
    final decoded = jsonDecode(reader.readString());
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw const FormatException('旧 Scholar JSON 不是字符串键对象');
    }
    return LegacyScholarRecord(Map<String, Object?>.from(decoded));
  }

  @override
  void write(BinaryWriter writer, LegacyScholarRecord record) {
    writer.writeString(jsonEncode(record.fields));
  }
}
