import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../services/follows.dart';
import '../services/voice_player.dart';
import '../widgets/animations.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import '../widgets/pill_chip.dart';
import '../widgets/voice_list.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _c = Supabase.instance.client;
  final _text = TextEditingController();
  Timer? _debounce;
  int _tab = 0; // 0 = People, 1 = Voices
  String? _mood;
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _voices = [];
  Set<String> _following = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Follows.mine().then((s) {
      if (mounted) setState(() => _following = s);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    VoicePlayer.instance.stop();
    super.dispose();
  }

  String get _q => _text
      .text
      .replaceAll(RegExp(r'[,()%*\\]'), ' ')
      .replaceFirst(RegExp(r'^\s*@'), '')
      .trim();

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  Future<void> _run() async {
    final q = _q;
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      if (_tab == 0) {
        if (q.isEmpty) {
          _people = [];
        } else {
          final uid = _c.auth.currentUser!.id;
          final rows = await _c
              .from('profiles')
              .select('id,username,nickname,avatar_path')
              .or('username.ilike.%$q%,nickname.ilike.%$q%')
              .neq('id', uid)
              .limit(30);
          _people = List<Map<String, dynamic>>.from(rows);
        }
      } else {
        if (q.isEmpty && _mood == null) {
          _voices = [];
        } else {
          var query = _c
              .from('voices')
              .select(
                  'id,user_id,audio_path,caption,mood,duration_ms,created_at,profiles(username,nickname,avatar_path)')
              .eq('kind', 'post');
          if (q.isNotEmpty) query = query.ilike('caption', '%$q%');
          if (_mood != null) query = query.eq('mood', _mood!);
          final rows =
              await query.order('created_at', ascending: false).limit(40);
          _voices = List<Map<String, dynamic>>.from(rows);
        }
      }
    } catch (_) {
      _error = 'Search failed. Try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _setTab(int t) {
    if (_tab == t) return;
    VoicePlayer.instance.stop();
    setState(() => _tab = t);
    _run();
  }

  void _pickMood(String? m) {
    if (_mood == m) return;
    VoicePlayer.instance.stop();
    setState(() => _mood = m);
    _run();
  }

  Future<void> _toggleFollow(String id) async {
    final had = _following.contains(id);
    HapticFeedback.selectionClick();
    setState(() => had ? _following.remove(id) : _following.add(id));
    try {
      await Follows.set(id, !had);
    } catch (_) {
      if (!mounted) return;
      setState(() => had ? _following.add(id) : _following.remove(id));
    }
  }

  Widget _personRow(Map<String, dynamic> p) {
    final cs = Theme.of(context).colorScheme;
    final id = p['id'] as String;
    final username = (p['username'] as String?) ?? '';
    final nick = (p['nickname'] as String?) ?? '';
    final following = _following.contains(id);
    final shown = nick.isNotEmpty ? nick : username;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FadeSlideIn(
        child: GlassBox(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Avatar(
                name: shown,
                path: p['avatar_path'] as String?,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shown,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    if (nick.isNotEmpty)
                      Text('@$username',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withAlpha(150))),
                  ],
                ),
              ),
              PressScale(
                child: GestureDetector(
                  onTap: () => _toggleFollow(id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      color: following
                          ? cs.onSurface.withAlpha(24)
                          : cs.primary,
                    ),
                    child: Text(
                      following ? 'Following' : 'Follow',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: following ? cs.onSurface : cs.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 50),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 50),
        child: Center(child: Text(_error!)),
      );
    }
    if (_tab == 0) {
      if (_q.isEmpty) {
        return const Padding(
          padding: EdgeInsets.only(top: 50),
          child: Center(child: Text('Type a username or nickname.')),
        );
      }
      if (_people.isEmpty) {
        return const Padding(
          padding: EdgeInsets.only(top: 50),
          child: Center(child: Text('No one found.')),
        );
      }
      return Column(children: [for (final p in _people) _personRow(p)]);
    }
    if (_q.isEmpty && _mood == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 50),
        child: Center(
          child: Text('Search captions, or pick a mood.',
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_voices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 50),
        child: Center(child: Text('No voices found.')),
      );
    }
    return VoiceList(items: _voices);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      bottom: false,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 16, 20, 130 + bottom),
        children: [
          FadeSlideIn(
            child: Text('Search',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            onChanged: _changed,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: const InputDecoration(
              hintText: 'People or voices',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              PillChip(
                  label: 'People',
                  selected: _tab == 0,
                  onTap: () => _setTab(0)),
              PillChip(
                  label: 'Voices',
                  selected: _tab == 1,
                  onTap: () => _setTab(1)),
            ],
          ),
          if (_tab == 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  PillChip(
                      label: 'Any mood',
                      selected: _mood == null,
                      onTap: () => _pickMood(null)),
                  for (final m in moods)
                    PillChip(
                        label: m.emoji,
                        selected: _mood == m.key,
                        onTap: () => _pickMood(m.key)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          _results(),
        ],
      ),
    );
  }
}
