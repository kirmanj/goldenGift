import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'gg_circle_button.dart';

/// Wishlist toggle: surface circle with a gold outline heart, filled gold
/// when saved, with a small pop animation on toggle (SRS §5.8, §5.9).
///
/// Called with the new value. May return a `Future<bool?>` (e.g. straight from
/// `toggleWishlist`) — the saved state, or null when nothing changed (guest,
/// failed write), in which case the heart flips back to [WishlistHeart.isActive].
/// Any other return (void, `Future<void>`) keeps the optimistic state.
typedef WishlistToggle = FutureOr<void> Function(bool next);

/// Flips immediately (optimistic) and reports the new value through
/// [onChanged]; a later [isActive] from the parent always wins.
/// Visual circle [size] (36–40); the tap target is 48 dp (GGCircleButton).
class WishlistHeart extends StatefulWidget {
  const WishlistHeart({
    super.key,
    required this.isActive,
    this.onChanged,
    this.size = 36,
  });

  final bool isActive;
  final WishlistToggle? onChanged;
  final double size;

  @override
  State<WishlistHeart> createState() => _WishlistHeartState();
}

class _WishlistHeartState extends State<WishlistHeart> with SingleTickerProviderStateMixin {
  late bool _active = widget.isActive;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.25), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 1), weight: 55),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void didUpdateWidget(WishlistHeart old) {
    super.didUpdateWidget(old);
    if (old.isActive != widget.isActive) _active = widget.isActive;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _active = !_active);
    _controller.forward(from: 0);
    final result = widget.onChanged?.call(_active);
    if (result is! Future<bool?>) return;
    final saved = await result;
    if (mounted && saved == null && _active != widget.isActive) setState(() => _active = widget.isActive);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ScaleTransition(
      scale: _scale,
      child: GGCircleButton(
        icon: _active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        iconColor: AppColors.gold(context),
        size: widget.size,
        iconSize: widget.size * 0.55,
        toggled: _active,
        tooltip: _active ? l10n.removeFromWishlist : l10n.addToWishlist,
        onPressed: widget.onChanged == null ? null : _toggle,
      ),
    );
  }
}
