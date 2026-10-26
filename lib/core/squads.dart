import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'native_bridge.dart';
import 'nudges.dart';
import 'providers.dart';

/// Max people per Squad (also enforced by the Firestore rules).
const kMaxSquadSize = 8;

/// Avatars to choose from. No photos are uploaded.
const kAvatars = ['🦊', '🐼', '🐯', '🐸', '🐙', '🦄', '🐧', '🐨', '🦁', '🐵', '🐳', '🦉'];

class Squad {
  final String id;
  final String name;
  final String code;
  final String ownerUid;
  final List<String> memberUids;

  const Squad({required this.id, required this.name, required this.code, required this.ownerUid, required this.memberUids});

  factory Squad.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Squad(
      id: d.id,
      name: m['name'] as String? ?? 'Squad',
      code: m['code'] as String? ?? '',
      ownerUid: m['ownerUid'] as String? ?? '',
      memberUids: ((m['memberUids'] as List?) ?? const []).cast<String>(),
    );
  }
}

class SquadMember {
  final String uid;
  final String name;
  final String avatar;
  final String weekKey;
  final int weekWatched;
  final int todayWatched;
  final String prevWeekKey;
  final int prevWeekWatched;
  final DateTime? updatedAt;

  const SquadMember({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.weekKey,
    required this.weekWatched,
    required this.todayWatched,
    required this.prevWeekKey,
    required this.prevWeekWatched,
    required this.updatedAt,
  });

  factory SquadMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return SquadMember(
      uid: d.id,
      name: m['name'] as String? ?? 'Friend',
      avatar: m['avatar'] as String? ?? '🙂',
      weekKey: m['weekKey'] as String? ?? '',
      weekWatched: n('weekWatched'),
      todayWatched: n('todayWatched'),
      prevWeekKey: m['prevWeekKey'] as String? ?? '',
      prevWeekWatched: n('prevWeekWatched'),
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class Profile {
  final String name;
  final String avatar;
  const Profile(this.name, this.avatar);
}

/// Monday of the week containing [day], as "yyyy-MM-dd" (same rule as the native SquadSync).
String weekKeyOf(DateTime day) {
  final monday = DateTime(day.year, day.month, day.day).subtract(Duration(days: day.weekday - 1));
  return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
}

/// Sorts a leaderboard: fewest reels this week first. Members who haven't synced this week go last.
List<SquadMember> rankForWeek(List<SquadMember> members, String weekKey) {
  int score(SquadMember m) => m.weekKey == weekKey ? m.weekWatched : 1 << 30;
  return [...members]..sort((a, b) => score(a).compareTo(score(b)));
}

/// Last week's winner: the fewest reels among members who reported that week.
SquadMember? lastWeekWinner(List<SquadMember> members, String lastWeekKey) {
  final reported = members.where((m) => m.prevWeekKey == lastWeekKey).toList()
    ..sort((a, b) => a.prevWeekWatched.compareTo(b.prevWeekWatched));
  return reported.isEmpty ? null : reported.first;
}

/// A short, plain message for a failed sign-in (the technical details only go to the log).
String signInErrorMessage(Object e) {
  if (e is SquadException) return e.message;
  if (e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled) return 'Sign-in cancelled.';
  if (e is FirebaseAuthException && e.code == 'network-request-failed') return 'No internet connection. Please try again.';
  return 'Sign-in didn\'t work. Please try again.';
}

/// Sign-in and Squads, backed by Firebase Auth and Firestore.
class SquadsRepo {
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final NativeBridge bridge;
  SquadsRepo(this.auth, this.db, this.bridge);

  static bool _googleReady = false;

  User? get user => auth.currentUser;

  Future<void> signInWithGoogle() async {
    final idToken = await _googleIdToken();
    await auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
  }

  Future<void> signInAsGuest() => auth.signInAnonymously();

  Future<String?> _googleIdToken() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize();
      _googleReady = true;
    }
    return (await google.authenticate()).authentication.idToken;
  }

