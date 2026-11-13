import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../health/analytics/sleep_analytics.dart';
import 'roast.dart';
import 'shared_night.dart';

/// A cloud operation that could not complete, with a sentence fit for the page.
class CloudException implements Exception {
  const CloudException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A Strand account as another person is allowed to see it: a name and the
/// email address they searched for. Nothing else.
class CloudPerson {
  const CloudPerson({
    required this.uid,
    required this.name,
    required this.email,
  });

  final String uid;
  final String name;
  final String email;
}

class IncomingRequest {
  const IncomingRequest({
    required this.id,
    required this.from,
    required this.fromName,
    required this.fromEmail,
    required this.toName,
    required this.toEmail,
  });

  final String id;
  final String from;
  final String fromName;
  final String fromEmail;
  final String toName;
  final String toEmail;
}

class OutgoingRequest {
  const OutgoingRequest({
    required this.id,
    required this.to,
    required this.toName,
    required this.toEmail,
  });

  final String id;
  final String to;
  final String toName;
  final String toEmail;
}

class Friendship {
  const Friendship({
    required this.id,
    required this.otherUid,
    required this.otherName,
    required this.otherEmail,
    required this.createdAt,
  });

  final String id;
  final String otherUid;
  final String otherName;
  final String otherEmail;
  final DateTime createdAt;
}

/// The Firestore side of Strand: profiles, the email index, friend requests,
/// accepted friendships, and shared nights.
///
/// Authorisation is enforced by Firestore security rules, not by this class.
/// The rules in `firestore.rules` allow a night to be read only by its owner or
/// by someone with an accepted friendship document; a pending request grants
/// nothing, and deleting the friendship revokes access on the next read.
abstract final class CloudStore {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String get _requireUid {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const CloudException('Sign in to use friends.');
    return user.uid;
  }

