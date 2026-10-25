import 'package:flutter/widgets.dart';

/// Calls [onLoadMore] when the enclosing vertical scroll view is less than one
/// viewport away from its end (SRS §5.4 item 12, §5.8 infinite scroll).
///
/// Transparent wrapper: [child] may be a sliver. It listens to the nearest
/// vertical [ScrollPosition] and re-checks after every rebuild, so a page
/// that doesn't fill the screen still pulls the next one. Nothing happens
/// while [enabled] is false (page loading, no more pages, or a failed page
/// waiting for the user's Retry). Checks run after the frame, so providers are
/// never modified while the tree is building.
class LoadMoreTrigger extends StatefulWidget {
  const LoadMoreTrigger({
    super.key,
    required this.enabled,
    required this.onLoadMore,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onLoadMore;
  final Widget child;

  @override
  State<LoadMoreTrigger> createState() => _LoadMoreTriggerState();
}

class _LoadMoreTriggerState extends State<LoadMoreTrigger> {
  ScrollPosition? _position;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (position != _position) {
      _position?.removeListener(_schedule);
      _position = position?..addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(LoadMoreTrigger old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  @override
  void dispose() {
    _position?.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() {
    if (_scheduled || !widget.enabled) return;
    _scheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) _check();
      })
      ..ensureVisualUpdate();
  }

  void _check() {
    final p = _position;
    if (!widget.enabled || p == null || !p.hasContentDimensions || !p.hasPixels) return;
    if (p.extentAfter <= p.viewportDimension) widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
