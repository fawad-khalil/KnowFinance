import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/currency.dart';
import '../../models/enums.dart';
import '../../services/analytics.dart';
import '../../services/investment_analytics.dart';
import '../../state/providers.dart';
import '../chart_colors.dart';
import '../widgets/breakdown_pie.dart';
import 'investment_detail_screen.dart';

/// Builds holdings from the investments and their linked entries.
final investmentAnalyticsProvider = Provider<AsyncValue<InvestmentAnalytics>>((ref) {
  final inv = ref.watch(investmentsProvider);
  final linked = ref.watch(investmentEntriesProvider);
  final home = ref.watch(homeCurrencyProvider);
  if (inv.hasError) return AsyncValue.error(inv.error!, inv.stackTrace ?? StackTrace.empty);
  if (linked.hasError) return AsyncValue.error(linked.error!, linked.stackTrace ?? StackTrace.empty);
  if (!inv.hasValue || !linked.hasValue) return const AsyncValue.loading();
  return AsyncValue.data(InvestmentAnalytics(inv.value!, linked.value!, home));
});

class InvestmentsScreen extends ConsumerStatefulWidget {
  const InvestmentsScreen({super.key});

  @override
  ConsumerState<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends ConsumerState<InvestmentsScreen> {
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Prices are fetched at most once a day unless refreshed by hand.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(force: false));
  }

  Future<void> _refresh({required bool force}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final updated = await ref.read(priceServiceProvider).refresh(ref.read(homeCurrencyProvider), force: force);
    if (!mounted) return;
    setState(() => _refreshing = false);
    if (updated > 0) ref.read(dataVersionProvider.notifier).bump();
    if (force) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(updated > 0
            ? 'Updated ${updated == 1 ? '1 price' : '$updated prices'}.'
            : 'No prices updated. Check your connection, or add a price feed to an asset.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(investmentAnalyticsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assets & investments'),
        actions: [
          _refreshing
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  tooltip: 'Refresh market prices',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _refresh(force: true),
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-investment',
        onPressed: () => InvestmentFormSheet.open(context),
        icon: const Icon(Icons.add),
        label: const Text('Asset'),
      ),
      body: analytics.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (a) => a.holdings.isEmpty ? const _Empty() : _Portfolio(analytics: a),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.trending_up, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Track your assets and what they earn', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Add gold, silver, oil, crypto, stocks, a plot or anything else you own. Link the expenses that bought '
              'it and the income it brought back (sales, dividends, rent) to see your profit or loss. Gold, silver, '
              'oil and crypto are valued at today\'s market price.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Portfolio extends StatelessWidget {
  const _Portfolio({required this.analytics});

  final InvestmentAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    final colors = ChartColors.of(context);
    final byType = a.investedByType().entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    final open = a.holdings.where((h) => !h.investment.closed).toList();
    final closed = a.holdings.where((h) => h.investment.closed).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        _SummaryCard(summary: a.summary(), currency: a.home),
        if (byType.length > 1)
          _Card(
            title: 'Where it is invested',
            child: BreakdownPie(
              slices: BreakdownPie.fold(
                [for (final t in byType) Share(t.key, t.key.label, t.value, 1)],
                (i, _) => colors.slot(i),
                colors.other,
              ),
              currency: a.home,
              centerLabel: 'Invested',
            ),
          ),
        if (open.any((h) => h.priceChange(a.home) != null))
          _Card(
            title: 'Purchase vs market',
            child: Column(
              children: [
                for (final h in open.where((h) => h.priceChange(a.home) != null)) _MarketRow(holding: h, home: a.home),
              ],
            ),
          ),
        if (open.isNotEmpty) _HoldingList(title: 'Open', holdings: open, home: a.home),
        if (closed.isNotEmpty) _HoldingList(title: 'Closed', holdings: closed, home: a.home),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.currency});

  final PortfolioSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final theme = Theme.of(context);
    return _Card(
      title: 'Portfolio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Profit / loss', style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    signedMoney(s.profit, currency),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: plColor(context, s.profit)),
                  ),
                ),
              ),
              if (s.roi != null) ...[
                const SizedBox(width: 8),
                ChangeChip(value: s.roi! * 100),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            runSpacing: 12,
            children: [
              StatTile(label: 'Invested', value: compactMoney(s.invested, currency)),
              StatTile(label: 'Cash returned', value: compactMoney(s.returned, currency)),
              StatTile(label: 'Current value', value: compactMoney(s.value, currency)),
              StatTile(label: 'Dividends & rent', value: compactMoney(s.income, currency)),
              StatTile(
                label: 'Annual return',
                value: s.annualReturn == null ? '–' : '${(s.annualReturn! * 100).toStringAsFixed(1)}%',
              ),
            ],
          ),
          if (s.unvalued > 0) ...[
            const SizedBox(height: 12),
            Text(
              '${s.unvalued} open ${s.unvalued == 1 ? 'holding has' : 'holdings have'} no current value and '
              "${s.unvalued == 1 ? "isn't" : "aren't"} counted. Open it and set what it's worth today.",
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _HoldingList extends StatelessWidget {
  const _HoldingList({required this.title, required this.holdings, required this.home});

  final String title;
  final List<Holding> holdings;
  final String home;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          for (final h in holdings) _HoldingTile(holding: h, home: home),
        ],
      ),
    );
  }
}

