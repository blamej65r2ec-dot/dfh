import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../services/drafts.dart';
import '../services/options.dart';
import '../services/voice_player.dart';
import '../widgets/animations.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import '../widgets/pill_chip.dart';
import '../widgets/voice_list.dart';

const _voiceCols =
    'id,user_id,audio_path,caption,mood,duration_ms,created_at,profiles(username,nickname,avatar_path)';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _voices = [];
  List<Map<String, dynamic>> _reposts = [];
  List<Draft> _drafts = [];
  int _likesIn = 0;
  int _repostsIn = 0;
  int _tab = 0; // 0 voices, 1 reposts, 2 drafts
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    VoicePlayer.instance.stop();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _profile == null;
      _error = null;
    });
    try {
      final uid = _c.auth.currentUser!.id;
      final profile =
          await _c.from('profiles').select().eq('id', uid).single();
      final voices = await _c
          .from('voices')
          .select(_voiceCols)
          .eq('user_id', uid)
          .eq('kind', 'post')
          .order('created_at', ascending: false)
          .limit(50);
      final reps = await _c
          .from('reposts')
          .select('created_at,voices($_voiceCols)')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      final ids = [for (final v in voices) v['id'] as String];
      var likesIn = 0;
      var repostsIn = 0;
      if (ids.isNotEmpty) {
        final l =
            await _c.from('likes').select('voice_id').inFilter('voice_id', ids);
        final r = await _c
            .from('reposts')
            .select('voice_id')
            .inFilter('voice_id', ids);
        likesIn = l.length;
        repostsIn = r.length;
      }
      final drafts = await DraftStore.load();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _voices = List<Map<String, dynamic>>.from(voices);
        _reposts = [
          for (final r in reps)
            if (r['voices'] != null)
              Map<String, dynamic>.from(r['voices'] as Map),
        ];
        _likesIn = likesIn;
        _repostsIn = repostsIn;
        _drafts = drafts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your profile.';
        _loading = false;
      });
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 800);
      if (x == null) return;
      setState(() => _uploading = true);
      final uid = _c.auth.currentUser!.id;
      var ext = x.path.split('.').last.toLowerCase();
      if (ext == 'jpg') ext = 'jpeg';
      if (!['jpeg', 'png', 'webp'].contains(ext)) ext = 'jpeg';
      final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _c.storage.from('avatars').upload(
            path,
            File(x.path),
            fileOptions: FileOptions(contentType: 'image/$ext'),
          );
      await _c.from('profiles').update({'avatar_path': path}).eq('id', uid);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update the photo')));
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _edit() async {
    final p = _profile;
    if (p == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditSheet(profile: p),
    );
    if (saved == true) _load();
  }

  void _setTab(int t) {
    if (_tab == t) return;
    VoicePlayer.instance.stop();
    setState(() => _tab = t);
  }

  Widget _tag(String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: cs.onSurface.withAlpha(24),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }

  Widget _stat(String value, String label) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withAlpha(160))),
        ],
      ),
    );
  }

  Widget _tabContent() {
    final cs = Theme.of(context).colorScheme;
    Widget empty(String t) => Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Center(child: Text(t, textAlign: TextAlign.center)),
        );
    switch (_tab) {
      case 0:
        return _voices.isEmpty
            ? empty('You have not posted any voices yet.')
            : VoiceList(items: _voices);
      case 1:
        return _reposts.isEmpty
            ? empty('Voices you repost show up here.')
            : VoiceList(items: _reposts);
      default:
        if (_drafts.isEmpty) return empty('No drafts yet.');
        return Column(
          children: [
            for (final d in _drafts)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassBox(
                  radius: 28,
                  padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                  child: Row(
                    children: [
                      Text(d.mood == null ? '🎙️' : moodOf(d.mood!).emoji,
                          style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.caption.isEmpty ? 'No caption' : d.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(fmtDuration(d.durationMs),
                                style: TextStyle(
                                    color: cs.onSurface.withAlpha(160))),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          await DraftStore.removeById(d.id, deleteAudio: true);
                          final l = await DraftStore.load();
                          if (mounted) setState(() => _drafts = l);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Open Record to post a draft.',
                  style: TextStyle(fontSize: 13)),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;
    final p = _profile;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (p == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? 'Something went wrong.'),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }

    final username = (p['username'] as String?) ?? '';
    final nick = (p['nickname'] as String?) ?? '';
    final age = p['age'];
    final country = (p['country'] as String?) ?? '';
    final hobbies = List<String>.from(p['hobbies'] ?? const []);
    final langs = List<String>.from(p['languages'] ?? const []);
    final hasBio =
        age != null || country.isNotEmpty || hobbies.isNotEmpty || langs.isNotEmpty;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 130 + bottom),
          children: [
            FadeSlideIn(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _uploading ? null : _pickAvatar,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: cs.onSurface, width: 2.5),
                          ),
                          child: Avatar(
                            name: nick.isNotEmpty ? nick : username,
                            path: p['avatar_path'] as String?,
                            size: 96,
                          ),
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: cs.primary),
                          child: _uploading
                              ? Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: cs.onPrimary),
                                )
                              : Icon(Icons.camera_alt_rounded,
                                  size: 17, color: cs.onPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    nick.isNotEmpty ? nick : '@$username',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (nick.isNotEmpty)
                    Text('@$username',
                        style: TextStyle(color: cs.onSurface.withAlpha(160))),
                  const SizedBox(height: 14),
                  PressScale(
                    child: GestureDetector(
                      onTap: _edit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 11),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          color: cs.onSurface.withAlpha(24),
                        ),
                        child: const Text('Edit profile',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (hasBio)
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (age != null) _tag('$age years'),
                    if (country.isNotEmpty) _tag(country),
                    for (final h in hobbies) _tag(h),
                    for (final l in langs) _tag(l),
                  ],
                ),
              )
            else
              Center(
                child: Text('Tap Edit profile to add a few details.',
                    style: TextStyle(color: cs.onSurface.withAlpha(160))),
              ),
            const SizedBox(height: 20),
            FadeSlideIn(
              delay: const Duration(milliseconds: 140),
              child: GlassBox(
                radius: 28,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded, size: 18),
                        const SizedBox(width: 8),
                        const Text('Only you can see this',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _stat('${_voices.length}', 'Voices'),
                        _stat('$_likesIn', 'Likes'),
                        _stat('$_repostsIn', 'Reposts'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                PillChip(
                    label: 'Voices',
                    selected: _tab == 0,
                    onTap: () => _setTab(0)),
                PillChip(
                    label: 'Reposts',
                    selected: _tab == 1,
                    onTap: () => _setTab(1)),
                PillChip(
                    label: 'Drafts',
                    selected: _tab == 2,
                    onTap: () => _setTab(2)),
              ],
            ),
            const SizedBox(height: 16),
            _tabContent(),
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: () => _c.auth.signOut(),
                child: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.profile});
  final Map<String, dynamic> profile;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _nick;
  late final TextEditingController _age;
  String? _country;
  late Set<String> _hobbies;
  late Set<String> _langs;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nick = TextEditingController(text: (p['nickname'] as String?) ?? '');
    _age = TextEditingController(text: p['age']?.toString() ?? '');
    _country = p['country'] as String?;
    if (_country != null && _country!.isEmpty) _country = null;
    _hobbies = Set<String>.from(p['hobbies'] ?? const []);
    _langs = Set<String>.from(p['languages'] ?? const []);
  }

  @override
  void dispose() {
    _nick.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    int? age;
    final t = _age.text.trim();
    if (t.isNotEmpty) {
      age = int.tryParse(t);
      if (age == null || age < 13 || age > 120) {
        setState(() => _error = 'Age must be between 13 and 120.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = Supabase.instance.client;
      final nick = _nick.text.trim();
      await c.from('profiles').update({
        'nickname': nick.isEmpty ? null : nick,
        'age': age,
        'country': _country,
        'hobbies': _hobbies.toList(),
        'languages': _langs.toList(),
      }).eq('id', c.auth.currentUser!.id);
      if (mounted) Navigator.of(context).pop(true);
      return;
    } on PostgrestException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _chip(String label, bool sel, ValueChanged<bool> onSel) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label,
          style: TextStyle(color: sel ? cs.onPrimary : cs.onSurface)),
      selected: sel,
      showCheckmark: false,
      selectedColor: cs.primary,
      backgroundColor: cs.onSurface.withAlpha(24),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      onSelected: onSel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final countries = [...kCountries];
    if (_country != null && !countries.contains(_country)) {
      countries.insert(0, _country!);
    }
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: GlassBox(
        radius: 32,
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Edit profile',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                TextField(
                  controller: _nick,
                  maxLength: 30,
                  decoration: const InputDecoration(hintText: 'Nickname'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _age,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 3,
                  decoration: const InputDecoration(hintText: 'Age'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _country,
                  isExpanded: true,
                  decoration: const InputDecoration(hintText: 'Country'),
                  items: [
                    for (final c in countries)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _country = v),
                ),
                const SizedBox(height: 20),
                Text('Hobbies (${_hobbies.length}/5)',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final h in kHobbies)
                      _chip(h, _hobbies.contains(h), (s) {
                        setState(() {
                          if (s) {
                            if (_hobbies.length < 5) _hobbies.add(h);
                          } else {
                            _hobbies.remove(h);
                          }
                        });
                      }),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Languages',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final l in kLanguages)
                      _chip(l, _langs.contains(l), (s) {
                        setState(() => s ? _langs.add(l) : _langs.remove(l));
                      }),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: cs.error)),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
