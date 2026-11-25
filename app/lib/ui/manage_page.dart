import 'package:flutter/material.dart';

import '../agent/autonomy.dart';
import '../agent/brainpack.dart';
import '../agent/experience.dart';
import '../agent/mcp/mcp_server.dart';
import '../agent/permissions.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'feature_help.dart';
import 'memory_page.dart';
import 'theme.dart';

enum ManageSection { skills, memory, plugins, mcp, access }

/// 智能体管理：技能 / 记忆 / 插件 / MCP / 权限五合一。
/// 从侧边栏或设置页进入；权限分段是全权限的总控台与审计入口。
class ManagePage extends StatefulWidget {
  const ManagePage({super.key, required this.controller});

  final AppController controller;

  static Future<void> open(BuildContext context, AppController controller) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => ManagePage(controller: controller)),
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
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                _header(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Insets.x5, 0, Insets.x5, Insets.x3),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppSegmented<ManageSection>(
                      values: ManageSection.values,
                      value: _section,
                      labelOf: (value) => _label(value),
                      iconOf: (value) => _icon(value),
                      onChanged: (value) => setState(() => _section = value),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Insets.x5),
                    child: switch (_section) {
                      ManageSection.skills => _skills(),
                      ManageSection.memory => _memory(),
                      ManageSection.plugins => _plugins(),
                      ManageSection.mcp => _mcp(),
                      ManageSection.access => _access(),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _label(ManageSection section) => switch (section) {
        ManageSection.skills => '技能',
        ManageSection.memory => '记忆',
        ManageSection.plugins => '插件',
        ManageSection.mcp => 'MCP',
        ManageSection.access => '权限',
      };

  IconData _icon(ManageSection section) => switch (section) {
        ManageSection.skills => Icons.auto_awesome_rounded,
        ManageSection.memory => Icons.psychology_outlined,
        ManageSection.plugins => Icons.extension_outlined,
        ManageSection.mcp => Icons.hub_outlined,
        ManageSection.access => Icons.shield_outlined,
      };

  Widget _header() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(Insets.x3, Insets.x3, Insets.x3, Insets.x3),
      child: Row(
        children: [
          RoundIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: '返回',
              onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: Insets.x2),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('智能体', style: AppType.titleColor),
                SizedBox(height: 2),
                Text(
                  '技能 · 记忆 · 插件 · MCP · 权限',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          RoundIconButton(
              icon: Icons.close_rounded,
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  /// 一行开关：图标 + 标题 + 说明 + 开关。整行悬停出详细说明。
  Widget _toggle({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData? icon,
    bool last = false,
  }) {
    return Column(
      children: [
        FeatureHelp(
          label: title,
          description: description,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: Insets.x4, vertical: 11),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                        color: AppColors.surfaceAlt, shape: BoxShape.circle),
                    child: Icon(icon, size: 15, color: AppColors.inkSoft),
                  ),
                  const SizedBox(width: Insets.x3),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.x3),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
        if (!last)
          const Divider(height: 1, indent: Insets.x4, endIndent: Insets.x4),
      ],
    );
  }

  /// 一行跳转：标题 + 说明 + chevron。
  Widget _jump({
    required String title,
    required String description,
    required VoidCallback onTap,
    IconData? icon,
    bool last = false,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Insets.x4, vertical: 12),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                          color: AppColors.surfaceAlt, shape: BoxShape.circle),
                      child: Icon(icon, size: 15, color: AppColors.inkSoft),
                    ),
                    const SizedBox(width: Insets.x3),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            const HelpBadge(),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.45,
                                color: AppColors.inkSoft),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.inkFaint),
                ],
              ),
            ),
          ),
        ),
        if (!last)
          const Divider(height: 1, indent: Insets.x4, endIndent: Insets.x4),
      ],
    );
  }

  Widget _list(List<Widget> children) => ListView(
        padding: const EdgeInsets.only(bottom: Insets.x5),
        children: children,
      );

  Widget _skills() {
    final skills = controller.skillRegistry.all;
    return _list([
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < skills.length; i++)
              _toggle(
                title: skills[i].name,
                description: skills[i].description,
                icon: Icons.auto_awesome_rounded,
                value: skills[i].enabled,
                onChanged: (v) => controller.setSkillEnabled(skills[i].id, v),
                last: i == skills.length - 1,
              ),
          ],
        ),
      ),
      const SizedBox(height: Insets.x3),
      const Text(
        '技能是给智能体预置的成套动作；关掉后它仍然能聊天，但不会再主动使用这套流程。',
        style:
            TextStyle(fontSize: 11.5, height: 1.6, color: AppColors.inkFaint),
      ),
    ]);
  }

  Widget _memory() => _list([
        AppCard(
          padding: EdgeInsets.zero,
          child: _jump(
            title: '情景记忆',
            description: controller.memoryService == null
                ? '未初始化'
                : '${controller.memoryService!.eventCount(controller.active?.id ?? '')} 条记录 · 按天归档',
            icon: Icons.psychology_outlined,
            onTap: () => MemoryPage.open(context, controller),
            last: true,
          ),
        ),
      ]);

  Widget _plugins() {
    final tools = BrainPack.builtInTools.toList();
    final triggers = BrainPack.builtInTriggers.toList();
    return _list([
      const SectionLabel('工具', description: '智能体可以调用的能力，关闭后不再被调用'),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < tools.length; i++)
              _toggle(
                title: _toolLabel(tools[i]),
                description: _toolHelp(tools[i]),
                icon: _toolIcon(tools[i]),
                value: controller.brainPack.toolEnabled(tools[i]),
                onChanged: (value) {
                  setState(() => controller.brainPack =
                      controller.brainPack.copyWithTool(tools[i], value));
                },
                last: i == tools.length - 1,
              ),
          ],
        ),
      ),
      const SizedBox(height: Insets.x4),
      const SectionLabel('触发器', description: '环境信号，关闭后不再产生该类事件'),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < triggers.length; i++)
              _toggle(
                title: _triggerLabel(triggers[i]),
                description: _triggerHelp(triggers[i]),
                icon: Icons.sensors_rounded,
                value: controller.brainPack.triggerEnabled(triggers[i]),
                onChanged: (value) {
                  setState(() => controller.brainPack =
                      controller.brainPack.copyWithTrigger(triggers[i], value));
                },
                last: i == triggers.length - 1,
              ),
          ],
        ),
      ),
    ]);
  }

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

  IconData _toolIcon(String id) => switch (id) {
        'reminder' => Icons.alarm_rounded,
        'clipboard' => Icons.content_paste_rounded,
        'pet_control' => Icons.pets_rounded,
        'run_command' => Icons.terminal_rounded,
        'process' => Icons.memory_rounded,
        'launch' => Icons.rocket_launch_rounded,
        'http_request' => Icons.public_rounded,
        'file_read' => Icons.description_outlined,
        'file_write' => Icons.edit_note_rounded,
        'file_list' => Icons.folder_open_rounded,
        'file_search' => Icons.search_rounded,
        'file_delete' => Icons.delete_outline_rounded,
        'clipboard_write' => Icons.content_copy_rounded,
        'window' => Icons.window_rounded,
        'input' => Icons.keyboard_rounded,
        'screenshot' => Icons.screenshot_monitor_rounded,
        _ => Icons.extension_outlined,
      };

  /// 插件页工具开关的说明。这里只讲「这个开关管什么」，授权边界在权限分段。
  String _toolHelp(String id) => switch (id) {
        'reminder' => '定时提醒 / 闹钟：说「十分钟后叫我」即可建立任务，到点主动冒泡。',
        'clipboard' => '读取系统剪贴板文本，供「复制这段」「翻译剪贴板」等指令使用。',
        'pet_control' => '让宠物做动作（散步、跳、睡、趴、卖萌），不改动任何系统状态。',
        'run_command' =>
          '执行 PowerShell / cmd / bash 命令，可管理文件、服务与系统配置；默认拦截 6 条不可逆命令。',
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
        'clipboard' =>
          '轮询剪贴板，识别网址 / 英文句子 / 数字串三类模式；原文不落盘，只在事件里带模式标签。开启「自主执行」后会自动派生翻译、查网页等目标。',
        'app_focus' => '读取前台窗口标题并归类（编辑器 / 浏览器 / 办公 / 游戏 / 聊天），只保留类别，不保存标题原文。',
        _ => '环境感知触发器，缺省启用；关闭后不再产生该类事件。',
      };

  /// 权限分段能力清单的说明：先讲能做什么，再讲关掉它会影响哪些工具。
  String _capabilityHelp(AgentCapability cap) => switch (cap) {
        AgentCapability.command =>
          '执行 PowerShell / cmd / bash 命令，可读写系统配置、安装软件、管理服务。默认拦截 6 条不可逆命令；命令超时 120 秒会被强制结束。',
        AgentCapability.process =>
          '列出当前进程（名称、PID、内存占用），并可按 PID 结束进程。关掉后 run_command 仍可通过系统命令操作进程。',
        AgentCapability.launch => '启动 exe、打开文档、用默认程序打开网址。关掉后智能体不能再替你打开程序或网页。',
        AgentCapability.fileRead =>
          '读文件、列目录、按文件名或内容搜索。输出会按上限截断；这是自主巡检最常用的只读能力。',
        AgentCapability.fileWrite =>
          '新建或覆盖本地文件。关掉后智能体只能读、不能改本机文件，适合想要「只读自治」时用。',
        AgentCapability.fileDelete => '删除单个文件；只接受文件路径，目录一律拒绝。建议在不放心时单独关掉这一项。',
        AgentCapability.clipboardWrite =>
          '把文本写入系统剪贴板，方便把整理结果直接粘贴到别的程序；不影响读取剪贴板的旧工具。',
        AgentCapability.network =>
          '发起任意 HTTP 请求（GET / POST 等），可访问内网接口与公网网页；URL 不做白名单限制。',
        AgentCapability.window =>
          '列出、置前、最小化、关闭其他程序窗口。仅 Windows 可用，关掉后仍可通过命令操作窗口。',
        AgentCapability.input =>
          '模拟键盘打字、组合键、鼠标点击 / 移动 / 滚轮，可操作任意图形界面。仅 Windows 可用，风险最高的一项。',
        AgentCapability.screen => '截取当前屏幕并保存为 PNG 文件，供后续查看或留档。仅 Windows 可用。',
        AgentCapability.mcp => '调用已连接的 MCP 服务器提供的远程工具；远程工具同样经过权限校验与审计，不会绕过急停。',
      };

  Widget _mcp() => _list([
        AppCard(
          padding: EdgeInsets.zero,
          child: controller.mcpServers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: Insets.x6),
                  child: EmptyHint(
                      text: '还没有连接 MCP 服务器', icon: Icons.hub_outlined),
                )
              : Column(
                  children: [
                    for (var i = 0; i < controller.mcpServers.length; i++)
                      _mcpRow(controller.mcpServers[i],
                          last: i == controller.mcpServers.length - 1),
                  ],
                ),
        ),
        const SizedBox(height: Insets.x3),
        Row(
          children: [
            PillButton(
                label: '添加服务器', icon: Icons.add_rounded, onPressed: _addServer),
            const SizedBox(width: Insets.x2),
            const Expanded(
              child: Text(
                'MCP 提供远程工具，调用同样走权限校验与审计。',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
              ),
            ),
          ],
        ),
        if (controller.mcpError != null) ...[
          const SizedBox(height: Insets.x3),
          AppBanner(tone: BannerTone.danger, text: controller.mcpError!),
        ],
      ]);

  Widget _mcpRow(McpServer server, {bool last = false}) {
    final count = controller.mcpTools[server.id]?.length ?? 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.x4, 8, Insets.x2, 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                    color: AppColors.surfaceAlt, shape: BoxShape.circle),
                child: const Icon(Icons.dns_outlined,
                    size: 15, color: AppColors.inkSoft),
              ),
              const SizedBox(width: Insets.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      count == 0
                          ? '未连接 · ${server.url}'
                          : '$count 个工具 · ${server.url}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              RoundIconButton(
                icon: Icons.link_rounded,
                tooltip: '连接',
                onPressed: () => controller.connectMcpServer(server.id),
              ),
              RoundIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: '移除',
                onPressed: () => controller.removeMcpServer(server.id),
              ),
            ],
          ),
        ),
        if (!last)
          const Divider(height: 1, indent: Insets.x4, endIndent: Insets.x4),
      ],
    );
  }

  /// M5 全权限总控台：总开关、一键急停、细粒度能力、目标队列与审计。
  Widget _access() => _list([
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _toggle(
                title: '完整本机权限',
                description: controller.agentPermissions.paused
                    ? '已暂停'
                    : '${controller.agentPermissions.enabled.length} / ${AgentCapability.values.length} 项已授予',
                icon: Icons.shield_outlined,
                value: controller.fullAccess,
                onChanged: controller.setFullAccess,
              ),
              _toggle(
                title: '自主执行',
                description: controller.settings.autonomyEnabled
                    ? '目标队列与多步规划循环：开着'
                    : '只响应当场指令：关着',
                icon: Icons.auto_mode_rounded,
                value: controller.autonomyEnabled,
                onChanged: controller.setAutonomyEnabled,
              ),
              _toggle(
                title: '环境感知',
                description: '剪贴板模式与前台窗口类别，只保留标签不落盘原文',
                icon: Icons.sensors_rounded,
                value: controller.perceptionEnabled,
                onChanged: controller.setPerceptionEnabled,
              ),
              _toggle(
                title: '拦截不可逆命令',
                description: '保留 6 条系统级黑名单（格式化、删根目录等）',
                icon: Icons.block_rounded,
                value: controller.agentPermissions.blockIrreversible,
                onChanged: (v) => controller.applyPermissions(
                  controller.agentPermissions.copyWith(blockIrreversible: v),
                ),
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.x3),
        // 急停放在最显眼的位置：出问题时第一反应应该是「先停住」。
        AppCard(
          padding: const EdgeInsets.all(Insets.x3),
          color: controller.agentPermissions.paused
              ? AppColors.warningTint
              : AppColors.surfaceAlt,
          border: false,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.agentPermissions.paused ? '已暂停运行' : '一切正常',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      controller.agentPermissions.paused
                          ? '工具、自主循环与感知全部停摆，设置仍可操作'
                          : '暂停后所有工具与自主任务立即停摆，不需要重启 App',
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Insets.x3),
              PillButton(
                label: controller.agentPermissions.paused ? '恢复运行' : '一键暂停',
                icon: controller.agentPermissions.paused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                dense: true,
                onPressed: () =>
                    controller.setPaused(!controller.agentPermissions.paused),
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.x4),
        const SectionLabel('能力清单', description: '逐项回收授权，命中被关闭的项时调用会被拦截'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < AgentCapability.values.length; i++)
                _toggle(
                  title: AgentCapability.values[i].label,
                  description: _capabilityHelp(AgentCapability.values[i]),
                  value: controller.agentPermissions.enabled
                      .contains(AgentCapability.values[i]),
                  onChanged: (v) => controller.setCapabilityEnabled(
                      AgentCapability.values[i], v),
                  last: i == AgentCapability.values.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.x4),
        const SectionLabel('执行留痕', description: '下达目标、查看队列与最近动作'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _jump(
                title: '派一个目标',
                description: '用一句自然语言下达多步任务',
                icon: Icons.flag_outlined,
                onTap: _newGoal,
              ),
              _jump(
                title: '目标队列',
                description: '排队 / 执行中 / 已完成 / 失败，可单独叫停',
                icon: Icons.list_alt_rounded,
                onTap: _showGoals,
              ),
              _jump(
                title: '最近动作',
                description: '审计日志：工具、来源、脱敏参数与结果摘要',
                icon: Icons.history_rounded,
                onTap: _showAudit,
              ),
              _jump(
                title: '学习沉淀',
                description: '同类请求的经验回灌给规划与聊天提示词',
                icon: Icons.lightbulb_outline_rounded,
                onTap: _showExperience,
                last: true,
              ),
            ],
          ),
        ),
      ]);

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
        title: const Text('派一个目标'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: _goal,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(hintText: '例如：检查 D 盘剩余空间并整理成清单'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始')),
        ],
      ),
    );
    if (ok != true) return;
    final text = _goal.text.trim();
    if (text.isEmpty) return;
    final line = await controller.submitAgentGoal(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(line, style: const TextStyle(fontSize: 12.5))),
    );
  }

  Future<void> _showGoals() async {
    final goals =
        await (controller.autonomy?.goals() ?? Future.value(<Goal>[]));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('目标队列'),
        content: SizedBox(
          width: 520,
          height: 400,
          child: goals.isEmpty
              ? const EmptyHint(text: '还没有派过目标', icon: Icons.flag_outlined)
              : ListView.separated(
                  itemCount: goals.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final goal = goals.reversed.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(goal.title,
                          maxLines: 2, style: const TextStyle(fontSize: 12.5)),
                      subtitle: Text(
                        '${_goalStatusLabel(goal.status)} · ${goal.steps.length} 步 · ${goal.origin == 'self' ? '自发' : '主人'}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: goal.active
                          ? RoundIconButton(
                              icon: Icons.stop_circle_outlined,
                              tooltip: '叫停',
                              iconColor: AppColors.danger,
                              onPressed: () async {
                                final navigator = Navigator.of(ctx);
                                await controller.autonomy?.cancel(goal.id);
                                navigator.pop();
                              },
                            )
                          : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
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
        title: const Text('最近动作'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: entries.isEmpty
              ? const EmptyHint(text: '还没有记录', icon: Icons.history_rounded)
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        entry.ok
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        size: 16,
                        color: entry.ok ? AppColors.success : AppColors.danger,
                      ),
                      title: Text(
                        '${entry.timeLabel}  ${entry.tool}  ·  ${entry.source}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        '${entry.argsSummary}\n${entry.outputSummary}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, height: 1.4),
                      ),
                    );
                  },
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
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _showExperience() async {
    final List<Experience> items =
        await controller.experienceBank.recent(limit: 60);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('学习沉淀 · 最近 ${items.length} 条'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: items.isEmpty
              ? const EmptyHint(
                  text: '还没有攒下经验\n让它在对话里办几件事就会开始记录',
                  icon: Icons.lightbulb_outline_rounded)
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        item.ok
                            ? Icons.lightbulb_outline_rounded
                            : Icons.error_outline_rounded,
                        size: 17,
                        color: item.ok ? AppColors.success : AppColors.danger,
                      ),
                      title: Text(
                        '${item.dayLabel}  ${item.ok ? '成功' : '失败'} · ${item.goal}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        '${item.tools.isEmpty ? '未调用工具' : item.tools.join(' → ')}\n${item.summary}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, height: 1.4),
                      ),
                    );
                  },
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
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _addServer() async {
    _name.clear();
    _url.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加 MCP 服务器'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppField(
                  label: '名称',
                  child: TextField(controller: _name, autofocus: true)),
              const SizedBox(height: Insets.x3),
              AppField(
                label: '地址',
                hint: '例如 http://127.0.0.1:5090/mcp',
                child: TextField(controller: _url),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('添加')),
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
