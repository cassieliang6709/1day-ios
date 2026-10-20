import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_day/services/prompt_suggestions.dart';

void main() {
  late HttpServer server;
  late Directory storage;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    storage = await Directory.systemTemp.createTemp('oneday-suggestions-');
  });
  tearDown(() async {
    await server.close(force: true);
    await storage.delete(recursive: true);
  });

  PromptSuggestions service({Duration timeout = const Duration(seconds: 2)}) =>
      PromptSuggestions(
        endpoint: Uri.parse(
          'http://127.0.0.1:${server.port}/api/suggest-prompts',
        ),
        timeout: timeout,
      );

  test(
    'sends the shared iOS contract and keeps installation identity',
    () async {
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        requests.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.write(
          jsonEncode({
            'prompts': [' 出门 ', '公园', '回家'],
          }),
        );
        await request.response.close();
      });
      for (var i = 0; i < 2; i++) {
        expect(
          await service().suggest(
            intent: '散步',
            count: 3,
            language: 'zh',
            storage: storage,
          ),
          ['出门', '公园', '回家'],
        );
      }
      expect(requests.first.keys.toSet(), {
        'intent',
        'count',
        'language',
        'device',
      });
      expect(requests.first['intent'], '散步');
      expect(requests.first['device'], requests.last['device']);
    },
  );

  for (final status in [429, 502]) {
    test('maps HTTP $status to an actionable failure', () async {
      server.listen((request) async {
        request.response.statusCode = status;
        await request.response.close();
      });
      await expectLater(
        service().suggest(
          intent: 'walk',
          count: 3,
          language: 'en',
          storage: storage,
        ),
        throwsA(
          isA<SuggestionException>().having(
            (e) => e.failure,
            'failure',
            status == 429
                ? SuggestionFailure.rateLimited
                : SuggestionFailure.unavailable,
          ),
        ),
      );
    });
  }

  test('rejects an incomplete list before replacing user input', () async {
    server.listen((request) async {
      request.response.write('{"prompts":["only one"]}');
      await request.response.close();
    });
    await expectLater(
      service().suggest(
        intent: 'walk',
        count: 7,
        language: 'en',
        storage: storage,
      ),
      throwsA(
        isA<SuggestionException>().having(
          (e) => e.failure,
          'failure',
          SuggestionFailure.malformed,
        ),
      ),
    );
  });

  test('a stalled response has a bounded wait', () async {
    server.listen((request) {});
    await expectLater(
      service(
        timeout: const Duration(milliseconds: 50),
      ).suggest(intent: 'walk', count: 3, language: 'en', storage: storage),
      throwsA(
        isA<SuggestionException>().having(
          (e) => e.failure,
          'failure',
          SuggestionFailure.unavailable,
        ),
      ),
    );
  });
}
