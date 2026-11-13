import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/account.dart';
import '../../auth/auth_scope.dart';
import '../../auth/auth_service.dart';
import '../../data/storage.dart';
import '../../health/analytics/sleep_analytics.dart';
import '../../health/sleep_controller.dart';
import '../../health/sleep_repository.dart';
import '../../social/cloud_store.dart';
import '../display_name.dart';
import '../widgets/strand_wordmark.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.showBack = false});

  /// Settings is no longer a tab. When it is pushed from the Home gear it needs
  /// its own way back; when it is embedded it must not grow one.
  final bool showBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  static const Color _muted = Color(0xFF6B6B6B);
  static const Color _hairline = Color(0xFFE6E6E6);

  bool loading = true;
  bool connecting = false;
  String healthStatus = 'Checking...';
  String? healthMessage;
  String? syncNote;

  // Profile editing.
  bool _editingName = false;
  final TextEditingController _nameController = TextEditingController();
  String? _nameError;
  bool _savingName = false;
  bool _nameSaved = false;
  Timer? _savedTimer;

  // Friends.
  final TextEditingController _friendEmail = TextEditingController();
  bool _searchingFriend = false;
  CloudPerson? _friendResult;
  String? _friendMessage;
  String? _friendError;
  bool _actingFriend = false;
  String? _removingFriendId;

  bool _uploaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // SleepScope is an InheritedNotifier, and looking it up creates a
    // dependency, which Flutter forbids during initState. Waiting for the first
    // frame keeps the lookup where it is legal. Without this the lookup threw,
    // `loading` never cleared, and Settings showed a blank white page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshHealthStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _friendEmail.dispose();
    _savedTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_uploaded) return;
    _uploaded = true;
    _uploadNights();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The permission sheet and Health Connect's own app both leave the app.
    // Coming back is the moment the answer may have changed, so re-ask
    // rather than leaving a status that was true before the person left.
    if (state == AppLifecycleState.resumed && !loading && !connecting) {
      _refreshHealthStatus();
    }
  }

  Future<void> _uploadNights() async {
    final StrandAuth auth = AuthScope.of(context);
    final SleepController? sleep = SleepScope.maybeOf(context);
    if (!auth.isConfigured || !auth.signedIn || sleep == null) return;
    try {
      await CloudStore.uploadNights(
        SleepAnalytics.canonicalNights(sleep.records),
      );
    } catch (_) {}
  }

  Future<void> _refreshHealthStatus() async {
    final SleepController? sleep = SleepScope.maybeOf(context);
    if (sleep == null) {
      if (!mounted) return;
      setState(() {
        loading = false;
        healthStatus = 'Unavailable';
      });
      return;
    }
    // Settings is the connection flow, so asking the device here is exactly the
    // explicit moment health access is allowed to be initialised.
    await sleep.checkAvailability();
    if (!mounted) return;
    setState(() {
      loading = false;
      healthStatus = _statusText(sleep.status);
      healthMessage = sleep.message;
    });
  }

  String _statusText(SleepStatus status) {
    return switch (status) {
      SleepStatus.checking => 'Checking...',
      SleepStatus.unsupported => 'Not supported on this device',
      SleepStatus.notInstalled => 'Health Connect not installed',
      SleepStatus.needsPermission => 'Permission required',
      SleepStatus.refused => 'Permission denied',
      SleepStatus.failed => 'Could not read sleep',
      SleepStatus.readyNoData => 'Connected - no sleep records',
      SleepStatus.readyWithData => 'Connected',
      SleepStatus.syncing => 'Reading sleep...',
    };
  }

  bool get _connected =>
      healthStatus == 'Connected' ||
      healthStatus == 'Connected - no sleep records';

  Future<void> _connectHealth() async {
    final SleepController? sleep = SleepScope.maybeOf(context);
    if (sleep == null || connecting) return;

    setState(() {
      connecting = true;
      healthMessage = null;
      syncNote = null;
    });

    try {
      // Ask the device first, so a source that is missing or unavailable is
      // reported as itself rather than as a silent no-op.
      await sleep.checkAvailability();

      switch (sleep.status) {
        case SleepStatus.notInstalled:
          // Health Connect is a separate app on this phone. Send the person to
          // its store page rather than leaving a dead button.
          await sleep.installSource();
        case SleepStatus.needsPermission:
        case SleepStatus.refused:
          // The real Android permission sheet, through the host activity's
          // Health Connect contract. It returns when the person has answered.
          final report = await sleep.requestAccess();
          syncNote = _note(report);
        case SleepStatus.readyNoData:
        case SleepStatus.readyWithData:
          final report = await sleep.sync();
          syncNote = _note(report);
        case SleepStatus.failed:
          final report = await sleep.retry();
          syncNote = _note(report);
        case SleepStatus.unsupported:
        case SleepStatus.checking:
        case SleepStatus.syncing:
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          connecting = false;
          healthStatus = _statusText(sleep.status);
          healthMessage = sleep.message;
        });
      }
    }
  }

  /// Turns a sync result into a sentence, so tapping SYNC SLEEP DATA always
  /// says what it did. A button that reads the device and then looks unchanged
  /// is indistinguishable from one that did nothing.
  String? _note(SleepSyncReport? report) {
    if (report == null) return null;
    return switch (report.outcome) {
      SleepSyncOutcome.added =>
        report.added == 1 ? 'Added 1 night.' : 'Added ${report.added} nights.',
      SleepSyncOutcome.updated =>
        report.updated == 1
            ? 'Updated 1 night.'
            : 'Updated ${report.updated} nights.',
      SleepSyncOutcome.nothingNew => 'Sleep is up to date.',
      SleepSyncOutcome.noData => 'No sleep records found yet.',
      SleepSyncOutcome.notPermitted => 'Health permission was not granted.',
      SleepSyncOutcome.unavailable =>
        'Health Connect is not available on this phone.',
      SleepSyncOutcome.failed => 'The sleep read failed.',
    };
  }

  String get _connectLabel {
    if (connecting) return 'CONNECTING...';
    if (healthStatus.startsWith('Health Connect not installed')) {
      return 'INSTALL HEALTH CONNECT';
    }
    if (_connected) return 'SYNC SLEEP DATA';
    if (healthStatus == 'Permission denied' ||
        healthStatus == 'Could not read sleep') {
      return 'TRY AGAIN';
    }
    return 'CONNECT HEALTH CONNECT';
  }

  Future<void> _signOut(StrandAuth auth) async {
    await auth.signOut();
    // Onboarding is a device-level flag, not part of the sleep archive. Clearing
    // it returns the app to its opening flow; the nights themselves are untouched.
    await Storage.setOnboarded(false);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/intro', (_) => false);
  }

  Future<void> _delete() async {
    final StrandAuth? auth = AuthScope.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'This will permanently delete all data stored on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await auth?.signOut();
    await Storage.clearAllData();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/intro', (_) => false);
  }

  // ---------- Profile ----------

  void _startEditingName(Account account) {
    _nameController.text = account.name;
    setState(() {
      _editingName = true;
      _nameError = null;
      _nameSaved = false;
    });
  }

  void _cancelEditingName() {
    setState(() {
      _editingName = false;
      _nameError = null;
      _nameController.clear();
    });
  }

  Future<void> _saveName(StrandAuth auth, Account account) async {
    final String value = _nameController.text.trim();
    if (value.isEmpty || value.length > 40) {
      setState(() => _nameError = 'Enter a name between 1 and 40 characters.');
      return;
    }
    setState(() {
      _savingName = true;
      _nameError = null;
    });
    try {
      await CloudStore.updateName(
        uid: account.uid,
        name: value,
        email: account.email,
      );
      // Local state immediately.
      await auth.updateAccountName(value);
      if (!mounted) return;
      setState(() {
        _editingName = false;
        _nameSaved = true;
      });
      _savedTimer?.cancel();
      _savedTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _nameSaved = false);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _nameError = 'Couldn\'t save your name. Try again.');
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  // ---------- Friends ----------

  Future<void> _runFriendSearch(StrandAuth auth) async {
    if (!auth.isConfigured) return;
    setState(() {
      _searchingFriend = true;
      _friendResult = null;
      _friendMessage = null;
      _friendError = null;
    });
    try {
      final CloudPerson? person = await CloudStore.findByEmail(
        _friendEmail.text.trim(),
      );
      if (person == null) {
        _friendMessage = 'No one found with that email.';
      } else {
        _friendResult = person;
      }
    } on CloudException catch (e) {
      _friendError = e.message;
    } catch (_) {
      _friendError = 'Search failed. Try again.';
    } finally {
      if (mounted) setState(() => _searchingFriend = false);
    }
  }

  Future<void> _sendFriendRequest(StrandAuth auth, CloudPerson person) async {
    setState(() => _actingFriend = true);
    try {
      await CloudStore.sendRequest(
        target: person,
        myName: auth.account?.name ?? '',
        myEmail: auth.account?.email ?? '',
      );
      if (mounted) {
        setState(() {
          _friendResult = null;
          _friendMessage = 'Request sent to ${displayName(person.name)}.';
          _friendEmail.clear();
        });
      }
    } on CloudException catch (e) {
      if (mounted) setState(() => _friendError = e.message);
    } catch (_) {
      if (mounted) setState(() => _friendError = 'Could not send the request.');
    } finally {
      if (mounted) setState(() => _actingFriend = false);
    }
  }

  Future<void> _confirmRemoveFriend(Friendship f) async {
    setState(() => _removingFriendId = f.id);
  }

  Future<void> _removeFriend(Friendship f) async {
    try {
      await CloudStore.removeFriend(f.id);
    } on CloudException catch (e) {
      if (mounted) setState(() => _friendError = e.message);
    } catch (_) {}
    if (mounted) setState(() => _removingFriendId = null);
  }

  String _lastSyncedText(DateTime moment) {
    final DateTime now = DateTime.now();
    final bool sameDay =
        moment.year == now.year &&
        moment.month == now.month &&
        moment.day == now.day;
    final String clock =
        '${moment.hour % 12 == 0 ? 12 : moment.hour % 12}:${moment.minute.toString().padLeft(2, '0')} ${moment.hour < 12 ? 'AM' : 'PM'}';
    if (sameDay) return 'Last synced today, $clock';
    return 'Last synced ${moment.day}/${moment.month}, $clock';
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: Colors.black,
      ),
    );
  }

  Widget _divider() => Container(height: 1, color: _hairline);

  Widget _avatar(String name, double size, {Color bg = Colors.black}) {
    final String initial = name.trim().isEmpty
        ? '?'
        : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final StrandAuth auth = AuthScope.of(context);
    final Account? account = auth.account;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: true,
        bottom: false,
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 1.4),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  16,
                  24,
                  100 + MediaQuery.of(context).padding.bottom,
                ),
                children: <Widget>[
                  if (widget.showBack) ...<Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.arrow_back,
                          size: 20,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  const Text(
                    'Settings',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // A. Profile
                  _sectionTitle('Profile'),
                  const SizedBox(height: 12),
                  _profileBlock(auth, account),
                  const SizedBox(height: 32),
                  _divider(),
                  const SizedBox(height: 32),

                  // B. Friends
                  Row(
                    children: <Widget>[
                      _sectionTitle('Friends'),
                      const SizedBox(width: 8),
                      if (account != null)
                        StreamBuilder<List<Friendship>>(
                          stream: CloudStore.friends(account.uid),
                          builder:
                              (
                                BuildContext context,
                                AsyncSnapshot<List<Friendship>> snap,
                              ) {
                                final int n = snap.data?.length ?? 0;
                                return Text(
                                  n == 1 ? '1 friend' : '$n friends',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _muted,
                                  ),
                                );
                              },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _friendsBlock(auth, account),
                  const SizedBox(height: 32),
                  _divider(),
                  const SizedBox(height: 32),

                  // C. Health Connect
                  Row(
                    children: <Widget>[
                      _sectionTitle('Health Connect'),
                      const Spacer(),
                      _statusIndicator(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _healthBlock(),
                  const SizedBox(height: 32),
                  _divider(),
                  const SizedBox(height: 32),

                  // D. Privacy and data
                  _privacyRow(),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF9C2E2E),
                        side: const BorderSide(color: _hairline),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      onPressed: _delete,
                      child: const Text(
                        'DELETE ALL DATA',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          letterSpacing: 1.6,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _divider(),
                  const SizedBox(height: 32),

                  // E. About
                  _sectionTitle('About'),
                  const SizedBox(height: 12),
                  _aboutBlock(),
                  const SizedBox(height: 32),
                  _divider(),
                  const SizedBox(height: 32),

                  // F. Sign out
                  _signOutBlock(auth, account),
                ],
              ),
      ),
    );
  }

  // ---------- Profile block ----------

  Widget _profileBlock(StrandAuth auth, Account? account) {
    if (account == null) {
      return Text('Not signed in', style: tBody(15));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _avatar(displayName(account.name), 56),
            const SizedBox(width: 14),
            Expanded(
              child: _editingName
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        TextField(
                          controller: _nameController,
                          autofocus: true,
                          maxLength: 40,
                          onChanged: (_) {
                            if (_nameError != null) {
                              setState(() => _nameError = null);
                            }
                          },
                          decoration: const InputDecoration(
                            isDense: true,
                            counterText: '',
                            border: UnderlineInputBorder(),
                          ),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                        if (_nameError != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            _nameError!,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF9C2E2E),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            SizedBox(
                              height: 36,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                                onPressed: _savingName
                                    ? null
                                    : () => _saveName(auth, account),
                                child: _savingName
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.6,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Text(
                                        'Save',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1.4,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 36,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.black,
                                  side: const BorderSide(color: _hairline),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                                onPressed: _savingName
                                    ? null
                                    : _cancelEditingName,
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                displayName(account.name),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black,
                                side: const BorderSide(color: _hairline),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _startEditingName(account),
                              child: const Text(
                                'Edit name',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          account.email,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _muted,
                          ),
                        ),
                        if (_nameSaved) ...<Widget>[
                          const SizedBox(height: 6),
                          const Text(
                            'Saved',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF176B4D),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- Friends block ----------

  Widget _friendsBlock(StrandAuth auth, Account? account) {
    if (!auth.isConfigured) {
      return Text('Friends need a configured Strand cloud.', style: tBody(13));
    }
    if (!auth.signedIn || account == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Sign in to find people and share nights.', style: tBody(13)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LoginScreen(returnOnSuccess: true),
              ),
            ),
            child: const Text(
              'SIGN IN',
              style: TextStyle(
                letterSpacing: 2,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }
    final String uid = account.uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Add friend input row.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _friendEmail,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  if (!_searchingFriend && !_actingFriend) {
                    _runFriendSearch(auth);
                  }
                },
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Add a friend by email',
                  border: UnderlineInputBorder(),
                  contentPadding: EdgeInsets.only(bottom: 8),
                ),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Search for friend',
              child: SizedBox(
                width: 48,
                height: 48,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black,
                    padding: EdgeInsets.zero,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  onPressed: (_searchingFriend || _actingFriend)
                      ? null
                      : () => _runFriendSearch(auth),
                  child: _searchingFriend
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.search, size: 20, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        if (_friendError != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _friendError!,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9C2E2E),
            ),
          ),
        ],
        if (_friendMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_friendMessage!, style: tBody(12)),
        ],
        if (_friendResult != null) ...<Widget>[
          const SizedBox(height: 12),
          _friendResultRow(auth, _friendResult!),
        ],
        const SizedBox(height: 16),
        StreamBuilder<List<Friendship>>(
          stream: CloudStore.friends(uid),
          builder:
              (BuildContext context, AsyncSnapshot<List<Friendship>> snapshot) {
                final List<Friendship> items =
                    snapshot.data ?? const <Friendship>[];
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'No friends yet. Add someone by email to start sharing sleep.',
                      style: tBody(13),
                    ),
                  );
                }
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: _hairline),
                  ),
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < items.length; i++) ...<Widget>[
                        if (i > 0) Container(height: 1, color: _hairline),
                        _friendRow(items[i]),
                      ],
                    ],
                  ),
                );
              },
        ),
        // Incoming / outgoing requests, kept minimal.
        StreamBuilder<List<IncomingRequest>>(
          stream: CloudStore.incomingRequests(uid),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<IncomingRequest>> snapshot,
              ) {
                final List<IncomingRequest> items =
                    snapshot.data ?? const <IncomingRequest>[];
                if (items.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(height: 16),
                    Text(
                      'Requests received',
                      style: tBody(12, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    for (final IncomingRequest r in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    displayName(r.fromName),
                                    style: tBody(14, weight: FontWeight.w500),
                                  ),
                                  Text(r.fromEmail, style: tBody(12)),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 36,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                                onPressed: _actingFriend
                                    ? null
                                    : () async {
                                        setState(() => _actingFriend = true);
                                        try {
                                          await CloudStore.acceptRequest(
                                            r,
                                            myName: auth.account?.name ?? '',
                                            myEmail: auth.account?.email ?? '',
                                          );
                                        } on CloudException catch (e) {
                                          if (mounted) {
                                            setState(
                                              () => _friendError = e.message,
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(
                                              () => _actingFriend = false,
                                            );
                                          }
                                        }
                                      },
                                child: const Text(
                                  'Accept',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              height: 36,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.black,
                                  side: const BorderSide(color: _hairline),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                                onPressed: _actingFriend
                                    ? null
                                    : () async {
                                        setState(() => _actingFriend = true);
                                        try {
                                          await CloudStore.declineRequest(r.id);
                                        } finally {
                                          if (mounted) {
                                            setState(
                                              () => _actingFriend = false,
                                            );
                                          }
                                        }
                                      },
                                child: const Text(
                                  'Decline',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
        ),
      ],
    );
  }

  Widget _friendResultRow(StrandAuth auth, CloudPerson person) {
    return FutureBuilder<String?>(
      future: CloudStore.relationshipWith(person.uid),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        final String? rel = snapshot.data;
        final bool isSelf = person.uid == auth.account?.uid;
        String label = 'ADD';
        VoidCallback? action;
        if (isSelf) {
          label = 'THAT\'S YOU';
        } else if (rel == 'friends') {
          label = 'FRIENDS';
        } else if (rel == 'outgoing') {
          label = 'REQUESTED';
        } else if (rel == 'incoming') {
          label = 'THEY REQUESTED YOU';
        } else {
          label = 'ADD';
          action = _actingFriend
              ? null
              : () => _sendFriendRequest(auth, person);
        }
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: _hairline)),
          child: Row(
            children: <Widget>[
              _avatar(person.name, 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      displayName(person.name),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    Text(person.email, style: tBody(12)),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black,
                    disabledForegroundColor: Colors.white70,
                    disabledBackgroundColor: Colors.black45,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  onPressed: action,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _friendRow(Friendship f) {
    final bool removing = _removingFriendId == f.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: removing
          ? Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Remove ${displayName(f.otherName)}?',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF9C2E2E),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    onPressed: () => _removeFriend(f),
                    child: const Text(
                      'Remove',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: _hairline),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    onPressed: () => setState(() => _removingFriendId = null),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: <Widget>[
                _avatar(f.otherName, 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        displayName(f.otherName),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(f.otherEmail, style: tBody(13)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    tooltip: 'Remove ${displayName(f.otherName)}',
                    padding: EdgeInsets.zero,
                    onPressed: () => _confirmRemoveFriend(f),
                    icon: const Icon(
                      Icons.more_vert,
                      size: 20,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statusIndicator() {
    final bool connected = _connected;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: connected ? const Color(0xFF1D9E75) : _muted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          connected ? 'Connected' : 'Not connected',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: connected ? const Color(0xFF176B4D) : _muted,
          ),
        ),
      ],
    );
  }

  // ---------- Health Connect block ----------

  Widget _healthBlock() {
    final SleepController? sleep = SleepScope.maybeOf(context);
    final DateTime? last = sleep?.lastSync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (last != null) ...<Widget>[
          Text(_lastSyncedText(last), style: tBody(13)),
          const SizedBox(height: 12),
        ],
        if (healthMessage != null) ...<Widget>[
          Text(healthMessage!, style: tBody(12)),
          const SizedBox(height: 8),
        ],
        if (syncNote != null) ...<Widget>[
          Text(syncNote!, style: tBody(12)),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.black,
              disabledForegroundColor: Colors.white,
              disabledBackgroundColor: Colors.black45,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            onPressed: connecting ? null : _connectHealth,
            child: connecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    _connectLabel,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      letterSpacing: 1.6,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () async {
              final SleepController? s = SleepScope.maybeOf(context);
              await s?.openSourceApp();
            },
            child: Text(
              'Open Health Connect',
              style: tBody(
                12,
                weight: FontWeight.w600,
              ).copyWith(color: Colors.black),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Strand only reads your sleep sessions and stages. It never writes to or changes your health records.',
          style: tBody(12),
        ),
      ],
    );
  }

  // ---------- Privacy row ----------

  Widget _privacyRow() {
    return InkWell(
      onTap: () {},
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Privacy and data',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Control what you share and your stored data',
                  style: tBody(13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 20, color: _muted),
        ],
      ),
    );
  }

  Widget _aboutBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const StrandWordmark(size: 20),
        const SizedBox(height: 6),
        Text('Version 1.0.0', style: tBody(13)),
        const SizedBox(height: 12),
        // Delete all data (existing action) surfaced here under privacy? keep under privacy row instead.
      ],
    );
  }

  Widget _signOutBlock(StrandAuth auth, Account? account) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          side: const BorderSide(color: _hairline),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: auth.busy
            ? null
            : account == null
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LoginScreen(returnOnSuccess: true),
                ),
              )
            : () => _signOut(auth),
        child: auth.busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            : Text(
                account == null ? 'SIGN IN' : 'SIGN OUT',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  letterSpacing: 2,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  // ---------- helpers ----------

  TextStyle tBody(double size, {FontWeight weight = FontWeight.w500}) {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      color: _muted,
      height: 1.4,
    );
  }
}
