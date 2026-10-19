import 'package:flutter/material.dart';

/// Charts arrive in step 2 of the plan.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: const Center(child: Text('Charts are coming next.')),
    );
  }
}
