import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show AppBar, FilledButton, MaterialApp, Scaffold;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive/hive.dart';
import 'package:app_links/app_links.dart';
import 'package:path_provider/path_provider.dart';

import 'package:celechron/page/home_page.dart';
import 'package:celechron/page/option/ecard_disabled_page.dart';
import 'package:celechron/utils/global.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/legacy_credential_cleanup.dart';
import 'package:celechron/debug/manual_preview_generation_access.dart';
import 'package:celechron/debug/manual_preview_task_store.dart';
import 'package:celechron/manual/bootstrap/local_application_bootstrap.dart';
import 'package:celechron/manual/data/manual_user_preferences_store.dart';
import 'package:celechron/manual/model/manual_user_preferences.dart';
import 'package:celechron/manual/migration/legacy_migration_coordinator.dart';
import 'package:celechron/manual/migration/migration_resolution_store.dart';
import 'package:celechron/manual/page/migration_result_page.dart';
import 'package:celechron/manual/service/course_deletion_coordinator.dart';
import 'package:celechron/manual/service/manual_preview_restore_coordinator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  final support = await getApplicationSupportDirectory();
  Hive.init(documents.path);
  LocalApplicationBootstrapResult? result;
  Object? startupError;
  try {
    await const LegacyCredentialCleanup().run(
      applicationSupportPath: support.path,
    );
    result = await const LocalApplicationBootstrap().run(
      documentsPath: documents.path,
      applicationSupportPath: support.path,
    );
  } on Object catch (error, stackTrace) {
    startupError = error;
    DiagnosticLogService.instance.record(
      level: CelechronLogLevel.error,
      module: '本地启动',
      operation: 'bootstrap',
      message: '本地数据初始化未完成，可重试；旧数据未删除',
      error: error,
      stackTrace: stackTrace,
    );
  }
  runApp(LocalCelechronApp(
    documentsPath: documents.path,
    applicationSupportPath: support.path,
    initialResult: result,
    startupError: startupError,
  ));
}

class LocalCelechronApp extends StatefulWidget {
  const LocalCelechronApp({
    super.key,
    required this.documentsPath,
    required this.applicationSupportPath,
    this.initialResult,
    this.startupError,
  });

  final String documentsPath;
  final String applicationSupportPath;
  final LocalApplicationBootstrapResult? initialResult;
  final Object? startupError;

  @override
  State<LocalCelechronApp> createState() => _LocalCelechronAppState();
}

class _LocalCelechronAppState extends State<LocalCelechronApp> {
  late LocalApplicationBootstrapResult? _result = widget.initialResult;
  Object? _startupError;
  bool _retrying = false;
  ManualUserPreferences _preferences = const ManualUserPreferences();

  @override
  void initState() {
    super.initState();
    _startupError = widget.startupError;
    _initAppLinks();
    _initNotification();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final generation = _result?.access.generation;
    if (generation == null) return;
    final preferences = await ManualUserPreferencesStore(generation).read();
    if (mounted) setState(() => _preferences = preferences);
  }

  Future<void> _retryBootstrap() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _startupError = null;
    });
    try {
      await Hive.close();
      Hive.init(widget.documentsPath);
      await const LegacyCredentialCleanup().run(
        applicationSupportPath: widget.applicationSupportPath,
      );
      final result = await const LocalApplicationBootstrap().run(
        documentsPath: widget.documentsPath,
        applicationSupportPath: widget.applicationSupportPath,
      );
      if (mounted) setState(() => _result = result);
      await _loadPreferences();
    } on Object catch (error, stackTrace) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.error,
        module: '本地启动',
        operation: 'bootstrapRetry',
        message: '本地数据初始化重试未完成；旧数据未删除',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _startupError = error);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _restoreBackup(String backupJson) async {
    final current = _result?.access;
    if (current == null) throw StateError('活动本地数据尚未准备好');
    await ManualPreviewRestoreCoordinator(access: current)
        .restoreAndActivate(backupJson);
    await Hive.close();
    final next = await ManualPreviewGenerationAccess.openLocalAt(
      widget.documentsPath,
    );
    await CourseDeletionCoordinator(
      repository: next.academicRepository,
      previewBox: next.previewBox,
    ).recoverPending();
    await ManualPreviewTaskStore(next.previewBox).reconcileReminders();
    final preferences =
        await ManualUserPreferencesStore(next.generation).read();
    if (mounted) {
      setState(() {
        _preferences = preferences;
        _result = LocalApplicationBootstrapResult(
          access: next,
          migration: const LegacyMigrationOutcome(
            status: LegacyMigrationStatus.noLegacyData,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (_startupError != null || result == null) {
      return MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('本地启动未完成')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('本地数据初始化未完成：${_startupError ?? '正在准备'}'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _retrying ? null : _retryBootstrap,
                    child: Text(_retrying ? '正在重试…' : '重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (result.isBlocked) {
      return MaterialApp(
        home: MigrationResultPage(
          report: result.migration.assembly!.report,
          onSkipIssue: _skipMigrationIssue,
          onCorrectIssue: _correctMigrationIssue,
        ),
      );
    }

    return CupertinoApp(
      theme: CupertinoThemeData(
        brightness: _preferences.brightness ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      locale: const Locale('zh'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      title: 'Celechron',
      home: HomePage(
        key: ValueKey(result.access.generation.generationId),
        title: 'Celechron',
        manualAcademicRepository: result.access.academicRepository,
        manualTaskBox: result.access.previewBox,
        manualActiveGeneration: result.access.generation,
        preferences: _preferences,
        onPreferencesChanged: (value) => setState(() => _preferences = value),
        onRestoreBackup: _restoreBackup,
      ),
      routes: {'/ecardpaypage': (context) => const ECardDisabledPage()},
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
    );
  }

  Future<void> _skipMigrationIssue(String issueCode) async {
    final resolutionPath =
        '${widget.applicationSupportPath}${Platform.pathSeparator}'
        '${MigrationResolutionStore.fileName}';
    await MigrationResolutionStore(resolutionPath).skipIssue(issueCode);
    await _retryBootstrap();
  }

  Future<void> _correctMigrationIssue(
    String issueCode,
    Object? correctedRecord,
  ) async {
    final resolutionPath =
        '${widget.applicationSupportPath}${Platform.pathSeparator}'
        '${MigrationResolutionStore.fileName}';
    await MigrationResolutionStore(resolutionPath)
        .saveCorrection(issueCode, correctedRecord);
    await _retryBootstrap();
  }

  void _initAppLinks() {
    AppLinks().uriLinkStream.listen((uri) {
      if (uri.toString() == 'celechron://ecardpaypage') {
        navigatorKey.currentState?.popUntil((route) =>
            !(route.settings.name?.endsWith('ecardpaypage') ?? false));
        navigatorKey.currentState?.pushNamed('/ecardpaypage');
      }
    });
  }

  void _initNotification() {
    final plugin = FlutterLocalNotificationsPlugin();
    const darwin = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    plugin.initialize(const InitializationSettings(
      iOS: darwin,
    ));
  }
}
