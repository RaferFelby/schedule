# Celechron iOS 与 Apple Watch 手动输入改造：逐步执行清单

> 根据 `MANUAL_INPUT_PLAN.md` 拆解，保留 **150 个编号**；其中 Android 专属 S114、S143 不适用，其余 148 项仍按授权范围实施。
> 状态：按序实施中。截至 2026-10-03，S001–S113 已完成（S028 暂缓），S114 不适用；S115 的 iOS 本地启动、迁移逐条 JSON 修正/显式跳过、App Support 决策持久化与重试，以及 S116–S122 的本地 tab、iPhone widget、Watch revision 同步均已接入并通过合成测试；S123 iPhone 旧凭据清理和 S124 手机到 Watch 的版本化凭据撤销已接入。跳过记录计入 ignored，旧源数据与原始备份保留；清理限定旧账号/密码/SSO/校园卡键。384 项 Flutter 测试、Watch harness 144 项断言、iOS Simulator 构建和 S124 Runner/Watch scheme 构建通过；目标文件 analyze 无问题。真实旧库升级、真机 Keychain/Watch 断连投递仍待平台验收。详情见 [操作日志](docs/WORK_LOG.md)；Windows 基线仅作历史记录。
> 所有路径均相对于项目根目录；`lib/manual/` 是建议新增目录。本文中尚未出现的文件名是拟定实现位置。

## 执行约定

通用工作范围、小步修改、提交授权及检查要求遵循 [AGENTS.md](AGENTS.md)；启用子 agent 时另遵循 [协作流程](docs/agent-workflow.md)。以下仅补充本次改造的具体要求。

每个编号是一项独立工作，仅在本次授权范围内按前置依赖顺序执行；步骤顺序不代表执行全部改造的授权。少数清理步骤是只读核查，核查通过后再进行删除。

平台与文件范围遵循 AGENTS.md 第 2 节：目标为 iOS、watchOS 及两端日程小组件，包含必要的共享 Flutter 改造。执行顺序跳过 S114、S143；阶段完成条件不要求这两项通过，记录为“不适用”，不得标成已实现。

- **拆分补充：**测试和生成文件另计；需要同时改多个控制器或发现额外依赖时，以 Sxxx-a、Sxxx-b 拆分并记录。删除单个无引用旧文件可以超过参考行数，但不能夹带新功能。
- **先可检验，再接入：**日期展开、GPA、存储和迁移先实现纯逻辑/可注入接口，再连接页面。
- **步骤停靠：**检查未通过先处理本步问题，不继续叠加依赖行为。获得提交授权后，由主 agent 按步骤提交，不将一个阶段合成一次提交。
- **开发隔离：**S001–S100 使用独立预览入口和独立数据。任务样例也使用预览专用 box，不连接真实账号、不修改真实用户缓存。
- **发布边界：**中间提交用于开发验收，不能作为老用户升级包发布。数据切换、旧任务停用和兼容清理完成前不发布手动版。
- **能力逐步出现：**只给已完成的能力提供可点击入口；预留区使用空态，不提供无实现按钮。

## 每一步如何检查

1. **分析基线：**按根规范执行检查，对照 S001 基线确认没有新增问题。
2. **行为：**执行表格里的具体案例，调度逻辑同样需要有意义的自动化测试。
3. **持久化：**涉及数据保存时至少做一次“保存 → 关闭 → 重新打开”；涉及取消时检查原数据不变。
4. **失败路径：**表格要求的写入失败、中断等通过假存储或夹具模拟，不破坏真实数据库。

本改造的预览入口命令：

```sh
flutter run -t lib/debug/manual_preview.dart
```

预览入口从 S003 开始存在，测试文件按对应步骤实际创建。完整测试的里程碑见下方停靠点；Apple 原生步骤需在 macOS/Xcode 上构建并进行相应设备检查。预览使用 iOS 模拟器或 iPhone；共享逻辑检查需在配置好 Flutter/Dart 的环境执行，不能替代 Apple 平台验收。

## 阶段与停靠点

| 范围 | 本阶段完成后应得到的结果 |
| --- | --- |
| S001–S006 | 建立可以反复检查的开发入口 |
| S007–S018 | 每次只增加一种本地数据能力 |
| S019–S027 | 完成学期管理、课程新增/编辑/详情的最小录入闭环 |
| S028 | 暂缓课程删除；依赖 Task 课程关联与跨存储恢复，实际删除移至 S067–S070 |
| S029–S040 | 将上课规则展开为真实课表 |
| S041–S054 | 分别接入考试与成绩 |
| S055–S062 | 补齐实践记录和本地作业 |
| S063–S072 | 让本地编辑正确影响规划和删除 |
| S073–S087 | 分开处理提醒、导出和备份 |
| S088–S100 | 每次只迁移一种旧数据 |
| S101–S122 | 正式切换前先停掉所有旧联网触发点 |
| S123–S150 | 收尾按模块删除，最后再删依赖 |

推荐停靠点：S018（本地读写）、S040（手录课表）、S054（成绩闭环）、S062（全部基础录入）、S087（提醒与备份）、S100（迁移可验证）、S122（正式入口和设备同步）、S150（发布验收）。每次只执行一到几个相邻步骤，完成一个停靠点再审视剩余工作。

第一个可见结果是 S020：用户能创建并保存一个学期。第一个课程闭环到 S033：手动添加课程与上课规则后能看到实际上课日期。无需等全部步骤完成才验收。


## A. 建立可以反复检查的开发入口

前置条件：起点；此阶段不切换正式应用的数据来源。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S001 记录运行基线** | 记录 Flutter/Dart、当前提交和测试结果，并核对 macOS/Xcode、Apple 依赖、签名与设备条件；不升级依赖。 | BASELINE.md | 通过、失败、阻塞分列；Flutter 缺失先补齐，Apple 构建条件缺失则对应验收保持待验证，不要求 Android SDK。 |
| **S002 固定演示数据** | 增加一份无真实个人信息的学期、课程、考试、成绩和任务样例，仅供开发与测试。 | test/fixtures/manual_sample.json | 样例包含两个同名但不同 ID 的课程、一个零分、一个未录成绩和一个空学期。 |
| **S003 增加本地预览入口** | 新增独立 Flutter 入口，只显示标题和空页面，不调用现有 main()、登录或刷新。 | lib/debug/manual_preview.dart | 在干净模拟器中使用 flutter run -t lib/debug/manual_preview.dart 能打开空页面。 |
| **S004 增加预览专用存储路径** | 预览使用独立临时/开发 box，不能打开旧学业、任务或凭据存储。 | 预览入口及存储路径配置 | 写入一条预览标记后，原有数据库内容不变；正式应用看不到该标记。 |
| **S005 定义本地数据错误类型** | 只定义校验失败、存储失败和版本不兼容三类错误，不搬动旧代码或新增业务界面。 | lib/manual/data/local_data_error.dart | 预览可编译；错误类型不依赖网络服务或页面控制器。 |
| **S006 建立样例检查入口** | 预览页增加仅开发可见的载入样例、清空预览数据按钮。 | 预览入口、样例装载器 | 按钮仅影响预览存储；清空不调用现有 logout()。 |

## B. 每次只增加一种本地数据能力

前置条件：完成 A。每个模型都只维护权威基础字段；聚合值随后计算。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S007 新增学期模型** | 包含 ID、名称、起止日期、第一周周一起点、时区；名称可自由填写。 | lib/manual/model/local_semester.dart | 名称填“暑期班”可序列化往返；结束早于开始被拒绝；不截取名称。 |
| **S008 新增节次配置** | 增加节次 ID、开始/结束分钟数及可编辑默认模板；暂不处理课程。 | lib/manual/model/time_slot.dart | 一节课 08:00–08:45 可用；结束早于开始和重复节次序号被拒绝。 |
| **S009 新增课程模型** | 包含 UUID、学期 ID、名称、可选课程号、可选学分、教师和主修标记。 | lib/manual/model/local_course.dart | 无课程号可保存；未知学分保持 null；两个同名课程 ID 不同。 |
| **S010 新增上课规则模型** | 只记录规则 ID、课程 ID、星期、周次集合、起止节次、地点。 | lib/manual/model/session_rule.dart | 周次 [1,3,5] 往返不变；空周次、越界星期和倒置节次被拒绝。 |
| **S011 新增考试模型** | 支持课程 ID、类型、可选起止时间、地点和座位；未定时间显式表示。 | lib/manual/model/local_exam.dart | 时间未定能保存；只填开始不填结束被拒绝；不访问 time[0]。 |
| **S012 新增成绩模型** | 记录成绩状态、计分方式、原始数值/等级、可选绩点和计算规则标识。 | lib/manual/model/grade_record.dart | 0 分与未录入不同；89.5 不丢失小数；主修/计算标记不依赖原接口 ID。 |
| **S013 新增实践记录模型** | 增加类别、项目名、日期、记点、状态、备注，以及独立美育/劳育三态字段。 | lib/manual/model/practice_record.dart | 待审核项目可保存；负记点被拒绝；未知与未通过可以区分。 |
| **S014 新增版本化学业快照** | 将上述实体收进带 schemaVersion、revision 的快照，关系只用 ID；不复制嵌套实体。 | lib/manual/model/academic_profile.dart | 未知新版本被拒绝；引用不存在课程的考试被校验发现。 |
| **S015 实现快照读取** | 读取新 box；无数据返回空快照，损坏数据返回明确错误且不覆写原值。 | lib/manual/data/academic_repository.dart | 分别用空值、有效样例、损坏 JSON 检查三种结果。 |
| **S016 实现快照保存** | 保存一个经过校验的候选快照；写成功后才提交新的 revision。 | lib/manual/data/academic_repository.dart | 注入写入失败时旧快照和 revision 不变。 |
| **S017 串行化快照修改** | 为读取—修改—写入增加单一队列，后一个操作在最新快照上执行。 | 同一 Repository | 并发修改两门课程后两项均保留，不出现后写覆盖前写。 |
| **S018 发布保存后的状态** | 新增 AcademicController；只在仓库保存成功后替换响应式快照。 | lib/manual/controller/academic_controller.dart | 一次保存只发布一次新 revision；保存失败页面继续显示旧数据。 |

## C. 先完成学期和课程的最小录入闭环

前置条件：完成 B。此阶段所有界面只从预览入口进入。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S019 显示学期列表** | 读取快照并显示名称和日期，不增加编辑能力。 | lib/manual/page/semester_list_page.dart | 空快照显示创建提示；两个学期按日期排序，短名称不会崩溃。 |
| **S020 新增学期表单** | 只提供名称、起止日期和第一周起点，保存调用统一 Controller。 | lib/manual/page/semester_edit_page.dart | 新增“暑期班”后列表立即出现；重启预览仍存在。 |
| **S021 编辑已有学期** | 复用表单，使用独立草稿，不直接修改共享实体。 | 学期编辑页 | 修改名称后取消，原值不变；保存后 ID 不变。 |
| **S022 选择当前学期** | 保存 currentSemesterId；找不到时按日期匹配，否则返回空。 | Controller、学期列表页 | 选中空学期也能打开；删除/损坏的 ID 不触发 .last 异常。 |
| **S023 编辑节次表** | 增加单个节次新增/修改/删除界面；暂时只允许删除未被规则引用的节次。 | lib/manual/page/time_slot_list_page.dart | 把第一节改为 08:10–08:55 后重启保留；有引用的节次不能静默删除。 |
| **S024 显示课程列表** | 按 semesterId 过滤，仅显示名称、教师、学分。 | lib/manual/page/course_list_page.dart | 不同学期的同名课程不串数据；未知学分显示“未填写”。 |
| **S025 新增课程表单** | 支持名称、课程号、学分、教师和主修标记，所属学期由入口固定。 | lib/manual/page/course_edit_page.dart | 只填课程名和学期能保存；负学分被拒绝。 |
| **S026 编辑课程基本资料** | 复用草稿表单，保留课程 ID 和学期关系。 | lib/manual/page/course_edit_page.dart | 改名后 ID 不变；取消编辑不变；重新读取后教师和主修标记仍在。 |
| **S027 增加课程详情容器** | 显示基本信息并预留上课安排、考试、成绩区域；只链接已完成能力。 | lib/manual/page/course_detail_page.dart | 进入详情和返回正常；未实现区域仅显示空态文字，不出现可点击空按钮。 |
| **S028 登记并暂缓课程删除** | 此处不实现删除命令或 UI；将删除依赖后移到 Task 课程关联、引用解除与恢复流程完成之后。 | 本清单与 MANUAL_INPUT_PLAN.md | S067–S070 完成前课程详情没有删除入口；实际删除及关联任务保留/解绑由 S067–S070 验收。 |

