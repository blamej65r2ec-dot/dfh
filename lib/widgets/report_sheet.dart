import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'glass.dart';

const _reasons = [
  'Spam',
  'Harassment or hate',
  'Inappropriate content',
  'Someone may be in danger',
  'Something else',
];

/// type: 'voice' or 'profile'. id: the voice id or the user id.
Future<void> showReportSheet(
  BuildContext context, {
  required String type,
  required String id,
}) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(12),
      child: GlassBox(
        radius: 32,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                type == 'voice'
                    ? 'Report this voice'
                    : type == 'message'
                        ? 'Report this message'
                        : 'Report this profile',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final r in _reasons)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(ctx).pop(r),
              ),
          ],
        ),
      ),
    ),
  );
  if (reason == null) return;
  String message;
  try {
    final c = Supabase.instance.client;
    await c.from('reports').insert({
      'reporter_id': c.auth.currentUser!.id,
      'target_type': type,
      'target_id': id,
      'reason': reason,
    });
    message = 'Thanks. We will take a look.';
  } catch (_) {
    message = 'Could not send the report. Try again.';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
