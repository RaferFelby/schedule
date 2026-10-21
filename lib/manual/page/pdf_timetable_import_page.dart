import 'package:flutter/cupertino.dart';

import '../data/academic_repository.dart';
import '../data/local_data_error.dart';
import '../model/academic_profile.dart';
import '../model/local_semester.dart';
import '../model/time_slot.dart';
import '../service/pdf_timetable_import_service.dart';
import '../service/pdf_timetable_parser.dart';
import '../service/pdf_timetable_reader.dart';
import 'pdf_timetable_draft_editor.dart';
import 'time_slot_list_page.dart';

final class PdfTimetableImportPage extends StatefulWidget {
  const PdfTimetableImportPage({
    super.key,
    required this.repository,
    required this.semester,
  });

  final AcademicRepository repository;
  final LocalSemester semester;

  @override
  State<PdfTimetableImportPage> createState() => _PdfTimetableImportPageState();
}

final class _PdfTimetableImportPageState extends State<PdfTimetableImportPage> {
  final _reader = PdfTimetableReader();
  final _importer = PdfTimetableImportService();
  AcademicProfile? _profile;
  TimetableImportDraft? _draft;
  LocalSemester? _semester;
  List<PdfTimetablePage> _pages = const [];
  bool _loading = true;
  bool _saving = false;
  bool _reading = false;
  int _documentGeneration = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _semester = widget.semester;
    _begin();
  }

  Future<void> _begin() async {
    if (_reading || _saving) return;
    _reading = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _profile = await widget.repository.read();
      final document = await _reader.pickAndRead();
      if (!mounted) return;
      if (document == null) {
        if (_draft == null) {
          Navigator.of(context).pop(false);
        } else {
          setState(() => _loading = false);
        }
        return;
      }
      final draft = PdfTimetableParser.parse(document);
      if (!draft.hasCourses) {
        throw const FormatException('没有识别到浙大课表中的课程格，请检查 PDF 版式或手动新增课程');
      }
      setState(() {
        _pages = document.pages;
        _draft = draft;
        _documentGeneration++;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _draft = null;
          _pages = const [];
          _error = _readableError(error);
          _loading = false;
        });
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> _chooseSemester() async {
    final profile = _profile!;
    final selected = await showCupertinoModalPopup<LocalSemester>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择导入学期'),
        actions: [
          for (final item in profile.semesters)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, item),
              child: Text(item.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _semester = selected);
  }

  Future<void> _configureSlots() async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => TimeSlotListPage(repository: widget.repository),
      ),
    );
    final profile = await widget.repository.read();
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _confirmImport() async {
    final draft = _draft!;
    final included = draft.courses.where((course) => course.include).toList();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('导入课程？'),
        content: Text(
          '将向「${_semester!.name}」新增 ${included.length} 门课程及其上课安排，不会覆盖已有课程。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回检查'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _importer.importReviewedDraft(
        repository: widget.repository,
        semesterId: _semester!.id,
        draft: draft,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _hasMissingSlots {
    final profile = _profile;
    final semester = _semester;
    if (profile == null || semester == null || _draft == null) return true;
    final ordinals = (profile.timeSlots.isEmpty
            ? TimeSlot.defaultTemplate()
            : profile.timeSlots)
        .map((slot) => slot.ordinal)
        .toSet();
    final semesterWeeks =
        semester.endDate.difference(semester.weekOneStart).inDays ~/ 7 + 1;
    for (final course in _draft!.courses.where((item) => item.include)) {
      for (final session in course.sessions) {
        if (!session.isComplete ||
            session.weekNumbers.any((week) => week > semesterWeeks)) {
          return true;
        }
        for (var slot = session.startSlot!; slot <= session.endSlot!; slot++) {
          if (!ordinals.contains(slot)) return true;
        }
      }
    }
    return false;
  }

  bool _isDuplicate(TimetableCourseDraft course) {
    return _profile!.courses.any(
      (existing) =>
          existing.semesterId == _semester!.id &&
          ((course.courseNumber?.isNotEmpty == true &&
                  existing.courseNumber == course.courseNumber) ||
              existing.name.trim().toLowerCase() ==
                  course.name.trim().toLowerCase()),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            previousPageTitle: '课程',
            middle: const Text('导入 PDF 课表'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _saving || _loading ? null : _begin,
              child: const Text('重选 PDF'),
            ),
          ),
          child: SafeArea(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator())
                : _draft == null
                    ? _errorView()
                    : AbsorbPointer(absorbing: _saving, child: _editorView()),
          ),
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? '请选择课表 PDF', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              CupertinoButton.filled(
                onPressed: _begin,
                child: const Text('重新选择文件'),
              ),
            ],
          ),
        ),
      );

  Widget _editorView() {
    final draft = _draft!;
    final includedCount =
        draft.courses.where((course) => course.include).length;
    final duplicates = draft.courses
        .where((course) => course.include && _isDuplicate(course))
        .length;
    final usedVision = _pages.any((page) => page.source == 'vision');
    final timeSlots = _profile!.timeSlots.isEmpty
        ? TimeSlot.defaultTemplate()
        : _profile!.timeSlots;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (draft.termLabel != null)
          Text('PDF 标注：${draft.termLabel}。请核对所选学期；日期及第一周起点以本地学期为准。'),
        if (usedVision)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('部分页面使用了设备端中文 OCR，请逐项核对识别结果。'),
          ),
        for (final warning in draft.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              warning,
              style: const TextStyle(color: CupertinoColors.systemOrange),
            ),
          ),
        const SizedBox(height: 8),
        CupertinoButton(
          key: const ValueKey('import-select-semester'),
          padding: EdgeInsets.zero,
          onPressed: _chooseSemester,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('导入学期：${_semester?.name ?? '请选择'}'),
          ),
        ),
        Text('已识别 ${draft.courses.length} 门课程，勾选开关可选择导入；疑似重复 $duplicates 门。'),
        const Text('导入前请逐项与 PDF 对照；未识别出的安排可在课程详情中手动补录。'),
        const SizedBox(height: 12),
        for (final course in draft.courses)
          PdfTimetableDraftEditor(
            key: ValueKey('import-course-$_documentGeneration-${course.id}'),
            course: course,
            duplicate: _isDuplicate(course),
            timeSlots: timeSlots,
            onChanged: () => setState(() {}),
            onRemove: () => setState(() => draft.courses.remove(course)),
          ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              error,
              style: const TextStyle(color: CupertinoColors.systemRed),
            ),
          ),
        if (_hasMissingSlots && includedCount > 0)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请补齐必填项和学期周次范围。未配置节次时，可在这里设置节次时间。'),
              CupertinoButton(
                key: const ValueKey('configure-import-slots'),
                padding: EdgeInsets.zero,
                onPressed: _saving ? null : _configureSlots,
                child: const Text('配置节次时间'),
              ),
            ],
          ),
        const SizedBox(height: 8),
        CupertinoButton.filled(
          key: const ValueKey('confirm-pdf-import'),
          onPressed: _saving ||
                  includedCount == 0 ||
                  !draft.isComplete ||
                  _hasMissingSlots
              ? null
              : _confirmImport,
          child: Text(_saving ? '正在保存…' : '确认导入 $includedCount 门课程'),
        ),
      ],
    );
  }

  static String _readableError(Object error) {
    if (error is FormatException) return error.message.toString();
    if (error is LocalDataValidationError) return error.message;
    return '导入或保存失败，请检查文件和本地数据后重试';
  }
}
