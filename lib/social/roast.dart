import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

/// Where the roast worker lives. The URL is not a secret; the Gemini key is
/// only ever held by the worker, never by this app.
abstract final class RoastConfig {
  static const String workerUrl = String.fromEnvironment(
    'ROAST_WORKER_URL',
    defaultValue: 'https://strand-roast.samratrockin.workers.dev',
  );
}

/// A path on the worker, whatever form the configured base URL takes.
///
/// The build can be given either the bare origin or a URL that already ends in
/// `/roast`; both have to resolve to the same endpoint, because a request to
/// `/` is a 404 on this worker and the app would silently show its cached
/// paragraph forever.
Uri workerEndpoint(String path) {
  final Uri base = Uri.parse(RoastConfig.workerUrl);
  String trimmed = base.path.replaceAll(RegExp(r'/+$'), '');
  if (trimmed.endsWith('/roast')) {
    trimmed = trimmed.substring(0, trimmed.length - '/roast'.length);
  }
  return base.replace(path: '$trimmed/$path');
}

/// A cached roast, as stored in `narratives/{pairId}`.
class RoastNarrative {
  const RoastNarrative({
    required this.status,
    required this.text,
    required this.dateKeyA,
    required this.dateKeyB,
    required this.generatedAt,
  });

  final String status;
  final String text;
  final String dateKeyA;
  final String dateKeyB;
  final int generatedAt;

  bool get isReady => status == 'ready' && text.trim().isNotEmpty;

  factory RoastNarrative.fromMap(Map<String, dynamic> map) {
    return RoastNarrative(
      status: (map['status'] as String?) ?? '',
      text: (map['text'] as String?) ?? '',
      dateKeyA: (map['dateKeyA'] as String?) ?? '',
      dateKeyB: (map['dateKeyB'] as String?) ?? '',
      generatedAt: (map['generatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The worker's answer. `status` is the worker's own vocabulary, kept small
/// and explicit so the page can say something honest for each case.
class RoastResult {
  const RoastResult(this.status, {this.text = ''});

  final String status;
  final String text;

  bool get ok => status == 'ok';
}

/// A small in-memory throttle. A list that rebuilds should not become a list
/// that posts. The worker also dedupes, but the request should not leave the
/// phone more than once a minute for the same pair of nights.
abstract final class RoastRequests {
  static final Map<String, DateTime> _lastSent = <String, DateTime>{};

  static bool shouldSend(String key) {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastSent[key];
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return false;
    }
    _lastSent[key] = now;
    return true;
  }
}

/// Asks the worker to make sure a roast exists for this pair.
///
/// This never invents a fallback roast. A failure is returned as a failure and
/// the page shows a plain sentence instead.
Future<RoastResult> requestRoast(String friendUid) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final HttpClientRequest request = await client
        .postUrl(workerEndpoint('roast'))
        .timeout(const Duration(seconds: 20));
    request.headers.set('content-type', 'application/json');
    final String? token = await _idToken();
    if (token == null || token.isEmpty) {
      return const RoastResult('unauthorized');
    }
    request.headers.set('authorization', 'Bearer $token');
    request.add(utf8.encode(jsonEncode(<String, String>{'friendUid': friendUid})));
    final HttpClientResponse response = await request
        .close()
        .timeout(const Duration(seconds: 75));
    final String body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 401) {
      return const RoastResult('unauthorized');
    }
    if (response.statusCode != 200) {
      return const RoastResult('error');
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return const RoastResult('error');
    }
    return RoastResult(
      (decoded['status'] as String?) ?? 'error',
      text: (decoded['text'] as String?) ?? '',
    );
  } catch (_) {
    return const RoastResult('network');
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
