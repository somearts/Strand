import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';
import '../../auth/auth_service.dart';
import '../../health/analytics/sleep_analytics.dart';
import '../../health/sleep_controller.dart';
import '../../social/cloud_store.dart';
import '../../ui/friend_selection.dart';
import '../../ui/display_name.dart';
import '../../ui/widgets/insights_view.dart';
import '../../ui/widgets/page_header.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  String? _selectedFriendUid;
  String? _selectedFriendName;

  @override
  void initState() {
    super.initState();
    selectedFriendInsights.addListener(_onSharedChanged);
  }

  void _onSharedChanged() {
    final dynamic f = selectedFriendInsights.value;
    final String? uid = f == null ? null : (f.otherUid as String?);
    final String? name = f == null ? null : (f.otherName as String?);
    if (mounted && (_selectedFriendUid != uid || _selectedFriendName != name)) {
      setState(() {
        _selectedFriendUid = uid;
        _selectedFriendName = name;
      });
    }
  }

  @override
  void dispose() {
    selectedFriendInsights.removeListener(_onSharedChanged);
    super.dispose();
  }

  void _selectFriend(dynamic f) {
    selectedFriendInsights.value = f;
  }

  Future<void> _showAddFriend(BuildContext context, StrandAuth auth) async {
    final TextEditingController ctrl = TextEditingController();
    CloudPerson? result;
    String? message;
    bool searching = false;
    bool sending = false;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSt) {
            return AlertDialog(
              title: const Text('Add friend'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Email address'), keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 8),
                  if (message != null) Text(message!, style: const TextStyle(fontSize: 12)),
                  if (result != null) Text(displayName(result!.name), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                TextButton(
                  onPressed: searching ? null : () async {
                    setSt(() => searching = true);
                    try {
                      final CloudPerson? p = await CloudStore.findByEmail(ctrl.text.trim());
                      if (p == null) {
                        setSt(() => message = 'No account found.');
                      } else {
                        setSt(() {
                          result = p;
                          message = null;
                        });
                      }
                    } catch (_) {
                      setSt(() => message = 'Search failed.');
                    } finally {
                      setSt(() => searching = false);
                    }
                  },
                  child: const Text('Search'),
                ),
                if (result != null)
                  TextButton(
                    onPressed: sending ? null : () async {
                      setSt(() => sending = true);
                      try {
                        await CloudStore.sendRequest(target: result!, myName: auth.account?.name ?? '', myEmail: auth.account?.email ?? '');
                        setSt(() {
                          message = 'Request sent.';
                          result = null;
                        });
                        ctrl.clear();
                      } catch (e) {
                        setSt(() => message = e.toString());
                      } finally {
                        setSt(() => sending = false);
                      }
                    },
                    child: const Text('Send request'),
                  ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SleepController sleep = SleepScope.of(context);
    final StrandAuth auth = AuthScope.of(context);
    final String uid = auth.account?.uid ?? '';
    final List<NightSummary> ownNights = SleepAnalytics.canonicalNights(sleep.records);

    final bool showFriends = auth.isConfigured && auth.signedIn && uid.isNotEmpty;

    Widget friendsRow = const SizedBox.shrink();
    if (showFriends) {
      friendsRow = StreamBuilder<List<Friendship>>(
        stream: CloudStore.friends(uid),
        builder: (BuildContext context, AsyncSnapshot<List<Friendship>> snapshot) {
          final List<Friendship> friends = snapshot.data ?? const <Friendship>[];
          return Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 12),
            child: SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: friends.length + 2,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int i) {
                  if (i == 0) {
                    final bool selected = _selectedFriendUid == null;
                    return GestureDetector(
                      onTap: () => _selectFriend(null),
                      child: Column(
                        children: <Widget>[
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected ? Colors.black : Colors.transparent,
                              border: Border.all(color: Colors.black, width: 1.2),
                            ),
                            child: Center(
                              child: Text('Me', style: TextStyle(color: selected ? Colors.white : Colors.black, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (i == friends.length + 1) {
                    return GestureDetector(
                      onTap: () => _showAddFriend(context, auth),
                      child: Column(
                        children: <Widget>[
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 1.2),
                            ),
                            child: const Icon(Icons.add, color: Colors.black, size: 22),
                          ),
                          const SizedBox(height: 4),
                          const Text('Add', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    );
                  }
                  final Friendship f = friends[i - 1];
                  final bool selected = _selectedFriendUid == f.otherUid;
                  return GestureDetector(
                    onTap: () => _selectFriend(f),
                    child: Column(
                      children: <Widget>[
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? Colors.black : const Color(0xFFE6E6E6),
                            border: Border.all(color: Colors.black, width: 1.2),
                          ),
                          child: Center(
                            child: Text(f.otherName.isEmpty ? '?' : f.otherName[0].toUpperCase(), style: TextStyle(color: selected ? Colors.white : Colors.black, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(width: 52, child: Text(displayName(f.otherName), style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: <Widget>[
            const PageHeader(showGreeting: false),
            friendsRow,
            Expanded(
              child: _selectedFriendUid == null
                  ? InsightsView(
                      key: const ValueKey('me'),
                      nights: ownNights,
                      ownerName: 'You',
                      showStatusCard: true,
                      sleepController: sleep,
                    )
                  : StreamBuilder<List<NightSummary>>(
                      stream: CloudStore.friendNights(_selectedFriendUid!),
                      builder: (BuildContext context, AsyncSnapshot<List<NightSummary>> snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting && (snapshot.data == null || snapshot.data!.isEmpty)) {
                          return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.6)));
                        }
                        final List<NightSummary> nights = snapshot.data ?? const <NightSummary>[];
                        return InsightsView(
                          key: ValueKey(_selectedFriendUid),
                          nights: nights,
                          ownerName: displayName(_selectedFriendName ?? '') == ''
                              ? 'Friend'
                              : displayName(_selectedFriendName!),
                          showStatusCard: false,
                          sleepController: null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
