import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/special_request_model.dart';
import '../../../gift_cards/presentation/widgets/gift_card_labels.dart';

String specialRequestStatusLabel(AppLocalizations l10n, SpecialRequestStatus status) => switch (status) {
      SpecialRequestStatus.submitted => l10n.srStatusSubmitted,
      SpecialRequestStatus.inReview => l10n.srStatusInReview,
      SpecialRequestStatus.quoted => l10n.srStatusQuoted,
      SpecialRequestStatus.accepted => l10n.srStatusAccepted,
      SpecialRequestStatus.rejected => l10n.srStatusRejected,
      SpecialRequestStatus.completed => l10n.srStatusCompleted,
    };

/// A distinct colour per status (SRS §5.17): submitted blue, in review
/// orange, quoted gold, accepted green, rejected red, completed neutral.
(Color fg, Color bg) specialRequestStatusColors(BuildContext context, SpecialRequestStatus status) =>
    switch (status) {
      SpecialRequestStatus.submitted => tonePillColors(context, InfoBannerType.info, AppColors.info),
      SpecialRequestStatus.inReview => tonePillColors(context, InfoBannerType.warning, AppColors.warning),
      SpecialRequestStatus.quoted => (AppColors.goldText(context), AppColors.soft(context)),
      SpecialRequestStatus.accepted => tonePillColors(context, InfoBannerType.success, AppColors.success),
      SpecialRequestStatus.rejected => tonePillColors(context, InfoBannerType.error, AppColors.error),
      SpecialRequestStatus.completed => neutralPillColors(context),
    };

/// Rejected and completed requests are closed: no reply box, no unread dot.
bool isClosedRequest(SpecialRequestModel r) =>
    r.status == SpecialRequestStatus.rejected || r.status == SpecialRequestStatus.completed;

/// Golden Gift wrote last and the request is still open.
bool hasUnreadReply(SpecialRequestModel r) => r.lastMessageBy == 'admin' && !isClosedRequest(r);

class SpecialRequestStatusChip extends StatelessWidget {
  const SpecialRequestStatusChip({super.key, required this.status});
  final SpecialRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = specialRequestStatusColors(context, status);
    return StatusPill(
      key: ValueKey('sr-status-${status.name}'),
      label: specialRequestStatusLabel(AppLocalizations.of(context)!, status),
      fg: fg,
      bg: bg,
    );
  }
}

class SupportTypeChip extends StatelessWidget {
  const SupportTypeChip({super.key});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = neutralPillColors(context);
    return StatusPill(
      key: const ValueKey('sr-type-support'),
      label: AppLocalizations.of(context)!.srTypeSupport,
      icon: Icons.support_agent_rounded,
      fg: fg,
      bg: bg,
    );
  }
}

/// One of my requests in the list: first line, status (+ Support), date and
/// a gold dot when Golden Gift replied.
class SpecialRequestTile extends StatelessWidget {
  const SpecialRequestTile({super.key, required this.request});
  final SpecialRequestModel request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final r = request;
    final firstLine = r.text.trim().split('\n').first;
    final date = r.createdAt;
    final unread = hasUnreadReply(r);
    return Material(
      color: AppColors.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: unread ? AppColors.gold(context) : AppColors.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('sr-tile-${r.id}'),
        onTap: () => context.push(AppRoutes.specialRequest(r.id)),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
                    child: Icon(
                      r.type == SpecialRequestType.support ? Icons.support_agent_rounded : Icons.lightbulb_outline_rounded,
                      color: AppColors.gold(context),
                    ),
                  ),
                  if (unread)
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: Semantics(
                        label: l10n.srNewReply,
                        child: Container(
                          key: ValueKey('sr-unread-${r.id}'),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.gold(context),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.card(context), width: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                        color: AppColors.text(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SpecialRequestStatusChip(status: r.status),
                        if (r.type == SpecialRequestType.support) const SupportTypeChip(),
                        if (date != null)
                          Text(
                            AppDates.display(date),
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Network thumbnails (request / message images); a tap opens the viewer.
class RequestImageStrip extends StatelessWidget {
  const RequestImageStrip({super.key, required this.urls, this.size = 72});
  final List<String> urls;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < urls.length; i++)
          Semantics(
            button: true,
            label: l10n.photoSlot(i + 1),
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('sr-image-$i'),
              onTap: () => showImageViewer(context, urls, initialIndex: i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox.square(dimension: size, child: GGNetworkImage(url: urls[i])),
              ),
            ),
          ),
      ],
    );
  }
}