## D. 将上课规则展开为真实课表

前置条件：完成 C。先做纯函数，再连接页面，避免日期算法和界面同时排错。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S029 展开一条普通上课规则** | 实现 ScheduleExpander，从第一周起点、星期、周次和节次生成 Period。 | lib/manual/service/schedule_expander.dart | 第一周周一 2026-09-14、周二第 1/2 周，得到 09-15、09-22 两次课。 |
| **S030 增加日期和 ID 边界** | 过滤学期范围外日期；事件 ID 使用规则 ID + 原始日期，不使用标题。 | ScheduleExpander | 修改课程名称/地点后事件 ID 不变；学期外不产生课程。 |
| **S031 显示日期展开结果** | 预览课程详情中显示规则展开后的日期清单，暂不改旧课表网格。 | 课程详情页 | 上述样例显示两条正确时间；没有规则显示空态。 |
| **S032 新增上课规则表单** | 输入星期、周次、节次、地点，关联当前课程。 | lib/manual/page/session_rule_edit_page.dart | 保存周二第 1、2 周第一节后，两次课立即出现在详情。已完成：支持课程详情进入、校验节次引用并在保存后刷新日期。 |
| **S033 增加周次快捷选择** | 表单提供全选、单周、双周和范围，最终仍保存显式周次集合。 | 规则编辑页 | 1–6 周选双周保存为 [2,4,6]；Repository 重读后周次集合一致。已完成：快捷项按范围筛选并校验学期周界。 |
| **S034 编辑和删除上课规则** | 复用表单和统一保存入口；删除只作用于选中规则。 | 规则编辑页、课程详情页 | 把第 2 周改为第 3 周后旧日期消失；删除后只剩其他规则。已完成：编辑保留规则 ID，删除经二次确认且仅按规则 ID 作用。 |
| **S035 增加停课例外** | 新增按规则/日期取消一次课的例外及小型编辑入口。 | 规则例外字段、ScheduleExpander、课程详情页 | 停掉 09-22 后只剩 09-15；取消例外后恢复。已完成：停课日期随规则快照序列化并可在详情停课/恢复。 |
| **S036 增加调课例外** | 增加一次发生实例的目标日期/时间覆盖，保留原发生身份。 | SessionReschedule、展开器、调课编辑页 | 把 09-22 移到 09-23，只出现目标日期的一次课；恢复后不重复。已完成：展开后的 Period 保留原始 UID，保存与恢复后重新读取显示日期。 |
| **S037 增加补课例外** | 支持额外添加一次明确日期和节次的课程。 | SessionExtraOccurrence、展开器、补课编辑页 | 增加 09-26 补课后多一条；删除补课不影响正常周期课。已完成：补课按独立 ID 存储、显示及确认删除。 |
| **S038 接入日程月历** | 给日历控制器增加独立的本地 Period 输入适配；预览走该入口。 | ManualCalendarPeriodAdapter、lib/page/calendar/calendar_controller.dart、预览月历 | 09-15 显示课程；停课和调课后对应日期马上更新。已完成：预览使用独立本地源，课程编辑返回后重读 Repository。 |
| **S039 接入课表网格** | 给课表视图提供显式学期标题、周次及节次读取方式，不伪造旧学期名。 | 课表展示适配器、lib/page/scholar/course_schedule/course_schedule_view.dart | “暑期班”与 18 周学期正常显示；不读取 name.substring(9)。已完成：新增独立手动课表网格，学期标题使用 LocalSemester.name、周数从 weekOneStart/endDate 计算、周次可选，课程按日期/节次显示；旧课表标题不再固定切片名称。 |
| **S040 显示课程时间冲突** | 只做重叠检测与警告，不改变算法、不禁止真实冲突保存。 | 冲突检测纯函数、规则编辑页 | 两课重叠有提示；首课结束等于后课开始不算冲突。已完成：规则编辑时将草稿与同学期其他课程的展开结果比较，显示“仍可保存”；相邻端点不告警，同课程规则不互相告警。 |

## E. 分别接入考试与成绩

前置条件：完成 D；成绩换算先确定规则，再增加派生展示。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S041 新增考试表单** | 录入课程、类型、时间、地点和座位，允许标记时间未定。 | lib/manual/page/exam_edit_page.dart | 新增考试可重启恢复；未定考试不出现在某个虚构日期。已完成：课程详情新增入口；考试默认时间未定，明确开启时间后输入并校验开始/结束；保存后按课程 ID 读取显示，取消不修改快照。 |
| **S042 编辑和删除考试** | 复用表单，关联 ID 不变，并更新课程详情。 | 考试编辑页、课程详情页 | 改时间后旧时间消失；删除不删除课程。已完成：编辑恢复原字段并保留考试 ID；删除经二次确认仅移除考试，取消删除无写入且课程保留。 |
| **S043 将考试接入日程** | 为已有 ScheduleExpander 增加考试到 Period 的独立转换。 | 考试转换函数、日程适配器 | 有时间考试出现一次；未定考试仍在考试列表但不进入日历。已完成：新增 `ExamPeriodAdapter`，稳定映射考试 ID；本地日历适配器加入有时间考试，未知时间考试不生成 Period，保留在课程详情考试列表。 |
| **S044 定义计分方式的支持边界** | 记录百分制、等级制、通过制和直接绩点可提供的指标；不可换算字段保持缺失。 | lib/manual/model/grading_policy.dart | 每种方式都有示例；明确未填写换算规则时仅展示原始值。已完成：四种计分方式都记录原始字段和绩点可用性；前三种要求显式规则，直接绩点按输入保留；89.5 不会自动生成 GPA。 |
| **S045 增加默认换算表** | 把当前项目明确存在的等级映射等移为纯规则；现有代码未定义的百分制到 GPA 不猜测，允许手填绩点。 | grading_policy.dart | 逐项核对原映射；89.5 分没有指定规则时不会自动生成虚构 GPA。已完成：23 项旧标签转百分展示值及 4 项五分绩点转四分展示值抽取为纯规则，旧 Grade 复用且输出保持兼容；不把标签展示百分数表当 GPA 规则。 |
| **S046 实现单科成绩换算** | 纯函数根据指定规则生成可用的成绩指标、获得学分和 GPA 参与标记。 | lib/manual/service/grade_calculator.dart | 零分、89.5、通过、待录和直接填绩点逐个符合规则示例。已完成：直接绩点与显式解析的 GPA 可参与；未录状态学分未知；零分获得学分为 0；通过标签按课程学分记入、无默认 GPA；非零百分分数无及格规则时保持学分未知。 |
| **S047 实现 GPA 汇总** | 按各口径可用课程加权，明确未知学分与不可换算的排除状态。 | lib/manual/service/gpa_calculator.dart | 2 学分 4.0 与 3 学分 3.0 算得 3.4；无有效课程显示暂无结果。已完成：只纳入明确可计 GPA 且有正学分的记录；缺学分单独计数并排除，无有效项返回 null。 |
| **S048 新增成绩录入表单** | 先支持一个课程的一条有效成绩，调用上述规则。 | lib/manual/page/grade_edit_page.dart | 填写成绩后课程详情可见；非法数值不能保存；未录与零分不同。已完成：提供四种计分方式及未录状态；手填绩点计入计算，百分分数不虚构 GPA；零分、89.5 与未录可区分，非法百分不写入，取消不保存。 |
| **S049 编辑和删除成绩** | 复用表单；删除只清空成绩记录，课程保留。 | 成绩编辑页、课程详情页 | 修改后 GPA 变化；删除后统计减少，重启结果一致。已完成：原位编辑保留记录 ID/courseId，直填绩点修改后详情显示新值；删除先确认，取消不写入，确认仅删除成绩并保留课程。定向 24 项、manual 全集 106 项通过，相关分析无问题，iOS Simulator 构建成功。 |
| **S050 接入成绩汇总展示** | 显示学期/总 GPA 和学分，通过本地展示适配器复用合适组件。 | 本地成绩展示页或适配器 | 样例 3.4 与页面一致；不要求学校账号或接口课程号。已完成：学期页显示全部学期及各学期 GPA、GPA 计入学分和已获学分；未知学分单独提示，不虚构 GPA。加权 3.4、分学期结果和缺学分用例通过；manual 全集 108 项、相关 analyze 和 iOS Simulator 构建通过。 |
| **S051 增加自选课程统计** | 保留用户选择，按课程修读 ID 保存。 | 成绩选择控制器、Repository 扩展 | 选中一门后只统计该门；改课程名不丢选择。已完成：每条 `LocalCourse` 按修读 ID 保存 `selectedForGpa`，课程详情可切换，课程名编辑保留该值；学期/总汇总只统计已选课程。关闭 GPA 4.0 课程后汇总变为暂无结果；旧快照无字段时默认纳入。相关定向 33 项、manual 全集 110 项通过，analyze 与 iOS Simulator build 通过。 |
| **S052 增加自定义权重** | 按原方案 Σ(绩点×权重×学分)/Σ学分计算，并保存用户设置。 | GPA 计算器、权重编辑入口 | 把 2 学分 4.0 的权重设 0.5，另有 3 学分 3.0 时结果为 2.6。已完成：课程保存 `gpaWeight`（旧数据默认 1），课程编辑页可调整；权重作用于 GPA 分子、学分分母保持 Σ学分。该示例计算为 2.6，负/非有限权重拒绝。相关定向 21 项、manual 全集 113 项通过，analyze 和 iOS Simulator build 通过。 |
| **S053 增加重修关联** | 允许用户明确把不同学期修读记录归为同组；不自动合并同名课。 | 课程模型小扩展、课程编辑页 | 关联两次修读后可选首次/最高；仅同名但未关联的仍是两门。已完成：课程可新建重修组或显式选入已有组，保存稳定 group UUID；同名课程默认未关联，修改名称后关系仍在。旧快照缺字段兼容。关联课程/模型定向 11 项、manual 全集 114 项通过，analyze 与 iOS Simulator 构建通过。 |
| **S054 增加重修选择计算** | 基于明确学期顺序选首次或按指定口径选最高；不原地排序原数组。 | GPA 计算器 | 连续切换首次/最高再切回结果一致，原始成绩顺序不变。已完成：重修组可设首次修读/最高绩点，策略统一写回组内课程；按学期日期稳定选择一门，最高策略只比较可用 GPA，无有效值时确定性回退首次。2.0/4.0 切换、反复切换、源数组不变及未归组同名独立用例通过；manual 全集 116 项，analyze 与 iOS Simulator build 通过。 |

## F. 补齐实践记录和本地作业

