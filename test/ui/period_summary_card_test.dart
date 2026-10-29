import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/models/entry_filter.dart';
import 'package:know_finance/ui/widgets/period_summary_card.dart';

Widget _card({double income = 397700, double expense = 343750, double loansIn = 0, double loansOut = 40000}) =>
    MaterialApp(
      home: Scaffold(
        body: PeriodSummaryCard(
          income: income,
          expense: expense,
          loansIn: loansIn,
          loansOut: loansOut,
          home: 'PKR',
          label: leftLabel(DatePreset.thisMonth),
        ),
      ),
    );

Finder _semantics(String label) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

void main() {
  testWidgets('shows share spent, net, compact flows and the loans chip', (tester) async {
    await tester.pumpWidget(_card());
    expect(find.text('86%'), findsOneWidget);
    expect(find.text('spent'), findsOneWidget);
    expect(find.text('Left this month'), findsOneWidget);
    expect(find.text('+Rs 53,950'), findsOneWidget);
    expect(find.text('Rs 397.7K'), findsOneWidget);
    expect(find.text('Rs 343.8K'), findsOneWidget);
    expect(find.text('Loans out Rs 40K'), findsOneWidget);
    expect(find.textContaining('Loans in'), findsNothing);
    expect(_semantics('Income PKR 397,700'), findsOneWidget);
    expect(_semantics('Expenses PKR 343,750'), findsOneWidget);
  });

  testWidgets('shows the real percentage when spending exceeds income', (tester) async {
    await tester.pumpWidget(_card(income: 35000, expense: 39200, loansOut: 0));
    expect(find.text('112%'), findsOneWidget);
    expect(find.text('−Rs 4,200'), findsOneWidget);
    expect(find.textContaining('Loans'), findsNothing);
  });

  testWidgets('shows a dash without income', (tester) async {
    await tester.pumpWidget(_card(income: 0, expense: 1200, loansIn: 5000));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('spent'), findsNothing);
    expect(find.text('Loans out Rs 40K'), findsOneWidget);
    expect(find.text('Loans in Rs 5K'), findsOneWidget);
  });

  testWidgets('tapping the card shows exact figures', (tester) async {
    await tester.pumpWidget(_card(loansIn: 2500));
    await tester.tap(find.byType(PeriodSummaryCard));
    await tester.pumpAndSettle();
    expect(find.text('PKR 397,700'), findsOneWidget);
    expect(find.text('PKR 343,750'), findsOneWidget);
    expect(find.text('PKR 2,500'), findsOneWidget);
    expect(find.text('PKR 40,000'), findsOneWidget);
    expect(find.text('+Rs 53,950'), findsNWidgets(2));
  });
}
