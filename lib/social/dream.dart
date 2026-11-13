import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import 'roast.dart';

/// Asks the worker to read one dream.
///
/// Same worker, same key discipline: the Gemini key stays on Cloudflare and the
/// only thing this app sends is the Firebase ID token and the dream itself.
/// Nothing is stored on the worker; the reading comes back once and lives in
/// Hive beside the entry.
class DreamResult {
  const DreamResult(this.status, {this.text = ''});

  final String status;
  final String text;

  bool get ok => status == 'ok' && text.trim().isNotEmpty;
}

Future<DreamResult> requestDreamInterpretation(String dream) async {
  final String text = dream.trim();
  if (text.isEmpty) return const DreamResult('empty');

  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final HttpClientRequest request = await client
        .postUrl(workerEndpoint('dream'))
        .timeout(const Duration(seconds: 20));
    request.headers.set('content-type', 'application/json');
    final String? token = await _idToken();
    if (token == null || token.isEmpty) {
      return const DreamResult('unauthorized');
    }
    request.headers.set('authorization', 'Bearer $token');
    request.add(utf8.encode(jsonEncode(<String, String>{'text': text})));
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 75),
    );
    final String body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 401) {
      return const DreamResult('unauthorized');
    }
    if (response.statusCode != 200) {
      return const DreamResult('error');
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return const DreamResult('error');
    }
    return DreamResult(
      (decoded['status'] as String?) ?? 'error',
      text: (decoded['text'] as String?) ?? '',
    );
  } catch (_) {
    return const DreamResult('network');
  } finally {
    client.close(force: true);
  }
}

Future<String?> _idToken() async {
  try {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  } catch (_) {
    return null;
  }
}