  static String pairId(String a, String b) {
    final List<String> ids = <String>[a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  /// Writes the searchable profile. The document id is the account uid; the
  /// email index is keyed by the lower-cased address so a search is one read.
  static Future<void> ensureProfile({
    required String uid,
    required String name,
    required String email,
  }) async {
    final String lower = email.trim().toLowerCase();
    if (lower.isEmpty) return;
    final WriteBatch batch = _db.batch();
    batch.set(
      _db.collection('users').doc(uid),
      <String, dynamic>{
        'uid': uid,
        'name': name.trim(),
        'email': email.trim(),
        'emailLower': lower,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      SetOptions(merge: true),
    );
    batch.set(
      _db.collection('emailIndex').doc(lower),
      <String, dynamic>{
        'uid': uid,
        'name': name.trim(),
        'email': email.trim(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      SetOptions(merge: true),
    );
    await _guard(batch.commit);
  }

  /// Renames the signed-in account on the existing profile record and every
  /// friendship that stores this person's name, so friends see the new name
  /// without a separate migration. Returns when the cloud writes have landed.
  static Future<void> updateName({
    required String uid,
    required String name,
    required String email,
  }) async {
    final String trimmed = name.trim();
    // Profile + email index, same as ensureProfile but name-only in intent.
    await ensureProfile(uid: uid, name: trimmed, email: email);

    // Friendships store each member's name at friend time, so refresh them.
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await _db
          .collection('friendships')
          .where('members', arrayContains: uid)
          .get();
      final WriteBatch batch = _db.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
        final Map<String, dynamic> data = doc.data();
        final List<String> members = <String>[
          for (final Object? id in (data['members'] as List<Object?>? ?? <Object?>[]))
            if (id is String) id,
        ];
        if (members.length != 2) continue;
        final bool first = members[0] == uid;
        batch.update(doc.reference, <String, dynamic>{
          first ? 'nameA' : 'nameB': trimmed,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
      await _guard(batch.commit);
    } catch (_) {
      // Best-effort: the profile record is the source of truth and the
      // friendship rows can be refreshed on the next sync.
    }

    // Keep Firebase's own display name in step so other surfaces agree.
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null && user.uid == uid) {
        await user.updateDisplayName(trimmed);
      }
    } catch (_) {}
  }

  /// Finds an account by email. Returns null when no Strand account exists.
  static Future<CloudPerson?> findByEmail(String email) async {
    final String lower = email.trim().toLowerCase();
    if (lower.isEmpty) return null;
    return _guard(() async {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _db.collection('emailIndex').doc(lower).get();
      final Map<String, dynamic>? data = doc.data();
      if (!doc.exists || data == null) return null;
      final String uid = (data['uid'] as String?) ?? '';
      if (uid.isEmpty) return null;
      return CloudPerson(
        uid: uid,
        name: (data['name'] as String?) ?? '',
        email: (data['email'] as String?) ?? lower,
      );
    });
  }

  /// 'friends', 'outgoing', 'incoming', or null for no relationship.
  static Future<String?> relationshipWith(String otherUid) async {
    final String uid = _requireUid;
    return _guard(() async {
      final String id = pairId(uid, otherUid);
      final DocumentSnapshot<Map<String, dynamic>> friend =
          await _db.collection('friendships').doc(id).get();
      if (friend.exists) return 'friends';
      final DocumentSnapshot<Map<String, dynamic>> request =
          await _db.collection('friendRequests').doc(id).get();
      final Map<String, dynamic>? data = request.data();
      if (!request.exists || data == null) return null;
      if (data['status'] != 'pending') return null;
      return data['from'] == uid ? 'outgoing' : 'incoming';
    });
  }

  static Future<void> sendRequest({
    required CloudPerson target,
    required String myName,
    required String myEmail,
  }) async {
    final String uid = _requireUid;
    if (target.uid == uid) {
      throw const CloudException('You cannot add yourself.');
    }
    await _guard(() async {
      final String id = pairId(uid, target.uid);
      final DocumentReference<Map<String, dynamic>> friendRef =
          _db.collection('friendships').doc(id);
      if ((await friendRef.get()).exists) {
        throw const CloudException('You are already friends.');
      }
      final DocumentReference<Map<String, dynamic>> requestRef =
          _db.collection('friendRequests').doc(id);
      final DocumentSnapshot<Map<String, dynamic>> existing =
          await requestRef.get();
      if (existing.exists) {
        final String status = (existing.data()?['status'] as String?) ?? '';
        if (status == 'pending' || status == 'accepted') {
          throw const CloudException('A request already exists.');
        }
        // A declined request may be sent again.
        await requestRef.delete();
      }
      await requestRef.set(<String, dynamic>{
        'from': uid,
        'fromName': myName,
        'fromEmail': myEmail.trim(),
        'to': target.uid,
        'toName': target.name,
        'toEmail': target.email.trim(),
        'status': 'pending',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  static Stream<List<IncomingRequest>> incomingRequests(String uid) {
    return _db
        .collection('friendRequests')
        .where('to', isEqualTo: uid)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      final List<IncomingRequest> out = <IncomingRequest>[];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final Map<String, dynamic> data = doc.data();
        if (data['status'] != 'pending') continue;
        out.add(
          IncomingRequest(
            id: doc.id,
            from: (data['from'] as String?) ?? '',
            fromName: (data['fromName'] as String?) ?? '',
            fromEmail: (data['fromEmail'] as String?) ?? '',
            toName: (data['toName'] as String?) ?? '',
            toEmail: (data['toEmail'] as String?) ?? '',
          ),
        );
      }
      out.sort((IncomingRequest a, IncomingRequest b) =>
          a.fromName.toLowerCase().compareTo(b.fromName.toLowerCase()));
      return out;
    });
  }

  static Stream<List<OutgoingRequest>> outgoingRequests(String uid) {
    return _db
        .collection('friendRequests')
        .where('from', isEqualTo: uid)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      final List<OutgoingRequest> out = <OutgoingRequest>[];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final Map<String, dynamic> data = doc.data();
        if (data['status'] != 'pending') continue;
        out.add(
          OutgoingRequest(
            id: doc.id,
            to: (data['to'] as String?) ?? '',
            toName: (data['toName'] as String?) ?? '',
            toEmail: (data['toEmail'] as String?) ?? '',
          ),
        );
      }
      out.sort((OutgoingRequest a, OutgoingRequest b) =>
          a.toName.toLowerCase().compareTo(b.toName.toLowerCase()));
      return out;
    });
  }

  /// Accepting is done by the recipient. The friendship document is what the
  /// security rules consult, so creating it is the moment access begins.
  static Future<void> acceptRequest(
    IncomingRequest request, {
    required String myName,
    required String myEmail,
  }) async {
    final String uid = _requireUid;
    if (request.from == uid) {
      throw const CloudException('You cannot accept your own request.');
    }
    await _guard(() async {
      final List<String> members = <String>[uid, request.from]..sort();
      final Map<String, String> names = <String, String>{
        uid: myName,
        request.from: request.fromName,
      };
      final Map<String, String> emails = <String, String>{
        uid: myEmail.trim(),
        request.from: request.fromEmail.trim(),
      };
      final DocumentReference<Map<String, dynamic>> friendship = _db
          .collection('friendships')
          .doc(pairId(uid, request.from));
      final WriteBatch batch = _db.batch();
      batch.set(friendship, <String, dynamic>{
        'members': members,
        'nameA': names[members[0]],
        'nameB': names[members[1]],
        'emailA': emails[members[0]],
        'emailB': emails[members[1]],
        'requestId': request.id,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      batch.update(
        _db.collection('friendRequests').doc(request.id),
        <String, dynamic>{'status': 'accepted'},
      );
      await batch.commit();
    });
  }

  static Future<void> declineRequest(String requestId) async {
    _requireUid;
    await _guard(() async {
      await _db.collection('friendRequests').doc(requestId).update(
        <String, dynamic>{'status': 'declined'},
      );
    });
  }

  static Future<void> cancelRequest(String requestId) async {
    _requireUid;
    await _guard(() async {
      await _db.collection('friendRequests').doc(requestId).delete();
    });
  }

  /// Deleting the friendship is the whole revocation: the rules look the
  /// document up for every shared read, so access ends immediately.
  static Future<void> removeFriend(String friendshipId) async {
    _requireUid;
    await _guard(() async {
      await _db.collection('friendships').doc(friendshipId).delete();
    });
  }

  static Stream<List<Friendship>> friends(String uid) {
    return _db
        .collection('friendships')
        .where('members', arrayContains: uid)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      final List<Friendship> out = <Friendship>[];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final Map<String, dynamic> data = doc.data();
        final List<String> members = <String>[
          for (final Object? id in (data['members'] as List<Object?>? ?? <Object?>[]))
            if (id is String) id,
        ];
        if (members.length != 2) continue;
        final bool first = members[0] == uid;
        out.add(
          Friendship(
            id: doc.id,
            otherUid: first ? members[1] : members[0],
            otherName:
                ((first ? data['nameB'] : data['nameA']) as String?) ?? '',
            otherEmail:
                ((first ? data['emailB'] : data['emailA']) as String?) ?? '',
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              (data['createdAt'] as num?)?.toInt() ?? 0,
            ),
          ),
        );
      }
      out.sort((Friendship a, Friendship b) =>
          a.otherName.toLowerCase().compareTo(b.otherName.toLowerCase()));
      return out;
    });
  }

  /// Uploads the nights Strand already computed locally. Called when the app
  /// opens and whenever the person refreshes, so a friend's view follows real
  /// syncs rather than a sample.
  static Future<void> uploadNights(List<NightSummary> nights) async {
    final String uid = _requireUid;
    if (nights.isEmpty) return;
    await _guard(() async {
      final CollectionReference<Map<String, dynamic>> collection =
          _db.collection('users').doc(uid).collection('nights');
      const int chunk = 450;
      for (int start = 0; start < nights.length; start += chunk) {
        final WriteBatch batch = _db.batch();
        final int end =
            (start + chunk) < nights.length ? start + chunk : nights.length;
        for (final NightSummary night in nights.sublist(start, end)) {
          final SharedNight shared = SharedNight.fromSummary(night);
          batch.set(collection.doc(shared.dateKey), shared.toMap());
        }
        await batch.commit();
      }
    });
  }

  static Stream<List<NightSummary>> friendNights(String friendUid) {
    return _db
        .collection('users')
        .doc(friendUid)
        .collection('nights')
        .orderBy('date', descending: true)
        .limit(120)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      final List<NightSummary> out = <NightSummary>[];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        try {
          out.add(SharedNight.fromMap(doc.data()).toSummary());
        } catch (_) {
          // One malformed document must not blank the whole history.
        }
      }
      out.sort((NightSummary a, NightSummary b) => b.date.compareTo(a.date));
      return out;
    });
  }

  /// Watches the roast written for this pair. The worker is the only writer;
  /// both people read the same paragraph, so the joke cannot arrive twice in
  /// two different shapes.
  static Stream<RoastNarrative?> narrative(String friendUid) {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream<RoastNarrative?>.value(null);
    return _db
        .collection('narratives')
        .doc(pairId(user.uid, friendUid))
        .snapshots()
        .map<RoastNarrative?>((DocumentSnapshot<Map<String, dynamic>> doc) {
          final Map<String, dynamic>? data = doc.data();
          if (!doc.exists || data == null) return null;
          return RoastNarrative.fromMap(data);
        })
        .handleError((Object error, StackTrace stack) {
          // A missing narrative is a normal state, not a broken page.
        });
  }

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on CloudException {
      rethrow;
    } on FirebaseException catch (e) {
      throw CloudException(
        switch (e.code) {
          'permission-denied' =>
            'The cloud refused this action. Friendship permissions are '
                'enforced on the server.',
          'unavailable' =>
            'Strand cloud is unreachable. Check your connection and try again.',
          'not-found' => 'That account or friendship no longer exists.',
          _ => 'Strand cloud could not complete this action (${e.code}).',
        },
      );
    } catch (_) {
      throw const CloudException(
        'Strand cloud could not complete this action. Try again.',
      );
    }
  }
}
