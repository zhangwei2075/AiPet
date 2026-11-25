import 'package:flutter/material.dart';

import '../agent/autonomy.dart';
import '../agent/brainpack.dart';
import '../agent/experience.dart';
import '../agent/mcp/mcp_server.dart';
import '../agent/permissions.dart';
import '../state/app_controller.dart';
import 'feature_help.dart';
import 'memory_page.dart';
import 'theme.dart';

enum ManageSection { skills, memory, plugins, mcp, access }

/// 智能体管理：技能 / 记忆 / 插件 / MCP / 权限五合一。
/// 从设置页进入；权限分段是全权限的总控台与审计入口。
class ManagePage extends StatefulWidget {
  const ManagePage({super.key, required this.controller});

  final AppController controller;

  static Future<void> open(BuildContext context, AppController controller) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ManagePage(controller: controller)),
    );
  }

  @override
  State<ManagePage> createState() => _ManagePageState();
}

class _ManagePageState extends State<ManagePage> {
  ManageSection _section = ManageSection.skills;
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _goal = TextEditingController();

  AppController get controller => widget.controller;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 全局主题 scaffoldBackgroundColor 是 transparent（为桌宠透明窗口），
      // 这是 Navigator 推出的整页，必须显式给不透明底色，否则桌面内容会透上来。
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('智能体', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ManageSection>(
                segments: const [
                  ButtonSegment(value: ManageSection.skills, label: Text('技能')),
                  ButtonSegment(value: ManageSection.memory, label: Text('记忆')),
                  ButtonSegment(value: ManageSection.plugins, label: Text('插件')),
                  ButtonSegment(value: ManageSection.mcp, label: Text('MCP')),
                  ButtonSegment(value: ManageSection.access, label: Text('权限')),
                ],
                selected: {_section},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                ),
                onSelectionChanged: (value) => setState(() => _section = value.first),
              ),
            ),
          ),
          Expanded(
            child: switch (_section) {
              ManageSection.skills => _skills(),
              ManageSection.memory => _memory(),
              ManageSection.plugins => _plugins(),
              ManageSection.mcp => _mcp(),
              ManageSection.access => _access(),
            },
          ),
        ],
      ),
    );
  }

  Widget _skills() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final skill in controller.skillRegistry.all)
            _tile(
              child: FeatureHelp(
                label: skill.name,
                description: skill.description,
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  title: helpTitle(skill.name),
                  value: skill.enabled,
                  onChanged: (v) => controller.setSkillEnabled(skill.id, v),
                ),
              ),
            ),
        ],
      );

  Widget _memory() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _tile(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              leading: const Icon(Icons.psychology_outlined, size: 20),
              title: const Text('查看情景记忆', style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                controller.memoryService == null
                    ? '未初始化'
                    : '${controller.memoryService!.eventCount(controller.active?.id ?? '')} 条记录',
                style: const TextStyle(fontSize: 11.5),
              ),
              onTap: () => MemoryPage.open(context, controller),
            ),
          ),
        ],
      );

  Widget _plugins() => ListView(
        padding: const EdgeInsets.all(10),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 2, 0, 6),
            child: Text('工具', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
          ),
          for (final tool in BrainPack.builtInTools)
            _tile(
              child: FeatureHelp(
                label: _toolLabel(tool),
                description: _toolHelp(tool),
                child: SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: helpTitle(_toolLabel(tool), fontSize: 13),
                  value: controller.brainPack.toolEnabled(tool),
                  onChanged: (value) {
                    setState(() => controller.brainPack = controller.brainPack.copyWithTool(tool, value));
                  },
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 0, 6),
            child: Text('触发器', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
          ),
          for (final trigger in BrainPack.builtInTriggers)
            _tile(
              child: FeatureHelp(
                label: _triggerLabel(trigger),
                description: _triggerHelp(trigger),
                child: SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: helpTitle(_triggerLabel(trigger), fontSize: 13),
                  value: controller.brainPack.triggerEnabled(trigger),
                  onChanged: (value) {
                    setState(() => controller.brainPack = controller.brainPack.copyWithTrigger(trigger, value));
                  },
                ),
              ),
            ),
        ],
      );

  /// 工具与触发器同名（clipboard），加类型后缀区分，避免看起来是重复项。
  String _toolLabel(String id) => switch (id) {
        'reminder' => '提醒',
        'clipboard' => '剪贴板 · 工具',
        'pet_control' => '宠物动作',
        _ => id,
      };

  String _triggerLabel(String id) => switch (id) {
        'clipboard' => '剪贴板 · 感知',
        'app_focus' => '前台应用',
        _ => id,
      };

  /// 插件页工具开关的说明。这里只讲「这个开关管什么」，授权边界在权限分段。
  String _toolHelp(String id) => switch (id) {
        'reminder' => '定时提醒 / 闹钟：说「十分钟后叫我」即可建立任务，到点主动冒泡。',
        'clipboard' => '读取系统剪贴板文本，供「复制这段」「翻译剪贴板」等指令使用。',
        'pet_control' => '让宠物做动作（散步、跳、睡、趴、卖萌），不改动任何系统状态。',
        'run_command' => '执行 PowerShell / cmd / bash 命令，可管理文件、服务与系统配置；默认拦截 6 条不可逆命令。',
        'process' => '列出正在运行的进程，并可按进程名或 PID 结束进程。',
        'launch' => '启动 exe、打开文档，或用默认浏览器 / 关联程序打开网址与文件。',
        'http_request' => '向本机或互联网发起 HTTP 请求，可读取接口数据、网页内容。',
        'file_read' => '读取任意本地文件内容；超长内容会按上限截断后回灌给模型。',
        'file_write' => '新建或覆盖本地文件，路径与内容由智能体决定。',
        'file_list' => '列出目录内容，支持递归与通配符过滤。',
        'file_search' => '在目录里按文件名或文本内容搜索，返回匹配路径与片段。',
        'file_delete' => '删除单个文件；只接受文件路径，目录一律拒绝。',
        'clipboard_write' => '把文本写进系统剪贴板，方便直接粘贴到别的程序。',
        'window' => '列出、置前、最小化或关闭其他程序窗口。',
        'input' => '模拟键盘打字、按键、鼠标点击 / 移动 / 滚轮，可操作任意图形界面。',
        'screenshot' => '截取当前屏幕并保存为 PNG，供后续查看或留档。',
        _ => '注册在 Brain 工具表中的内置能力，缺省启用；关闭后该工具不再被调用。',
      };

  String _triggerHelp(String id) => switch (id) {
        'clipboard' => '轮询剪贴板，识别网址 / 英文句子 / 数字串三类模式；原文不落盘，只在事件里带模式标签。开启「自主执行」后会自动派生翻译、查网页等目标。',
        'app_focus' => '读取前台窗口标题并归类（编辑器 / 浏览器 / 办公 / 游戏 / 聊天），只保留类别，不保存标题原文。',
        _ => '环境感知触发器，缺省启用；关闭后不再产生该类事件。',
      };

  /// 权限分段能力清单的说明：先讲能做什么，再讲关掉它会影响哪些工具。
  String _capabilityHelp(AgentCapability cap) => switch (cap) {
        AgentCapability.command =>
          '执行 PowerShell / cmd / bash 命令，可读写系统配置、安装软件、管理服务。默认拦截 6 条不可逆命令；命令超时 120 秒会被强制结束。',
        AgentCapability.process =>
          '列出当前进程（名称、PID、内存占用），并可按 PID 结束进程。关掉后 run_command 仍可通过系统命令操作进程。',
        AgentCapability.launch =>
          '启动 exe、打开文档、用默认程序打开网址。关掉后智能体不能再替你打开程序或网页。',
        AgentCapability.fileRead =>
          '读文件、列目录、按文件名或内容搜索。输出会按上限截断；这是自主巡检最常用的只读能力。',
        AgentCapability.fileWrite =>
          '新建或覆盖本地文件。关掉后智能体只能读、不能改本机文件，适合想要「只读自治」时用。',
        AgentCapability.fileDelete =>
          '删除单个文件；只接受文件路径，目录一律拒绝。建议在不放心时单独关掉这一项。',
        AgentCapability.clipboardWrite =>
          '把文本写入系统剪贴板，方便把整理结果直接粘贴到别的程序；不影响读取剪贴板的旧工具。',
        AgentCapability.network =>
          '发起任意 HTTP 请求（GET / POST 等），可访问内网接口与公网网页；URL 不做白名单限制。',
        AgentCapability.window =>
          '列出、置前、最小化、关闭其他程序窗口。仅 Windows 可用，关掉后仍可通过命令操作窗口。',
        AgentCapability.input =>
          '模拟键盘打字、组合键、鼠标点击 / 移动 / 滚轮，可操作任意图形界面。仅 Windows 可用，风险最高的一项。',
        AgentCapability.screen =>
          '截取当前屏幕并保存为 PNG 文件，供后续查看或留档。仅 Windows 可用。',
        AgentCapability.mcp =>
          '调用已连接的 MCP 服务器提供的远程工具；远程工具同样经过权限校验与审计，不会绕过急停。',
      };

  Widget _mcp() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final server in controller.mcpServers)
            _tile(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                title: Text(server.name, style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  '${controller.mcpTools[server.id]?.length ?? 0} 个工具',
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.link_rounded, size: 18),
                      onPressed: () => controller.connectMcpServer(server.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () => controller.removeMcpServer(server.id),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('添加服务器'),
            onPressed: _addServer,
          ),
          if (controller.mcpError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(controller.mcpError!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            ),
        ],
      );

  /// M5 全权限总控台：总开关、一键急停、细粒度能力、目标队列与审计。
  Widget _access() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _tile(
            child: FeatureHelp(
              label: '完整本机权限',
              description: '总授权闸门。开启即一次性授予下面 12 项本机能力；关闭则清空授权，所有工具、自主循环与感知事件都会被 ToolRuntime 拦截。单项回收请用「能力清单」。',
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                title: helpTitle('完整本机权限'),
                subtitle: Text(
                  controller.agentPermissions.paused
                      ? '已暂停'
                      : '${controller.agentPermissions.enabled.length} / ${AgentCapability.values.length} 项已授予',
                  style: const TextStyle(fontSize: 11.5),
                ),
                value: controller.fullAccess,
                onChanged: (v) => controller.setFullAccess(v),
              ),
            ),
          ),
          _tile(
            child: FeatureHelp(
              label: '自主执行',
              description: '目标队列 + 多步 ReAct 规划循环：自己拆步骤、调工具、复盘，步数与连败会自动熔断；空闲 30 分钟发起只读巡检。关掉后只响应你当场下达的单条指令，未完成目标在重启后仍会续跑。',
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                title: helpTitle('自主执行'),
                subtitle: Text(
                  controller.settings.autonomyEnabled ? '开着' : '关着',
                  style: const TextStyle(fontSize: 11.5),
                ),
                value: controller.autonomyEnabled,
                onChanged: (v) => controller.setAutonomyEnabled(v),
              ),
            ),
          ),
          _tile(
            child: FeatureHelp(
              label: '环境感知',
              description: '启用剪贴板模式检测与前台窗口类别识别。只产生模式标签、不落盘原文；开启「自主执行」后感知事件还会转成待办目标（翻译、查网页等）。',
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                title: helpTitle('环境感知'),
                value: controller.perceptionEnabled,
                onChanged: (v) => controller.setPerceptionEnabled(v),
              ),
            ),
          ),
          _tile(
            child: FeatureHelp(
              label: '拦截不可逆命令',
              description: '保留 6 条系统级黑名单：格式化磁盘、递归删根目录、删除 Windows 目录、擦除磁盘剩余空间等。关掉后命令工具不再做任何拦截，请确认已理解影响。',
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                title: helpTitle('拦截不可逆命令'),
                value: controller.agentPermissions.blockIrreversible,
                onChanged: (v) => controller.applyPermissions(
                  controller.agentPermissions.copyWith(blockIrreversible: v),
                ),
              ),
            ),
          ),
          _tile(
            child: FeatureHelp(
              label: '一键暂停 / 恢复运行',
              description: '急停按钮：暂停后所有工具、自主循环与感知全部停摆，但设置界面仍可操作、审计记录不清空。再次点击恢复，不需要重启 App。',
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                leading: Icon(
                  controller.agentPermissions.paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  size: 20,
                ),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      controller.agentPermissions.paused ? '恢复运行' : '一键暂停',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    const HelpBadge(),
                  ],
                ),
                onTap: () => controller.setPaused(!controller.agentPermissions.paused),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 10, 0, 6),
            child: Text('能力清单', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
          ),
          for (final cap in AgentCapability.values)
            _tile(
              child: FeatureHelp(
                label: cap.label,
                description: _capabilityHelp(cap),
                child: SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: helpTitle(cap.label, fontSize: 13),
                  value: controller.agentPermissions.enabled.contains(cap),
                  onChanged: (v) => controller.setCapabilityEnabled(cap, v),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 10, 0, 6),
            child: Text('执行留痕', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
          ),
          _tile(
            child: FeatureHelp(
              label: '派一个目标',
              description: '手动给智能体下一句自然语言目标，例如「检查 D 盘剩余空间并整理成清单」。目标进入队列后由自主循环分多步执行。',
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('派一个目标', style: TextStyle(fontSize: 13)), HelpBadge()],
                ),
                onTap: _newGoal,
              ),
            ),
          ),
          _tile(
            child: FeatureHelp(
              label: '目标队列',
              description: '查看排队 / 执行中 / 已完成 / 失败 / 已取消的目标，包含步数、来源（主人或自发）。执行中的目标可在这里单独叫停。',
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('目标队列', style: TextStyle(fontSize: 13)), HelpBadge()],
                ),
                onTap: _showGoals,
              ),
            ),
          ),
          _tile(
            child: FeatureHelp(
              label: '最近动作',
              description: '审计日志：每次工具调用的时间、工具名、来源、脱敏后的参数与结果摘要，最多显示最近 60 条。可一键清空，但历史不会自动删除。',
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('最近动作', style: TextStyle(fontSize: 13)), HelpBadge()],
                ),
                onTap: _showAudit,
              ),
            ),
          ),
          _tile(
            child: FeatureHelp(
              label: '学习沉淀',
              description: '每完成（或失败）一个目标 / 一轮带工具执行的聊天，都会记下「目标、用过哪些工具、结论」。下次遇到同类请求，这些经验会回灌给聊天提示词与自主规划，越用越会。可一键清空。',
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('学习沉淀', style: TextStyle(fontSize: 13)), HelpBadge()],
                ),
                onTap: _showExperience,
              ),
            ),
          ),
        ],
      );

  String _goalStatusLabel(GoalStatus status) => switch (status) {
        GoalStatus.queued => '排队中',
        GoalStatus.running => '执行中',
        GoalStatus.done => '已完成',
        GoalStatus.failed => '失败',
        GoalStatus.cancelled => '已取消',
      };

  Future<void> _newGoal() async {
    _goal.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('派一个目标', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: _goal,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '例如：检查 D 盘剩余空间并整理成清单'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始')),
        ],
      ),
    );
    if (ok != true) return;
    final text = _goal.text.trim();
    if (text.isEmpty) return;
    final line = await controller.submitAgentGoal(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(line, style: const TextStyle(fontSize: 12))),
    );
  }

  Future<void> _showGoals() async {
    final goals = await (controller.autonomy?.goals() ?? Future.value(<Goal>[]));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('目标队列', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 520,
          height: 400,
          child: goals.isEmpty
              ? const Center(child: Text('暂无目标'))
              : ListView(
                  children: [
                    for (final goal in goals.reversed)
                      ListTile(
                        dense: true,
                        title: Text(goal.title, maxLines: 2, style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(
                          '${_goalStatusLabel(goal.status)} · ${goal.steps.length} 步 · '
                          '${goal.origin == 'self' ? '自发' : '主人'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: goal.active
                            ? IconButton(
                                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                                onPressed: () async {
                                  final navigator = Navigator.of(ctx);
                                  await controller.autonomy?.cancel(goal.id);
                                  navigator.pop();
                                },
                              )
                            : null,
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _showAudit() async {
    final entries = await controller.toolRuntime.audit.recent(limit: 60);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('最近动作', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 560,
          height: 420,
          child: entries.isEmpty
              ? const Center(child: Text('还没有记录'))
              : ListView(
                  children: [
                    for (final entry in entries)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          entry.ok ? Icons.check_circle_outline : Icons.error_outline,
                          size: 16,
                          color: entry.ok ? null : AppColors.danger,
                        ),
                        title: Text(
                          '${entry.timeLabel}  ${entry.tool}  ·  ${entry.source}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          '${entry.argsSummary}\n${entry.outputSummary}',
                          maxLines: 2,
                          style: const TextStyle(fontSize: 10.5),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(ctx);
              await controller.clearAudit();
              navigator.pop();
            },
            child: const Text('清空'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _showExperience() async {
    final List<Experience> items = await controller.experienceBank.recent(limit: 60);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('学习沉淀 · 最近 ${items.length} 条', style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 560,
          height: 420,
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    '还没有攒下经验。\n让它在对话里办几件事，或派一个目标，就会开始记录。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                )
              : ListView(
                  children: [
                    for (final item in items)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          item.ok ? Icons.lightbulb_outline_rounded : Icons.error_outline,
                          size: 17,
                          color: item.ok ? const Color(0xFF3E9B68) : AppColors.danger,
                        ),
                        title: Text(
                          '${item.dayLabel}  ${item.ok ? '成功' : '失败'} · ${item.goal}',
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          '${item.tools.isEmpty ? '未调用工具' : item.tools.join(' → ')}\n${item.summary}',
                          maxLines: 2,
                          style: const TextStyle(fontSize: 10.5),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(ctx);
              await controller.clearExperience();
              navigator.pop();
            },
            child: const Text('清空'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 显式不透明的卡片：Material 3 默认 Card 用 surfaceContainerLow（带透明），
  /// 在透明底色上会漏出后面的桌面内容。
  Widget _tile({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );

  Future<void> _addServer() async {
    _name.clear();
    _url.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加 MCP 服务器', style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: '名称')),
            TextField(controller: _url, decoration: const InputDecoration(labelText: '地址')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
        ],
      ),
    );
    if (ok != true) return;
    final problem = McpServer.validateUrl(_url.text);
    if (problem != null) {
      setState(() => controller.mcpError = problem);
      return;
    }
    final id = 'mcp-${DateTime.now().microsecondsSinceEpoch}';
    await controller.saveMcpServer(McpServer(
      id: id,
      name: _name.text.trim().isEmpty ? '未命名' : _name.text.trim(),
      url: _url.text.trim(),
    ));
  }
}
