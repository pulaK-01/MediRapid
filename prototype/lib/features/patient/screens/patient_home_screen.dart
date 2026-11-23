import 'package:flutter/material.dart';
import 'package:medirapid/core/routes/app_routes.dart';
import 'package:medirapid/features/patient/models/emergency_model.dart';
import 'package:medirapid/features/patient/providers/patient_provider.dart';
import 'package:medirapid/features/patient/widgets/emergency_button.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key, this.provider});

  /// Defaults to [PatientProvider.instance]; tests inject their own.
  final PatientProvider? provider;

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  late final PatientProvider _patient =
      widget.provider ?? PatientProvider.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _patient.refresh();
    });
  }

  Future<void> _onSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request an ambulance?'),
        content: const Text(
          'Your current location will be shared with nearby ambulance drivers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final sent = await _patient.sendSos();
    if (!mounted || !sent) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency sent! Help is on the way.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _onCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: const Text('No ambulance has accepted yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _patient.cancel(reason: 'Cancelled by patient');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Are you in emergency ?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'My requests',
            icon: const Icon(Icons.history),
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.patientHistory),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.patientSettings);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _patient,
          builder: (context, _) {
            final emergency = _patient.emergency;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      kToolbarHeight -
                      MediaQuery.of(context).padding.vertical -
                      40,
                ),
                child: Center(
                  child: emergency == null
                      ? _buildSos(context)
                      : _TrackingPanel(
                          emergency: emergency,
                          connectionLost: _patient.connectionLost,
                          canCancel: _patient.canCancel,
                          isCancelling: _patient.isCancelling,
                          error: _patient.error,
                          onCancel: _onCancel,
                          onDone: _patient.dismissFinished,
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSos(BuildContext context) {
    final error = _patient.error;
    final location = _patient.location;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Column(
          children: [
            Text(
              "Press the 'SOS' button for help",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 1),
            Text(
              'An ambulance will be requested',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        EmergencyButton(onPressed: _onSos, isLoading: _patient.isSending),
        const SizedBox(height: 40),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: error != null ? Colors.red[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: error != null ? Colors.red : Colors.grey[300]!,
            ),
          ),
          child: Column(
            children: [
              Icon(
                error != null ? Icons.error_outline : Icons.location_on,
                size: 40,
                color: error != null ? Colors.red : Colors.orange,
              ),
              const SizedBox(height: 10),
              Text(
                _patient.statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: error != null ? Colors.red : Colors.black87,
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 6),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              if (location != null && error == null) ...[
                const SizedBox(height: 8),
                Text(
                  'Lat ${location.latitude.toStringAsFixed(6)}, '
                  'Lng ${location.longitude.toStringAsFixed(6)} '
                  '(±${location.accuracy.toStringAsFixed(0)} m)',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TrackingPanel extends StatelessWidget {
  const _TrackingPanel({
    required this.emergency,
    required this.connectionLost,
    required this.canCancel,
    required this.isCancelling,
    required this.error,
    required this.onCancel,
    required this.onDone,
  });

  final Emergency emergency;
  final bool connectionLost;
  final bool canCancel;
  final bool isCancelling;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  static const _steps = [
    'Request sent',
    'Ambulance assigned',
    'Ambulance arrived',
    'On the way to hospital',
  ];

  @override
  Widget build(BuildContext context) {
    final status = emergency.status;
    final cancelled = status == EmergencyStatus.cancelled;
    final color = cancelled
        ? Colors.grey
        : status == EmergencyStatus.completed
        ? Colors.green
        : Colors.red;
    final driver = emergency.driver;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          cancelled
              ? Icons.cancel_outlined
              : status == EmergencyStatus.completed
              ? Icons.check_circle_outline
              : Icons.local_hospital,
          size: 72,
          color: color,
        ),
        const SizedBox(height: 12),
        Text(
          status.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          status.message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
        if (status == EmergencyStatus.requested) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (connectionLost) ...[
          const SizedBox(height: 12),
          const Text(
            'Connection lost. Reconnecting…',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.orange),
          ),
        ],
        if (!cancelled) ...[
          const SizedBox(height: 20),
          for (var i = 0; i < _steps.length; i++)
            _StepRow(
              label: _steps[i],
              done: status.progress > i,
              current: status.progress == i,
            ),
        ],
        if (driver != null) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.airport_shuttle_rounded),
              ),
              title: Text(driver.name.isEmpty ? 'Your driver' : driver.name),
              subtitle: Text(
                [
                  if (driver.vehicleNumber.isNotEmpty) driver.vehicleNumber,
                  if (driver.phone.isNotEmpty) '+${driver.phone}',
                ].join(' · '),
              ),
            ),
          ),
        ],
        if (status == EmergencyStatus.completed && emergency.fare != null) ...[
          const SizedBox(height: 8),
          Text(
            'Fare: ₹${emergency.fare!.toStringAsFixed(2)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 24),
        if (canCancel)
          OutlinedButton.icon(
            onPressed: isCancelling ? null : onCancel,
            icon: const Icon(Icons.close),
            label: Text(isCancelling ? 'Cancelling…' : 'Cancel request'),
          ),
        if (emergency.isTerminal)
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(cancelled ? 'Request again' : 'Done'),
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.current,
  });

  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle
                : current
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: done
                ? Colors.green
                : current
                ? Colors.red
                : Colors.black26,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight: current ? FontWeight.bold : FontWeight.normal,
              color: done || current ? Colors.black87 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}
