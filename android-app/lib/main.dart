import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'data/story_store.dart';
import 'ui/app_style.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OneDayApp());
}

class OneDayApp extends StatefulWidget {
  const OneDayApp({super.key});

  @override
  State<OneDayApp> createState() => _OneDayAppState();
}

class _OneDayAppState extends State<OneDayApp> {
  late final Future<StoryStore> _store = _load();

  Future<StoryStore> _load() async {
    final directory = await getApplicationSupportDirectory();
    return StoryStore.open(directory);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '1Day',
    debugShowCheckedModeBanner: false,
    theme: oneDayTheme(),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: FutureBuilder<StoryStore>(
      future: _store,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    say(
                      context,
                      '故事库暂时无法打开。请保留应用数据并稍后再试。',
                      'Your story library could not open. Keep app data and try again.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return HomeScreen(store: snapshot.data!);
      },
    ),
  );
}
