import 'package:flutter/material.dart';

class AppTheme {
  static final ThemeData patientTheme = _createTheme(Colors.red);
  static final ThemeData driverTheme = _createTheme(Colors.blueAccent);

  static ThemeData get theme => patientTheme;

  static ThemeData _createTheme(Color accentColor) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentColor,
        brightness: Brightness.light,
      ).copyWith(primary: accentColor, secondary: accentColor),
      primaryColor: accentColor,
      appBarTheme: AppBarTheme(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
    );
  }
}
