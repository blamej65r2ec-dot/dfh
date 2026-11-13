import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_events.dart';
import '../services/drafts.dart';
import '../services/in_app_notifier.dart';
import '../services/voice_player.dart';
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
  bool _storyMode = false;
  final PageController _pc = PageController();
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    AppEvents.pagingLocked.addListener(_onLock);
    InAppNotifier.start();
  }

  @override
  void dispose() {
    AppEvents.pagingLocked.removeListener(_onLock);
    InAppNotifier.stop();
    _pc.dispose();
    super.dispose();
  }

  void _onLock() {
    if (mounted && _locked != AppEvents.pagingLocked.value) {
      setState(() => _locked = AppEvents.pagingLocked.value);
    }
  }

  void _go(int k) {
    if (!_pc.hasClients) return;
    if ((k - _i).abs() > 1) {
      _pc.jumpToPage(k);
    } else {
      _pc.animateToPage(k,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic);
    }
  }

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
        return FeedPage(
          onAddStory: () {
            setState(() => _storyMode = true);
            _go(2);
          },
        );
      case 1:
        return const SearchPage();
      case 2:
        return RecordPage(
          storyMode: _storyMode,
          onPosted: () {
            setState(() => _storyMode = false);
            _go(0);
          },
          onClose: () {
            setState(() => _storyMode = false);
            _go(0);
          },
        );
      case 3:
        return const ChatPage();
      case 4:
        return ProfilePage(onOpenDraft: (d) {
          setState(() => _storyMode = false);
          DraftStore.setPending(d);
          _go(2);
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
          PageView(
            controller: _pc,
            physics: _locked
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            onPageChanged: (i) {
              VoicePlayer.instance.stop();
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() {
                if (i != 2) _storyMode = false;
                _i = i;
              });
            },
            children: [
              for (var k = 0; k < 5; k++)
                _KeepAlive(key: ValueKey('tab$k'), child: _page(k)),
            ],
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
                                    if (k != 2) _storyMode = false;
                                    _go(k);
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

/// Keeps a tab alive while you swipe to other tabs.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({super.key, required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