前置条件：完成 E；任务沿用原有表，不另造一套作业数据库。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S055 新增实践记录表单** | 只实现新增与列表，汇总暂不显示。 | lib/manual/page/practice_record_edit_page.dart、列表页 | 通过和待审核两条记录均能保存并重启恢复。已完成：预览入口可进入本地实践记录列表，表单新增类别、项目、日期、记点、备注和审核状态；已通过/待审核记录可保存、刷新展示并经新 Repository 读回，美育/劳育状态保留未知，不显示合计。定向 1 项、manual 全集 117 项通过，analyze 与 iOS Simulator build 通过。 |
| **S056 编辑和删除实践记录** | 复用草稿表单，取消不修改原值。 | 实践编辑页、列表页 | 改记点和删记录后列表正确；不影响其他课堂类别。已完成：表单载入原记录并按稳定 ID 更新，保留审核及美育/劳育状态；取消编辑与删除确认取消均不写快照；确认仅删除选中记录，其他类别/项目保留。实践记录定向 2 项、manual 全集 118 项通过，analyze 与 iOS Simulator build 通过。 |
| **S057 计算并展示实践合计** | 只合计通过、有效类别、非负记点项目，接入现有合适的展示卡片。 | 实践汇总纯函数、展示适配器 | 通过 1.5 + 待审核 2.0 的总数为 1.5。已完成：`PracticePointsCalculator` 仅累加状态通过、非空类别和非负有限记点；列表与空态显示通过项目合计及项数，审核中/未通过排除，美育/劳育状态不参与记点。定向 4 项、manual 全集 120 项通过，analyze 与 iOS Simulator build 通过。 |
| **S058 编辑美育和劳育状态** | 增加未知/未通过/通过选择，与记点合计分开保存。 | 实践状态编辑入口 | 改为通过不会增加记点；两个状态互不覆盖。已完成：实践表单提供独立美育、劳育三态控件并持久化各字段；验证美育通过与劳育未通过可同时保存，points 及通过项目合计保持 1.5，审核状态不变。定向实践流程 3 项、manual 全集 121 项通过，analyze 与 iOS Simulator build 通过。 |
| **S059 扩展 Task 的可选课程关联** | 新增 courseId、保留原课程文本的字段，更新 adapter 缺省读取。 | lib/model/task.dart、lib/database/adapters/deadline_adapter.dart | 旧任务无新字段仍能读取；新任务保存后课程 ID 不丢。已完成：共享 Task 增加可选 courseId，Hive typeId/旧索引不变，新字段使用索引 16；旧字段映射默认 null，原 summary 课程文本保留。adapter/model 定向 3 项与全仓测试 236 项通过，相关 analyze 无问题，iOS Simulator 预览构建成功。 |
| **S060 扩展 Task 的作业类别与估时状态** | 区别普通任务/课程作业及是否已估时；兼容已有 timeNeeded。 | Task、对应 adapter | 旧任务进度不变；无估时作业不因 timeNeeded=0 自动完成。已完成：Task 增加 `isCoursework`、`isTimeEstimated`；Hive 索引 17/18 保存，新字段缺失时按旧任务默认值读取；进度、计时更新及自动状态判断尊重估时状态。未估时且 timeNeeded=0 的课程作业保持进行中、进度 0；既有估时任务完成语义保留。专项 5 项、全仓 238 项通过，analyze 无问题，iOS Simulator 构建成功。 |
| **S061 在任务表单增加课程与作业选项** | 复用现有编辑页面，不复制整张作业表单。 | lib/page/task/task_edit_page.dart | 可以只填标题和截止时间创建作业，课程可留空。已完成：任务编辑页增加课程作业开关、可选本地课程 ID 选择和“已估算工作量”开关；新建作业默认无估时，只有启用估时才显示预计用时编辑，仍可单独保存标题与截止时间。读取课程通过异步 loader，可注入测试数据；选择只保存稳定 courseId，不覆盖标题/原课程文本。widget 定向 2 项、全仓 240 项通过，analyze 无问题，iOS Simulator 构建成功。 |
| **S062 从 Task 展示学业作业列表** | 按 courseId、状态和截止时间过滤，替换预览中的 Todo 来源。 | 本地作业查询、学业展示适配器 | 改课程名仍关联正确；完成作业从未完成列表消失。已完成：在独立 ManualPreviewApp 新增“本地作业预览”入口，读取样例 Task 并将编辑/完成状态保存在预览专用 Hive box；正式任务库不参与。`ManualHomeworkAdapter` 按稳定 courseId 解析课程名，列出未完成已关联的 deadline 课程作业，按截止日/ID 排序，逾期未完成仍显示；completed/deleted、普通任务、固定日程和未关联作业排除。完成状态保存并重读后不再出现在未完成查询，课程名更新仍按 ID 关联。存储/样例/adapter 定向 4 项、全仓 243 项通过，analyze 无问题，iOS Simulator 构建成功。预览页 widget 交互测试因加载动画等待挂起而撤换为 store/adapter 集成测试；页面编译已验证，完整交互尚待后续手动预览。旧 Scholar/Todo 主页面和抓取源保持未改。 |

## G. 让本地编辑正确影响规划和删除

前置条件：完成 F；每个控制器单独接入，不同时重写规划算法。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S063 将本地 Period 接入接下来页面** | 给 FlowController 增加本地日程读取入口，预览按本地配置初始化。 | lib/page/flow/flow_controller.dart、预览入口 | 近期手录课程和考试可见，无需填充旧 Scholar。已完成：FlowController 增加只读 `readLocalPeriods(AcademicRepository)` 入口，复用本地日历 adapter 展开课程和定时考试；ManualPreviewApp 增加“接下来（本地预览）”，显示未来 7 天 Period。测试以空 Scholar 环境的本地 Repository 验证近期课程与考试均可见；未改 `generateNewFlowList` 或规划占用输入。定向 1 项、全仓 244 项通过，analyze 无问题，iOS Simulator 构建成功。 |
| **S064 让规划读取本地占用时段** | 只替换规划的课程/考试输入，保留现有分配算法。 | FlowController | 09:00–10:00 有课时任务不会排入这一小时。已完成：新增可注入本地占用 Period 的规划入口，扣除与可用窗口相交的课程/考试时段后调用原 `getTimeAssignSet`；课程与考试定向用例通过。 |
| **S065 排除尚未估时的作业** | 规划输入只接受已填写剩余工作量且有效的 DDL。 | FlowController、TaskController 的相关判定 | 未估时作业仍未完成，但不生成工作片段；补估时后才参与规划。已完成：规划入口筛掉未估时、无剩余工作、非活动/非 DDL 及首个可用时段前已过期的任务；估时任务保留 timeSpent 并只规划剩余量。4 项定向、全仓 249 项通过，分析和 iOS 构建通过。 |
| **S066 标记规划已过期** | 保存学期/规则/考试/规划相关任务后更新独立的规划依赖 revision。 | Controller、规划状态适配 | 改考试时间显示需要重新规划；只改课程备注不无故重排。已完成：AcademicProfile 持久化独立 planningRevision，仅学期/节次/课程排程标识、规则、考试时间及当前学期变化递增；ManualPlanRevisionStamp 可比较生成计划时和当前学业/任务 revision。预览任务仅排程字段变化时递增其专用 revision，课程 GPA 学分等字段变化不触发。考试改期后状态显示需重排、学分更新不触发的用例通过；旧快照缺字段默认 0。全仓 251 项通过，分析和 iOS 构建通过。 |
| **S067 实现学业内课程级联删除** | 只生成移除课程及其规则/考试/成绩后的新学业快照，暂不接 UI。 | 本地删除服务 | 删除一课后其他课程不变，学业内没有悬空引用。已完成：新增纯 `CourseDeletionService.removeCourse`；按稳定 courseId 从新快照移除课程及其 SessionRule、Exam、GradeRecord，未知 ID 原样返回。2 项定向、全仓 253 项通过，分析及 iOS 模拟器构建通过；本步未写存储或接 UI。 |
| **S068 实现任务解除课程引用** | 新增按 courseId 批量解除关联的幂等命令，保留标题、截止时间、已用时和原课程文本。 | Task 数据访问层 | 执行两次任务数量和已用时均不变。已完成：ManualPreviewTaskStore.unlinkCourse 按稳定 courseId 解除专用预览任务关联；重复执行第二次返回 0，标题、描述/原课程文本、DDL、已用时、任务数和其他课程关联保持不变。定向 2 项、全仓 254 项通过，分析和 iOS 模拟器构建通过。 |
| **S069 串联课程删除与任务解绑** | 以持久化操作标记记录跨存储删除；启动时完成未结束的解绑，查询对缺失课程安全降级。 | 本地删除协调服务 | 在两个保存之间模拟失败，重启补完操作且不删任务、不重复累计进度。已完成：CourseDeletionCoordinator 先写 preview journal，再删除学业快照并幂等解绑 Task，成功后清除 journal；ManualPreviewApp 启动时恢复 pending 操作。故障注入验证学业已删、Task 保存失败后重启可补解绑，Task 数量/timeSpent 不变，缺失课程可安全显示 fallback。1 项定向、全仓 255 项通过，分析及 iOS 模拟器构建通过。 |
| **S070 接入课程删除确认** | 展示依赖数量，确认后调用已验证命令。 | 课程详情页 | 取消不变化；确认后日历、成绩和任务引用一致。已完成：仅在传入 ManualPreview Box 的本地预览课程详情显示删除操作；确认框列出规则/考试/成绩/关联任务数并说明任务会保留。取消/确认 widget 测试通过，取消无变化，确认删除学业内依赖且保留并解绑任务。真实跨存储恢复由 S069 故障注入集成测试覆盖；全仓 256 项、分析和 iOS 模拟器构建通过。 |
| **S071 实现学期删除命令** | 复用已验证的课程删除流程与恢复标记，生成学期级影响清单。 | 学期删除服务 | 删除后所有课程依赖正确处理；中断后可继续；其他学期不受影响。已完成：新增 SemesterDeletionService 影响清单和级联快照；按学期课程 ID 统计并删除课程、规则、考试、成绩，清空被删 currentSemesterId，保留其它学期。CourseDeletionCoordinator journal 扩展为课程/学期操作，保存完整待解绑 courseId 列表，启动恢复逐项幂等解除；兼容旧 courseId-only journal。定向 6 项、全仓 261 项通过，分析和 iOS 模拟器构建通过。 |
| **S072 接入学期删除确认** | 展示影响范围与备份入口，确认后调用删除命令，当前学期回退为空或其他学期。 | 学期列表页 | 取消不变化；删除最后一个学期后空态可继续创建。已完成：仅在独立预览学期列表显示删除图标；确认框列出课程、规则、考试、成绩和关联作业数量，说明任务保留。取消不变；确认调用 S071 coordinator 后刷新，删除当前学期时 currentSemesterId 清空，其他学期可用。widget 用例及全仓 262 项通过，分析和 iOS 模拟器构建通过。 |

## H. 分开处理提醒、导出和备份

