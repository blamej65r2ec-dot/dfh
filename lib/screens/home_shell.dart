import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/glass.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

  static const _icons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.add_rounded,
    Icons.notifications_none_rounded,
    Icons.person_outline_rounded,
  ];
  static const _labels = ['Home', 'Search', 'Record', 'Alerts', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _i,
            children: const [
              _Soon('Home'),
              _Soon('Search'),
              _Soon('Record'),
              _Soon('Alerts'),
              ProfilePage(),
            ],
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24 + bottom,
            child: GlassBox(
              radius: 36,
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var k = 0; k < 5; k++)
                    IconButton(
                      tooltip: _labels[k],
                      onPressed: () => setState(() => _i = k),
                      style: IconButton.styleFrom(
                        fixedSize: const Size(52, 52),
                        backgroundColor:
                            k == _i ? cs.primary : Colors.transparent,
                        foregroundColor: k == _i
                            ? cs.onPrimary
                            : cs.onSurface.withAlpha(150),
                      ),
                      icon: Icon(_icons[k], size: 24),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Soon extends StatelessWidget {
  const _Soon(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('$name: coming next'));
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    return SafeArea(
      child: Center(
        child: FutureBuilder<Map<String, dynamic>>(
          future: client.from('profiles').select().eq('id', uid ?? '').single(),
          builder: (context, snap) {
            final name = snap.hasData ? '@${snap.data!['username']}' : '...';
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                FilledButton(
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(160, 50)),
                  onPressed: () => client.auth.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
