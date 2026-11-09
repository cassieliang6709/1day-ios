import 'story.dart';

class LocalizedLabel {
  const LocalizedLabel(this.zh, this.en);

  final String zh;
  final String en;

  String inLanguage(String code) => code.startsWith('zh') ? zh : en;
}

class StoryTemplate {
  const StoryTemplate({
    required this.key,
    required this.name,
    required this.description,
    required this.mode,
    required this.momentKeys,
  });

  final String key;
  final LocalizedLabel name;
  final LocalizedLabel description;
  final StoryMode mode;
  final List<String> momentKeys;
}

/// Keys and template identity match the iOS ChallengeTemplate catalog.
/// The Android library remains local until a shared room backend exists.
const storyTemplates = <StoryTemplate>[
  StoryTemplate(
    key: 'Live With Me',
    name: LocalizedLabel('和我过一天', 'Live With Me'),
    description: LocalizedLabel(
      '没有题目，只记录此刻发生的事。',
      'No prompts. Just moments as the day happens.',
    ),
    mode: StoryMode.oneDay,
    momentKeys: [
      'time_1',
      'time_2',
      'time_3',
      'time_4',
      'time_5',
      'time_6',
      'time_7',
    ],
  ),
  StoryTemplate(
    key: 'Perfect Day',
    name: LocalizedLabel('完美的一天', 'Perfect Day'),
    description: LocalizedLabel(
      '愿意再过一遍的一天。',
      "The day you'd happily live twice.",
    ),
    mode: StoryMode.oneDay,
    momentKeys: [
      'wake_up',
      'coffee',
      'get_ready',
      'out_the_door',
      'midday',
      'golden_hour',
      'wind_down',
    ],
  ),
  StoryTemplate(
    key: 'Soft Reset',
    name: LocalizedLabel('慢慢重启', 'Soft Reset'),
    description: LocalizedLabel('安静地重新开始。', 'A quiet day to begin again.'),
    mode: StoryMode.oneDay,
    momentKeys: [
      'messy_start',
      'clear_one_thing',
      'reset_corner',
      'step_outside',
      'small_treat',
      'cozy_detail',
      'after',
    ],
  ),
  StoryTemplate(
    key: 'Lock In',
    name: LocalizedLabel('进入状态', 'Lock In'),
    description: LocalizedLabel('先专注，其他都等等。', 'Focus. Everything else waits.'),
    mode: StoryMode.oneDay,
    momentKeys: [
      'desk_setup',
      'first_sprint',
      'the_wall',
      'refuel',
      'breakthrough',
      'almost_there',
      'shut_the_laptop',
    ],
  ),
  StoryTemplate(
    key: 'Main Character',
    name: LocalizedLabel('我的主角日', 'Main Character'),
    description: LocalizedLabel('今天，镜头跟着你走。', 'Today the camera follows you.'),
    mode: StoryMode.oneDay,
    momentKeys: [
      'morning_light',
      'fit_check',
      'on_the_move',
      'what_i_ate',
      'little_win',
      'mirror_moment',
      'night',
    ],
  ),
  StoryTemplate(
    key: 'Cook With Me',
    name: LocalizedLabel('和我做饭', 'Cook With Me'),
    description: LocalizedLabel(
      '从备料，到第一口。',
      'Raw ingredients to the first bite.',
    ),
    mode: StoryMode.oneDay,
    momentKeys: [
      'ingredients',
      'prep',
      'the_sizzle',
      'taste_test',
      'plate_it',
      'first_bite',
      'clean_up',
    ],
  ),
  StoryTemplate(
    key: 'Little Adventure',
    name: LocalizedLabel('出门冒险', 'Little Adventure'),
    description: LocalizedLabel(
      '出门，看看会遇到什么。',
      'Leave the house. See what happens.',
    ),
    mode: StoryMode.oneDay,
    momentKeys: [
      'heading_out',
      'first_stop',
      'street_snack',
      'found_a_spot',
      'people_watching',
      'golden_light',
      'back_home',
    ],
  ),
  StoryTemplate(
    key: '7 Days Moving',
    name: LocalizedLabel('动起来的一周', '7 Days Moving'),
    description: LocalizedLabel(
      '连续七天，动起来。',
      'Seven days of showing up sweaty.',
    ),
    mode: StoryMode.sevenDay,
    momentKeys: ['commit', 'sweat', 'sore', 'push', 'flow', 'strong', 'proof'],
  ),
  StoryTemplate(
    key: 'Morning Person',
    name: LocalizedLabel('早起的人', 'Morning Person'),
    description: LocalizedLabel(
      '遇见早起的自己。',
      'Meet the version of you that wakes early.',
    ),
    mode: StoryMode.sevenDay,
    momentKeys: [
      'the_6am_test',
      'make_the_bed',
      'move_your_body',
      'no_phone',
      'real_breakfast',
      'sunlight',
      'your_best_morning',
    ],
  ),
  StoryTemplate(
    key: 'Study Streak',
    name: LocalizedLabel('学习打卡', 'Study Streak'),
    description: LocalizedLabel(
      '一周，一件事，不找借口。',
      'One week, one subject, no excuses.',
    ),
    mode: StoryMode.sevenDay,
    momentKeys: [
      'first_sitdown',
      'getting_into_it',
      'the_wall',
      'little_win',
      'refill_tank',
      'almost_there',
      'look_back',
    ],
  ),
  StoryTemplate(
    key: 'Eat Well',
    name: LocalizedLabel('好好吃饭', 'Eat Well'),
    description: LocalizedLabel(
      '好好吃饭的一周。',
      'A week of feeding yourself kindly.',
    ),
    mode: StoryMode.sevenDay,
    momentKeys: [
      'fridge_check',
      'cook_one_meal',
      'try_something_new',
      'meal_prep',
      'no_takeout',
      'share_a_meal',
      'favorite_dish',
    ],
  ),
  StoryTemplate(
    key: 'Calm Week',
    name: LocalizedLabel('平静一周', 'Calm Week'),
    description: LocalizedLabel('刻意慢下来的一周。', 'A slower week, on purpose.'),
    mode: StoryMode.sevenDay,
    momentKeys: [
      'one_deep_breath',
      'five_min_sit',
      'walk_no_phone',
      'journal',
      'stretch',
      'digital_sunset',
      'stillness',
    ],
  ),
  StoryTemplate(
    key: 'Make Something',
    name: LocalizedLabel('做点东西', 'Make Something'),
    description: LocalizedLabel('从空白页，到完成品。', 'Blank page to finished piece.'),
    mode: StoryMode.sevenDay,
    momentKeys: [
      'blank_page',
      'first_mark',
      'ugly_middle',
      'keep_going',
      'detail',
      'almost',
      'finished_piece',
    ],
  ),
];

