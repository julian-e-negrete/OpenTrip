import 'dart:async';

import 'package:flutter/material.dart';

import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import 'friend_models.dart';

/// Search for other riders, respond to incoming friend requests, and see
/// (or remove) your current friends. Feeds the "Friends" scope on
/// leaderboard/leaderboard_screen.dart and territory_map_screen.dart.
/// Sign-in only, same as the rest of the social features — there's no
/// cross-device concept of "friends" for a local guest.
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
      appBar: AppBar(
        title: const Text('Friends', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: -0.44)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Noct.surface,
                      borderRadius: BorderRadius.circular(Noct.rMd),
                      border: Border.all(color: Noct.divider),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Ph.magnifyingGlass, size: 15, color: Noct.n500),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(fontSize: 13, color: Noct.text),
                            cursorColor: Noct.accent,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 11),
                              hintText: 'Find a rider by name',
                              hintStyle: TextStyle(fontSize: 13, color: Noct.n500),
                            ),
                          ),
                        ),
                        if (_searching)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Noct.n500),
                          ),
                      ],
                    ),
                  ),
                  for (final r in _searchResults) _SearchResultRow(rider: r, onAdd: () => _sendRequest(r)),
                  if (_pending.isNotEmpty) ...[
                    _SectionHeader('Requests · ${_pending.length}', color: Noct.accent),
                    for (final p in _pending)
                      _RequestRow(request: p, onAccept: () => _accept(p), onDecline: () => _remove(p.requesterId)),
                  ],
                  _SectionHeader('Your friends · ${_friends.length}', color: Noct.n500),
                  if (_friends.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No friends yet — search above to add one.',
                        style: TextStyle(color: Noct.n500, fontSize: 13),
                      ),
                    )
                  else
                    for (final f in _friends) _FriendRow(friend: f, onRemove: () => _remove(f.userId)),
                ],
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: color, fontWeight: FontWeight.w400),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.accent = false});
  final String name;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: accent ? Noct.a900 : Noct.n800, shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(fontSize: 13, color: accent ? Noct.a200 : Noct.n300, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.rider, required this.onAdd});
  final RiderSummary rider;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _Avatar(name: rider.displayName),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              rider.displayName,
              style: const TextStyle(fontSize: 13.5, color: Noct.text, fontWeight: FontWeight.w400),
            ),
          ),
          NoctOutlinedButton(label: 'Add', expand: false, onPressed: onAdd),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request, required this.onAccept, required this.onDecline});
  final PendingFriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NoctPanel(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            _Avatar(name: request.displayName, accent: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.displayName,
                    style: const TextStyle(fontSize: 13.5, color: Noct.text, fontWeight: FontWeight.w400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text('Wants to be friends', style: TextStyle(fontSize: 11, color: Noct.n500)),
                ],
              ),
            ),
            NoctOutlinedButton(label: 'Accept', expand: false, onPressed: onAccept),
            IconButton(icon: const Icon(Ph.x, size: 15, color: Noct.n500), tooltip: 'Decline', onPressed: onDecline),
          ],
        ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend, required this.onRemove});
  final RiderSummary friend;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Noct.n900, width: 1))),
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          _Avatar(name: friend.displayName),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              friend.displayName,
              style: const TextStyle(fontSize: 13.5, color: Noct.text, fontWeight: FontWeight.w400),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PopupMenuButton<void>(
            icon: const Icon(Ph.dotsThree, size: 16, color: Noct.n600),
            color: Noct.surface,
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: onRemove,
                child: const Text('Remove friend', style: TextStyle(color: Noct.text)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
