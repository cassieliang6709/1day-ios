import 'dart:io';

import 'package:flutter/material.dart';

import '../data/story_store.dart';
import '../domain/story.dart';
import '../domain/templates.dart';
import 'app_style.dart';
import '../services/prompt_suggestions.dart';
import 'story_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final StoryStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('1Day')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Text(
              say(
                context,
                '几个短暂瞬间，\n留住这一天。',
                'A few short moments\nkeep the whole day.',
              ),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 14),
            Text(
              say(
                context,
                '拍下片段，在手机上变成一支短片。',
                'Capture little clips. Make a film on your phone.',
              ),
              style: const TextStyle(color: Color(0xFF5B7099), fontSize: 16),
            ),
            const SizedBox(height: 28),
            if (store.stories.isEmpty)
              BluePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 26,
                      backgroundColor: oneDayMist,
                      child: Icon(
                        Icons.movie_creation_outlined,
                        color: oneDayBlue,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      say(context, '今天还没有故事', 'Your first story starts here'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      say(
                        context,
                        '选一种心情，每次拍几秒。漏掉一段也没关系。',
                        'Pick a mood and film a few seconds at a time.',
                      ),
                      style: const TextStyle(color: Color(0xFF5B7099)),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => _create(context),
                      child: Text(say(context, '开始今天的故事', 'Start a story')),
                    ),
                  ],
                ),
              )
            else ...[
              FilledButton.icon(
                onPressed: () => _create(context),
                icon: const Icon(Icons.add),
                label: Text(say(context, '新建故事', 'New story')),
              ),
              const SizedBox(height: 22),
              Text(
                say(context, '我的故事', 'My stories'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final story in store.stories) ...[
                _StoryCard(story: story, store: store),
                const SizedBox(height: 12),
              ],
            ],
            const SizedBox(height: 26),
            Text(
              say(
                context,
                '单人故事只保存在这台设备上。',
                'Solo stories stay on this device.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF7186AA), fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  void _create(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CreateStoryScreen(store: store)),
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.story, required this.store});

  final Story story;
  final StoryStore store;

  @override
  Widget build(BuildContext context) => BluePanel(
    padding: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StoryScreen(store: store, storyId: story.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 66,
              height: 82,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [oneDayBlue, oneDayCyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${story.recordedCount}/${story.moments.length} · '
                    '${story.mode == StoryMode.oneDay ? say(context, '一天', 'One day') : say(context, '七天', 'Seven days')}',
                    style: const TextStyle(color: Color(0xFF5B7099)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: oneDayBlue),
          ],
        ),
      ),
    ),
  );
}

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key, required this.store});

  final StoryStore store;

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  StoryMode mode = StoryMode.oneDay;
  StoryTemplate? selected;
  int seconds = 2;
  StoryOrientation orientation = StoryOrientation.portrait;
  final title = TextEditingController();
  bool saving = false;
  bool custom = false;
  bool generating = false;
  String? suggestionError;
  final intent = TextEditingController();
  final prompts = List.generate(7, (_) => TextEditingController());

  @override
  void dispose() {
    title.dispose();
    intent.dispose();
    for (final prompt in prompts) {
      prompt.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final available = storyTemplates.where((item) => item.mode == mode);
    return Scaffold(
      appBar: AppBar(title: Text(say(context, '新故事', 'New story'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              say(context, '想记录怎样的一天？', 'What kind of day?'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            SegmentedButton<StoryMode>(
              segments: [
                ButtonSegment(
                  value: StoryMode.oneDay,
                  label: Text(say(context, '一天', 'One day')),
                ),
                ButtonSegment(
                  value: StoryMode.sevenDay,
                  label: Text(say(context, '七天', 'Seven days')),
                ),
              ],
              selected: {mode},
              onSelectionChanged: generating || saving
                  ? null
                  : (value) => setState(() {
                      mode = value.first;
                      custom = false;
                      selected = null;
                      title.clear();
                    }),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: generating || saving
                  ? null
                  : () => setState(() {
                      custom = !custom;
                      selected = null;
                      suggestionError = null;
                    }),
              icon: const Icon(Icons.edit_outlined),
              label: Text(
                custom
                    ? say(context, '改用现成模板', 'Choose a template')
                    : say(context, '自己写拍摄提示', 'Write my own moments'),
              ),
            ),
            for (final template
                in (custom ? <StoryTemplate>[] : available)) ...[
              BluePanel(
                padding: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: generating || saving
                      ? null
                      : () => setState(() {
                          custom = false;
                          selected = template;
                          title.text = template.name.inLanguage(language);
                        }),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Icon(
                          selected == template
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: oneDayBlue,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                template.name.inLanguage(language),
                                style: const TextStyle(
                                  color: oneDayNavy,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                template.description.inLanguage(language),
                                style: const TextStyle(
                                  color: Color(0xFF5B7099),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (custom) ...[
              TextField(
                controller: intent,
                enabled: !generating && !saving,
                maxLength: 140,
                decoration: InputDecoration(
                  labelText: say(
                    context,
                    '今天想做什么？（可选）',
                    'What are you doing? (optional)',
                  ),
                  helperText: say(
                    context,
                    '生成时会将这句话发送给 AI 服务。',
                    'Generating sends this sentence to the AI service.',
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: generating || saving ? null : _suggest,
                child: Text(
                  generating
                      ? say(context, '正在生成…', 'Generating…')
                      : say(context, '帮我想拍摄提示', 'Suggest moments'),
                ),
              ),
              if (suggestionError != null)
                Text(
                  suggestionError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              for (var i = 0; i < 7; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: prompts[i],
                    enabled: !generating && !saving,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: mode == StoryMode.sevenDay
                          ? say(context, '第 ${i + 1} 天', 'Day ${i + 1}')
                          : say(context, '拍摄提示 ${i + 1}', 'Moment ${i + 1}'),
                    ),
                  ),
                ),
              Text(
                say(
                  context,
                  mode == StoryMode.sevenDay ? '每天填写一条，共七条。' : '至少填写三条，最多七条。',
                  mode == StoryMode.sevenDay
                      ? 'Add one moment for each of seven days.'
                      : 'Add three to seven moments.',
                ),
              ),
            ],
            if (selected != null || custom) ...[
              const SizedBox(height: 15),
              TextField(
                controller: title,
                maxLength: 50,
                decoration: InputDecoration(
                  labelText: say(context, '故事名称', 'Story title'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                say(context, '每段拍多久', 'Clip length'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 9,
                children: [
                  for (final value in [2, 5, 10])
                    ChoiceChip(
                      label: Text('$value s'),
                      selected: seconds == value,
                      onSelected: (_) => setState(() => seconds = value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                say(context, '画面方向', 'Frame direction'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              SegmentedButton<StoryOrientation>(
                segments: [
                  ButtonSegment(
                    value: StoryOrientation.portrait,
                    label: Text(say(context, '竖屏', 'Portrait')),
                  ),
                  ButtonSegment(
                    value: StoryOrientation.landscape,
                    label: Text(say(context, '横屏', 'Landscape')),
                  ),
                ],
                selected: {orientation},
                onSelectionChanged: (value) =>
                    setState(() => orientation = value.first),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: saving || generating ? null : _save,
                child: Text(
                  saving
                      ? say(context, '正在创建…', 'Creating…')
                      : say(context, '开始故事', 'Start story'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _suggest() async {
    final sentence = intent.text.trim();
    if (sentence.isEmpty) {
      setState(
        () => suggestionError = say(
          context,
          '先写一句今天想做的事，也可以直接填写下方提示。',
          'Describe your day, or write the moments below yourself.',
        ),
      );
      return;
    }
    setState(() {
      generating = true;
      suggestionError = null;
    });
    try {
      final suggestions = await PromptSuggestions().suggest(
        intent: sentence,
        count: 7,
        language: Localizations.localeOf(context).languageCode,
        storage: widget.store.root,
      );
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < suggestions.length; i++) {
          prompts[i].text = suggestions[i];
        }
      });
    } on SuggestionException catch (error) {
      if (!mounted) return;
      setState(
        () => suggestionError = error.failure == SuggestionFailure.rateLimited
            ? say(
                context,
                '生成次数较多，请稍后重试。你仍可以自己填写。',
                'Too many requests. Try later or write your own moments.',
              )
            : say(
                context,
                '暂时生成不了，请重试或自己填写。已写内容仍保留。',
                'Could not generate. Retry or write your own moments; your text is kept.',
              ),
      );
    } on FileSystemException {
      if (!mounted) return;
      setState(
        () => suggestionError = say(
          context,
          '无法保存生成设置，请检查设备存储后重试。',
          'Could not save settings. Check device storage and retry.',
        ),
      );
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> _save() async {
    final template = selected;
    final storyTitle = title.text.trim();
    final written = prompts
        .map((p) => p.text.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if ((!custom && template == null) ||
        storyTitle.isEmpty ||
        (custom &&
            (written.length < 3 ||
                (mode == StoryMode.sevenDay && written.length != 7)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            say(
              context,
              '请填写名称和拍摄提示；一天至少三条，七天需七条。',
              'Add a title and moments: at least three for one day, seven for seven days.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => saving = true);
    final story = Story(
      id: Story.newId(),
      title: storyTitle,
      startDate: DateTime.now(),
      mode: mode,
      clipSeconds: seconds,
      orientation: orientation,
      templateKey: custom ? 'custom' : template!.key,
      moments: custom
          ? [
              for (var i = 0; i < written.length; i++)
                StoryMoment(key: 'custom_${i + 1}', prompt: written[i]),
            ]
          : template!.momentKeys.map((key) => StoryMoment(key: key)).toList(),
    );
    try {
      await widget.store.add(story);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => StoryScreen(store: widget.store, storyId: story.id),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            say(
              context,
              '创建失败，请再试一次。',
              'Could not create the story. Try again.',
            ),
          ),
        ),
      );
      setState(() => saving = false);
    }
  }
}
