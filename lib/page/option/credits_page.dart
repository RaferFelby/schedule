import 'package:flutter/cupertino.dart';
import 'package:celechron/design/persistent_headers.dart';

class CreditsPage extends StatelessWidget {
  final String version;
  const CreditsPage({required this.version, super.key});

  static const _contributors = [
    'nosig',
    'iotang',
    'cxz66666',
    'Azuk 443',
    'FoggyDawn',
    'poormonitor',
    'heddxh',
    'ChenyuHeee',
  ];

  List<Widget> _buildContributorRows() {
    final rows = <Widget>[];
    for (var i = 0; i < _contributors.length; i += 2) {
      rows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(_contributors[i], textAlign: TextAlign.center),
            ),
            if (i + 1 < _contributors.length)
              Expanded(
                child: Text(_contributors[i + 1], textAlign: TextAlign.center),
              ),
          ],
        ),
      );
      if (i + 2 < _contributors.length) {
        rows.add(const SizedBox(height: 12));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            const CelechronSliverTextHeader(subtitle: '关于'),
            SliverToBoxAdapter(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 64),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/logo.png', height: 108),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          const Text(
                            'Celechron',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 32),
                          ),
                          Text(
                            '$version 版本',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '制作人员',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '🎨设计',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: Text('nosig', textAlign: TextAlign.center)),
                        Expanded(
                          child:
                              Text('空之探险队的 Kate', textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '🧑‍💻开发',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(children: _buildContributorRows()),
                  ),
                ],
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '本程序采用 GPLv3 协议开源',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondaryLabel,
                        context,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '浙ICP备2024061973号-2A',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondaryLabel,
                        context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
