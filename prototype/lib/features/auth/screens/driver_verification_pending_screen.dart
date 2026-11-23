import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medirapid/core/routes/app_routes.dart';
import 'package:medirapid/features/auth/providers/driver_verification_provider.dart';
import 'package:medirapid/features/driver/providers/driver_provider.dart';

class DriverVerificationPendingScreen extends StatefulWidget {
  const DriverVerificationPendingScreen({super.key});

  @override
  State<DriverVerificationPendingScreen> createState() =>
      _DriverVerificationPendingScreenState();
}

class _DriverVerificationPendingScreenState
    extends State<DriverVerificationPendingScreen> {
  final _verification = DriverVerificationProvider.instance;
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // The admin approves on the server; check every 10 s while this is open.
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _check(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await _verification.refresh();
    if (!mounted) return;
    setState(() => _checking = false);

    if (!ok) {
      if (!silent) _snack(_verification.error ?? 'Could not check your status.');
      return;
    }
    if (_verification.isApproved) {
      await DriverProvider.instance.restore(isAvailable: false);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.driverHome,
        (route) => false,
      );
    } else if (_verification.isRejected || !_verification.isPending) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.driverVerification,
        (route) => false,
      );
    } else if (!silent) {
      _snack('Still under review. We will let you in as soon as it is approved.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    surfaceTintColor: Colors.blue,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(
                        color: Color.fromARGB(255, 184, 211, 242),
                      ),
                    ),

                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(255, 212, 240, 222),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                    color: Color(0xFF15803D),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Documents uploaded',
                                    style: TextStyle(
                                      color: Color(0xFF166534),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFDE68A),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.pending_actions_rounded,
                              size: 62,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Verification pending',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0F172A),
                                ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Your documents have been submitted successfully.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: const Color(0xFF475569),
                                  height: 1.5,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'We’ll notify you after review.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF64748B),
                                  height: 1.5,
                                ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 18,
                                  color: Color(0xFF0EA5E9),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Processing time: usually within 24–48 hours',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF334155),
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.maxFinite,
                            child: OutlinedButton.icon(
                              icon: _checking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                              label: const Text('Check status'),
                              onPressed: _checking ? null : _check,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.maxFinite,
                            child: FilledButton.icon(
                              icon: const Icon(Icons.done_all_rounded),
                              label: const Text('Go to Profile'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 20,
                                ),
                              ),
                              onPressed: () {
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  AppRoutes.driverProfile,
                                  (route) => false,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
