import 'package:celechron/page/option/credits_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('credits render from the local contributor list', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(home: CreditsPage(version: 'test')),
    );

    expect(find.text('test 版本'), findsOneWidget);
    expect(find.text('nosig'), findsNWidgets(2));
    for (final contributor in [
      'iotang',
      'cxz66666',
      'Azuk 443',
      'FoggyDawn',
      'poormonitor',
      'heddxh',
      'ChenyuHeee',
    ]) {
      expect(find.text(contributor), findsOneWidget);
    }
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });
}