前置条件：完成 G。通知先测试调度计划，接平台插件时再做设备验证。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S073 保存任务提醒设置** | 增加提醒偏移与开关，兼容旧任务；不调用系统通知。 | Task、adapter、任务编辑页 | 选择提前一天后重启保留；关闭后仍保留任务内容。已完成：Task 增加提醒开关和 offset，Hive 新增字段 19/20，旧 Task/预览 JSON 缺字段默认关闭/一天；deadline 编辑页可选择提前 5 分钟至一天，只保存偏好。关闭开关不改变任务内容和 offset，reminder 修改不增加 planning revision。定向 11 项、全仓 264 项通过，目标文件 analyze 无问题。iOS 构建被未改动 CalendarView 访问不存在的 CalendarController.scholar 字段阻断；全仓 analyze 同有该错误及根目录 legacy preview 导入错误。 |
| **S074 生成纯本地提醒计划** | 按任务状态、截止时间、时区生成未来通知列表，稳定映射通知 ID。 | lib/manual/service/reminder_planner.dart | 同一输入两次生成相同 ID；已完成和过期任务不产生新提醒。已完成：ReminderPlanner 纯函数只对启用提醒的 deadline、running/suspended Task 生成未来提醒；忽略过期/已完成/非活动/提醒时间已过及负 offset，保留本地或 UTC 时间语义。notification ID 按 task UID 稳定哈希，碰撞按 taskId 稳定消解；输出按触发时间和 taskId 排序。定向 3 项、全仓 267 项通过，目标分析无问题；未触碰系统通知调度。 |
| **S075 接入 iOS 通知创建与取消** | 将计划映射至现有通知插件的 iOS 能力；拒绝权限返回可见状态。 | lib/manual/service/reminder_scheduler.dart、必要的 iOS 通知配置 | iPhone 真机短时提醒可到达；取消后不触发；拒绝权限不影响保存任务；不在此步增加 Watch 独立调度。已实现：iOS-only ReminderScheduler 使用现有插件 requestPermissions/zonedSchedule/cancel，权限拒绝和平台不支持返回明确状态；只对传入的标题和计划安排，payload 是 taskId，无 Watch 调度。fake gateway 定向 3 项、全仓 270 项通过，目标分析无问题。iOS Simulator 构建被既有 CalendarView/Controller 不匹配阻断，iPhone 真机到达/取消验收待执行。 |
| **S076 在任务变化时更新提醒** | 编辑/完成/删除后比较新旧计划，取消旧条目并安排新条目。 | 任务保存入口、ReminderScheduler | 改截止时间后只有新通知；连续保存不重复提醒。已完成：仅 ManualPreviewTaskStore 持久化任务后比较前后 reminder plan；截止时间/标题变化先按旧稳定 ID 取消后安排新项，完成/关闭/删除取消旧项，重复保存相同计划不重复安排。权限拒绝不会回滚任务，并在预览页提示提醒未安排；通知同步异常保留任务并在下次保存重试。预览作业入口处理编辑器删除返回。定向 8 项、全仓 272 项通过，目标实现 analyze 无问题；iOS 构建仍受既有 CalendarView/Controller 错误阻断。 |
| **S077 在启动和恢复时核对提醒** | 重启、时区变化和平台限额按同一计划重建缺失项。 | 本地启动入口、ReminderScheduler | 重启后不重复；设备时区变化后按约定时区显示；超过限额有明确状态。已完成代码实现：ManualPreviewApp 启动及作业页 resume 时按当前 Tasks reconcile；payload 记录 taskId 和 fire epoch，用于识别过期/时区变化计划并补建缺失请求。只取消本功能 namespace，保留成绩 ID 0 和旧 DDL ID 1000 请求；将 iOS 全部 pending 数限制为 64，超限返回 limitExceeded 并显示提示；权限关闭时明确返回/提示。定向 16 项、全仓 277 项通过，8 个目标文件 analyze 无问题。设备重启/时区变化仍仅由逻辑测试模拟，真机验证待做；iOS Simulator build 被既有 CalendarView/Controller 不匹配阻断。 |
| **S078 让 ICS 导出使用本地 Period** | 只替换导出数据入口，保留已有文件分享流程；校验必要文本转义。 | lib/model/calendar_to_ical.dart、本地导出适配器 | 已完成：ManualCalendarPage 提供预览数据 ICS 导出，课程与定时考试转换为事件，未定考试跳过；日历名、标题、描述、地点转义反斜线/换行/逗号/分号。旧 Scholar 导出入口保留。定向 4 项、全仓 279 项通过，3 个目标文件 analyze 无问题；文件分享的 iOS 真机行为待平台验收。 |
| **S079 让系统日历同步使用本地 Period** | 先保持显式同步操作，不在后台新增自动写日历行为。 | lib/model/calendar_to_system.dart、本地日历适配器 | 已完成：本地日历页新增显式同步入口，从 ManualCalendarPeriodAdapter 读取课程与定时考试 Period，用户点击后才请求权限并写入“Celechron本地课表”；拒绝权限时显示状态且 repository 快照不变。6 项定向测试、281 项全仓测试通过，目标 analyze 无问题。iOS Simulator 构建成功，iPhone 16/iOS 18.5 Simulator 安装启动并显示预览入口；Simulator 上实际授权/日历写入及真机行为待平台验收。 |
| **S080 维护应用自己的日历事件映射** | 记录源事件 ID 到系统事件 ID；修改/删除只操作已登记事件。 | 日历同步服务、映射存储 | 已完成：稳定 Period.uid → calendarId/eventId 写入独立 Hive `manual-calendar-event-map-v1`；重复显式同步更新原 eventId，源 Period 消失后只删除其映射事件，未映射的用户事件保留；失败映射保留以便重试。Hive 重开持久化和 fake gateway 定向 9 项、全仓 284 项通过，6 个目标 analyze 无问题，iOS Simulator build 成功。Simulator 真正日历 EventKit 写入仍待平台验收。 |
| **S081 增加备份导出** | 导出版本化学业、任务和设置；排除账号、密码、token、日志及旧网页缓存。 | lib/manual/service/backup_service.dart | 已完成：BackupService 生成 version 1 JSON，白名单导出当前 AcademicProfile 与 ManualPreviewTaskStore 全部 Task 字段，保留稳定 ID、学业 revision、Task planning revision、courseId 和提醒偏好；settings 采用独立 schemaVersion/values，当前无设置仓库时 values 为空。嵌套凭据/token/account/cookie/auth/API key/学号/log/response/cache key 会拒绝导出；不读取日志/网络/网页缓存/日历映射。目标 2 项、全仓 286 项通过，3 个目标 analyze 无问题。 |
| **S082 增加备份恢复预览** | 只解析、校验和显示记录数/错误，不修改任何存储。 | BackupService、恢复预览页 | S082 完成时：独立页面可粘贴 JSON，只读校验 format/version、AcademicProfile、Task ID/course 引用、settings 敏感键及 revisions；显示分类计数与错误。S087 后仅在手动预览入口注入恢复协调器时，校验通过才显示恢复按钮；确认前不会写数据。目标 6 项 analyze 无问题，S082 阶段 preview/export 定向 6 项、全仓 290 项通过；恢复 UI/会话重载另见 S087。 |
| **S083 建立存储代次描述** | 新增包含学业、任务和设置存储位置的代次 manifest；旧任务 adapter 格式不变。 | lib/manual/data/storage_generation.dart | 已完成：schema v1 manifest 记录 generation ID/role/parent 和学业、任务、设置独立 location；路径从安全 ID 推导，反序列化校验 location 一致性。Candidate 只关联活动代次；清理守卫拒绝活动/非关联代次，只把 candidate 根目录交给注入 cleaner。本步无磁盘读写/删除。目标 analyze 无问题，5 项定向、全仓 295 项通过。 |
| **S084 让数据访问读取活动代次** | 给学业、任务和设置的启动初始化传入统一代次；本步不提供切换。 | `lib/manual/data/storage_generation.dart`、`lib/debug/manual_preview_generation_access.dart`、手动预览初始化 | 已完成：以 legacy-active manifest 兼容 `Documents/celechron_manual_preview` 原路径，不搬移既有数据；AcademicRepository 与 Task/恢复/提醒访问从同一个 Hive root 初始化，settings 位置由 box 名预留但不自动创建；只允许访问 active，不打开/创建 candidate。6 个目标 analyze 无问题，18 项定向、297 项全仓测试通过，iOS Simulator build 成功。候选写入与活动切换仍分别留在 S085/S086。 |
| **S085 写入恢复候选代次** | 将已预览的备份写入新位置，随后重新读回校验，暂不改活动指针。 | `lib/manual/service/candidate_backup_restore_service.dart`、代次 Hive box 和测试 | 已完成：只接受通过 S082 校验的备份，在 generation 专属 academic/task/settings box 写入；候选 box 使用 generation ID 后缀，可与仍打开的 legacy active box 并存。写入后 flush、关闭并重开，再逐项验证学业快照、Task 全字段/提醒偏好、settings 和 revision。S087 已将 service 接入确认恢复流程。测试覆盖非空 Task、错误版本不创建候选、模拟写完中断后旧活动数据不变。目标 7 个文件 analyze 无问题，16 项定向、300 项全仓测试通过，iOS Simulator build 成功。中断留下的部分候选保留供后续诊断/清理，不自动删除。 |
| **S086 提交活动代次指针** | 旧数据保留；单独更新带校验和/有效标记的选择记录，损坏时退回最后有效代次。 | `lib/manual/data/generation_selection_store.dart` | 已完成独立双槽选择 journal：候选提交为新 active manifest，按单调序号、SHA-256 与 valid marker 持久化；每次只覆盖非最新槽，先使槽无效、写记录/checksum 并 flush，最后写 valid 并 flush。启动读取选最高序号的完整校验记录；损坏/未完成时回退前一槽或传入的 legacy active。测试模拟 commit 前后中断、最新 checksum 损坏、重启选择、拒绝跨 root 指针，且旧代次文件保留。目标 2 文件 analyze 无问题，15 项定向、305 项全仓测试通过；本步纯数据服务未单独构建 app。S087 已接入预览启动及确认恢复流程。 |
| **S087 连接恢复确认与重新加载** | 恢复前保存当前备份；候选通过后提交指针，并关闭旧 box、重建本地状态。 | `lib/manual/service/manual_preview_restore_coordinator.dart`、`lib/debug/manual_preview_generation_access.dart`、`lib/debug/manual_preview.dart`、`lib/manual/page/backup_preview_page.dart` | 已完成手动预览路径：校验成功后才可发起，二次确认取消不触发写入；先将当前 AcademicProfile/Task 导出到旧 root 的 `recovery-backups/`，随后写入并重读校验 candidate，再提交 selection。提交后关闭旧 Hive boxes、按 pointer 重开新 active、恢复删除日志并重建提醒。若候选失败则不提交 pointer，旧 active 继续可读；旧代次与 pre-restore 文件保留。6 个目标 analyze 无问题，18 项定向、309 项全仓测试通过，iOS Simulator build 成功。文件分享导入/Watch widget 实际重载仍待后续验收。 |
| **S088 准备旧数据迁移夹具** | 覆盖旧版本缺字段、同名课程、仅成绩学期、损坏项和部分缓存。 | `test/fixtures/legacy_*`、`test/manual/legacy_fixture_manifest_test.dart` | 已完成 5 组纯构造/脱敏 fixture，包含缺学期日期/课程 ID、同名不同来源 ID 的课程、无学期成绩（分数 0 与待录状态区分）、null/错误字段及有效兄弟记录、部分课程/课时缓存。manifest 明列源记录数、可读/待确认/无效预期数量及覆盖标签；测试核对统计与实际输入条数、只包含 synthetic identifiers 且不含凭据字段。1 个目标 analyze 无问题，2 项定向、311 项全仓测试通过。未读取真实数据或接入迁移。 |
| **S089 增加旧存储只读读取与备份** | 保留旧 reader/adapter，不调用 logout、不清空旧 box；形成迁移输入副本。 | `lib/manual/migration/legacy_reader.dart` | 已完成：只按明确 box 名扫描 legacy root；对旧 box `.hive`/`.hivec` 先读 bytes、复制和 SHA-256 校验，再复读源文件与文件集合，发现并发变化则报错。原始副本包含 `dbOptions/dbDeadline/dbFlow/dbOriginalWebPage/dbFuse/dbCustomGpa`；旧 `dbUser` 不复制原文件，只以 Hive memory bytes 解析并写出不含 username/password 的 Scholar projection；不读取/复制 Keychain。要求目标目录不存在且不能嵌套在 source 中。合成旧 Hive 测试确认源 key/value/file bytes 不变、普通 box 副本字节相等、Scholar 投影无凭据。2 个目标 analyze 无问题，2 项定向、313 项全仓测试通过；未接生产迁移入口，也未读取真实用户目录。 |

## I. 每次只迁移一种旧数据

