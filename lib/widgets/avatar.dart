import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.path, this.size = 46});

  final String name;
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();
    final fallback = Center(
      child: Text(
        letter,
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w800),
      ),
    );
    final p = path;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.onSurface.withAlpha(30),
      ),
      child: (p == null || p.isEmpty)
          ? fallback
          : Image.network(
              Supabase.instance.client.storage.from('avatars').getPublicUrl(p),
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}
