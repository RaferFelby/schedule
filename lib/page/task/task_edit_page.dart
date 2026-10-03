import 'package:flutter/cupertino.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/utils.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/local_course.dart';

typedef TaskCourseLoader = Future<List<LocalCourse>> Function();

class TaskEditPage extends StatefulWidget {
  final Task deadline;
  final TaskCourseLoader? courseLoader;
  const TaskEditPage(this.deadline, {super.key, this.courseLoader});

  @override
  State<TaskEditPage> createState() => _TaskEditPageState();
}

class _TaskEditPageState extends State<TaskEditPage> {
  late Task now;
  int __got = 0;
  List<LocalCourse> _courses = const [];
  bool _coursesLoaded = false;
  bool _courseLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    try {
      final courses = await (widget.courseLoader ?? _readLocalCourses)();
      if (mounted) {
        setState(() {
          _courses = courses;
          _coursesLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _coursesLoaded = true;
          _courseLoadFailed = true;
        });
      }
    }
  }

  Future<List<LocalCourse>> _readLocalCourses() async {
    final repository = await AcademicRepository.open();
    return (await repository.read()).courses;
  }

  String get _selectedCourseLabel {
    if (now.courseId == null) return '不关联';
    for (final course in _courses) {
      if (course.id == now.courseId) return course.name;
    }
    return '课程不可用（保留原关联）';
  }

  Future<void> _chooseCourse() async {
    final actions = <CupertinoActionSheetAction>[
      CupertinoActionSheetAction(
        onPressed: () {
          setState(() => now.courseId = null);
          Navigator.of(context).pop();
        },
        child: const Text('不关联课程'),
      ),
      ..._courses.map(
        (course) => CupertinoActionSheetAction(
          onPressed: () {
            setState(() => now.courseId = course.id);
            Navigator.of(context).pop();
          },
          child: Text(course.name),
        ),
      ),
    ];
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('关联课程（可选）'),
        message: _courseLoadFailed
            ? const Text('暂时无法读取本地课程，仍可不关联课程。')
            : _courses.isEmpty
                ? Text(_coursesLoaded ? '还没有本地课程。' : '正在读取本地课程…')
                : null,
        actions: actions,
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _setCoursework(bool value) {
    setState(() {
      now.isCoursework = value;
      if (value) {
        now.isTimeEstimated = false;
        now.timeNeeded = Duration.zero;
      } else {
        now.isTimeEstimated = true;
        if (now.timeNeeded <= Duration.zero) {
          now.timeNeeded = const Duration(hours: 1);
        }
      }
    });
  }

  void _setTimeEstimated(bool value) {
    setState(() {
      now.isTimeEstimated = value;
      if (value && now.timeNeeded <= Duration.zero) {
        now.timeNeeded = const Duration(hours: 1);
      } else if (!value) {
        now.timeNeeded = Duration.zero;
      }
    });
  }

  String _reminderOffsetLabel(Duration offset) {
    if (offset == const Duration(days: 1)) return '提前一天';
    if (offset == const Duration(hours: 1)) return '提前一小时';
    if (offset == const Duration(minutes: 30)) return '提前 30 分钟';
    if (offset == const Duration(minutes: 15)) return '提前 15 分钟';
    if (offset == const Duration(minutes: 5)) return '提前 5 分钟';
    return '提前 ${durationToString(offset)}';
  }

  Future<void> _chooseReminderOffset() async {
    const offsets = [
      Duration(days: 1),
      Duration(hours: 1),
      Duration(minutes: 30),
      Duration(minutes: 15),
      Duration(minutes: 5),
    ];
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('提醒时间'),
        actions: offsets
            .map(
              (offset) => CupertinoActionSheetAction(
                key: ValueKey('task-reminder-offset-${offset.inMinutes}'),
                onPressed: () {
                  setState(() => now.reminderOffset = offset);
                  Navigator.of(popupContext).pop();
                },
                child: Text(_reminderOffsetLabel(offset)),
              ),
            )
            .toList(growable: false),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void saveAndExit() {
    if (now.type == TaskType.fixed && !now.startTime.isBefore(now.endTime)) {
      showCupertinoDialog(
        context: context,
        builder: (BuildContext context) {
          return CupertinoAlertDialog(
            title: const Text(
              '开始时间必须晚于结束时间',
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () async {
                  Navigator.of(context).pop();
                },
              )
            ],
          );
        },
      );
      return;
    }

    if (now.type == TaskType.fixed &&
        now.repeatType != TaskRepeatType.norepeat &&
        dateOnly(now.startTime).isAfter(dateOnly(now.repeatEndsTime))) {
      showCupertinoDialog(
        context: context,
        builder: (BuildContext context) {
          return CupertinoAlertDialog(
            title: const Text(
              '开始时间不能晚于重复截止日期',
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () async {
                  Navigator.of(context).pop();
                },
              )
            ],
          );
        },
      );
      return;
    }

    if (now.type == TaskType.fixed &&
        now.repeatType != TaskRepeatType.norepeat) {
      int length = now.endTime.difference(now.startTime).inMinutes;
      if ((now.repeatType == TaskRepeatType.days &&
              length > now.repeatPeriod * 24 * 60) ||
          (now.repeatType == TaskRepeatType.month && length > 28 * 24 * 60) ||
          (now.repeatType == TaskRepeatType.year && length > 365 * 24 * 60)) {
        showCupertinoDialog(
          context: context,
          builder: (BuildContext context) {
            return CupertinoAlertDialog(
              title: const Text(
                '这个重复日程的持续时间太长',
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('确定'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                  },
                )
              ],
            );
          },
        );
        return;
      }
    }

    FormState().save();
    now.forceRefreshStatus();
    Navigator.of(context).pop(now);
  }

  void removeAndExit() {
    FormState().save();
    now.forceRefreshStatus();
    now.status = TaskStatus.deleted;
    Navigator.of(context).pop(now);
  }

  void exitWithoutSave() {
    now = widget.deadline.copyWith();
    Navigator.of(context).pop(now);
  }

  @override
  Widget build(BuildContext context) {
    if (__got == 0) {
      now = widget.deadline.copyWith();
      if (now.startTime.isAfter(now.endTime)) {
        now.startTime = now.endTime.add(const Duration(minutes: -1));
      }
      if (now.repeatEndsTime.isAfter(DateTime(2099, 1, 1)) ||
          dateOnly(now.repeatEndsTime).isBefore(dateOnly(now.startTime))) {
        now.repeatEndsTime = dateOnly(now.startTime);
      }
      if (now.isCoursework && !now.isTimeEstimated) {
        now.timeNeeded = Duration.zero;
      }
      __got = 1;
    }

    List<String> deadlineRepeatTypeNameList = [];
    for (var i in TaskRepeatType.values) {
      deadlineRepeatTypeNameList.add(deadlineRepeatTypeName[i]!);
    }

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        leading: CupertinoButton(
          key: const ValueKey('task-edit-cancel'),
          padding: EdgeInsets.zero,
          onPressed: exitWithoutSave,
          child: const Icon(CupertinoIcons.xmark),
        ),
        middle: const Text('编辑任务'),
        trailing: CupertinoButton(
          key: const ValueKey('task-edit-save'),
          padding: EdgeInsets.zero,
          onPressed: saveAndExit,
          child: const Icon(CupertinoIcons.check_mark),
        ),
        border: null,
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.only(
                    left: 20.0,
                    right: 20.0,
                    top: 20.0,
                    bottom: 8.0,
                  ),
                  child: CupertinoSlidingSegmentedControl<TaskType>(
                    groupValue: now.type,
                    children: <TaskType, Widget>{
                      TaskType.deadline: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text('${deadlineTypeName[TaskType.deadline]}'),
                      ),
                      TaskType.fixed: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text('${deadlineTypeName[TaskType.fixed]}'),
                      ),
                    },
                    onValueChanged: (TaskType? value) {
                      if (value != null) {
                        setState(() {
                          now.type = value;
                          if (now.type == TaskType.fixed) {
                            now.status = TaskStatus.running;
                          }
                        });
                      }
                    },
                  ),
                ),
                CupertinoListSection.insetGrouped(
                  children: [
                    CupertinoTextFormFieldRow(
                      placeholder: '任务名',
                      textAlign: TextAlign.left,
                      controller: TextEditingController(text: now.summary),
                      onChanged: (String value) {
                        now.summary = value;
                      },
                    ),
                    if (now.type == TaskType.fixed)
                      CupertinoTextFormFieldRow(
                        placeholder: '开始时间',
                        textAlign: TextAlign.left,
                        controller: TextEditingController(
                            text:
                                '开始于 ${TimeHelper.chineseDateTime(now.startTime)}'),
                        readOnly: true,
                        onTap: () async {
                          await showCupertinoModalPopup(
                              context: context,
                              builder: (BuildContext context) {
                                return CupertinoPageScaffold(
                                  child: SizedBox(
                                    height: MediaQuery.of(context)
                                            .copyWith()
                                            .size
                                            .height /
                                        3,
                                    child: CupertinoDatePicker(
                                      initialDateTime: now.startTime,
                                      use24hFormat: true,
                                      minuteInterval: 1,
                                      mode: CupertinoDatePickerMode.dateAndTime,
                                      onDateTimeChanged: (DateTime newTime) {
                                        setState(() {
                                          now.startTime = newTime;
                                        });
                                      },
                                    ),
                                  ),
                                );
                              });
                          if (now.endTime.isBefore(now.startTime)) {
                            setState(() {
                              now.endTime = now.startTime;
                            });
                          }
                        },
                      ),
                    CupertinoTextFormFieldRow(
                      placeholder: '结束时间',
                      textAlign: TextAlign.left,
                      controller: TextEditingController(
                          text:
                              '${now.type == TaskType.deadline ? '截止于' : '结束于'} ${TimeHelper.chineseDateTime(now.endTime)}'),
                      readOnly: true,
                      onTap: () async {
                        await showCupertinoModalPopup(
                            context: context,
                            builder: (BuildContext context) {
                              return CupertinoPageScaffold(
                                child: SizedBox(
                                  height: MediaQuery.of(context)
                                          .copyWith()
                                          .size
                                          .height /
                                      3,
                                  child: CupertinoDatePicker(
                                    initialDateTime: now.endTime,
                                    use24hFormat: true,
                                    minuteInterval: 1,
                                    mode: CupertinoDatePickerMode.dateAndTime,
                                    onDateTimeChanged: (DateTime newTime) {
                                      setState(() {
                                        now.endTime = newTime;
                                      });
                                    },
                                  ),
                                ),
                              );
                            });
                        if (now.type == TaskType.fixed &&
                            now.startTime.isAfter(now.endTime)) {
                          setState(() {
                            now.startTime = now.endTime;
                          });
                        }
                      },
                    ),
                  ],
                ),
                if (now.type == TaskType.deadline)
                  CupertinoListSection.insetGrouped(
                    header: const Text('提醒设置'),
                    footer: const Text('此处只保存提醒偏好；系统通知将在后续步骤接入。'),
                    children: [
                      CupertinoListTile(
                        title: const Text('截止前提醒'),
                        trailing: CupertinoSwitch(
                          key: const ValueKey('task-reminder-switch'),
                          value: now.reminderEnabled,
                          onChanged: (value) => setState(
                            () => now.reminderEnabled = value,
                          ),
                        ),
                      ),
                      if (now.reminderEnabled)
                        CupertinoListTile(
                          key: const ValueKey('task-reminder-offset'),
                          title: const Text('提醒时间'),
                          trailing: Text(
                            _reminderOffsetLabel(now.reminderOffset),
                          ),
                          onTap: _chooseReminderOffset,
                        ),
                    ],
                  ),
                if (now.type == TaskType.deadline)
                  CupertinoListSection.insetGrouped(
                    header: const Text('课程作业'),
                    footer: const Text('截止日期可以单独保存；未估时的课程作业不会进入自动规划。'),
                    children: [
                      CupertinoListTile(
                        title: const Text('作为课程作业'),
                        trailing: CupertinoSwitch(
                          key: const ValueKey('task-coursework-switch'),
                          value: now.isCoursework,
                          onChanged: _setCoursework,
                        ),
                      ),
                      if (now.isCoursework) ...[
                        CupertinoListTile(
                          key: const ValueKey('task-course-selector'),
                          title: const Text('关联课程（可选）'),
                          trailing: Text(_selectedCourseLabel),
                          onTap: _chooseCourse,
                        ),
                        CupertinoListTile(
                          title: const Text('已估算工作量'),
                          trailing: CupertinoSwitch(
                            key: const ValueKey('task-estimate-switch'),
                            value: now.isTimeEstimated,
                            onChanged: _setTimeEstimated,
                          ),
                        ),
                      ],
                    ],
                  ),
                if (now.type == TaskType.deadline)
                  CupertinoListSection.insetGrouped(
                    header: const Text('时间安排'),
                    children: [
                      if (!now.isCoursework || now.isTimeEstimated)
                        CupertinoListTile(
                          title: const Text('预期用时'),
                          trailing: Text(durationToString(now.timeNeeded)),
                          onTap: () async {
                            await showCupertinoModalPopup(
                                context: context,
                                builder: (BuildContext context) {
                                  return CupertinoPageScaffold(
                                    child: SizedBox(
                                      height: MediaQuery.of(context)
                                              .copyWith()
                                              .size
                                              .height /
                                          3,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 150,
                                            child: CupertinoPicker(
                                              itemExtent: 32,
                                              scrollController:
                                                  FixedExtentScrollController(
                                                initialItem:
                                                    now.timeNeeded.inHours,
                                              ),
                                              onSelectedItemChanged: (value) {
                                                now.timeNeeded = Duration(
                                                    hours: value,
                                                    minutes: now.timeNeeded
                                                            .inMinutes %
                                                        60);
                                                if (now.timeNeeded <=
                                                    Duration.zero) {
                                                  now.timeNeeded =
                                                      const Duration(
                                                          minutes: 1);
                                                }

                                                setState(() {});
                                              },
                                              children: List.generate(
                                                1000,
                                                (index) => Center(
                                                    child: Text("$index")),
                                              ),
                                            ),
                                          ),
                                          const Text('小时'),
                                          SizedBox(
                                            width: 150,
                                            child: CupertinoPicker(
                                              itemExtent: 32,
                                              looping: true,
                                              scrollController:
                                                  FixedExtentScrollController(
                                                initialItem:
                                                    now.timeNeeded.inMinutes %
                                                        60,
                                              ),
                                              onSelectedItemChanged: (value) {
                                                now.timeNeeded = Duration(
                                                  hours: now.timeNeeded
                                                          .inMinutes ~/
                                                      60,
                                                  minutes: value,
                                                );
                                                if (now.timeNeeded <=
                                                    Duration.zero) {
                                                  now.timeNeeded =
                                                      const Duration(
                                                          minutes: 1);
                                                }

                                                setState(() {});
                                              },
                                              children: List.generate(
                                                60,
                                                (index) => Center(
                                                    child: Text("$index")),
                                              ),
                                            ),
                                          ),
                                          const Text('分钟'),
                                        ],
                                      ),
                                      // CupertinoTimerPicker(
                                      //   mode: CupertinoTimerPickerMode.hm,
                                      //   initialTimerDuration: now.timeNeeded,
                                      //   onTimerDurationChanged: (value) {
                                      //     if (value > Duration.zero) {
                                      //       setState(() {
                                      //         now.timeNeeded = value;
                                      //       });
                                      //     } else {
                                      //       setState(() {
                                      //         now.timeNeeded =
                                      //             const Duration(minutes: 1);
                                      //       });
                                      //     }
                                      //   },
                                      // ),
                                    ),
                                  );
                                });
                          },
                        )
                      else
                        const CupertinoListTile(
                          title: Text('预期用时'),
                          trailing: Text('尚未估时'),
                        ),
                      CupertinoListTile(
                        title: const Text('已经用时'),
                        trailing: Text(durationToString(now.timeSpent)),
                        onTap: () async {
                          await showCupertinoModalPopup(
                              context: context,
                              builder: (BuildContext context) {
                                return CupertinoPageScaffold(
                                  child: SizedBox(
                                    height: MediaQuery.of(context)
                                            .copyWith()
                                            .size
                                            .height /
                                        3,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 150,
                                          child: CupertinoPicker(
                                            itemExtent: 32,
                                            scrollController:
                                                FixedExtentScrollController(
                                              initialItem:
                                                  now.timeSpent.inHours,
                                            ),
                                            onSelectedItemChanged: (value) {
                                              now.timeSpent = Duration(
                                                  hours: value,
                                                  minutes:
                                                      now.timeSpent.inMinutes %
                                                          60);

                                              setState(() {});
                                            },
                                            children: List.generate(
                                              1000,
                                              (index) =>
                                                  Center(child: Text("$index")),
                                            ),
                                          ),
                                        ),
                                        const Text('小时'),
                                        SizedBox(
                                          width: 150,
                                          child: CupertinoPicker(
                                            itemExtent: 32,
                                            looping: true,
                                            scrollController:
                                                FixedExtentScrollController(
                                              initialItem:
                                                  now.timeSpent.inMinutes % 60,
                                            ),
                                            onSelectedItemChanged: (value) {
                                              now.timeSpent = Duration(
                                                hours:
                                                    now.timeSpent.inMinutes ~/
                                                        60,
                                                minutes: value,
                                              );

                                              setState(() {});
                                            },
                                            children: List.generate(
                                              60,
                                              (index) =>
                                                  Center(child: Text("$index")),
                                            ),
                                          ),
                                        ),
                                        const Text('分钟'),
                                      ],
                                    ),
                                    // child: CupertinoTimerPicker(
                                    //   mode: CupertinoTimerPickerMode.hm,
                                    //   initialTimerDuration: now.timeSpent,
                                    //   onTimerDurationChanged: (value) {
                                    //     setState(() {
                                    //       now.timeSpent = value;
                                    //     });
                                    //   },
                                    // ),
                                  ),
                                );
                              });
                        },
                      ),
                      CupertinoListTile(
                        title: const Text('允许插入休息时间'),
                        trailing: CupertinoSwitch(
                          value: now.isBreakable,
                          onChanged: (value) {
                            setState(() {
                              now.isBreakable = !now.isBreakable;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                if (now.type == TaskType.fixed) ...[
                  CupertinoListSection.insetGrouped(
                    header: const Text('日程设置'),
                    children: [
                      CupertinoListTile(
                        title: const Text('重复'),
                        trailing: Text(deadlineRepeatTypeName[now.repeatType]!),
                        onTap: () async {
                          await showCupertinoModalPopup(
                              context: context,
                              builder: (BuildContext context) {
                                return CupertinoPageScaffold(
                                  child: SizedBox(
                                    height: MediaQuery.of(context)
                                            .copyWith()
                                            .size
                                            .height /
                                        3,
                                    child: CupertinoPicker(
                                      itemExtent: 32,
                                      scrollController:
                                          FixedExtentScrollController(
                                        initialItem: now.repeatType.index,
                                      ),
                                      onSelectedItemChanged: (int value) {
                                        setState(() {
                                          now.repeatType =
                                              TaskRepeatType.values[value];

                                          if (now.repeatType !=
                                                  TaskRepeatType.norepeat &&
                                              dateOnly(now.repeatEndsTime)
                                                  .isBefore(dateOnly(
                                                      now.startTime))) {
                                            now.repeatEndsTime =
                                                dateOnly(now.startTime);
                                          }
                                        });
                                      },
                                      children: List<Widget>.generate(
                                        deadlineRepeatTypeNameList.length,
                                        (int index) {
                                          return Center(
                                            child: Text(
                                              deadlineRepeatTypeNameList[index],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              });
                        },
                      ),
                      if (now.repeatType == TaskRepeatType.days)
                        CupertinoListTile(
                          title: const Text('重复周期'),
                          trailing: Text('${now.repeatPeriod} 天'),
                          onTap: () async {
                            await showCupertinoModalPopup(
                                context: context,
                                builder: (BuildContext context) {
                                  return CupertinoPageScaffold(
                                    child: SizedBox(
                                      height: MediaQuery.of(context)
                                              .copyWith()
                                              .size
                                              .height /
                                          3,
                                      child: CupertinoPicker(
                                        itemExtent: 32,
                                        scrollController:
                                            FixedExtentScrollController(
                                          initialItem: now.repeatPeriod - 1,
                                        ),
                                        onSelectedItemChanged: (int value) {
                                          setState(() {
                                            now.repeatPeriod = value + 1;
                                          });
                                        },
                                        children: List<Widget>.generate(
                                          999,
                                          (int index) {
                                            return Center(
                                              child:
                                                  Text((index + 1).toString()),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                });
                          },
                        ),
                      if (now.repeatType != TaskRepeatType.norepeat)
                        CupertinoListTile(
                          title: const Text('重复截止日期'),
                          trailing:
                              Text(TimeHelper.chineseDate(now.repeatEndsTime)),
                          onTap: () async {
                            await showCupertinoModalPopup(
                                context: context,
                                builder: (BuildContext context) {
                                  return CupertinoPageScaffold(
                                    child: SizedBox(
                                      height: MediaQuery.of(context)
                                              .copyWith()
                                              .size
                                              .height /
                                          3,
                                      child: CupertinoDatePicker(
                                        mode: CupertinoDatePickerMode.date,
                                        initialDateTime: now.repeatEndsTime,
                                        onDateTimeChanged: (value) {
                                          setState(() {
                                            now.repeatEndsTime = value;
                                          });
                                        },
                                      ),
                                    ),
                                  );
                                });
                          },
                        ),
                      CupertinoListTile(
                        title: const Text('不在这个日程中安排任务'),
                        trailing: CupertinoSwitch(
                          value: now.blockArrangements,
                          onChanged: (value) {
                            setState(() {
                              now.blockArrangements = !now.blockArrangements;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  // Container(
                  //   padding: const EdgeInsets.only(left: 40, right: 40),
                  //   child: Text(
                  //     '可以在其中安排任务的日程不会出现在“接下来”栏中。',
                  //     style: TextStyle(
                  //         color: CupertinoDynamicColor.resolve(
                  //             CupertinoColors.secondaryLabel, context),
                  //         fontSize: 14),
                  //   ),
                  // ),
                ],
                CupertinoListSection.insetGrouped(
                  header: const Text('附加信息'),
                  children: [
                    CupertinoTextFormFieldRow(
                      placeholder: '地点',
                      textAlign: TextAlign.left,
                      controller: TextEditingController(text: now.location),
                      onChanged: (String value) {
                        now.location = value;
                      },
                    ),
                    CupertinoTextFormFieldRow(
                      placeholder: '说明',
                      textAlign: TextAlign.left,
                      controller: TextEditingController(text: now.description),
                      onChanged: (String value) {
                        now.description = value;
                      },
                    ),
                  ],
                ),
                CupertinoButton(
                  onPressed: removeAndExit,
                  child: const Text(
                    '删除任务',
                    style: TextStyle(
                      color: CupertinoColors.systemPink,
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
