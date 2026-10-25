import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../data/dashboard_kpis.dart';

/// Grey placeholder block shown while a number or list loads.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 16});
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('skeleton'),
        width: width,
        height: height,
        decoration: BoxDecoration(color: AppColors.field(context), borderRadius: BorderRadius.circular(AppRadius.xs)),
      );
}

/// Inline "couldn't load" with a Retry button (one failing tile never blanks the page).
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.onRetry, this.message = 'Couldn’t load'});
  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpacing.xs, children: [
      Icon(Icons.error_outline, size: 16, color: color),
      Text(message, style: TextStyle(color: color)),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ]);
  }
}

/// One KPI: label, value (skeleton while loading, error with retry).
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.onRetry,
    this.caption,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final AsyncValue<String> value;
  final VoidCallback onRetry;
  final String? caption;
  final VoidCallback? onTap;

  static const width = 228.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 20, color: AppColors.gold(context)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: AppSpacing.sm),
              // Grows when the inline error wraps onto two lines.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: value.isLoading || !(value.hasValue || value.hasError)
                      ? const SkeletonBox(width: 110, height: 26)
                      : value.hasError
                          ? InlineError(onRetry: onRetry)
                          : Text(value.requireValue,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
              if (caption != null)
                Text(caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Orders per Iraq day (SRS §9 Dashboard): gold bars, theme-aware axes.
class OrdersPerDayChart extends StatelessWidget {
  const OrdersPerDayChart({super.key, required this.days});
  final List<DayCount> days;

  static const height = 220.0;

  @override
  Widget build(BuildContext context) {
    final maxCount = days.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    final interval = maxCount <= 4 ? 1.0 : (maxCount / 4).ceilToDouble();
    final maxY = maxCount == 0 ? 4.0 : (maxCount / interval).ceil() * interval;
    final muted = TextStyle(color: AppColors.textMuted(context), fontSize: 11);
    final gold = AppColors.gold(context);
    final label = DateFormat('MMM d', 'en_US');
    final total = days.fold<int>(0, (n, d) => n + d.count);
    return Semantics(
      label: 'Orders per day, last ${days.length} days: $total orders',
      child: SizedBox(
        height: height,
        child: BarChart(
          key: const ValueKey('ordersPerDayChart'),
          BarChartData(
            maxY: maxY,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (_) => FlLine(color: AppColors.line(context), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: interval,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(NumberFormat.decimalPattern('en_US').format(value.round()), style: muted),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= days.length) return const SizedBox.shrink();
                    // Every other day (and always today) keeps the labels readable at 800 px.
                    final show = i == days.length - 1 || (days.length - 1 - i).isEven;
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(show ? '${days[i].day.day}' : '', style: muted),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.text(context),
                getTooltipItem: (group, _, rod, __) {
                  final d = days[group.x];
                  return BarTooltipItem(
                    '${label.format(d.day.date)}\n${d.count} order${d.count == 1 ? '' : 's'}',
                    TextStyle(color: AppColors.card(context), fontWeight: FontWeight.w600, fontSize: 12),
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < days.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: days[i].count.toDouble(),
                    color: gold,
                    width: 14,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xs)),
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