const momentLabels = <String, LocalizedLabel>{
  'wake_up': LocalizedLabel('起床', 'Wake up'),
  'coffee': LocalizedLabel('咖啡', 'Coffee'),
  'get_ready': LocalizedLabel('收拾出门', 'Get ready'),
  'out_the_door': LocalizedLabel('出门', 'Out the door'),
  'midday': LocalizedLabel('正午', 'Midday'),
  'golden_hour': LocalizedLabel('傍晚的光', 'Golden hour'),
  'wind_down': LocalizedLabel('睡前放松', 'Wind down'),
  'messy_start': LocalizedLabel('一团糟的开始', 'Messy start'),
  'clear_one_thing': LocalizedLabel('先清一样东西', 'Clear one thing'),
  'reset_corner': LocalizedLabel('整理一角', 'Reset corner'),
  'step_outside': LocalizedLabel('出去走走', 'Step outside'),
  'small_treat': LocalizedLabel('小奖励', 'Small treat'),
  'cozy_detail': LocalizedLabel('温柔的细节', 'Cozy detail'),
  'after': LocalizedLabel('之后', 'After'),
  'desk_setup': LocalizedLabel('布置桌面', 'Desk setup'),
  'first_sprint': LocalizedLabel('第一段冲刺', 'First sprint'),
  'the_wall': LocalizedLabel('卡住了', 'The wall'),
  'refuel': LocalizedLabel('补充能量', 'Refuel'),
  'breakthrough': LocalizedLabel('突破', 'Breakthrough'),
  'almost_there': LocalizedLabel('就快好了', 'Almost there'),
  'shut_the_laptop': LocalizedLabel('合上电脑', 'Shut the laptop'),
  'morning_light': LocalizedLabel('晨光', 'Morning light'),
  'fit_check': LocalizedLabel('今日穿搭', 'Fit check'),
  'on_the_move': LocalizedLabel('在路上', 'On the move'),
  'what_i_ate': LocalizedLabel('今天吃点什么', "Today's plate"),
  'little_win': LocalizedLabel('小胜利', 'Little win'),
  'mirror_moment': LocalizedLabel('镜子前', 'Mirror moment'),
  'night': LocalizedLabel('夜晚', 'Night'),
  'ingredients': LocalizedLabel('备料', 'Ingredients'),
  'prep': LocalizedLabel('切配', 'Prep'),
  'the_sizzle': LocalizedLabel('下锅', 'The sizzle'),
  'taste_test': LocalizedLabel('尝味道', 'Taste test'),
  'plate_it': LocalizedLabel('摆盘', 'Plate it'),
  'first_bite': LocalizedLabel('第一口', 'First bite'),
  'clean_up': LocalizedLabel('收拾', 'Clean up'),
  'heading_out': LocalizedLabel('出发', 'Heading out'),
  'first_stop': LocalizedLabel('第一站', 'First stop'),
  'street_snack': LocalizedLabel('街边小吃', 'Street snack'),
  'found_a_spot': LocalizedLabel('找个地方坐下', 'A good spot'),
  'people_watching': LocalizedLabel('看人来人往', 'People watching'),
  'golden_light': LocalizedLabel('傍晚的光', 'Golden light'),
  'back_home': LocalizedLabel('到家', 'Back home'),
  'commit': LocalizedLabel('下定决心', 'Commit'),
  'sweat': LocalizedLabel('流汗', 'Sweat'),
  'sore': LocalizedLabel('酸痛', 'Sore'),
  'push': LocalizedLabel('逼自己一把', 'Push'),
  'flow': LocalizedLabel('顺起来了', 'Flow'),
  'strong': LocalizedLabel('变强了', 'Strong'),
  'proof': LocalizedLabel('证明', 'Proof'),
  'the_6am_test': LocalizedLabel('六点起床挑战', 'The 6am test'),
  'make_the_bed': LocalizedLabel('叠被子', 'Make the bed'),
  'move_your_body': LocalizedLabel('动一动', 'Move your body'),
  'no_phone': LocalizedLabel('不看手机', 'No phone'),
  'real_breakfast': LocalizedLabel('好好吃早饭', 'Real breakfast'),
  'sunlight': LocalizedLabel('晒太阳', 'Sunlight'),
  'your_best_morning': LocalizedLabel('最好的早晨', 'Your best morning'),
  'first_sitdown': LocalizedLabel('第一次坐下', 'First sit-down'),
  'getting_into_it': LocalizedLabel('进入状态了', 'Getting into it'),
  'refill_tank': LocalizedLabel('给自己充电', 'Refill the tank'),
  'look_back': LocalizedLabel('回头看看', 'Look back'),
  'fridge_check': LocalizedLabel('看看冰箱', 'Fridge check'),
  'cook_one_meal': LocalizedLabel('做一顿饭', 'Cook one meal'),
  'try_something_new': LocalizedLabel('试点新的', 'Try something new'),
  'meal_prep': LocalizedLabel('备餐', 'Meal prep'),
  'no_takeout': LocalizedLabel('不点外卖', 'No takeout'),
  'share_a_meal': LocalizedLabel('一起吃', 'Share a meal'),
  'favorite_dish': LocalizedLabel('拿手菜', 'Favorite dish'),
  'one_deep_breath': LocalizedLabel('深呼吸', 'One deep breath'),
  'five_min_sit': LocalizedLabel('静坐五分钟', '5-min sit'),
  'walk_no_phone': LocalizedLabel('散步不带手机', 'Walk, no phone'),
  'journal': LocalizedLabel('写日记', 'Journal'),
  'stretch': LocalizedLabel('拉伸', 'Stretch'),
  'digital_sunset': LocalizedLabel('睡前断网', 'Digital sunset'),
  'stillness': LocalizedLabel('安静下来', 'Stillness'),
  'blank_page': LocalizedLabel('空白页', 'Blank page'),
  'first_mark': LocalizedLabel('第一笔', 'First mark'),
  'ugly_middle': LocalizedLabel('丑陋的中途', 'Ugly middle'),
  'keep_going': LocalizedLabel('继续', 'Keep going'),
  'detail': LocalizedLabel('细节', 'Detail'),
  'almost': LocalizedLabel('快好了', 'Almost'),
  'finished_piece': LocalizedLabel('完成的作品', 'Finished piece'),
};

String momentTitle(String key, String language, int slot) {
  if (key.startsWith('time_')) {
    return language.startsWith('zh') ? '片段 $slot' : 'Moment $slot';
  }
  return momentLabels[key]?.inLanguage(language) ?? key;
}