class _HoldingTile extends StatelessWidget {
  const _HoldingTile({required this.holding, required this.home});

  final Holding holding;
  final String home;

  @override
  Widget build(BuildContext context) {
    final h = holding;
    final theme = Theme.of(context);
    final profit = h.profit(home);
    final roi = h.roi(home);
    final value = h.valueIn(home);
    final unit = h.investment.unit;
    final sub = [
      h.investment.type.label,
      if (h.tracksQuantity && unit != null) '${formatQuantity(h.held)} ${unit.label}',
      'in ${compactMoney(h.invested, home)}',
      if (h.returned > 0) 'back ${compactMoney(h.returned, home)}',
      if (!h.investment.closed && value != null) 'worth ${compactMoney(value, home)}',
    ].join(' · ');
    return ListTile(
      onTap: () => InvestmentDetailScreen.open(context, h.investment.id!),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(assetIcon(h.investment.type), color: theme.colorScheme.onSecondaryContainer, size: 20),
      ),
      title: Text(h.investment.name),
      subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            profit == null ? 'Set value' : signedMoney(profit, home, compact: true),
            style: theme.textTheme.titleSmall?.copyWith(
              color: profit == null ? theme.colorScheme.error : plColor(context, profit),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (roi != null)
            Text('${roi >= 0 ? '+' : '−'}${(roi.abs() * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.bodySmall?.copyWith(color: plColor(context, profit!))),
        ],
      ),
    );
  }
}

/// Average price paid per unit next to today's market price, with bars for
/// what the units held cost and what they are worth now.
class _MarketRow extends StatelessWidget {
  const _MarketRow({required this.holding, required this.home});

  final Holding holding;
  final String home;

  @override
  Widget build(BuildContext context) {
    final h = holding;
    final theme = Theme.of(context);
    final unit = h.investment.unit!.label;
    final change = h.priceChange(home)!;
    final cost = h.costOfHeld ?? 0, value = h.marketValue(home) ?? 0;
    final max = cost > value ? cost : value;
    final colors = ChartColors.of(context);
    Widget bar(String label, double v, Color c) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              SizedBox(width: 64, child: Text(label, style: theme.textTheme.labelSmall)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: max <= 0 ? 0 : v / max,
                    minHeight: 10,
                    color: c,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              SizedBox(
                width: 84,
                child: Text(compactMoney(v, home), textAlign: TextAlign.right, style: theme.textTheme.labelMedium),
              ),
            ],
          ),
        );
    return InkWell(
      onTap: () => InvestmentDetailScreen.open(context, h.investment.id!),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(h.investment.name, style: theme.textTheme.titleSmall)),
                ChangeChip(value: change * 100),
              ],
            ),
            Text(
              'Paid ${formatMoney(h.avgBuyPrice!.roundToDouble(), home)}/$unit · '
              'market ${formatMoney(h.marketPrice(home)!.roundToDouble(), home)}/$unit',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            bar('Cost', cost, colors.other),
            bar('Market', value, plColor(context, value - cost)),
          ],
        ),
      ),
    );
  }
}

// Shared bits used by the detail screen too.

/// "2", "2.5" or "0.125": up to four decimals, no trailing zeros.
String formatQuantity(double q) {
  final s = q.toStringAsFixed(4);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

IconData assetIcon(AssetType t) => switch (t) {
      AssetType.stocks => Icons.candlestick_chart_outlined,
      AssetType.fund => Icons.pie_chart_outline,
      AssetType.property => Icons.home_work_outlined,
      AssetType.gold => Icons.diamond_outlined,
      AssetType.silver => Icons.diamond_outlined,
      AssetType.commodity => Icons.oil_barrel_outlined,
      AssetType.vehicle => Icons.directions_car_outlined,
      AssetType.crypto => Icons.currency_bitcoin,
      AssetType.deposit => Icons.savings_outlined,
      AssetType.business => Icons.storefront_outlined,
      AssetType.other => Icons.category_outlined,
    };

Color plColor(BuildContext context, double v) =>
    v >= 0 ? Colors.green.shade600 : Theme.of(context).colorScheme.error;

String signedMoney(double v, String currency, {bool compact = false}) {
  final s = compact ? compactMoney(v.abs(), currency) : formatMoney(v.abs(), currency);
  return '${v >= 0 ? '+' : '−'}$s';
}

/// A small green or red pill showing a percentage.
class ChangeChip extends StatelessWidget {
  const ChangeChip({super.key, required this.value, this.suffix = '%'});

  final double value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final color = plColor(context, value);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(
        '${value >= 0 ? '+' : '−'}${value.abs().toStringAsFixed(1)}$suffix',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.width = 150});

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
