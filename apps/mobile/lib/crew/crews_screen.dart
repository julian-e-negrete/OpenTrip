import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../config/app_config.dart';
import '../friends/friend_models.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import 'crew_map_screen.dart';
import 'crew_models.dart';
import 'crew_service.dart';

const _sectionStyle = TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400);

/// Your crews: create one, open one to manage members and what you share
/// with it, and jump to the live crew map. Sign-in only — see
/// crew_service.dart.
class CrewsScreen extends StatefulWidget {
  const CrewsScreen({super.key});

  @override
  State<CrewsScreen> createState() => _CrewsScreenState();
}

class _CrewsScreenState extends State<CrewsScreen> {
  List<Crew> _crews = [];
  bool _loading = true;
  bool _shareWhileRiding = true;
  StreamSubscription<Object>? _authSub;

  @override
  void initState() {
    super.initState();
    _load();
    // This is a bottom-bar tab root, so it stays alive across a guest
    // signing in (or a rider signing out) — without this it would keep
    // showing whatever it loaded under the old session.
    if (AppConfig.isSupabaseConfigured) {
      _authSub = AuthService.instance.onAuthStateChange.listen((_) => _load());
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final crews = await CrewService.instance.fetchMyCrews();
    final share = await CrewService.instance.shareWhileRiding();
    if (!mounted) return;
    setState(() {
      _crews = crews;
      _shareWhileRiding = share;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final name = await _promptName(context, title: 'New crew', initial: '');
    if (name == null) return;
    final id = await CrewService.instance.createCrew(name);
    if (!mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t create the crew — ${CrewService.instance.lastError ?? 'try again'}')),
      );
      return;
    }
    await _load();
    final created = _crews.where((c) => c.id == id).firstOrNull;
    if (created != null && mounted) await _open(created);
  }

  Future<void> _open(Crew crew) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CrewDetailScreen(crew: crew)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final available = CrewService.instance.isAvailable;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crews', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: -0.44)),
        actions: [
          if (available)
            IconButton(
              tooltip: 'Crew live map',
              icon: const Icon(Ph.mapTrifold, size: 19),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CrewMapScreen())),
            ),
        ],
      ),
      floatingActionButton: available
          ? FloatingActionButton.extended(
              onPressed: _create,
              backgroundColor: Noct.a900,
              foregroundColor: Noct.a200,
              icon: const Icon(Ph.plus, size: 16),
              label: const Text('New crew'),
            )
          : null,
      body: !available
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Sign in to create crews and see your friends live on the map while you ride.',
                style: TextStyle(color: Noct.n400, fontSize: 13.5),
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
                    children: [
                      NoctPanel(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Share my location while riding',
                              style: TextStyle(color: Noct.text, fontSize: 13.5)),
                          subtitle: const Text(
                            'Crews you share with see you on their map during a recording. Off rides privately.',
                            style: TextStyle(color: Noct.n500, fontSize: 11),
                          ),
                          value: _shareWhileRiding,
                          onChanged: (v) async {
                            setState(() => _shareWhileRiding = v);
                            await CrewService.instance.setShareWhileRiding(v);
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('YOUR CREWS · ${_crews.length}', style: _sectionStyle),
                      const SizedBox(height: 8),
                      if (_crews.isEmpty)
                        const Text(
                          'No crews yet. Create one and add friends to ride together — you\'ll see each other\'s position, speed and lean live on the map.',
                          style: TextStyle(color: Noct.n500, fontSize: 13),
                        ),
                      for (final crew in _crews)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: NoctPanel(
                            onTap: () => _open(crew),
                            child: Row(
                              children: [
                                const Icon(Ph.usersThree, size: 20, color: Noct.a300),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(crew.name, style: const TextStyle(fontSize: 14, color: Noct.text)),
                                      Text(
                                        '${crew.memberCount} rider${crew.memberCount == 1 ? '' : 's'} · ${_sharingSummary(crew)}',
                                        style: const TextStyle(fontSize: 11.5, color: Noct.n500),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Ph.caretRight, size: 14, color: Noct.n600),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

String _sharingSummary(Crew crew) {
  if (!crew.shareLocation) return 'not sharing';
  final extras = [if (crew.shareSpeed) 'speed', if (crew.shareLean) 'lean'];
  return extras.isEmpty ? 'sharing location' : 'sharing location, ${extras.join(' & ')}';
}

Future<String?> _promptName(BuildContext context, {required String title, required String initial}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'e.g. Sunday Twisties'),
        onSubmitted: (v) => Navigator.pop(dialogContext, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final v = controller.text.trim();
            Navigator.pop(dialogContext, v.isEmpty ? null : v);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// One crew: members (the owner can remove people), adding friends, what
/// *you* share with this crew, rename (owner) and leave.
class CrewDetailScreen extends StatefulWidget {
  const CrewDetailScreen({super.key, required this.crew});

  final Crew crew;

  @override
  State<CrewDetailScreen> createState() => _CrewDetailScreenState();
}

class _CrewDetailScreenState extends State<CrewDetailScreen> {
  late Crew _crew = widget.crew;
  List<CrewMember> _members = [];
  bool _loading = true;

  bool get _isOwner => _crew.ownerId == AuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final members = await CrewService.instance.fetchMembers(_crew.id);
    if (!mounted) return;
    setState(() {
      _members = members;
      _loading = false;
    });
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _updateSharing(Crew updated) async {
    final previous = _crew;
    setState(() => _crew = updated);
    final ok = await CrewService.instance.setSharing(updated);
    if (!ok && mounted) {
      setState(() => _crew = previous);
      _snack('Couldn\'t update sharing — ${CrewService.instance.lastError ?? 'try again'}');
    }
  }

  Future<void> _addFriend() async {
    final friends = await SyncService.instance.fetchFriends();
    if (!mounted) return;
    final memberIds = _members.map((m) => m.userId).toSet();
    final candidates = friends.where((f) => !memberIds.contains(f.userId)).toList();
    final picked = await showModalBottomSheet<RiderSummary>(
      context: context,
      backgroundColor: Noct.surface,
      builder: (sheetContext) => SafeArea(
        child: candidates.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'All your friends are already in this crew — or you haven\'t added any yet. Crews can only include friends.',
                  style: TextStyle(color: Noct.n400, fontSize: 13),
                ),
              )
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final f in candidates)
                    ListTile(
                      title: Text(f.displayName, style: const TextStyle(color: Noct.text, fontSize: 14)),
                      trailing: const Icon(Ph.plus, size: 16, color: Noct.a300),
                      onTap: () => Navigator.pop(sheetContext, f),
                    ),
                ],
              ),
      ),
    );
    if (picked == null) return;
    final outcome = await CrewService.instance.addMember(_crew.id, picked.userId);
    if (!mounted) return;
    _snack(switch (outcome) {
      'added' => '${picked.displayName} added to ${_crew.name}',
      'already_member' => '${picked.displayName} is already in this crew',
      'not_friends' => 'You can only add friends to a crew',
      'not_member' => 'You\'re no longer in this crew',
      _ => 'Couldn\'t add — ${CrewService.instance.lastError ?? 'try again'}',
    });
    await _load();
  }

  Future<void> _remove(CrewMember member) async {
    final ok = await CrewService.instance.removeMember(_crew.id, member.userId);
    if (!mounted) return;
    if (!ok) _snack('Couldn\'t remove — ${CrewService.instance.lastError ?? 'try again'}');
    await _load();
  }

  Future<void> _rename() async {
    final name = await _promptName(context, title: 'Rename crew', initial: _crew.name);
    if (name == null) return;
    final ok = await CrewService.instance.renameCrew(_crew.id, name);
    if (!mounted) return;
    if (ok) {
      setState(() => _crew = _crew.copyWith(name: name));
    } else {
      _snack('Couldn\'t rename — ${CrewService.instance.lastError ?? 'try again'}');
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave ${_crew.name}?'),
        content: Text(
          _members.length <= 1
              ? 'You\'re the last member — the crew will be deleted.'
              : _isOwner
                  ? 'Ownership passes to the longest-standing member.'
                  : 'You can be added back by any member.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await CrewService.instance.leaveCrew(_crew.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      _snack('Couldn\'t leave — ${CrewService.instance.lastError ?? 'try again'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = AuthService.instance.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(_crew.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
        actions: [
          if (_isOwner) IconButton(tooltip: 'Rename', icon: const Icon(Ph.pencilSimple, size: 18), onPressed: _rename),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                children: [
                  const Text('WHAT YOU SHARE WITH THIS CREW', style: _sectionStyle),
                  const SizedBox(height: 8),
                  NoctPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Live location', style: TextStyle(color: Noct.text, fontSize: 13.5)),
                          subtitle: const Text(
                            'Only while you\'re recording a ride.',
                            style: TextStyle(color: Noct.n500, fontSize: 11),
                          ),
                          value: _crew.shareLocation,
                          onChanged: (v) => _updateSharing(_crew.copyWith(shareLocation: v)),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Speed', style: TextStyle(color: Noct.text, fontSize: 13.5)),
                          value: _crew.shareSpeed,
                          onChanged: _crew.shareLocation ? (v) => _updateSharing(_crew.copyWith(shareSpeed: v)) : null,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Lean angle', style: TextStyle(color: Noct.text, fontSize: 13.5)),
                          value: _crew.shareLean,
                          onChanged: _crew.shareLocation ? (v) => _updateSharing(_crew.copyWith(shareLean: v)) : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(child: Text('MEMBERS · ${_members.length}', style: _sectionStyle)),
                      NoctOutlinedButton(label: 'Add friend', icon: Ph.plus, expand: false, onPressed: _addFriend),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final m in _members)
                    Container(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Noct.n900, width: 1))),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.userId == myId ? '${m.displayName} (you)' : m.displayName,
                              style: const TextStyle(fontSize: 13.5, color: Noct.text),
                            ),
                          ),
                          if (m.isOwner) const NoctTagChip('owner', accent: true),
                          if (!m.shareLocation) ...[const SizedBox(width: 6), const NoctTagChip('hidden')],
                          if (_isOwner && m.userId != myId)
                            IconButton(
                              tooltip: 'Remove from crew',
                              icon: const Icon(Ph.x, size: 15, color: Noct.n500),
                              onPressed: () => _remove(m),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 28),
                  TextButton.icon(
                    onPressed: _leave,
                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    icon: const Icon(Ph.signOut, size: 16),
                    label: const Text('Leave crew'),
                  ),
                ],
              ),
            ),
    );
  }
}
