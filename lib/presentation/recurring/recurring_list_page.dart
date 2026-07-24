import 'package:flutter/material.dart';

/// Lista movimenti ricorrenti. Placeholder di M0: CRUD in Milestone M5.
class RecurringListPage extends StatelessWidget {
  const RecurringListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ricorrenze')),
      body: const Center(
        child: Text('Ricorrenze — in sviluppo (Milestone M5)'),
      ),
    );
  }
}
