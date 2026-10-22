import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Address of the nudge Worker on Cloudflare (worker/). Empty until it is deployed; the 👋 button then hides.
const kNudgeWorkerUrl = 'https://brain-buddy-nudge.brainbuddy-app.workers.dev';

bool get nudgesAvailable => kNudgeWorkerUrl.isNotEmpty;

/// Saves this phone's push address so squad friends can nudge us. Only we can write it; only the Worker reads it.
Future<void> registerPushToken() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();
  // The push address arrives (and later refreshes) on onRegistered.
  _registrations ??= messaging.onRegistered.listen((t) {
    final u = FirebaseAuth.instance.currentUser?.uid;
    if (u != null) _save(u, t);
  });
  await messaging.register();
}

StreamSubscription<String>? _registrations;

Future<void> _save(String uid, String token) => FirebaseFirestore.instance
    .collection('fcmTokens')
    .doc(uid)
    .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});

/// Stops nudges reaching this phone (on sign-out and account deletion).
Future<void> forgetPushToken(String uid) async {
  try {
    await FirebaseFirestore.instance.collection('fcmTokens').doc(uid).delete();
  } catch (_) {}
}

enum NudgeResult { sent, tooSoon, friendHasNoNotifications, failed }

/// Sends a 👋 to a squad friend through the Worker.
Future<(NudgeResult, int)> sendNudge(String squadId, String toUid) async {
  final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (idToken == null || !nudgesAvailable) return (NudgeResult.failed, 0);
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$kNudgeWorkerUrl/nudge'));
    req.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $idToken')
      ..contentType = ContentType.json;
    req.write(jsonEncode({'squadId': squadId, 'toUid': toUid}));
    final res = await req.close();
    final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    return switch (res.statusCode) {
      200 => (NudgeResult.sent, 0),
      429 => (NudgeResult.tooSoon, (body['retryInMinutes'] as num?)?.toInt() ?? 0),
      404 => (NudgeResult.friendHasNoNotifications, 0),
      _ => (NudgeResult.failed, 0),
    };
  } catch (_) {
    return (NudgeResult.failed, 0);
  } finally {
    client.close();
  }
}
