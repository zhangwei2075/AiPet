import 'package:flutter/services.dart';

import '../brain_host.dart';
import '../pet_tool.dart';

/// 读剪贴板（M1 只做按需读取；持续监听属于 M3 的 ClipboardTrigger）。
class ClipboardTool extends PetTool {
  const ClipboardTool();

  @override
  String get name => 'clipboard';

  @override
  String get description => '读取系统剪贴板的文本内容，无参数。';

  @override
  Map<String, dynamic> get parametersSchema => {'type': 'object', 'properties': {}};

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return const ToolResult.ok('剪贴板是空的。');
    final snippet = text.length > 100 ? '${text.substring(0, 100)}…' : text;
    return ToolResult.ok('剪贴板里是：「$snippet」');
  }
}

/// 让宠物做动作：把自己当成工具交给模型，是「模型发起动作」的通道。
class PetControlTool extends PetTool {
  const PetControlTool(this._host);

  final BrainHost _host;

  @override
  String get name => 'pet_control';

  @override
  String get description =>
      '让宠物自己做一个动作。action: stroll=散步, run=小跑一圈, hop=开心跳, '
      'sleep=睡觉, wake=叫醒, beg=趴下求摸。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['stroll', 'run', 'hop', 'sleep', 'wake', 'beg'],
          },
        },
        'required': ['action'],
      };

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = (args['action'] as String?)?.trim();
    switch (action) {
      case 'stroll':
        _host.agentStroll(run: false);
      case 'run':
        _host.agentStroll(run: true);
      case 'hop':
        _host.agentHop();
      case 'sleep':
        _host.agentSleep();
      case 'wake':
        _host.agentWake();
      case 'beg':
        _host.agentBeg();
      default:
        return const ToolResult.fail('不认识的动作，可选：stroll/run/hop/sleep/wake/beg。');
    }
    return ToolResult.ok('好嘞，这就${_label(action)}。');
  }

  static String _label(String? action) => switch (action) {
        'stroll' => '去散步',
        'run' => '跑一圈',
        'hop' => '跳一个',
        'sleep' => '打个盹',
        'wake' => '醒过来',
        'beg' => '趴下卖萌',
        _ => '行动',
      };
}