前置条件：完成 H；准备旧缓存夹具。此阶段只生成新代次候选数据，不开启正式切换。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S088 准备旧数据迁移夹具** | 覆盖旧版本缺字段、同名课程、仅成绩学期、损坏项和部分缓存。 | test/fixtures/legacy_* | 全部为脱敏/构造数据；记录每份预期可迁移数量和异常数量。 |
| **S089 增加旧存储只读读取与备份** | 保留旧 reader/adapter，不调用 logout、不清空旧 box；形成迁移输入副本。 | lib/manual/migration/legacy_reader.dart | 读取和备份前后旧 box 内容相同；备份路径可找到。 |
| **S090 迁移学期与节次** | 恢复能确定的日期/节次；不确定项标记待补齐，不猜开学时间。 | `lib/manual/migration/semester_converter.dart` | 已完成：只读取脱敏 Scholar projection；仅显式且有效的起止日期、周一第一周起点创建 LocalSemester。短名称与空课程学期可保留；缺日期/名称或日期不合法的学期进入待补齐清单并保留来源序号、名称和课程计数。仅导入明确的 `[startMinute,endMinute]` 节次对，保留旧数组一基节次序号（索引 0 是占位）；损坏或冲突配置列入 review，不套用默认节次、不生成课表日期。目标 analyze、5 项定向及全仓测试结果见 LOG-20261002-191；纯数据转换未单独构建 iOS。 |
| **S091 迁移课程并建立 ID 映射** | 仅转换课程基础信息；稳定记录旧 ID 到新 UUID。 | `lib/manual/migration/course_converter.dart` | 已完成：仅转换有明确旧课程 ID、名称且所属学期已确定的课程基础字段；用学期 UUID+旧课程 ID 生成确定性课程 UUID，映射键显式包含两者。同名不同旧 ID 保持独立；缺 ID/名称、重复 ID 或学期待补齐的记录进入 unresolved/review，不从名称推导。不会转换 sessions/exams/grades；LocalCourse 不支持的旧确认/线上/类型字段写入 review，旧快照继续保留。目标分析、定向与全仓结果见 LOG-20261002-192。 |
| **S092 迁移上课安排** | 使用已建立映射转换规则与可确认的例外；保留无法转换项的报告。 | `lib/manual/migration/session_converter.dart` | 已完成：仅读取已映射课程的嵌套 session；explicit customRepeatWeeks 转显式周次，普通单双周只从旧 `dayOfWeekToDays` 的具体缓存日期推导并校验 LocalSemester 第一周周一、学期范围和 weekday。保留连续节次范围与地点；未映射课程、缓存缺失/损坏、未确认课程、ID 冲突和非连续节次进入待处理。13 项 S090–S092 定向、326 项全仓测试通过（见最终 LOG-193）；纯数据转换未单独构建 iOS。 |
| **S093 迁移考试** | 单独转换考试关联和时间；无法关联时保留待确认记录。 | `lib/manual/migration/exam_converter.dart` | 已完成：只转换已映射课程内嵌考试；保留有效双端时间与明确空列表代表的未定时间，不将缺时间字段当未定。检查考试 ID 与 parent course ID；学期级未关联考试、坏时间/类型及冲突项均进入待处理清单。S090–S093 共 16 项定向、329 项全仓测试通过；纯数据层未单独构建 iOS。 |
| **S094 迁移成绩和重修关系** | 转换成绩、主修标记和可确定的重修关联；无法确定的保留原记录并报告。 | `lib/manual/migration/grade_converter.dart` | 已完成：嵌套成绩/学期成绩/全局成绩仅按明确旧课程 ID 关联并去重；数值分、等级/通过标签、旧五分绩点和计入 flags 映射到 GradeRecord；数字 0 保持已录，「待录」作为 notRecorded。旧快照未序列化逐科 major 标记，明确报告未知且不推断；学分不等/模型无处保存时不转换该成绩；无显式重修关系时不按名称/编号合并。S090–S094 的最终 Grade.id 映射 seam 另经 5 项 grade 定向通过；S090–S095 最终测试见 LOG-196。 |
| **S095 迁移自选与加权设置** | 利用课程/成绩映射单独转换选择记录、权重和已有 GPA 策略。 | `lib/manual/migration/grade_preference_converter.dart` | 已完成：读取只读旧 dbOptions/dbCustomGpa 投影；明确 Grade.id 选择/权重通过 S094 gradeIdMappings 聚合到目标 course，唯一且一致时应用，冲突/孤立 ID 有 unresolved。GpaStrategy 0/1 转 highestGpa/firstAttempt 并保存在课程策略字段。不调用旧 DatabaseHelper getter，不打开/写 Hive。 |
| **S096 迁移实践记录与历史汇总** | 明细和历史汇总分开保存，标注统计范围与口径。 | migration/practice_converter.dart | 已完成：明细独立生成 PracticeRecord 候选并保留旧字段 sidecar；汇总单独输出，汇总-only 不虚构项目，默认 pt 零值不伪造 summary；日期等关键字段不足进入待处理。派生汇总与明细不相加。S090–S096 全仓 344 项通过，见 LOG-197。 |
| **S097 迁移作业到 Task** | 旧本地任务原 ID/进度保留；Todo 生成可去重任务并尝试关联课程。 | migration/task_converter.dart | 已完成：旧 Task 以 copyWith 保留 UID、状态、timeSpent/timeNeeded 与排程；Todo 来源 ID 生成稳定 UUID，创建未估时课程作业，相同来源去重。旧 Todo 只有 course_name、没有 courseId，故保留课程文本并提示待关联，不按名称猜测。缺截止日期、冲突重复 ID unresolved。S090–S097 当时全仓 348 项通过；S090–S098 当时全仓 351 项通过；S090–S099 当时全仓 355 项通过；S090–S100 当时全仓 357 项通过；S101 当时全仓 357 项通过；S102 当时全仓 357 项通过；S103 当时全仓 359 项通过；S104 当前全仓 359 项通过，见 LOG-205。 |
| **S098 校验完整候选并生成报告** | 汇总转换结果、引用校验、计数差异、待处理项；不切活动代次。 | migration/migration_validator.dart | 已完成只读候选校验：每类来源记录需归入 converted/unresolved/explicitly ignored；未解释差异、ID 冲突、Task 缺失课程引用会报告为阻断项。S090–S098 当时全仓 351 项通过；S090–S099 当时全仓 355 项通过；S090–S100 当时全仓 357 项通过；S101 当时全仓 357 项通过；S102 当时全仓 357 项通过；S103 当时全仓 359 项通过；S104 当前全仓 359 项通过，见 LOG-205。 |
| **S099 提交迁移代次** | 复用备份恢复的切换机制，持久化完成标记；失败保留旧数据和旧备份。 | migration/migration_runner.dart | 已完成：runner 先阻断有问题的校验报告，再由 CandidateRestoreMigrationWriter 写入隔离代次并回读核对，最后调用双槽 generation selector 切换活动代次；旧代次保留。写入后中断可验证候选并重试，指针提交后响应丢失可回读确认，重复调用不重复写入。S090–S099 当时全仓 355 项通过；S090–S100 当时全仓 357 项通过；S101 当时全仓 357 项通过；S102 当时全仓 357 项通过；S103 当时全仓 359 项通过；S104 当前全仓 359 项通过，见 LOG-205。 |
| **S100 显示迁移结果与待补齐内容** | 仅增加报告页和通往学期/课程编辑的入口。 | migration/migration_result_page.dart | 已完成只读报告页：展示来源/已转换/待确认/明确忽略数量、阻断与提示问题；通过可注入回调提供学期日期和课程关联修正入口，无目标时隐藏按钮；明确保留旧备份。页面尚未接入正式导航，待将来正式迁移入口调用。S090–S100 当时全仓 357 项通过；S101 当时全仓 357 项通过；S102 当时全仓 357 项通过；S103 当时全仓 359 项通过；S104 当前全仓 359 项通过，见 LOG-205。 |

## J. 正式切换前先停掉所有旧联网触发点

前置条件：完成 I。以下每一步仍可编译；整个阶段只在开发分支验收，不逐步发布给旧用户。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S101 关闭 Dart 启动与前台联网** | 移除启动 Scholar.refresh、校园卡更新和前台租约的生产调用。 | lib/main.dart | 已完成：保留旧 dbUser Scholar 缓存注入和原页面；main 启动不再自动 refresh，不调用校园卡 update，不设置或续约 foreground lease。移除了 lifecycle observer 的前台租约行为。Worker 注册/旧 callback 尚待 S102，阶段完成前不发布。main analyze 无问题、全仓 357 项通过，见 LOG-202。 |
| **S102 停止 Dart 后台抓取** | 禁止重新注册旧任务，并让旧 callbackDispatcher 一开始直接结束；保留取消所需插件。 | lib/worker/background_app_refresh.dart、lib/page/option/option_controller.dart | 已完成：callbackDispatcher 对任何已排程 task 直接返回成功，不运行 Scholar.refresh；OptionController 启动时尝试取消旧 unique task，切换成绩/作业通知设置不再注册后台刷新。保留 Workmanager 仅用于取消。两目标 analyze 无问题、全仓 357 项通过。共享代码影响 Android 旧后台刷新，本轮未做 Android 验收。旧注册清理将在 S103 启动重试服务持久化。 |
| **S103 增加遗留后台任务取消** | 启动时按旧任务名幂等取消，保存清理状态；清理失败下次重试。 | `lib/services/legacy_background_task_cleanup.dart` | 已完成：Hive 独立 marker box 保存指定旧 task 的完成 key；启动时先取消再 flush 标记；取消失败不写完成 key且 main 记录 warning 后继续显示缓存，下次启动重试。OptionController 不重复取消。定向 2 项、全仓 359 项通过。 |
| **S104 移除登录入口** | 设置页取消账号登录、退出入口，保留其他设置。 | `lib/page/option/option_view.dart` | 已完成：设置页不再导入/呈现 LoginForm，不再出现点击登录、账号退出按钮或 logout 调用；原 GPA、课程代码映射、异步刷新和其他偏好仍可显示，未登录用户也能使用。提示文案同步说明旧后台自动刷新已停用。未删除 LoginForm、logout 实现或任何缓存。目标 analyze 无问题，源码入口核对通过，全仓 359 项通过，见 LOG-205。 |
| **S105 移除学业刷新入口** | 取消下拉刷新和刷新按钮，预览中已完成的编辑入口随后接管。 | lib/page/scholar/scholar_view.dart | 已完成：移除下拉刷新控件、桌面刷新按钮和错误页重试入口；ScholarPage 无 fetchData 调用，保留缓存展示及无缓存提示。刷新结果对话框函数仅保留兼容测试，不再由页面调用。隔离副本 analyze 通过，全仓 359 项通过，见 LOG-206。 |
| **S106 关闭手机付款码入口和深链** | 移除设置中的付款按钮；旧支付深链落入本地说明而非请求付款码。 | `lib/page/option/option_view.dart`、`lib/main.dart`、`lib/page/option/ecard_disabled_page.dart` | 已完成：设置不再展示付款码按钮；`/ecardpaypage` 及旧 `celechron://ecardpaypage` 链接映射到本地停用说明，不再实例化 ECardPayPage。目标 analyze 和定向页面测试通过，全仓 360 项通过；路由源码核对通过，见 LOG-207。日程原生 handler 保留。 |
| **S107 停止自动版本检查** | 取消 HomePage 启动时的 Fuse.checkUpdate 调用，不在本步删除类。 | `lib/page/home_page.dart` | 已完成：移除启动调用和更新弹窗逻辑及其专用导入；保留 Fuse 类、数据类型与数据库兼容。隔离副本 analyze 通过，全仓 360 项通过；源码核对 HomePage 不再引用 `checkUpdate`，见 LOG-208。 |
| **S108 贡献者信息改为本地内容** | 使用仓库中可核对的本地信息/说明，取消页面 API 查询。 | `lib/page/option/credits_page.dart` | 已完成：使用 GitHubService 原有默认贡献者名单作为本地静态内容，移除 HttpClient/GitHubService 请求及异步 loading 状态。widget 测试确认版本和名单立即展示，目标 analyze 无问题，全仓 361 项通过，见 LOG-209。 |
| **S109 停止 iOS 原生自动校园卡行为** | 断开启动同步、凭据刷新、余额/付款码代理请求；保留日程桥接。 | `ios/Runner/AppDelegate.swift`、`ios/Runner/WatchConnectivityBridge.swift`、`lib/main.dart` | 已完成：AppDelegate 不再安装 ECard MethodChannel 或同步校园卡缓存；main 不再安装 Watch 凭据刷新 handler；WCSession 桥仅读写 flowList，旧手表消息收到 featureDisabled。Swift frontend parse、main analyze、全仓 361 项通过。Simulator app build 被既有 CalendarView/Controller Dart 成员不匹配阻断，见 LOG-210。 |
| **S110 停止 iPhone 校园卡组件请求** | 旧 widget 改为停用提示并清理缓存；暂保留组件标识服务升级过渡。 | `ios/WidgetExtensions/ECardWidget/ECardWidget.swift`、`ios/Runner/AppDelegate.swift` | 已完成：iPhone 组件 timeline/snapshot 不读 Keychain、不调用 ECardService，显示本地停用说明并移除 App Group 的余额/更新时间/登录标记；保留 `ECardWidget` kind，AppDelegate 启动触发旧组件刷新。Swift parse 与 iOS SDK 类型检查通过；完整 Flutter iOS build 仍受 LOG-210 日历接口不匹配阻断。 |
| **S111 停止手表校园卡组件请求** | 表盘校园卡入口转为停用提示，不能再拉起联网付款流程。 | `ios/WatchWidgetExtensions/ECardWidget/WatchECardWidget.swift` | 已完成：保留 `ECardWidget` kind 与全部表盘 family，但 timeline/snapshot 只显示停用说明并清除 watch App Group 的余额、更新时间、登录标记；移除旧余额视图与付款码 deep link。watchOS Simulator SDK Swift typecheck 通过；完整 Flutter iOS/watchOS app build 仍受 LOG-210 既有日历 Dart 接口错误阻断，见 LOG-212。 |
| **S112 停止 Watch 应用校园卡请求** | 移除付款页导航和主动请求，旧深链转日程/停用说明。 | `ios/CelechronWatch/CelechronWatchApp.swift` | 已完成：移除主页付款按钮和付款页的网络/凭据请求实现；旧 ecard/pay deep link 继续进入本地停用说明。启动时清理 watch App Group 的校园卡缓存并刷新旧表盘；WCSession 仅接受 flowList，旧校园卡 action 返回停用错误。watchOS Simulator SDK 对主 App 与共享日程/深链代码 typecheck 通过。 |
| **S113 清理 Watch 本地凭据** | 手表升级启动时幂等删除本机校园卡 Keychain 项，不触碰日程缓存。 | `ios/CelechronWatch/CelechronWatchApp.swift`、`ios/CelechronWatch/WatchECardCredentialStore.swift`、Watch 测试 harness | 已完成：WCSession 激活前每次启动按精确 service/account 删除凭据；删除成功和不存在均视为完成，其他状态记录无敏感信息的 warning 并留待下次启动重试。注入式状态测试覆盖删除、重复删除及错误；92 项 QR、45 项服务/Keychain 测试通过；watchOS Simulator SDK typecheck 通过。真机钥匙串升级验证待执行，见 LOG-214。 |
| **S114 不适用：Android 校园卡组件** | 原 Android 停用任务排除出本轮范围；保留编号，不执行。 | 无 | 记录“不适用：仅面向 iOS/watchOS”，不修改 Android 文件。 |
| **S115 接入正式本地启动入口** | 启动顺序为停旧任务 → 迁移/读取本地代次 → 注入控制器 → 本地主界面。 | lib/main.dart、本地 bootstrap | 新安装无账号可建学期；旧安装进迁移流程；迁移失败也不恢复联网。 |
| **S116 接入正式学业 tab** | 主导航只替换学业页面为已完成的本地页面。 | lib/page/home_page.dart、学业适配入口 | 无需账号可新增课程，返回再进入仍是同一份数据。 |
| **S117 接入正式日程 tab** | 主导航日程页使用本地 Period 和显式学期配置。 | 主导航、日程适配入口 | 新增课程/考试立即反映在日程，短学期名无崩溃。 |
| **S118 接入正式接下来 tab** | FlowController 使用活动代次中的本地课程/考试和任务。 | 主导航、FlowController 初始化 | 手工课程与任务均显示，生成规划避开上课时间。 |
| **S119 接入正式任务 tab** | 任务页使用同一活动代次，启用课程关联和本地提醒。 | 主导航、TaskController 初始化 | 新建作业在学业 tab 也可见；完成状态跨页一致。 |
| **S120 接入正式设置 tab** | 接入学期、数据管理、提醒设置，旧联网配置不恢复。 | 主导航、设置页 | 备份/恢复入口可用，切换所有 tab 不重复初始化仓库。 |
| **S121 接入 iPhone 日程小组件** | 将本地 Period 变为现有 Pigeon DTO；包含空列表更新。 | 本地日程桥接、iOS FlowWidget 数据读取 | 增改删课程均更新；删掉全部数据后组件变空，不残留旧课。 |
| **S122 接入 Watch 日程同步** | 只同步日程快照、revision 与必要设置，不夹带旧校园卡状态。 | WatchConnectivityBridge.swift、Watch 日程接收 | 手机删课后手表同步删除；较旧 revision 不覆盖较新快照。 |

