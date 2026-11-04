import 'dart:math';

import '../../models/chat.dart';
import '../../models/pet.dart';

/// 离线「小脑」：不联网也能聊几句，同时作为在线模型失败时的兜底。
class LocalBrain {
  LocalBrain([Random? random]) : _random = random ?? Random();

  final Random _random;

  PetReply reply(String input, Pet pet, {int affection = 0}) {
    final text = input.trim();
    if (text.isEmpty) return PetReply('嗯？', PetMood.idle);

    bool hit(List<String> words) => words.any(text.toLowerCase().contains);

    if (hit(['你好', '嗨', '在吗', 'hello', 'hi', '早上好', '晚上好'])) {
      return PetReply(_pick([
        '在的在的！我一直都在这里呀。',
        '嗨——今天过得怎么样？',
        '你终于来找我啦，我等了好久。',
        '${pet.personality.traits.first}模式，启动！',
      ]));
    }

    if (hit(['摸', 'rua', '撸', '抱', '贴贴', '亲', '蹭'])) {
      final level = affection > 20 ? '再摸下去我要融化了…' : '嘿嘿，好舒服。';
      return PetReply(
        _pick(['唔…最喜欢被摸头了。', level, '（眯起眼睛蹭了蹭你的手）', '再、再摸一下也可以哦。']),
        affection > 12 ? PetMood.love : PetMood.happy,
      );
    }

    if (hit(['吃', '饿', '零食', '投喂', '饭'])) {
      return PetReply(
        _pick(['有吃的吗？我不挑食的！', '肚子在叫了…你听见了吗？', '投喂一只小饼干，好感度 +10！', '我可以吃一点点，就一点点。']),
        PetMood.happy,
      );
    }

    if (hit(['名字', '叫什么', '是谁', '自我介绍'])) {
      return PetReply(
        '我叫${pet.name}。${pet.personality.traits.join('、')}，请多指教！',
        PetMood.happy,
      );
    }

    if (hit(['几点', '时间', '日期', '今天星期'])) {
      final now = DateTime.now();
      const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
      return PetReply(
        '现在是 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}，'
        '星期${weekdays[now.weekday - 1]}。要早点休息哦。',
        PetMood.idle,
      );
    }

    if (hit(['晚安', '睡觉', '困', '熬夜'])) {
      return PetReply(_pick(['晚安…我就在桌面上守着你。', '呼…一起睡吧。', '记得定闹钟，别迟到啦。']), PetMood.sleepy);
    }

    if (hit(['笑话', '讲个', '逗我'])) {
      return PetReply(
        _pick([
          '为什么程序员分不清万圣节和圣诞节？因为 Oct 31 == Dec 25。',
          '我昨天想减肥，结果把「想」字删掉了。',
          '一只猫走进咖啡馆，说：喵 latte，谢谢。',
          '主人知道我为什么不怕黑吗？因为我本来就住在桌面里呀。',
        ]),
        PetMood.happy,
      );
    }

    if (hit(['喜欢', '爱你', '想你', '宝贝', '可爱'])) {
      return PetReply(
        _pick(['我、我也最喜欢主人了！', '（脸红）这种话…不要突然说啦。', '那你要一直把我带在身边哦。']),
        PetMood.love,
      );
    }

    if (hit(['难过', '烦', '压力', '哭', '伤心', 'emo', '焦虑', '累'])) {
      return PetReply(
        _pick([
          '先深呼吸一下。我陪着你，不说话也可以。',
          '今天辛苦啦。要不要摸摸我的头，充会儿电？',
          '难过的话就靠过来一点点，我不走。',
        ]),
        PetMood.sleepy,
      );
    }

    if (hit(['笨', '丑', '讨厌', '滚', '闭嘴', '烦人'])) {
      return PetReply(_pick(['哼！不理你了。', '（把脸转过去）…三分钟。', '你再说一次试试？']), PetMood.angry);
    }

    if (hit(['天气', '下雨', '好冷', '好热'])) {
      return PetReply(
        _pick(['我看不到窗外…不过有你在，就是晴天。', '冷的话，多穿一件，别硬扛。', '下雨天最适合窝在桌面上发呆。']),
        PetMood.idle,
      );
    }

    if (hit(['会什么', '能做什么', '功能', '帮我'])) {
      return PetReply(
        '我会陪着你、听你说话、记住你摸过我几次。\n'
        '还可以换形象：把照片丢进「生成」页，我就变成那只小家伙啦。',
        PetMood.happy,
      );
    }

    if (hit(['再见', '拜拜', '走了', '下班'])) {
      return PetReply(_pick(['去吧去吧，我在这里等你。', '路上小心，早点回来。', '（挥手）要记得我哦。']), PetMood.sleepy);
    }

    if (hit(['谢谢', '谢啦'])) {
      return PetReply(_pick(['不用谢，这是我应该做的！', '嘿嘿，被夸到了。', '那…摸一下头当报酬？']), PetMood.love);
    }

    if (text.endsWith('?') || text.endsWith('？')) {
      return PetReply(
        _pick([
          '唔…这个问题有点难住我了。要不我们聊点别的？',
          '我只是一只小宠物，不过我可以认真听你说。',
          '让我想想…想不出来，先装可爱蒙混过关。',
        ]),
        PetMood.idle,
      );
    }

    final trait = pet.personality.traits[_random.nextInt(pet.personality.traits.length)];
    return PetReply(
      _pick([
        '（歪头）「$text」…是什么意思呀？',
        '我在听，继续说嘛。',
        '嗯嗯，然后呢？',
        '以我$trait的性格，我觉得你说得对。',
        '虽然听不太懂，但我会一直陪着你的。',
      ]),
      PetMood.idle,
    );
  }

  String _pick(List<String> options) => options[_random.nextInt(options.length)];
}
