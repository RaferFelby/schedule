import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart'
    show Brightness, Icons, MaterialApp, ThemeData, ThemeMode;
import 'package:hive/hive.dart';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/page/semester_list_page.dart';
import 'package:celechron/manual/page/manual_calendar_page.dart';
import 'package:celechron/manual/page/manual_upcoming_preview_page.dart';
import 'package:celechron/manual/page/manual_homework_preview_page.dart';
import 'package:celechron/debug/manual_preview_task_store.dart';
import 'package:celechron/manual/page/manual_settings_page.dart';
import 'package:celechron/manual/data/storage_generation.dart';
import 'package:celechron/manual/model/manual_user_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.title,
    required this.manualAcademicRepository,
    required this.manualTaskBox,
    required this.manualActiveGeneration,
    required this.preferences,
    required this.onPreferencesChanged,
    this.onRestoreBackup,
  });

  final String title;

  /// When provided, the academic tab reads and writes the active local profile.
  final AcademicRepository manualAcademicRepository;

  /// Task storage used to keep course/semester deletion associations consistent.
  final Box<String> manualTaskBox;
  final StorageGenerationManifest manualActiveGeneration;
  final ManualUserPreferences preferences;
  final ValueChanged<ManualUserPreferences> onPreferencesChanged;
  final Future<void> Function(String backupJson)? onRestoreBackup;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _indexNum = 0;
  final PageController _pageController = PageController();
  final GlobalKey<ManualCalendarPageState> _manualCalendarKey =
      GlobalKey<ManualCalendarPageState>();
  final GlobalKey<ManualUpcomingPreviewPageState> _manualUpcomingKey =
      GlobalKey<ManualUpcomingPreviewPageState>();

  // 只构建一次，保持各页 widget 身份稳定，切页时不会重跑各页构造器里的 Get.put
  late List<Widget> _pages;

  List<Widget> _makePages() => [
        _KeepAlivePage(
          child: MaterialApp(
            theme: ThemeData(
                brightness: widget.preferences.brightness ?? Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: widget.preferences.brightness == null
                ? ThemeMode.system
                : ThemeMode.values.firstWhere(
                    (mode) => mode.name == widget.preferences.theme),
            home: ManualUpcomingPreviewPage(
              key: _manualUpcomingKey,
              repository: widget.manualAcademicRepository,
              preferences: widget.preferences,
              onOpenSemesters: () => _pageController.jumpToPage(3),
              onOpenTasks: () => _pageController.jumpToPage(2),
              taskLoader: () =>
                  ManualPreviewTaskStore(widget.manualTaskBox).readTasks(),
            ),
          ),
        ),
        _KeepAlivePage(
          child: MaterialApp(
            theme: ThemeData(
                brightness: widget.preferences.brightness ?? Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: widget.preferences.brightness == null
                ? ThemeMode.system
                : ThemeMode.values.firstWhere(
                    (mode) => mode.name == widget.preferences.theme),
            home: ManualCalendarPage(
              key: _manualCalendarKey,
              repository: widget.manualAcademicRepository,
            ),
          ),
        ),
        _KeepAlivePage(
          child: MaterialApp(
            theme: ThemeData(
                brightness: widget.preferences.brightness ?? Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: widget.preferences.brightness == null
                ? ThemeMode.system
                : ThemeMode.values.firstWhere(
                    (mode) => mode.name == widget.preferences.theme),
            home: ManualHomeworkPreviewPage(
              previewBox: widget.manualTaskBox,
              repository: widget.manualAcademicRepository,
            ),
          ),
        ),
        _KeepAlivePage(
          child: SemesterListPage(
            repository: widget.manualAcademicRepository,
            previewBox: widget.manualTaskBox,
          ),
        ),
        _KeepAlivePage(
          child: MaterialApp(
            theme: ThemeData(
                brightness: widget.preferences.brightness ?? Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: widget.preferences.brightness == null
                ? ThemeMode.system
                : ThemeMode.values.firstWhere(
                    (mode) => mode.name == widget.preferences.theme),
            home: ManualSettingsPage(
              repository: widget.manualAcademicRepository,
              taskBox: widget.manualTaskBox,
              activeGeneration: widget.manualActiveGeneration,
              preferences: widget.preferences,
              onPreferencesChanged: widget.onPreferencesChanged,
              onRestoreBackup: widget.onRestoreBackup,
            ),
          ),
        ),
      ];

  @override
  void initState() {
    super.initState();
    _pages = _makePages();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) _pages = _makePages();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabBar = CupertinoTabBar(
      iconSize: 26,
      backgroundColor: CupertinoDynamicColor.resolve(
              CupertinoColors.secondarySystemBackground, context)
          .withValues(alpha: 0.5),
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.time),
          label: '接下来',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.calendar),
          label: '日程',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.check_mark),
          label: '任务',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.school_rounded),
          label: '学业',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.settings),
          label: '设置',
        ),
      ],
      currentIndex: _indexNum,
      // 点按瞬时切换（iOS 原生习惯）。jumpToPage 会同步触发 onPageChanged，
      // _indexNum 只在 onPageChanged 里更新，这里不再 setState
      onTap: (int index) => _pageController.jumpToPage(index),
    );

    final ScrollBehavior scrollBehavior = ScrollConfiguration.of(context);
    // HeroMode 关闭：原先嵌套 CupertinoTabView 导航器会屏蔽标签页内的 Hero
    // 飞行动画（如学业页成绩卡片），这里显式关闭以保持原有行为
    Widget content = HeroMode(
      enabled: false,
      child: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          if (index == 0) {
            unawaited(_manualUpcomingKey.currentState?.refresh() ??
                Future<void>.value());
          }
          if (index == 1) {
            unawaited(_manualCalendarKey.currentState?.refresh() ??
                Future<void>.value());
          }
          if (index != _indexNum) {
            setState(() {
              _indexNum = index;
            });
          }
        },
        // 允许鼠标拖动切页（与原 GestureDetector 行为一致），只作用于本 PageView，
        // 不影响页面内部列表；scrollbars 必须关掉，否则桌面端会叠一条横向滚动条
        scrollBehavior: scrollBehavior.copyWith(
          scrollbars: false,
          dragDevices: {
            ...scrollBehavior.dragDevices,
            PointerDeviceKind.mouse,
          },
        ),
        children: _pages,
      ),
    );

    // 以下复刻 CupertinoTabScaffold（resizeToAvoidBottomInset: true）的布局逻辑：
    // 键盘高度转为内容 Padding 并从子 MediaQuery 移除；本应用标签栏为半透明
    // （alpha 0.5），栏高只注入 MediaQuery.padding，内容延伸到栏后方由各页
    // SafeArea 自行避让
    final MediaQueryData existingMediaQuery = MediaQuery.of(context);
    MediaQueryData newMediaQuery =
        existingMediaQuery.removeViewInsets(removeBottom: true);
    final EdgeInsets contentPadding =
        EdgeInsets.only(bottom: existingMediaQuery.viewInsets.bottom);

    // 键盘完全盖住标签栏时不再为栏高留白
    if (tabBar.preferredSize.height > existingMediaQuery.viewInsets.bottom) {
      final double bottomPadding =
          tabBar.preferredSize.height + existingMediaQuery.padding.bottom;
      newMediaQuery = newMediaQuery.copyWith(
        padding: newMediaQuery.padding.copyWith(bottom: bottomPadding),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).scaffoldBackgroundColor,
      ),
      child: Stack(
        children: [
          // 内容在下层，半透明标签栏的 BackdropFilter 才有内容可模糊
          MediaQuery(
            data: newMediaQuery,
            child: Padding(padding: contentPadding, child: content),
          ),
          // 标签栏放在修改后的 MediaQuery 之外，读原始 viewPadding 计算安全区
          MediaQuery.withNoTextScaling(
            child: Align(alignment: Alignment.bottomCenter, child: tabBar),
          ),
        ],
      ),
    );
  }
}

// 离屏页面保活：保留滚动位置等临时状态，等价于原先 CupertinoTabScaffold
// 对已构建标签页的常驻行为
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