## K. 收尾按模块删除，最后再删依赖

前置条件：完成 J 且通过整体手动流程。凭据清理必须在删除安全存储插件前完成。

| 编号 / 本步目标 | 本次只改什么 | 主要位置 | 最小验收案例 |
| --- | --- | --- | --- |
| **S123 清理旧手机凭据** | 只删除该应用旧账号/密码/SSO/校园卡键，不调用会删除学业的 logout。 | 本地升级清理服务 | 已完成代码与合成验证：iOS bootstrap/retry 清理 ungrouped 旧域和当前 App Group 中的 `username`、`password`、`zju_sso_cookie_*`、`synjonesAuth`、`eCardAccount`；完成标记仅在删除成功后写入，失败会重试，其他 Keychain key 保留。清理不打开/修改 Hive 数据，不调用 logout。测试 2 项、目标 analyze 与 iOS Simulator build 通过；真实 Keychain 升级行为待设备验收。 |
| **S124 收紧跨设备注销兼容** | 手机发送一次可重试的撤销消息，手表识别后删除凭据并记录版本；不包含凭据本身。 | 手机 Watch 桥接、手表兼容接收分支 | 已完成代码与合成验证：iPhone App Group 保存固定 version/request ID，WCSession applicationContext 与 transferUserInfo 投递；Watch 只在旧凭据删除成功后持久记录版本并回传 ACK，失败不 ACK、重复请求幂等。Watch harness 覆盖无凭据 payload、删除失败重试、成功记版本和重复请求；Runner scheme（含 Watch 与组件依赖）构建通过。断连重连的真机投递和先后升级仍待设备验收；不影响未升级旧 Watch。 |
| **S125 隔离旧 Scholar 读取** | 把迁移真正需要的旧格式解析移到 legacy 模块，使用中立的数据传输对象。 | migration/legacy_reader.dart、legacy DTO | 已完成：`LegacyScholarRecord` adapter 保持 Hive typeId 5 与 JSON 字符串格式；reader 移除 username/password 后生成旧 Scholar projection。reader/coordinator/bootstrap 11 项、全仓 384 项测试通过，5 个目标文件 analyze 无 issue。 |
| **S126 审查残余 Scholar 引用** | 只执行引用检查，列出尚未改完的具体调用者；不在该步骤批量替换文件。 | 残余依赖清单 | 审查时确认 migration 无 Scholar/Spider 导入，但有旧启动根和大量共享源码依赖。用户随后明确 iOS/watchOS 为唯一标准。S126A 已删除 iOS-only root 中未引用的旧登录表单；剩余调用者继续逐项处理。初次盘点见 `docs/WORK_LOG.md` LOG-20261003-127，范围调整与入口改造见 LOG-20261003-128/134。 |
| **S126A 移除孤立旧登录表单** | 旧登录入口已关闭且文件无调用者后，删除学号/密码登录实现。 | `lib/page/option/login_page.dart` | 已完成：删除无 import/call-site 的 `LoginForm` 文件；全 lib analyze 无 error（4 项既有 warning）、384 项全仓测试通过、iOS Simulator build 和 `git diff --check` 通过。详见 LOG-20261003-134/135/136。 |
| **S127A 抽离纯 iCalendar 编码** | 将 Period 到 ICS 文本编码从含 Scholar/分享逻辑的混合类提取为纯服务，保留旧 facade 行为。 | `lib/manual/service/ical_period_encoder.dart`、`lib/model/calendar_to_ical.dart` | 已完成：两入口共用纯 encoder；旧 `CalendarToIcal.generateIcal` 签名不变，定向日程/ICS 测试 9 项及目标 analyze 通过。详见 LOG-20261003-137/138。 |
| **S127B 本地 ICS 导出脱离旧 Scholar facade** | 手动日程页使用独立本地数据 exporter，旧 Scholar 分享保持隔离。 | `local_calendar_ics_exporter.dart`、`manual_calendar_page.dart`、ICS test | 已完成：本地 repository 读 Period、生成 ICS、写文件并系统分享由 `LocalCalendarIcsExporter` 承担；active manual page 不再 import `model/calendar_to_ical.dart`。目标 analyze 通过、9 项日程测试和 iOS Simulator build 通过。详见 LOG-20261003-139–142。 |
| **S127C 本地日程控制器脱离 Scholar** | 手动日程页使用只处理 Period 的 controller；遗留日历 controller 暂时保留。 | `local_calendar_controller.dart`、manual calendar page | 已完成：本地页面不再导入 Scholar/Task/Database 依赖的旧 `CalendarController`；9 项测试、目标 analyze、iOS Simulator build 均通过。详见 LOG-20261003-143–146。 |
| **S127D 本地 Upcoming planner 脱离旧 FlowController** | 将本地 Period 读取与任务空档排程移出含 Scholar/DatabaseHelper 状态的旧 controller。 | `local_upcoming_schedule_planner.dart`、本地 Upcoming 页 | 已完成：本地页面及其测试改用纯本地 planner；目标 analyze 无 issue、算法与页面定向测试 7 项通过、iOS Simulator build 成功。详见 LOG-20261003-147–149。 |
| **S127E 删除旧 Scholar 缓存主页面** | iOS 本地导航不再进入旧只读 Scholar/联网错误页后，移除页面和专属过期弹窗测试。 | `lib/page/scholar/scholar_view.dart`、refresh dialog test | 已完成：页面与错误 handler 删除；全仓 382 项通过，lib analyze 无 error（保留既有 warnings/infos）。详见 LOG-20261003-151/152。 |
| **S127F 删除旧 Flow/Calendar/Task tab 页面** | iOS 唯一 HomePage 已用本地页面替代后，移除旧缓存 tab view；保留新本地页与 Watch 日程 sync。 | `page/{flow,calendar,task}/*_view.dart` | 已完成：三文件无其他 caller；全仓 382 项、全 lib analyze 无 error、iOS Simulator build 通过。旧控制器/model 仍需单独检查。详见 LOG-20261003-153/154。 |
| **S127G 删除孤立旧 FlowController** | 本地 Upcoming planner 与 Apple 日程同步已有独立实现后，删除旧缓存 Flow 计划/同步控制器。 | `page/flow/flow_controller.dart` | 已完成：搜索无调用者；全仓 382 项测试和 iOS Simulator build 通过，analyze 无 error。详见 LOG-20261003-155–157。 |
| **S127H 删除孤立旧日历控制器** | ManualCalendarPage 使用独立本地 controller 后，删除无 caller 的 Scholar日历状态及 schedule view。 | `page/calendar/calendar_controller.dart`、`schedule_view.dart` | 已完成：新 ManualCalendarPage 不依赖旧 Scholar/Task 日历 controller；全 lib analyze 无 error、382 项全仓测试、iOS Simulator build 通过。详见 LOG-20261003-158–160。 |
| **S127I 删除孤立旧 TaskController** | 旧数据库任务页已退出 iOS root 后，删除无 caller 的旧任务列表/计时 controller，保留本地 Task store 与提醒。 | `page/task/task_controller.dart` | 已完成：全仓无旧 controller 引用；full lib analyze 无 error、382 项全仓测试和 iOS Simulator build 通过。详见 LOG-20261003-161–163。 |
| **S127J 删除孤立旧 ScholarController** | 旧缓存刷新页面已退出 iOS root 后，移除无调用者的 controller，保留迁移 DTO。 | `lib/page/scholar/scholar_controller.dart` | 已完成：旧 controller 删除；full lib analyze 无 error（4 warnings/22 infos）、382 项全仓测试通过、iOS Simulator build 通过。构建时另修复 iOS Widget App Group target source 与 Watch 图标脚本调用/行尾。详见 LOG-20261003-164–167。 |
| **S127K 删除失效旧实践分数展示页** | iOS 采用本地 PracticeRecord 录入后，移除仅由自身导航/旧测试使用的 Scholar 页面。 | `practice_score_page.dart`、专属 widget test | 已完成：页面与测试删除；旧数据模型和迁移/汇总测试保留；full lib analyze 无新增错误、376 项全仓测试及 iOS Simulator build 通过。详见 LOG-20261003-168/169。 |
| **S127L1 移除孤立旧加权 GPA 子页** | 旧成绩详情无 iOS root caller 后，先拆除内部加权 GPA 入口和专属 controller/view。 | `weighted_gpa_view.dart`、`weighted_gpa_controller.dart`、旧 grade detail view | 已完成：本地 GPA 数据和计算保留；full lib analyze 无新增 error、376 项测试及 iOS Simulator build 通过。详见 LOG-20261003-170/171。 |
| **S127L2 删除失效旧成绩详情子树** | 旧成绩详情无 iOS root caller 后，删除专属 view/controller/card；保留仍有旧 Search 引用的课程详情卡。 | `grade_detail_view.dart`、`grade_detail_controller.dart`、`grade_card.dart` | 已完成：本地成绩录入保留；full lib analyze 无新增 error、376 项测试及 iOS Simulator build 通过。详见 LOG-20261003-172/173。 |
| **S127 后续** | 逐项移除 iOS 代码中仍编译依赖旧 Scholar 登录/刷新聚合的调用者；migration 保持使用中立 DTO。调用链清空后再删除认证实现及孤立 adapter。 | 旧 Scholar 与具体调用者 | iOS 本地 root/HomePage 已脱离旧 tab；login form、ScholarPage、旧控制器及 Flow/Calendar/Task tab 已删除，本地 ICS/calendar/upcoming 已隔离。仍需审查 option/scholar/course/search/export/database/worker 源码及依赖；按单步拆分，不整类删除。详见 S127A–J 日志。 |
| **S127M 删除无入口旧 Scholar 搜索页** | 移除无 root caller 的旧 Scholar 搜索状态和页面；本地课程筛选保留。 | `search_view.dart`、`search_controller.dart` | 已完成：源码零旧 SearchPage 引用；full lib analyze 无新增 errors、376 项测试和 iOS Simulator build 通过。详见 LOG-20261003-174/175。 |
| **S127N 删除失效旧 Scholar 课程列表页** | 删除无 root caller 的旧课程列表和 controller；本地课程列表保留。 | `course_list_view.dart`、`course_list_controller.dart` | 已完成：学期页明确使用 manual list；旧 controller 零引用；full lib analyze 无新增 errors、376 项测试和 iOS Simulator build 通过。详见 LOG-20261003-176/177。 |
| **S127O 移除失效旧 Scholar 排课页** | 删除无 root caller 的旧排课 view/controller/card；本地课表与课程节次详情保留。 | `course_schedule_view.dart`、`course_schedule_controller.dart`、`course_card.dart` | 已完成：旧类零引用；full lib analyze 无新增 errors、376 项全仓测试和 iOS Simulator build 通过。详见 LOG-20261003-178/179。 |
| **S127P 删除无入口旧 Scholar 考试列表页** | 移除无 root caller 的考试列表 UI 和状态；保留考试数据及本地编辑。 | `exam_list_view.dart`、`exam_list_controller.dart` | 已完成：源码零旧 ExamList 引用；full lib analyze 无新增 errors、376 项全仓测试和 iOS Simulator build 通过。详见 LOG-20261003-180/181。 |
| **S127Q 移除孤立旧 Scholar UI 卡片** | 删除已断开入口的课程详情/课程摘要/待办旧卡片，保留 manual replacements 与迁移领域数据。 | `course_detail_view.dart`、`course_brief_card.dart`、`todo_card.dart` | 已完成：manual 同名课程详情与任务模块保留；旧 UI 符号零引用；full lib analyze 无新增 errors、376 项测试和 iOS Simulator build 通过。详见 LOG-20261003-182/183。 |
| **S127P 删除无入口旧 Scholar 考试列表页** | 移除无 root caller 的考试列表 UI 和状态；保留考试数据及本地编辑。 | `exam_list_view.dart`、`exam_list_controller.dart` | 已完成：源码零旧 ExamList 引用；full lib analyze 无新增 errors、376 项全仓测试和 iOS Simulator build 通过。详见 LOG-20261003-180/181。 |
| **S127Q 移除孤立旧 Scholar UI 卡片** | 删除已断开入口的课程详情/课程摘要/待办旧卡片，保留 manual replacements 与迁移领域数据。 | `course_detail_view.dart`、`course_brief_card.dart`、`todo_card.dart` | 已完成：manual 同名课程详情与任务模块保留；旧 UI 符号零引用；full lib analyze 无新增 errors、376 项测试和 iOS Simulator build 通过。详见 LOG-20261003-182/183。 |
| **S127R 删除孤立旧后台 Scholar 刷新实现** | 删除未注册/未调用的旧 SecureStorage 凭据读取及抓取刷新任务，保留兼容取消旧 pending task。 | `lib/worker/background_app_refresh.dart` | 已完成：worker/callback 零引用；保留 `LegacyBackgroundTaskCleanup` 和 Workmanager 插件以取消旧任务；full lib analyze 无新增 errors、376 项测试和 iOS Simulator build 通过。详见 LOG-20261003-184/185。 |
| **S128A 迁移测试使用中立旧 Hive DTO** | migration/bootstrap 测试直接写 typeId 5 旧字段 JSON，不实例化联网 Scholar 聚合。 | 两份 manual migration/bootstrap tests | 已完成：fixture 改用 LegacyScholarRecord Map；目标 9 项、全仓 376 项测试和 iOS Simulator build 通过；保留备份字节断言和冲突解决测试。详见 LOG-20261003-186/187。 |
| **S128B 移除旧实践缓存模型测试依赖** | 删除测试中对停用 Scholar ZDBK 旧缓存字段回退的断言，保留纯响应 JSON parser 覆盖。 | `test/practice_score_item_test.dart` | 已完成：9 项 PracticeScoreItem parser tests、全仓 376 项测试与 iOS Simulator build 通过；分析无新增 errors。详见 LOG-20261003-188/189。 |
| **S128C 剥离 Scholar 网络聚合** | 移除旧登录、Spider session 与刷新编排，保留迁移 wire data 和必要的离线兼容投影。 | `lib/model/scholar.dart` | 已完成：login/session/refresh/partial fetch 与 Spider 引用已从 Scholar 删除；保留 typeId 5 JSON 投影。
| **S128D 停止 Scholar 凭据读写** | DatabaseHelper 不再装载/回写 Scholar 账号密码，仍清理明确的历史凭据 key。 | `lib/database/database_helper.dart` | 已完成：Scholar 无 username/password；旧 key 仅在显式清理时删除。26 项定向、375 项全仓测试及 iOS Simulator build 通过；analyzer 0 errors（4 warnings/22 infos）。详见 LOG-20261003-190–194。
| **S128E 删除本科抓取编排** | 生产无引用后删除 UgrsSpider，保留仍由迁移使用的纯解析函数。 | `lib/http/ugrs_spider.dart` 及直接引用 | 已完成：删除无外部 caller 的本科 `UgrsSpider`/`MockSpider`；独立校历 parser/time-config 服务保留。定向 18 项、全仓 375 项测试和 iOS Simulator build 通过；analyzer 无 errors，warning 减少 1。详见 LOG-20261003-195/196。 |
| **S129 删除研究生抓取编排** | 单独删除 GrsSpider 及其无用引用。 | `lib/http/grs_spider.dart` | 已完成：删除无 caller 的研究生认证/刷新编排，保留由纯状态测试使用的 `spider.dart` helper；refresh status 3 项、全仓 375 项测试及 iOS Simulator build 通过，analyzer 无 errors（只剩 2 条刷新协调 warning）。详见 LOG-20261003-197/198。 |
| **S130 删除统一认证实现** | 其他旧网络/校园卡调用点清理后，再移除 ZjuAm 与专属测试。 | `lib/http/zjuServices/zjuam.dart` 及专属测试 | 已完成：删除生产无调用的 ZjuAm CAS 实现与 5 项仅测旧登录/session 的测试；保留独立旧 Keychain 清理。全仓 360 项测试、iOS Simulator build 通过，analyzer 无 errors。详见 LOG-20261003-210/211。 |
| **S131 删除本科教务服务** | 只清理无引用 Zdbk，保留迁移已提取的解析。 | `lib/http/zjuServices/zdbk.dart` | 已完成：删除无 import/实例化 caller 的 Zdbk 网络 service；独立 `Session.fromZdbk` / `ExamDto.fromZdbk` 旧 wire parsers 保留。360 项全仓测试、iOS Simulator build 通过，analyzer 无 errors。 |
| **S132 删除研究生院服务** | 只清理无引用 GrsNew。 | `lib/http/zjuServices/grs_new.dart` | 已完成：删除无生产 caller 的 GrsNew 与一项只覆盖该旧服务登录的测试；迁移旧成绩结构未依赖该联网类。保留 ZjuAm 的 5 项 fake-response 认证测试。全仓 372 项测试、iOS Simulator build 通过；analyzer 无 errors。详见 LOG-20261003-206/207。 |
| **S133 删除学在浙大服务** | 只删除无引用 Courses 和独立在线 probe 入口。 | `courses.dart`、`lib/debug/courses_probe.dart` 及专属测试 | 已完成：删除无生产 caller 的 Courses service、debug probe 和两项仅测试旧认证跳转的测试；Todo 旧 parser 暂保留。373 项全仓测试、iOS Simulator build 通过，analyzer 无 errors。详见 LOG-20261003-204/205。 |
| **S134 删除素质拓展服务** | 只删除无引用 Sztz；保留仍适用的记录/汇总校验测试。 | `sztz.dart` 及专属认证测试 | 已完成：删除 Sztz network/login/cache service、其专属认证测试与两组 service-only assertions；保留 PracticeScoreItem 纯 parser 和 Snapshot/summary tests（定向 24 项）。全仓 365 项测试与 iOS Simulator build 通过，analyzer 无 errors。详见 LOG-20261003-208/209。 |
| **S135 删除校园卡 Dart 服务** | 移除无调用的校园卡请求、付款页面和消息入口。 | `ecard.dart`、`ecard_pay_page.dart`、消息入口 | 已完成：删除 ECardWidgetMessenger、Dart 请求服务与无 caller 付款页；disabled deep link 和升级凭据清理保留。360 项全仓测试及 iOS Simulator build 通过，analyzer 无 errors。详见 LOG-20261003-202/203/214/215。 |
| **S136 删除校历远程服务** | 移除请求代码，保留内置节次模板和迁移所需校历解析。 | `time_config_service.dart` 及纯解析迁移引用 | 已完成：删除无 caller 的远程请求/缓存 service；独立 `calendar_config_parser.dart` 的日期/节次解析、校验及安全模板保留。全仓 360 项测试、iOS Simulator build 通过，analyzer 无 errors。 |
| **S137 删除版本和贡献者请求服务** | 清理已无入口的 Fuse 网络逻辑、GitHubService；应用版本显示使用本地元数据。 | `fuse.dart`、github service 与本地版本显示 | 已完成：GitHubService 已删除，Credits 使用本地名单；Fuse 在线更新请求/版本比较逻辑已移除，保留 dbFuse Hive adapter typeId 12 和原 `lastUpdateTime` JSON wire field。Analyzer 无 warnings/errors，343 项测试与 iOS Simulator build 通过。详见 LOG-20261003-222–225。 |
| **S138 清理剩余 HTTP 公共文件** | 按引用确认 Spider 接口、重试、响应工具及旧 appservice 壳均不再使用；仍有引用则先保留。 | `lib/http/` 剩余无引用文件 | 已完成：无 caller 的 Spider/重试/校历网络服务/旧 appservice 壳/DataSourceStatus/module status mapping 和 HTTP response validation/body read/authentication/network exception conversion 均已删除；保留本地校历 parser/JSON decoder/response summary 与通用错误脱敏。336 项测试、iOS Simulator build 通过，analyzer 0 warnings/errors。详见 LOG-20261003-199–201/216–221/226/228/230/232。 |
| **S139 清理抓取专用状态与诊断** | 移除刷新进度控件、旧来源枚举等无引用项；保留通用脱敏和本地操作记录。 | 单个废弃文件或一组直接引用 | 已完成：移除旧模块刷新状态 mapper、DiagnosticLogService 当前写入中的 refreshId/来源/HTTP/retry/cache fields 和 runRefresh 上下文，保留本地操作错误、堆栈、脱敏、日志读写/复制/导出/清理；日志页空态不再要求执行在线刷新。旧日志解析保留只用于读取历史记录。Analyzer 0 warnings/errors，336 项测试与 iOS Simulator build 通过。详见 LOG-20261003-232/234。 |
| **S140 整理数据管理设置** | 仅整理学期、备份、恢复入口与说明。 | 设置页数据管理分组 | 已验证：iOS 实际 Settings tab 包含学期/课程/节次管理、单一备份校验/恢复入口和独立备份导出操作；校验有效且用户确认后才恢复。相关 15 项测试通过，无需改动。详见 LOG-20261003-236。 |
| **S141 整理提醒与显示设置** | 保留本地提醒、主题和规划偏好，删除联网刷新与出分推送选项。 | 设置页相关分组 | 已完成：旧 `brightnessMode/workTime/restTime/allowTime` 白名单迁入隔离代次 settings；iOS 设置页可改主题、专注/休息时长和每日时段，备份恢复含严格校验，Upcoming 排程实时采用设置。全仓 343 项测试及 iOS Simulator build 通过，analyzer 无 errors/warnings（21 条既有 infos）。详见 LOG-20261003-238–246。 |
| **S142 补齐首次使用空态** | 学业为空时引导建学期，允许跳过并使用任务。 | 本地学业空态、首次使用入口 | 已完成：Upcoming 学期为空时可选创建学期或跳过到任务页；任务页可新增未关联学期/课程的普通任务，并显示全部未完成 deadline task；未显示登录提示。定向 17 项、全仓 347 项测试通过；analyzer 无 errors/warnings（21 条既有日历 infos），iOS Simulator build 通过。详见 LOG-20261003-248/249。 |
| **S143 不适用：Android 声明清理** | 原 Android 配置清理任务排除出本轮范围；保留编号，不执行。 | 无 | 记录“不适用：仅面向 iOS/watchOS”，不要求 Android 构建。 |
| **S144 清理 iOS 无用声明** | 移除无调用校园卡源文件引用与后台注册，保留日程 Widget、App Group 和升级清理。 | ios/Runner.xcodeproj、AppDelegate、相关 plist/entitlements | 已完成本步可安全移除项：删除旧 Scholar BGTask 的 AppDelegate 周期注册/后台 callback 及 Runner 的 permitted identifier/fetch mode；旧任务升级时仍由本地启动清理按名称取消。引用审查发现 iOS ECardWidget 仍被 bundle/AppDelegate 使用以清除旧 App Group 缓存，属于升级清理而非无调用声明，因此保留；FlowWidget、App Group 保留。Info.plist lint、定向 6 项、全仓 347 项、analyzer 0 errors/warnings（21 条既有 infos）、iOS Simulator build 通过。详见 LOG-20261003-250/251。 |
| **S145 清理 Watch 无用声明** | 移除无调用支付/二维码源码与专属测试引用，保留日程、撤销消息兼容和必要组件壳。 | Watch targets 与相关配置 | 已完成：移除仅由专属测试使用的 SimpleQRCode/矩阵夹具生成器与用例、无产品调用的共享校园卡网络 client 及所有 target 引用；Watch credential store 收缩为旧 Keychain item 删除，versioned revocation/ack 完整保留；无调用的余额付款复杂功能删除。Watch disabled deep link 与 ECardWidget cache-clearing shell 保留用于升级清理；FlowWidget/App Group 保留。专属兼容 harness 12 assertions、iOS Simulator Flutter build、`CelechronWatch` scheme（含 WatchWidgetExtensions）build 通过。详见 LOG-20261003-252/253。 |
| **S146 移除不再使用的二维码插件** | 无 Dart 支付页面依赖后移除 qr_flutter；仍需保留的测试依赖显式声明。 | pubspec.yaml、工具生成文件 | 已完成：全仓无 Dart QR 页面/导入和 QR 专属 Swift encoder/tests，因此移除 `qr_flutter` direct dependency，Pub lock 同步删除间接 `qr` 与 `qr_flutter`，无测试依赖需保留。Pub get、全仓 analyzer（0 errors/warnings，21 条既有 infos）、347 项全仓测试及 iOS Simulator build 通过。详见 LOG-20261003-254/255。 |
| **S147 核查后台与安全存储依赖退出条件** | 列出 workmanager 和 flutter_secure_storage 的残余升级清理用途；仍有需要则保留兼容版本。 | 依赖清理记录，必要时单个插件配置 | 已完成退出条件审查，两项均保留：本地 bootstrap 在数据切换前按稳定旧 identifier 取消 workmanager 任务，失败不记完成标记并可重试；`flutter_secure_storage` 启动清理仅处理旧 app-group/ungrouped scope 的白名单认证键，失败不记 marker，旧 DatabaseHelper 也仍有兼容引用。依赖源码确认取消方法不要求重新初始化 callback；定向 8 项任务/凭据/bootstrap tests 通过。真实旧版用户数据升级仍待 S150 设备验收。详见 LOG-20261003-256。 |
| **S148 核对其余依赖** | 记录剩余包的实际用途，避免误删通知、分享、日期哈希和迁移依赖；不升级依赖。 | `docs/DEPENDENCY_AUDIT.md` | 已逐包核对；单包移除 rename_app、hive_flutter、flutter_svg、extended_sliver，intl 改为传递依赖；图标生成器移入 dev_dependencies。每项均 analyzer、347 项测试、iOS Simulator build 通过。保留项用途与升级清理理由见依赖审计和 LOG-20261003-258–263。 |
| **S149 启用并固定 CI 检查** | 加入本地模型、日期、保存、迁移等测试；使用已验证 SDK 与锁文件策略，记录 Apple 构建入口与条件。 | `.github/workflows/code_check.yml`、`pubspec.lock`、`docs/APPLE_CI.md` | 已固定 macOS 15/Xcode 16.4、Flutter 3.47.5；隔离镜像 `pub get --enforce-lockfile`、analyzer、347 项测试、iOS simulator build、CelechronWatch + WatchWidgetExtensions build、Watch cleanup 12 assertions 全通过。外部 GitHub runner 尚未触发；模拟器不覆盖签名/真机验收，详见 APPLE_CI。原有 10 个格式不一致文件未批量改写，因此未启用全仓格式门禁。 |
| **S150 执行 Apple 最终离线与升级验收** | 检查 iOS/watchOS 新装、升级、前后台、通知、两端小组件及日程同步。 | `docs/APPLE_ACCEPTANCE.md`，不混入功能修改 | 自动测试、iOS/watchOS/两端 widgets 编译、Watch cleanup harness、plist lint 与源码离线调用审查通过。临时无 entitlement simulator 启动显示 `-34018`，不能替代有效签名构建验收；当前未连接真机且无已确认签名 profile。升级旧数据、后台通知、widget、Watch/Calendar 同步与备份恢复待真机验收，需保留旧版 app/data；详见验收记录，不标为完成。 |

