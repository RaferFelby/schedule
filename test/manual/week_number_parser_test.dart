import 'package:celechron/manual/service/week_number_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts explicit weeks, ranges, Chinese separators and parity', () {
    expect(WeekNumberParser.parse('1,3,5'), [1, 3, 5]);
    expect(WeekNumberParser.parse('第1至6周（双）'), [2, 4, 6]);
    expect(WeekNumberParser.parse('1-3周，5、7周'), [1, 2, 3, 5, 7]);
    expect(WeekNumberParser.extract('(1-2节)1,3,5周'), [1, 3, 5]);
    expect(WeekNumberParser.extract('(1-2节)1-3周,5-8周(单)'), [1, 2, 3, 5, 7]);
  });

  test('rejects the whole input when any token or range is invalid', () {
    for (final value in ['1,abc,3', '1,', '3-1', '0,1', '100', '1 3', 'NaN']) {
      expect(WeekNumberParser.parse(value), isEmpty, reason: value);
    }
  });

  test('keeps truncated PDF week expressions incomplete', () {
    for (final text in ['1-3周,5-17', '1-2周,9-1', '-3周', '111周', '1,错误,3周']) {
      expect(WeekNumberParser.extract(text), isEmpty, reason: text);
    }
  });
}
