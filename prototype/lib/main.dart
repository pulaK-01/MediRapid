import 'package:flutter/material.dart';
import 'package:medirapid/app.dart';
import 'package:medirapid/core/routes/app_routes.dart';
import 'package:medirapid/core/theme/app_theme.dart';
import 'package:medirapid/features/auth/screens/driver_verification_pending_screen.dart';
import 'package:medirapid/features/auth/screens/driver_verification_screen.dart';
import 'package:medirapid/features/auth/screens/role_selection_screen.dart';
import 'package:medirapid/features/driver/screens/driver_current_trip_flow_screen.dart';
import 'package:medirapid/features/driver/screens/driver_dispatch_screen.dart';
import 'package:medirapid/features/driver/screens/driver_home_screen.dart';
import 'package:medirapid/features/driver/screens/driver_profile_screen.dart';
import 'package:medirapid/features/driver/screens/driver_settings_screen.dart';
import 'package:medirapid/features/driver/screens/driver_trip_history_screen.dart';
import 'package:medirapid/features/patient/screens/patient_home_screen.dart';
import 'package:medirapid/features/patient/screens/patient_settings_screen.dart';

void main() {
  runApp(
    MediRapid(
      initialRoute: AppRoutes.driverVerification,
      routes: {
        AppRoutes.roleSelection: (_) => const RoleSelectionScreen(),
        AppRoutes.patientHome: _withTheme(
          AppTheme.patientTheme,
          (_) => const PatientHomeScreen(),
        ),
        AppRoutes.patientSettings: _withTheme(
          AppTheme.patientTheme,
          (_) => const PatientSettingsScreen(),
        ),
        AppRoutes.driverVerification: _withTheme(
          AppTheme.driverTheme,
          (_) => const DriverVerificationScreen(),
        ),
        AppRoutes.driverVerificationPending: _withTheme(
          AppTheme.driverTheme,
          (_) => const DriverVerificationPendingScreen(),
        ),
        AppRoutes.driverHome: _withTheme(
          AppTheme.driverTheme,
          (_) => const DriverAccessGuard(child: DriverHomeScreen()),
        ),
        AppRoutes.driverDispatch: _withTheme(
          AppTheme.driverTheme,
          (_) => const DriverAccessGuard(child: DriverDispatchScreen()),
        ),
        AppRoutes.driverCurrentTripFlow: _withTheme(
          AppTheme.driverTheme,
          (_) => const DriverAccessGuard(child: DriverCurrentTripFlowScreen()),
        ),
        AppRoutes.driverTripHistory: _withTheme(
          AppTheme.driverTheme,
          (_) => const DriverAccessGuard(child: DriverTripHistoryPage()),
        ),
        AppRoutes.driverProfile: _withTheme(
          AppTheme.driverTheme,
          (_) => const DriverProfileScreen(),
        ),
        AppRoutes.driverSettings: _withTheme(
          AppTheme.driverTheme,
          (_) => const DriverSettingsScreen(),
        ),
      },
    ),
  );
}

WidgetBuilder _withTheme(ThemeData theme, WidgetBuilder builder) {
  return (context) => Theme(data: theme, child: builder(context));
}
