import 'package:flutter/material.dart';
import 'package:medirapid/core/routes/app_routes.dart';
import 'package:medirapid/core/services/session_service.dart';
import 'package:medirapid/features/auth/models/driver_verification_status.dart';
import 'package:medirapid/features/auth/providers/driver_verification_provider.dart';
import 'package:medirapid/features/driver/providers/driver_provider.dart';
import 'package:medirapid/features/driver/widgets/driver_page_scaffold.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DriverVerificationProvider.instance.refresh();
      DriverProvider.instance.refreshTrips();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = SessionService.instance.user;
    final verification = DriverVerificationProvider.instance;
    final driver = DriverProvider.instance;

    return DriverPageScaffold(
      title: 'My Profile',
      showBottomNavigationBar: false,
      actions: IconButton(
        tooltip: 'Dashboard',
        icon: const Icon(Icons.dashboard_outlined),
        onPressed: () =>
            Navigator.pushReplacementNamed(context, AppRoutes.driverHome),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: verification,
          builder: (context, _) {
            final status = verification.status;
            final statusStyle = _VerificationStyle.fromStatus(status);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                _ProfileHeader(
                  name: (user?.name.isNotEmpty ?? false)
                      ? user!.name
                      : 'Driver account',
                  subtitle: (user?.phone.isNotEmpty ?? false)
                      ? '+${user!.phone}'
                      : 'Emergency response partner',
                  statusLabel: statusStyle.shortLabel,
                  statusColor: statusStyle.foreground,
                ),
                const SizedBox(height: 20),
                _VerificationCard(
                  style: statusStyle,
                  note: status == DriverVerificationStatus.rejected
                      ? verification.reason
                      : null,
                  onPressed: () {
                    final route = status == DriverVerificationStatus.pending
                        ? AppRoutes.driverVerificationPending
                        : AppRoutes.driverVerification;
                    Navigator.pushNamed(context, route);
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Your activity',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: driver,
                  builder: (context, _) => Row(
                    children: [
                      Expanded(
                        child: _ActivityCard(
                          icon: Icons.route_outlined,
                          label: 'Completed trips',
                          value: '${driver.completedTrips.length}',
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActivityCard(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Total earnings',
                          value: '₹${driver.totalEarnings.toStringAsFixed(0)}',
                          color: const Color(0xFF0F9D72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Account',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                _AccountAction(
                  icon: Icons.description_outlined,
                  title: 'Verification documents',
                  subtitle: 'Review or submit your driver documents',
                  onTap: () => Navigator.pushNamed(
                    context,
                    status == DriverVerificationStatus.pending
                        ? AppRoutes.driverVerificationPending
                        : AppRoutes.driverVerification,
                  ),
                ),
                const SizedBox(height: 10),
                _AccountAction(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  subtitle: 'Notifications, privacy, and account options',
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.driverSettings),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.subtitle,
    required this.statusLabel,
    required this.statusColor,
  });

  final String name;
  final String subtitle;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1749A6), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.medical_services_outlined,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.style,
    required this.onPressed,
    this.note,
  });

  final String? note;
  final _VerificationStyle style;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(style.icon, color: style.foreground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Driver verification',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      style.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(
              'Reason: $note',
              style: TextStyle(
                color: style.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: style.foreground,
                side: BorderSide(color: style.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(style.actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF2563EB)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _VerificationStyle {
  const _VerificationStyle({
    required this.shortLabel,
    required this.description,
    required this.actionLabel,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final String shortLabel;
  final String description;
  final String actionLabel;
  final IconData icon;
  final Color foreground;
  final Color background;
  final Color border;

  factory _VerificationStyle.fromStatus(DriverVerificationStatus status) {
    return switch (status) {
      DriverVerificationStatus.notStarted => const _VerificationStyle(
        shortLabel: 'Not submitted',
        description: 'Submit your documents to start the review.',
        actionLabel: 'Start verification',
        icon: Icons.assignment_outlined,
        foreground: Color(0xFF1D4ED8),
        background: Color(0xFFEFF6FF),
        border: Color(0xFFBFDBFE),
      ),
      DriverVerificationStatus.pending => const _VerificationStyle(
        shortLabel: 'Under review',
        description: 'Your documents are being reviewed.',
        actionLabel: 'View review status',
        icon: Icons.hourglass_top_rounded,
        foreground: Color(0xFF9A6700),
        background: Color(0xFFFFF8E7),
        border: Color(0xFFF3D58A),
      ),
      DriverVerificationStatus.approved => const _VerificationStyle(
        shortLabel: 'Verified',
        description: 'Your driver account is approved.',
        actionLabel: 'View documents',
        icon: Icons.verified_rounded,
        foreground: Color(0xFF15803D),
        background: Color(0xFFF0FDF4),
        border: Color(0xFFBBF7D0),
      ),
      DriverVerificationStatus.rejected => const _VerificationStyle(
        shortLabel: 'Action required',
        description: 'Review your documents and submit them again.',
        actionLabel: 'Update documents',
        icon: Icons.error_outline_rounded,
        foreground: Color(0xFFB42318),
        background: Color(0xFFFFF1F0),
        border: Color(0xFFFECACA),
      ),
    };
  }
}
