import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/story.dart';

enum SuggestionFailure { unavailable, rateLimited, malformed }

class SuggestionException implements Exception {
  const SuggestionException(this.failure);
  final SuggestionFailure failure;
}

/// Only filming intent is sent; video files always remain on the device.
class PromptSuggestions {
  PromptSuggestions({Uri? endpoint, this.timeout = const Duration(seconds: 20)})
    : endpoint =
          endpoint ??
          Uri.parse(
            'https://oneday-suggest-prompts.oneday-cassie.workers.dev/api/suggest-prompts',
          );

  final Uri endpoint;
  final Duration timeout;

  Future<List<String>> suggest({
    required String intent,
    required int count,
    required String language,
    required Directory storage,
  }) async {
    final identity = File('${storage.path}/suggestion-install-id');
    final device = await identity.exists()
        ? await identity.readAsString()
        : Story.newId();
    if (!await identity.exists()) {
      await identity.writeAsString(device, flush: true);
    }
    final client = HttpClient();
    try {
      return await _request(
        client,
        intent,
        count,
        language,
        device,
      ).timeout(timeout);
    } on TimeoutException {
      throw const SuggestionException(SuggestionFailure.unavailable);
    } on IOException {
      throw const SuggestionException(SuggestionFailure.unavailable);
    } on FormatException {
      throw const SuggestionException(SuggestionFailure.malformed);
    } finally {
      client.close(force: true);
    }
  }

  Future<List<String>> _request(
    HttpClient client,
    String intent,
    int count,
    String language,
    String device,
  ) async {
    final request = await client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'intent': intent,
        'count': count,
        'language': language.startsWith('zh') ? 'zh' : 'en',
        'device': device,
      }),
    );
    final response = await request.close();
    if (response.statusCode == 429) {
      throw const SuggestionException(SuggestionFailure.rateLimited);
    }
    if (response.statusCode != 200) {
      throw const SuggestionException(SuggestionFailure.unavailable);
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    final prompts = decoded is Map ? decoded['prompts'] : null;
    if (prompts is! List ||
        prompts.length != count ||
        prompts.any(
          (value) =>
              value is! String || value.trim().isEmpty || value.length > 80,
        )) {
      throw const SuggestionException(SuggestionFailure.malformed);
    }
    return prompts.cast<String>().map((value) => value.trim()).toList();
  }
}