## 固定样例与预期结果

优先反复使用同一组人工样例，避免每一步临时换数据而失去可比性：

| 样例 | 预期 |
| --- | --- |
| 第一周周一起点 2026-09-14；课程在周二第 1、2 周 | 两次日期为 2026-09-15、2026-09-22 |
| 将 09-22 停课 | 只保留 09-15 |
| 将 09-22 调到 09-23 | 原 09-22 不再出现，09-23 只出现一次 |
| 2 学分、绩点 4.0；3 学分、绩点 3.0 | GPA 为 3.4 |
| 上一行第一门权重改为 0.5，分母仍按原学分 | 加权结果为 2.6 |
| 实践项目：通过 1.5、待审核 2.0 | 通过项目总记点为 1.5 |
| 同名课程分别位于两个学期 | 两个独立修读记录，改一个不影响另一个 |
| 课程零分与未录入成绩 | 是不同状态；不会都显示成“暂无” |
| 无估时的作业 | 可以保存、提醒和标记完成，暂不参与工作时间分配 |
| 删除课程时有一个关联任务 | 任务保留，解除课程引用，已用时不变 |
| 迁移或恢复在候选写入时中断 | 正式读取仍指向完整旧代次 |
| 全部课程删除 | 日历和小组件都为空，不显示上一次缓存 |

