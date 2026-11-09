import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_day/data/story_store.dart';
import 'package:one_day/ui/home_screen.dart';

void main() {
  testWidgets('custom moments can be created and reopened without AI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('oneday-custom-ui-'),
    );
    addTearDown(() => root!.delete(recursive: true));
    final store = await tester.runAsync(() => StoryStore.open(root!));
    await tester.pumpWidget(
      MaterialApp(home: CreateStoryScreen(store: store!)),
    );
    await tester.tap(find.text('Write my own moments'));
    await tester.pumpAndSettle();
    Future<void> fill(String label, String value) async {
      final field = find.widgetWithText(TextField, label);
      await tester.scrollUntilVisible(
        field,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(field, value);
    }

    await fill('Moment 1', 'The first coffee');
    await fill('Moment 2', 'A quiet street');
    await fill('Moment 3', 'Home again');
    await fill('Story title', 'My Saturday');
    await tester.ensureVisible(find.text('Start story'));
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start story'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Start story')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(store.stories, hasLength(1));
    expect(find.text('My Saturday'), findsOneWidget);
    expect(find.text('The first coffee'), findsOneWidget);
    final reopened = await tester.runAsync(() => StoryStore.open(root!));
    expect(reopened!.stories.single.moments.map((m) => m.prompt), [
      'The first coffee',
      'A quiet street',
      'Home again',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home opens the offline story creator and selects a template', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('one-day-ui-test-'),
    );
    if (root == null) throw StateError('Could not create test directory');
    addTearDown(() => root.delete(recursive: true));
    final store = await tester.runAsync(() => StoryStore.open(root));
    if (store == null) throw StateError('Could not open test store');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: HomeScreen(store: store),
      ),
    );

    await tester.tap(find.text('Start a story'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('What kind of day?'), findsOneWidget);
    await tester.tap(find.text('Live With Me'));
    await tester.pump();
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(store.stories, isEmpty);
  });
}
