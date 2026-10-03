import 'package:celechron/page/option/ecard_disabled_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('legacy payment route explains that the feature is disabled',
      (tester) async {
    await tester.pumpWidget(const CupertinoApp(home: ECardDisabledPage()));

    expect(find.text('校园卡付款码'), findsOneWidget);
    expect(find.text('校园卡付款码功能已停用。请使用学校官方渠道完成支付。'), findsOneWidget);
    expect(find.byType(CupertinoButton), findsNothing);
  });
}
