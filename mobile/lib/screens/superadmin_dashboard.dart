import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class SuperadminDashboard extends StatelessWidget {
  const SuperadminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DormMate — Superadmin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => await Provider.of<AuthService>(context, listen: false).signOut(),
            tooltip: 'Sign out',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          const Text('Monthly metrics (placeholder)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Collected: ₱120,000 — On-time rate: 87%'))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('SMS delivered: 340 — Failed: 4'))),
          const SizedBox(height: 24),
          const Text('User/flow diagram placeholder')
        ]),
      ),
    );
  }
}
