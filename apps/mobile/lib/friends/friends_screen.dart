import 'dart:async';

import 'package:flutter/material.dart';

import '../sync/sync_service.dart';
import 'friend_models.dart';

/// Search for other riders, respond to incoming friend requests, and see
/// (or remove) your current friends. Feeds the "Friends" tab on
/// leaderboard/leaderboard_screen.dart — reusing get_friends_leaderboard()
/// there needs an actual friends list to be worth anything, which is what
/// this screen builds up. Sign-in only, same as the rest of the social
/// features (see supabase/friends.sql) — there's no cross-device concept
/// of "friends" for a local guest.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<RiderSummary> _searchResults = [];
  bool _searching = false;

  List<PendingFriendRequest> _pending = [];
  List<RiderSummary> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final pending = await SyncService.instance.fetchPendingFriendRequests();
    final friends = await SyncService.instance.fetchFriends();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _friends = friends;
      _loading = false;
    });
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      final results = await SyncService.instance.searchRiders(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    });
  }

  Future<void> _sendRequest(RiderSummary rider) async {
    final outcome = await SyncService.instance.sendOrAcceptFriendRequest(rider.userId);
    if (!mounted) return;
    final message = switch (outcome) {
      'requested' => 'Friend request sent to ${rider.displayName}',
      'accepted' => '${rider.displayName} is now a friend — they\'d already sent you a request',
      'already_friends' => 'You and ${rider.displayName} are already friends',
      'already_requested' => 'You already sent ${rider.displayName} a request',
      _ => 'Couldn\'t send that request — ${SyncService.instance.lastError ?? 'try again'}',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    await _load();
  }

  Future<void> _accept(PendingFriendRequest request) async {
    final ok = await SyncService.instance.acceptFriendRequest(request.requesterId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t accept — ${SyncService.instance.lastError ?? 'try again'}')));
      return;
    }
    await _load();
  }

  Future<void> _remove(String userId) async {
    final ok = await SyncService.instance.removeFriendship(userId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t remove — ${SyncService.instance.lastError ?? 'try again'}')));
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Find a rider by name',
                      border: const OutlineInputBorder(),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : const Icon(Icons.search),
                    ),
                  ),
                  ..._searchResults.map(
                    (r) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                      title: Text(r.displayName),
                      trailing: OutlinedButton(onPressed: () => _sendRequest(r), child: const Text('Add')),
                    ),
                  ),
                  if (_pending.isNotEmpty) ...[
                    const _SectionHeader('Requests'),
                    ..._pending.map(
                      (p) => ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_add_alt_outlined)),
                        title: Text(p.displayName),
                        subtitle: const Text('Wants to be friends'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.tealAccent),
                              tooltip: 'Accept',
                              onPressed: () => _accept(p),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.redAccent),
                              tooltip: 'Decline',
                              onPressed: () => _remove(p.requesterId),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const _SectionHeader('Your friends'),
                  if (_friends.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No friends yet — search above to add one.', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._friends.map(
                      (f) => ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                        title: Text(f.displayName),
                        trailing: TextButton(onPressed: () => _remove(f.userId), child: const Text('Remove')),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }
}