/// Full-screen, swipeable, pinch-to-zoom image viewer.
Future<void> showImageViewer(BuildContext context, List<String> urls, {int initialIndex = 0}) =>
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      pageBuilder: (_, __, ___) => _ImageViewer(urls: urls, initialIndex: initialIndex),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    ));

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.urls, required this.initialIndex});
  final List<String> urls;
  final int initialIndex;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      key: const ValueKey('image-viewer'),
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: GGNetworkImage(
                    url: widget.urls[i],
                    fit: BoxFit.contain,
                    fallbackColor: AppColors.black,
                    semanticLabel: l10n.photoSlot(i + 1),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              top: AppSpacing.sm,
              start: AppSpacing.md,
              child: GGCircleButton(
                key: const ValueKey('image-viewer-close'),
                icon: Icons.close_rounded,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (widget.urls.length > 1)
              PositionedDirectional(
                bottom: AppSpacing.lg,
                start: 0,
                end: 0,
                child: Text(
                  '${_index + 1} / ${widget.urls.length}',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: AppTextStyles.label.copyWith(color: AppColors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Soft-gold "idea" illustration (stand-in for the IMG_4492 artwork until the
/// final brand illustrations exist, SRS §12 item 1).
class IdeaIllustration extends StatelessWidget {
  const IdeaIllustration({super.key, this.icon = Icons.lightbulb_rounded, this.size = 132});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: size + 32,
        height: size,
        child: Stack(
          children: [
            PositionedDirectional(
              start: 16,
              top: 0,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
              ),
            ),
            PositionedDirectional(
              start: 0,
              top: size * 0.08,
              child: Icon(Icons.settings_outlined, size: size * 0.24, color: gold.withValues(alpha: 0.6)),
            ),
            PositionedDirectional(
              end: 0,
              bottom: size * 0.06,
              child: Icon(Icons.auto_awesome_rounded, size: size * 0.2, color: gold.withValues(alpha: 0.75)),
            ),
            PositionedDirectional(
              start: 16 + size * 0.2,
              top: size * 0.2,
              child: Container(
                width: size * 0.6,
                height: size * 0.6,
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  shape: BoxShape.circle,
                  boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
                ),
                child: Icon(icon, size: size * 0.32, color: gold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Submitted · In review · Quoted · Accepted · Completed" with the current
/// step highlighted (gift requests); a declined request shows a red note.
class RequestStatusSteps extends StatelessWidget {
  const RequestStatusSteps({super.key, required this.status});
  final SpecialRequestStatus status;

  static const _steps = [
    SpecialRequestStatus.submitted,
    SpecialRequestStatus.inReview,
    SpecialRequestStatus.quoted,
    SpecialRequestStatus.accepted,
    SpecialRequestStatus.completed,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (status == SpecialRequestStatus.rejected) {
      return InfoBanner(
        key: const ValueKey('sr-rejected-note'),
        message: l10n.srRejectedNote,
        type: InfoBannerType.error,
      );
    }
    final current = _steps.indexOf(status);
    final gold = AppColors.gold(context);
    return Semantics(
      label: specialRequestStatusLabel(l10n, status),
      excludeSemantics: true,
      child: Row(
        key: const ValueKey('sr-steps'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _steps.length; i++)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(height: 2, color: i == 0 ? Colors.transparent : (i <= current ? gold : AppColors.line(context))),
                      ),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= current ? gold : AppColors.card(context),
                          border: Border.all(color: i <= current ? gold : AppColors.line(context), width: 2),
                        ),
                        child: i < current
                            ? const Icon(Icons.check_rounded, size: 12, color: AppColors.textOnPrimary)
                            : null,
                      ),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == _steps.length - 1
                              ? Colors.transparent
                              : (i < current ? gold : AppColors.line(context)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    specialRequestStatusLabel(l10n, _steps[i]),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11,
                      fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                      color: i == current ? AppColors.text(context) : AppColors.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
