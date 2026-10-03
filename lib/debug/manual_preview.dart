import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../manual/data/academic_repository.dart';
import '../manual/page/semester_list_page.dart';
import '../manual/page/manual_calendar_page.dart';
import '../manual/page/backup_preview_page.dart';
import '../manual/page/manual_course_schedule_page.dart';
import '../manual/page/practice_record_list_page.dart';
import '../manual/page/manual_homework_preview_page.dart';
import '../manual/page/manual_upcoming_preview_page.dart';
import '../manual/service/course_deletion_coordinator.dart';
import '../manual/service/manual_preview_restore_coordinator.dart';
import 'manual_preview_sample_loader.dart';
import '../manual/data/storage_generation.dart';
import 'manual_preview_generation_access.dart';
import 'manual_preview_task_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final access = await ManualPreviewGenerationAccess.open();
  final previewBox = access.previewBox;
  final repository = access.academicRepository;
  await CourseDeletionCoordinator(
    repository: repository,
    previewBox: previewBox,
  ).recoverPending();
  await ManualPreviewTaskStore(previewBox).reconcileReminders();
  runApp(ManualPreviewApp(
    previewBox: previewBox,
    repository: repository,
    activeGeneration: access.generation,
  ));
}

class ManualPreviewApp extends StatefulWidget {
  const ManualPreviewApp({
    super.key,
    required this.previewBox,
    required this.repository,
    required this.activeGeneration,
  });

  final Box<String> previewBox;
  final AcademicRepository repository;
  final StorageGenerationManifest activeGeneration;

  @override
  State<ManualPreviewApp> createState() => _ManualPreviewAppState();
}

class _ManualPreviewAppState extends State<ManualPreviewApp> {
  String? _status;

  Future<void> _loadSample() async {
    await ManualPreviewSampleLoader.load(widget.previewBox);
    if (mounted) setState(() => _status = '样例已载入预览存储');
  }

  Future<void> _clearPreviewData() async {
    await ManualPreviewSampleLoader.clear(widget.previewBox);
    if (mounted) setState(() => _status = '预览存储已清空');
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('手动录入预览')),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_status ?? '预览数据与正式数据隔离'),
                const SizedBox(height: 16),
                CupertinoButton.filled(
                  onPressed: _loadSample,
                  child: const Text('载入样例'),
                ),
                CupertinoButton(
                  onPressed: _clearPreviewData,
                  child: const Text('清空预览数据'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => SemesterListPage(
                        repository: widget.repository,
                        previewBox: widget.previewBox,
                      ),
                    ),
                  ),
                  child: const Text('查看学期'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => MaterialApp(
                        home: ManualCalendarPage(repository: widget.repository),
                      ),
                    ),
                  ),
                  child: const Text('查看本地日程月历'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => MaterialApp(
                        home: ManualCourseSchedulePage(
                            repository: widget.repository),
                      ),
                    ),
                  ),
                  child: const Text('查看手录课表'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => PracticeRecordListPage(
                        repository: widget.repository,
                      ),
                    ),
                  ),
                  child: const Text('实践记录'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => MaterialApp(
                        home: ManualHomeworkPreviewPage(
                          previewBox: widget.previewBox,
                          repository: widget.repository,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('本地作业预览'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => MaterialApp(
                        home: BackupPreviewPage(onRestore: _restoreBackup),
                      ),
                    ),
                  ),
                  child: const Text('预览备份'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => MaterialApp(
                        home: ManualUpcomingPreviewPage(
                          repository: widget.repository,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('接下来（本地预览）'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _restoreBackup(String backupJson) async {
    final access = ManualPreviewGenerationAccess(
      generation: widget.activeGeneration,
      previewBox: widget.previewBox,
      academicRepository: widget.repository,
    );
    await ManualPreviewRestoreCoordinator(access: access)
        .restoreAndActivate(backupJson);

    // Closing every old box releases stale references before the app reloads
    // from the committed active generation.
    await Hive.close();
    final nextAccess = await ManualPreviewGenerationAccess.open();
    await CourseDeletionCoordinator(
      repository: nextAccess.academicRepository,
      previewBox: nextAccess.previewBox,
    ).recoverPending();
    await ManualPreviewTaskStore(nextAccess.previewBox).reconcileReminders();
    runApp(ManualPreviewApp(
      previewBox: nextAccess.previewBox,
      repository: nextAccess.academicRepository,
      activeGeneration: nextAccess.generation,
    ));
  }
}