## 步骤记录模板

每完成一步只需要填下面几项：
每次修改和检查仍须按 [操作与恢复流程](docs/operation-recovery.md) 留日志；本模板只汇总步骤结果，不替代操作记录。

```text
步骤：Sxxx
操作日志：路径及操作编号
状态：未开始 / 进行中 / 已验证 / 待外部环境验证 / 不适用（注明原因）
实际变更文件：
行为变化：
检查命令或手工操作：
检查结果：
提交：未提交 / 已授权提交的 hash
剩余问题：
```

系统通知、旧版升级和手表暂时离线等尚未验证的场景，列入“剩余问题”。

## 最终发布前的集中验收

- 新安装断网启动，可完成学期、课程、规则、考试、成绩、实践和任务录入。
- 旧版升级先停用抓取再迁移；没有因为取消后台任务失败而重新联网。
- 新旧数据存储隔离，迁移和恢复的失败、中断及重复执行均可恢复。
- 保存、取消、删除和重启行为一致；GPA、课表、规划和小组件使用同一份基础数据。
- 拒绝通知/日历权限不阻断任务保存；已启用功能对修改和删除正确同步。
- 手机、手表和小组件的生产路径没有主动请求外部数据；新版本不能控制未升级旧客户端的行为，升级验证需注明两端版本。
- 对 iOS 主应用、Apple Watch 及两端小组件完成构建与必要真机检查；Android 和桌面平台标记为范围外，Apple 条件不足的检查标记为待验证。
- 执行全量测试、核对备份恢复、更新使用说明和版本信息后，再进入发布流程。

这份清单刻意把开发过程拆细。实际使用时直接指定“执行 S007”或“执行 S019–S021”，即可限定修改范围和验收目标；无需一次启动整个阶段。

## 2026-10-03 启动与本地 tab 阶段复核

- **S115（代码实现完成，平台验收待完成）**：iOS main 已按顺序清理旧后台任务、选择本地活动代次、备份并迁移旧 Hive 数据、注入本地页面；首次安装使用 `Documents/celechron_manual_data`，与 `celechron_manual_preview` 样例目录分开。阻断记录可在应用内编辑 JSON 后重新校验，也可逐条确认跳过；修正和跳过选择保存在 App Support，重试始终从不可变备份读取。跳过计入 ignored，源 Hive 文件与原始备份不删除。合成测试覆盖日期缺失学期修正、跳过和备份保留；真实旧库升级/回滚行为仍待平台验收。
- **S116–S117**：本地学业、日程 tab 已注入同一活动学业仓库；日历 Period 来自明确学期、上课规则、节次和考试数据。
- **S118**：接下来页面读取同一代次课程、考试和任务，排程会避开占用 Period；当前使用 08:00–22:00 与 25/5 分钟默认规划值，建议不自动写回任务。
- **S119–S120**：任务页使用共享 task box，支持课程关联与本地提醒；设置提供学业管理、备份导出/校验/恢复回调和提醒重同步。恢复后会重开活动代次。旧联网配置不进入本地 tab。
- **检查**：截至 S123，隔离副本 `flutter test --no-pub test` 384 项通过；Flutter iOS Simulator build 通过；Xcode workspace 的 Runner、WidgetExtensions、CelechronWatch、WatchWidgetExtensions 均以 generic Simulator、无签名构建通过。analyze 无 error，4 条既有 warning 使其退出码为 1。
- **S121**：ManualCalendarPage 在 iOS 进入/刷新时通过 Pigeon 将本地 Period DTO 与 AcademicProfile revision 推送到 App Group，空快照也会写入并刷新 FlowWidget；新增快照同步测试，Calendar 页面相关 9 项与新增 service 测试 2 项合计 11 项通过。
- **S122**：WatchConnectivity payload/applicationContext 携带 `flowRevision`；手表只接受 revision 不低于当前快照的日程，并在新快照为空时保存空列表以清除旧日程。Pigeon 源定义更新后由 lock 中 pigeon 29.0.4 生成 Dart/Swift。Runner、CelechronWatch、WidgetExtensions、WatchWidgetExtensions generic Simulator 无签名构建均通过。
- **S123**：iOS 启动清理服务只删除旧用户名、密码、SSO Cookie 前缀与校园卡凭据键；使用 App Support 成功标记，清理失败时重试；不调用 logout、不改业务 Hive。
- **S124**：手机对 Watch 持久化发送 version 1 的旧凭据撤销请求，payload 仅有 action/version/request ID；Watch 删除成功后记录版本并返送 ACK。未 ACK 时手机保留请求、下一次启动重发；真实断连升级流程待真机验收。
- **待验收**：未对真实旧库运行升级或迁移修正/跳过、未在真实 Keychain 验证旧条目清理；不做真机通知权限交互、iPhone↔Watch 同步和恢复后设备行为检查。
