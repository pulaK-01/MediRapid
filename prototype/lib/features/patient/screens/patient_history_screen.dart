import 'package:flutter/material.dart';
import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/features/patient/models/emergency_model.dart';
import 'package:medirapid/features/patient/providers/patient_provider.dart';

class PatientHistoryScreen extends StatefulWidget {
  const PatientHistoryScreen({super.key, this.provider});

  final PatientProvider? provider;

  @override
  State<PatientHistoryScreen> createState() => _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends State<PatientHistoryScreen> {
  late final PatientProvider _patient =
      widget.provider ?? PatientProvider.instance;
  late Future<List<Emergency>> _future = _patient.loadHistory();

  Future<void> _reload() async {
    final next = _patient.loadHistory();
    setState(() => _future = next);
    try {
      await next;
    } on ApiException {
      // shown by the FutureBuilder
    }
  }

  String _formatDateTime(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}  '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My requests'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Emergency>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      error is ApiException
                          ? error.message
                          : 'Could not load your requests.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('No requests yet'));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final e = items[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      e.status == EmergencyStatus.completed
                          ? Icons.check_circle
                          : e.status == EmergencyStatus.cancelled
                          ? Icons.cancel
                          : Icons.local_hospital,
                      color: e.status == EmergencyStatus.completed
                          ? Colors.green
                          : e.status == EmergencyStatus.cancelled
                          ? Colors.grey
                          : Colors.red,
                    ),
                    title: Text(e.status.title),
                    subtitle: Text(
                      '${_formatDateTime(e.createdAt)}'
                      '${e.driver == null ? '' : '\n${e.driver!.name} · ${e.driver!.vehicleNumber}'}',
                    ),
                    isThreeLine: e.driver != null,
                    trailing: e.fare == null
                        ? null
                        : Text('₹${e.fare!.toStringAsFixed(0)}'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
