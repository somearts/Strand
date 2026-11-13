import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';
import '../../auth/auth_service.dart';
import '../../health/analytics/sleep_analytics.dart';
import '../../health/sleep_controller.dart';
import '../../social/cloud_store.dart';
import '../display_name.dart';
import '../widgets/auth_form.dart';
import '../screens/login_screen.dart';

/// Friends management, embeddable in Settings.
class FriendsSection extends StatefulWidget {
  const FriendsSection({super.key});

  @override
  State<FriendsSection> createState() => _FriendsSectionState();
}

class _FriendsSectionState extends State<FriendsSection> {
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  bool _acting = false;
  CloudPerson? _result;
  String? _searchMessage;
  String? _searchError;
  bool _uploaded = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_uploaded) return;
    _uploaded = true;
    _uploadNights();
  }

  Future<void> _uploadNights() async {
    final StrandAuth auth = AuthScope.of(context);
    final SleepController? sleep = SleepScope.maybeOf(context);
    if (!auth.isConfigured || !auth.signedIn || sleep == null) return;
    try {
      await CloudStore.uploadNights(SleepAnalytics.canonicalNights(sleep.records));
    } catch (_) {}
  }

  Future<void> _runSearch() async {
    final StrandAuth auth = AuthScope.of(context);
    if (!auth.isConfigured) return;
    setState(() {
      _searching = true;
      _result = null;
      _searchMessage = null;
      _searchError = null;
    });
    try {
      final CloudPerson? person = await CloudStore.findByEmail(_search.text.trim());
      if (person == null) {
        _searchMessage = 'No Strand account found for that email address.';
      } else {
        _result = person;
      }
    } on CloudException catch (e) {
      _searchError = e.message;
    } catch (_) {
      _searchError = 'Search failed. Try again.';
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(StrandAuth auth, CloudPerson person) async {
    setState(() => _acting = true);
    try {
      await CloudStore.sendRequest(target: person, myName: auth.account?.name ?? '', myEmail: auth.account?.email ?? '');
      if (mounted) {
        setState(() {
          _result = null;
          _searchMessage = 'Request sent to ${displayName(person.name)}.';
          _search.clear();
        });
      }
    } on CloudException catch (e) {
      if (mounted) setState(() => _searchError = e.message);
    } catch (_) {
      if (mounted) setState(() => _searchError = 'Could not send the request.');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final StrandAuth auth = AuthScope.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final String? uid = auth.account?.uid;

    if (!auth.isConfigured) {
      return Padding(padding: const EdgeInsets.all(16), child: Text('Friends need a configured Strand cloud.', style: t.bodySmall));
    }
    if (!auth.signedIn) {
      return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Sign in to find people and share nights.', style: t.bodySmall),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen(returnOnSuccess: true))), child: const Text('SIGN IN', style: TextStyle(letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w600))),
      ]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(padding: const EdgeInsets.fromLTRB(0, 8, 0, 8), child: Text('FIND BY EMAIL', style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5))),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
          Expanded(child: AuthField(controller: _search, label: '', keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.search, onSubmitted: (_) { if (!_searching && !_acting) _runSearch(); })),
          const SizedBox(width: 12),
          SizedBox(height: 40, child: TextButton(style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 16), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)), onPressed: (_searching || _acting) ? null : _runSearch, child: _searching ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))) : const Text('SEARCH', style: TextStyle(letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w600)))),
        ]),
        if (_searchError != null) ...<Widget>[const SizedBox(height: 10), AuthErrorText(message: _searchError!)],
        if (_searchMessage != null) ...<Widget>[const SizedBox(height: 10), Text(_searchMessage!, style: t.bodySmall)],
        if (_result != null) ...<Widget>[const SizedBox(height: 14), _resultCard(auth, _result!, t)],
        const SizedBox(height: 16),
        if (uid != null) ...<Widget>[
          _incoming(uid, t),
          _outgoing(uid, t),
          _friends(uid, t),
        ],
      ],
    );
  }

  Widget _resultCard(StrandAuth auth, CloudPerson person, TextTheme t) {
    return FutureBuilder<String?>(
      future: CloudStore.relationshipWith(person.uid),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        final String? rel = snapshot.data;
        final bool isSelf = person.uid == auth.account?.uid;
        String label;
        VoidCallback? action;
        if (isSelf) { label = 'THAT\'S YOU'; }
        else if (rel == 'friends') { label = 'ALREADY FRIENDS'; }
        else if (rel == 'outgoing') { label = 'REQUEST SENT'; }
        else if (rel == 'incoming') { label = 'THEY REQUESTED YOU'; }
        else { label = 'ADD FRIEND'; action = _acting ? null : () => _sendRequest(auth, person); }
        return Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE6E6E6))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(displayName(person.name), style: t.bodyLarge),
          const SizedBox(height: 2),
          Text(person.email, style: t.bodySmall),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 44, child: TextButton(style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.black, disabledForegroundColor: Colors.white70, disabledBackgroundColor: Colors.black45, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)), onPressed: action, child: Text(label, style: const TextStyle(letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w600)))),
        ]));
      },
    );
  }

  Widget _incoming(String uid, TextTheme t) {
    return StreamBuilder<List<IncomingRequest>>(
      stream: CloudStore.incomingRequests(uid),
      builder: (BuildContext context, AsyncSnapshot<List<IncomingRequest>> snapshot) {
        final List<IncomingRequest> items = snapshot.data ?? const <IncomingRequest>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('REQUESTS RECEIVED', style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5)),
          const SizedBox(height: 10),
          for (final IncomingRequest r in items)
            Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE6E6E6))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(displayName(r.fromName), style: t.bodyLarge),
              const SizedBox(height: 2),
              Text(r.fromEmail, style: t.bodySmall),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Expanded(child: SizedBox(height: 42, child: TextButton(style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.black, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)), onPressed: _acting ? null : () async {
                  setState(() => _acting = true);
                  try {
                    final StrandAuth auth = AuthScope.of(context);
                    await CloudStore.acceptRequest(r, myName: auth.account?.name ?? '', myEmail: auth.account?.email ?? '');
                  } on CloudException catch (e) { if (mounted) setState(() => _searchError = e.message); } finally { if (mounted) setState(() => _acting = false); }
                }, child: const Text('ACCEPT', style: TextStyle(letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w600))))),
                const SizedBox(width: 10),
                Expanded(child: SizedBox(height: 42, child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Colors.black, side: const BorderSide(color: Color(0xFFE6E6E6)), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)), onPressed: _acting ? null : () async {
                  setState(() => _acting = true);
                  try { await CloudStore.declineRequest(r.id); } finally { if (mounted) setState(() => _acting = false); }
                }, child: const Text('DECLINE', style: TextStyle(letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w600))))),
              ]),
            ])),
        ]);
      },
    );
  }

  Widget _outgoing(String uid, TextTheme t) {
    return StreamBuilder<List<OutgoingRequest>>(
      stream: CloudStore.outgoingRequests(uid),
      builder: (BuildContext context, AsyncSnapshot<List<OutgoingRequest>> snapshot) {
        final List<OutgoingRequest> items = snapshot.data ?? const <OutgoingRequest>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('REQUESTS SENT', style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5)),
          const SizedBox(height: 10),
          for (final OutgoingRequest r in items)
            Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE6E6E6))), child: Row(children: <Widget>[
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(displayName(r.toName), style: t.bodyLarge), const SizedBox(height: 2), Text(r.toEmail, style: t.bodySmall)])),
              TextButton(style: TextButton.styleFrom(foregroundColor: Colors.black54, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), onPressed: _acting ? null : () async {
                setState(() => _acting = true);
                try { await CloudStore.cancelRequest(r.id); } finally { if (mounted) setState(() => _acting = false); }
              }, child: const Text('CANCEL', style: TextStyle(letterSpacing: 2, fontSize: 10, fontWeight: FontWeight.w600))),
            ])),
        ]);
      },
    );
  }

  Widget _friends(String uid, TextTheme t) {
    return StreamBuilder<List<Friendship>>(
      stream: CloudStore.friends(uid),
      builder: (BuildContext context, AsyncSnapshot<List<Friendship>> snapshot) {
        final List<Friendship> items = snapshot.data ?? const <Friendship>[];
        if (items.isEmpty) return Padding(padding: const EdgeInsets.only(top: 8), child: Text('No friends yet.', style: t.bodySmall));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('FRIENDS', style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5)),
          const SizedBox(height: 10),
          for (final Friendship f in items)
            Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE6E6E6))), child: Row(children: <Widget>[
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(displayName(f.otherName), style: t.bodyLarge), const SizedBox(height: 2), Text(f.otherEmail, style: t.bodySmall)])),
              TextButton(style: TextButton.styleFrom(foregroundColor: Colors.black54, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), onPressed: () async {
                final bool? ok = await showDialog<bool>(context: context, builder: (BuildContext ctx) => AlertDialog(title: const Text('Remove friend?'), content: Text('You will no longer see ${displayName(f.otherName)}\'s sleep data.'), actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove'))]));
                if (ok != true) return;
                try { await CloudStore.removeFriend(f.id); } on CloudException catch (e) { if (mounted) setState(() => _searchError = e.message); }
              }, child: const Text('REMOVE', style: TextStyle(letterSpacing: 2, fontSize: 10, fontWeight: FontWeight.w600))),
            ])),
        ]);
      },
    );
  }
}
