import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../orders/presentation/widgets/order_card.dart' show popOrGo;
import '../../data/ai_search_repository.dart';
import '../providers/ai_search_controller.dart';
import '../widgets/ai_suggestion_grid.dart';

/// AI Gift Search (SRS §5.6, `/ai-gift-search`, from the Home header): a
/// free-text description (≤ 300) with example, occasion, recipient and budget
/// chips → "Find gifts" → up to 12 product cards, each with a one-line "why".
/// Keyword results when the function is down or the daily limit is reached.
/// Works for guests.
class AiGiftSearchScreen extends ConsumerStatefulWidget {
  const AiGiftSearchScreen({super.key});

  /// Shortest description worth sending.
  static const minQuery = 3;

  @override
  ConsumerState<AiGiftSearchScreen> createState() => _AiGiftSearchScreenState();
}

class _AiGiftSearchScreenState extends ConsumerState<AiGiftSearchScreen> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _resultsKey = GlobalKey();
  int? _budget;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setText(String text) {
    final capped = text.length > AiSearchRepository.maxQuery ? text.substring(0, AiSearchRepository.maxQuery) : text;
    _query.value = TextEditingValue(text: capped, selection: TextSelection.collapsed(offset: capped.length));
    if (_error != null) setState(() => _error = null);
  }

  static bool _contains(String text, String word) => text.toLowerCase().contains(word.toLowerCase());

  /// Occasion / recipient chips add their word to the description (or take
  /// it out again).
  void _toggleWord(String word) {
    final text = _query.text;
    if (_contains(text, word)) {
      final pattern = RegExp('[,،]?\\s*${RegExp.escape(word)}', caseSensitive: false);
      final next = text.replaceFirst(pattern, '').replaceFirst(RegExp(r'^[\s,،]+'), '');
      _setText(next);
      return;
    }
    final base = text.trimRight();
    if (base.isEmpty) {
      _setText(word);
      return;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final endsWithComma = base.endsWith(',') || base.endsWith('،');
    final next = endsWithComma ? '$base $word' : '$base${rtl ? '،' : ','} $word';
    if (next.length <= AiSearchRepository.maxQuery) _setText(next);
  }

  String? _validate(AppLocalizations l10n, String text) {
    if (text.isEmpty) return l10n.aiSearchQueryRequired;
    if (text.length < AiGiftSearchScreen.minQuery) return l10n.aiSearchQueryTooShort;
    return null;
  }

  void _search() {
    final l10n = AppLocalizations.of(context)!;
    final text = _query.text.trim();
    final error = _validate(l10n, text);
    setState(() => _error = error);
    if (error != null) return;
    FocusScope.of(context).unfocus();
    ref
        .read(aiSearchControllerProvider.notifier)
        .search(text, locale: Localizations.localeOf(context).languageCode, budgetMax: _budget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _resultsKey.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(aiSearchControllerProvider);
    final loading = state.phase == AiSearchPhase.loading;
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    const side = EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal);

    final occasions = [
      l10n.aiOccasionBirthday,
      l10n.aiOccasionAnniversary,
      l10n.aiOccasionGraduation,
      l10n.aiOccasionWedding,
      l10n.aiOccasionNewBaby,
      l10n.aiOccasionEid,
      l10n.aiOccasionThankYou,
    ];
    final recipients = [
      l10n.aiRecipientMum,
      l10n.aiRecipientDad,
      l10n.aiRecipientWife,
      l10n.aiRecipientHusband,
      l10n.aiRecipientSister,
      l10n.aiRecipientBrother,
      l10n.aiRecipientFriend,
      l10n.aiRecipientColleague,
      l10n.aiRecipientChild,
    ];

    final form = <Widget>[
      Padding(
        padding: side,
        child: GGInput(
          key: const ValueKey('ai-query'),
          label: l10n.aiGiftSearchHint,
          hint: l10n.aiSearchFieldHint,
          controller: _query,
          multiline: true,
          minLines: 3,
          maxLines: 6,
          maxLength: AiSearchRepository.maxQuery,
          showCounter: true,
          errorText: _error,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      ),
      _ChipSection(
        key: const ValueKey('ai-row-examples'),
        title: l10n.aiSearchExamplesTitle,
        chips: [
          for (var i = 0; i < aiSearchExamples.length; i++)
            // Long sentences: show the start, the tap fills in all of it.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
              child: CategoryChip(
                key: ValueKey('ai-example-$i'),
                label: aiSearchExamples[i].of(context),
                icon: Icons.lightbulb_outline_rounded,
                onTap: () => _setText(aiSearchExamples[i].of(context)),
              ),
            ),
        ],
      ),
      // Only these rows follow the text (selected = the word is in it).
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _query,
        builder: (context, value, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChipSection(
              key: const ValueKey('ai-row-occasion'),
              title: l10n.aiSearchOccasion,
              chips: [
                for (final word in occasions)
                  CategoryChip(
                    label: word,
                    selected: _contains(value.text, word),
                    onTap: () => _toggleWord(word),
                  ),
              ],
            ),
            _ChipSection(
              key: const ValueKey('ai-row-recipient'),
              title: l10n.aiSearchRecipient,
              chips: [
                for (final word in recipients)
                  CategoryChip(
                    label: word,
                    selected: _contains(value.text, word),
                    onTap: () => _toggleWord(word),
                  ),
              ],
            ),
          ],
        ),
      ),
      _ChipSection(
        key: const ValueKey('ai-row-budget'),
        title: l10n.aiSearchBudget,
        chips: [
          CategoryChip(
            key: const ValueKey('ai-budget-any'),
            label: l10n.aiSearchAnyBudget,
            selected: _budget == null,
            onTap: () => setState(() => _budget = null),
          ),
          for (final amount in aiSearchBudgets)
            CategoryChip(
              key: ValueKey('ai-budget-$amount'),
              label: l10n.aiSearchUpTo(CurrencyFormatter.format(amount)),
              selected: _budget == amount,
              onTap: () => setState(() => _budget = amount),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Padding(
        padding: side,
        child: PrimaryButton(
          key: const ValueKey('ai-find-gifts'),
          label: l10n.aiSearchFindGifts,
          icon: Icons.auto_awesome_rounded,
          isLoading: loading,
          onPressed: _search,
        ),
      ),
    ];

    final results = <Widget>[];
    switch (state.phase) {
      case AiSearchPhase.idle:
        break;
      case AiSearchPhase.loading:
        results.add(const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
          sliver: SliverToBoxAdapter(child: SkeletonLoader.productGrid()),
        ));
      case AiSearchPhase.error:
        results.add(SliverToBoxAdapter(child: ErrorState(onRetry: _search)));
      case AiSearchPhase.done:
        final result = state.result!;
        final note = result.rateLimited
            ? InfoBanner(
                key: const ValueKey('ai-rate-limited'),
                message: l10n.aiSearchRateLimited,
                type: InfoBannerType.warning,
              )
            : result.usedFallback
                ? InfoBanner(key: const ValueKey('ai-fallback'), message: l10n.aiSearchFallbackNote)
                : null;
        if (note != null) {
          results.add(SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              0,
              AppSpacing.screenHorizontal,
              AppSpacing.md,
            ),
            sliver: SliverToBoxAdapter(child: note),
          ));
        }
        if (result.suggestions.isEmpty) {
          results.add(SliverToBoxAdapter(
            child: EmptyState(
              key: const ValueKey('ai-empty'),
              title: l10n.aiSearchNoResultsTitle,
              subtitle: l10n.aiSearchNoResultsBody,
              icon: Icons.search_off_rounded,
            ),
          ));
        } else {
          results
            ..add(SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                0,
                AppSpacing.screenHorizontal,
                AppSpacing.sm + AppSpacing.xs,
              ),
              sliver: SliverToBoxAdapter(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.aiSearchResultsTitle,
                    style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                  ),
                ),
              ),
            ))
            ..add(SliverPadding(
              padding: side,
              sliver: AiSuggestionGrid(suggestions: result.suggestions),
            ));
        }
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(
        title: l10n.aiGiftSearch,
        showBack: true,
        onBack: () => popOrGo(context, AppRoutes.mainTab(0)),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        // Tapping outside the field just hides the keyboard: not an action
        // for screen readers (it made the whole page an unlabelled button).
        excludeFromSemantics: true,
        child: CustomScrollView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              sliver: SliverList.list(children: form),
            ),
            SliverToBoxAdapter(key: _resultsKey, child: const SizedBox(height: AppSpacing.lg)),
            ...results,
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        ),
      ),
    );
  }
}

/// A titled, horizontally scrolling chip row that runs to the screen edges.
class _ChipSection extends StatelessWidget {
  const _ChipSection({super.key, required this.title, required this.chips});

  final String title;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
            child: Text(title, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: CategoryChip.height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
              itemCount: chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, i) => chips[i],
            ),
          ),
        ],
      ),
    );
  }
}
