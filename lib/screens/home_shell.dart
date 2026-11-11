import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/drafts.dart';
import '../widgets/animations.dart';
import '../widgets/glass.dart';
import 'chat_page.dart';
import 'feed_page.dart';
import 'profile_page.dart';
import 'record_page.dart';
import 'search_page.dart';

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
    Icons.chat_bubble_outline_rounded,
    Icons.person_outline_rounded,
  ];
  static const _labels = ['Home', 'Search', 'Record', 'Chat', 'Profile'];

  Widget _page(int i) {
    switch (i) {
      case 0:
        return const FeedPage();
      case 1:
        return const SearchPage();
      case 2:
        return RecordPage(onPosted: () => setState(() => _i = 0));
      case 3:
        return const ChatPage();
      case 4:
        return ProfilePage(onOpenDraft: (d) {
          DraftStore.setPending(d);
          setState(() => _i = 2);
        });
      default:
        return _Soon(_labels[i]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(_i), child: _page(_i)),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24 + bottom,
            child: FadeSlideIn(
              offset: const Offset(0, 0.5),
              delay: const Duration(milliseconds: 150),
              child: GlassBox(
                radius: 36,
                padding: const EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final step = (c.maxWidth - 52) / 4;
                    return SizedBox(
                      height: 52,
                      child: Stack(
                        children: [
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.easeOutCubic,
                            left: _i * step,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cs.primary,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color.fromRGBO(0, 0, 0, .35),
                                    blurRadius: 14,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          for (var k = 0; k < 5; k++)
                            Positioned(
                              left: k * step,
                              child: SizedBox(
                                width: 52,
                                height: 52,
                                child: IconButton(
                                  tooltip: _labels[k],
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _i = k);
                                  },
                                  icon: AnimatedScale(
                                    scale: k == _i ? 1.12 : 1,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                    child: TweenAnimationBuilder<Color?>(
                                      tween: ColorTween(
                                        end: k == _i
                                            ? cs.onPrimary
                                            : cs.onSurface.withAlpha(150),
                                      ),
                                      duration:
                                          const Duration(milliseconds: 250),
                                      builder: (context, color, _) =>
                                          Icon(_icons[k], size: 24, color: color),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
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
    return Center(
      child: FadeSlideIn(child: Text('$name: coming next')),
    );
  }
}