  /// Turns a guest account into a Google account. Squads and nickname are kept, and the account
  /// can then be used on another phone.
  Future<void> upgradeGuestToGoogle() async {
    final idToken = await _googleIdToken();
    try {
      await user!.linkWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      await user!.reload();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use') {
        throw const SquadException(
            'That Google account already has Brain Bean. Sign out of the guest account, then sign in with Google.');
      }
      rethrow;
    }
  }

  /// Backs out of a sign-in that was just made (nickname not chosen yet). A fresh guest account
  /// has nothing in it and could never be signed into again, so it is deleted rather than left behind.
  Future<void> cancelSignIn() async {
    final u = user;
    if (u == null) return;
    if (u.isAnonymous) {
      await u.delete();
    } else {
      await signOut();
    }
  }

  Future<Profile?> profile() async {
    final uid = user?.uid;
    if (uid == null) return null;
    final d = await db.collection('users').doc(uid).get();
    final m = d.data();
    if (m == null || (m['name'] as String?)?.isNotEmpty != true) return null;
    return Profile(m['name'] as String, m['avatar'] as String? ?? kAvatars.first);
  }

  /// Saves the nickname/avatar and updates it in every Squad.
  Future<void> saveProfile(Profile p) async {
    final uid = user!.uid;
    await db.collection('users').doc(uid).set({'name': p.name, 'avatar': p.avatar}, SetOptions(merge: true));
    final squads = await db.collection('squads').where('memberUids', arrayContains: uid).get();
    for (final s in squads.docs) {
      await s.reference.collection('members').doc(uid).set({'name': p.name, 'avatar': p.avatar}, SetOptions(merge: true));
    }
  }

  Stream<List<Squad>> mySquads() {
    final uid = user?.uid;
    if (uid == null) return Stream.value(const []);
    return db
        .collection('squads')
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map((q) => q.docs.map(Squad.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name)));
  }

  Stream<List<SquadMember>> members(String squadId) =>
      db.collection('squads').doc(squadId).collection('members').snapshots().map((q) => q.docs.map(SquadMember.fromDoc).toList());

  Stream<Squad?> squad(String squadId) =>
      db.collection('squads').doc(squadId).snapshots().map((d) => d.exists ? Squad.fromDoc(d) : null);

  Future<Squad> create(String name, Profile me) async {
    final uid = user!.uid;
    final ref = db.collection('squads').doc();
    final code = await _freeCode();
    final batch = db.batch()
      ..set(ref, {'name': name, 'code': code, 'ownerUid': uid, 'memberUids': [uid], 'createdAt': FieldValue.serverTimestamp()})
      ..set(db.collection('codes').doc(code), {'squadId': ref.id})
      ..set(ref.collection('members').doc(uid), {'name': me.name, 'avatar': me.avatar});
    await batch.commit();
    await _afterChange();
    return Squad(id: ref.id, name: name, code: code, ownerUid: uid, memberUids: [uid]);
  }

  /// Joins with an invite code. Throws [SquadException] with a friendly message on problems.
  Future<Squad> join(String rawCode, Profile me) async {
    final uid = user!.uid;
    final code = rawCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final codeDoc = await db.collection('codes').doc(code).get();
    final squadId = codeDoc.data()?['squadId'] as String?;
    if (squadId == null) throw const SquadException('No squad has that code. Check it and try again.');
    final ref = db.collection('squads').doc(squadId);
    final squad = await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw const SquadException('That squad no longer exists.');
      final s = Squad.fromDoc(snap);
      if (s.memberUids.contains(uid)) return s;
      if (s.memberUids.length >= kMaxSquadSize) throw const SquadException('That squad is full ($kMaxSquadSize people).');
      tx.update(ref, {'memberUids': FieldValue.arrayUnion([uid])});
      return s;
    });
    await ref.collection('members').doc(uid).set({'name': me.name, 'avatar': me.avatar}, SetOptions(merge: true));
    await _afterChange();
    return squad;
  }

  /// Leaves a squad. The last person out deletes it; an owner leaving hands it to the next member.
  Future<void> leave(Squad s) async {
    final uid = user!.uid;
    final ref = db.collection('squads').doc(s.id);
    final others = s.memberUids.where((m) => m != uid).toList();
    await ref.collection('members').doc(uid).delete();
    if (others.isEmpty) {
      await db.collection('codes').doc(s.code).delete();
      await ref.delete();
    } else if (s.ownerUid == uid) {
      await ref.update({'memberUids': others, 'ownerUid': others.first});
    } else {
      await ref.update({'memberUids': FieldValue.arrayRemove([uid])});
    }
    await _afterChange();
  }

  /// Owner only: removes someone from the squad.
  Future<void> removeMember(Squad s, String memberUid) async {
    final ref = db.collection('squads').doc(s.id);
    await ref.update({'memberUids': FieldValue.arrayRemove([memberUid])});
    await ref.collection('members').doc(memberUid).delete();
  }

  /// Owner only: deletes the squad for everyone (all members' numbers, the invite code and the squad).
  Future<void> deleteSquad(Squad s) async {
    final ref = db.collection('squads').doc(s.id);
    final batch = db.batch();
    // One batch, so the rules still see the squad (and that we own it) while its parts are removed.
    for (final m in (await ref.collection('members').get()).docs) {
      batch.delete(m.reference);
    }
    batch.delete(db.collection('codes').doc(s.code));
    batch.delete(ref);
    await batch.commit();
    await _afterChange();
  }

  Future<void> rename(Squad s, String name) => db.collection('squads').doc(s.id).update({'name': name});

  Future<void> signOut() async {
    final uid = user?.uid;
    if (uid != null) await forgetPushToken(uid);
    await bridge.setConfigRaw({'squadIds': <String>[]});
    await auth.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- cloud backup

  /// After signing in with Google on a phone with (almost) no history, offer to restore from the cloud.
  Future<bool> shouldOfferRestore() async {
    final u = user;
    if (u == null || u.isAnonymous) return false;
    if (await bridge.localDays() >= 3) return false;
    final days = await db.collection('users').doc(u.uid).collection('days').limit(1).get();
    return days.docs.isNotEmpty;
  }

  /// Brings back day summaries and settings from the Google account. Returns how many days.
  Future<int> restoreFromCloud() async {
    final userDoc = db.collection('users').doc(user!.uid);
    final days = await userDoc.collection('days').get();
    final summaries = days.docs.map((d) => Map<String, dynamic>.of(d.data())..remove('updatedAt')).toList();
    final count = await bridge.importSummaries(jsonEncode(summaries));
    final settings = (await userDoc.collection('backup').doc('settings').get()).data()?['config'] as Map?;
    if (settings != null) {
      // Running timers and today's extras belong to the old phone's day, not this one.
      const skip = {'pausedUntil', 'hardLockedUntil', 'focusUntil', 'today', 'extraToday', 'emergencyLeft', 'earnedToday', 'stepsToday', 'activeSchedule'};
      await bridge.restoreSettings({
        for (final e in settings.entries)
          if (!skip.contains(e.key)) e.key as String: e.value,
      });
    }
    // This phone now has the backed-up settings, so its later changes may update the cloud copy.
    await bridge.settingsRestored();
    return count;
  }

  /// Deletes the online account with one tap. The nudge Worker does it with admin rights (Firebase only
  /// lets an app delete a login that signed in minutes ago, which would mean signing in again):
  /// it leaves every squad, deletes the nickname, cloud backup, push address and nudge notes, then the login.
  Future<void> deleteAccount() async {
    final idToken = await user!.getIdToken();
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('$kNudgeWorkerUrl/delete-account'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode != 200) throw const SquadException('Could not delete the account. Please try again.');
    } finally {
      client.close();
    }
    await bridge.setConfigRaw({'squadIds': <String>[]});
    // The login is gone on the server; drop it on this phone too.
    await auth.signOut();
    // The next Google sign-in shows the account picker instead of reusing the deleted account.
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  /// Tells the background counter which squads to sync, and syncs now.
  Future<void> _afterChange() async {
    final uid = user?.uid;
    if (uid == null) return;
    final squads = await db.collection('squads').where('memberUids', arrayContains: uid).get();
    await bridge.setConfigRaw({'squadIds': squads.docs.map((d) => d.id).toList()});
    await bridge.syncSquads();
  }

  /// Keeps the background counter's squad list right after sign-in or on another phone.
  Future<void> refreshSync() => _afterChange();

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O, 1/I

  Future<String> _freeCode() async {
    final rnd = Random.secure();
    for (var i = 0; i < 10; i++) {
      final code = List.generate(6, (_) => _alphabet[rnd.nextInt(_alphabet.length)]).join();
      if (!(await db.collection('codes').doc(code).get()).exists) return code;
    }
    throw const SquadException('Could not make an invite code. Try again.');
  }
}

class SquadException implements Exception {
  final String message;
  const SquadException(this.message);
  @override
  String toString() => message;
}

final squadsRepoProvider = Provider<SquadsRepo>(
  (ref) => SquadsRepo(FirebaseAuth.instance, FirebaseFirestore.instance, ref.watch(bridgeProvider)),
);

final authUserProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

final profileProvider = FutureProvider<Profile?>((ref) {
  ref.watch(authUserProvider);
  return ref.watch(squadsRepoProvider).profile();
});

final mySquadsProvider = StreamProvider<List<Squad>>((ref) {
  ref.watch(authUserProvider);
  return ref.watch(squadsRepoProvider).mySquads();
});

final squadProvider = StreamProvider.family<Squad?, String>((ref, id) => ref.watch(squadsRepoProvider).squad(id));

final squadMembersProvider =
    StreamProvider.family<List<SquadMember>, String>((ref, id) => ref.watch(squadsRepoProvider).members(id));
