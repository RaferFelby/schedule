import 'package:flutter/cupertino.dart';

/// Landing page for the legacy payment-code deep link.
///
/// The old link remains registered so an existing QR code or widget opens a
/// useful local explanation instead of starting the retired network flow.
class ECardDisabledPage extends StatelessWidget {
  const ECardDisabledPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('校园卡付款码'),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '校园卡付款码功能已停用。请使用学校官方渠道完成支付。',
              textAlign: TextAlign.center,
              style: CupertinoTheme.of(context).textTheme.textStyle,
            ),
          ),
        ),
      ),
    );
  }
}
