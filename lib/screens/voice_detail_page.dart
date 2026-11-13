import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/activity.dart';
import '../services/voice_player.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/glass.dart';
import '../widgets/voice_list.dart';

/// One voice, opened from a notification.
class VoiceDetailPage extends StatefulWidget {
  const VoiceDetailPage({
    super.key,
    required this.voiceId,
    this.openComments = false,
  });

  final String voiceId;
  final bool openComments;

  @override
  State<VoiceDetailPage> createState() => _VoiceDetailPageState();
}

class _VoiceDetailPageState extends State<VoiceDetailPage> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _voice;
  bool _loading = true;

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
    try {
      final rows = await loadVoices((cols) =>
          _c.from('voices').select(cols).eq('id', widget.voiceId).limit(1));
      if (!mounted) return;
      setState(() {
        _voice = rows.isEmpty ? null : rows.first;
        _loading = false;
      });
      if (widget.openComments && _voice != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            showCommentsSheet(context,
                voiceId: widget.voiceId,
                ownerId: _voice!['user_id'] as String);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: GlassBox(
                      radius: 23,
                      child: const SizedBox(
                        width: 46,
                        height: 46,
                        child: Icon(Icons.chevron_left_rounded, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text('Voice',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _voice == null
                      ? const Center(
                          child: Text('This voice is not available anymore.'))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                          children: [VoiceList(items: [_voice!])],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
