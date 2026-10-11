import 'package:flutter/material.dart';

/// Design tokens – deep navy night-sky palette with amber/cyan accents.
class AppColors {
  static const bg = Color(0xFF070B17);
  static const surface = Color(0xFF0F1629);
  static const surfaceHi = Color(0xFF172038);
  static const stroke = Color(0x1FFFFFFF);
  static const text = Color(0xFFEAF0FF);
  static const textDim = Color(0xFF8A96B8);
  static const amber = Color(0xFFFFB547);
  static const cyan = Color(0xFF3DD9EB);
  static const violet = Color(0xFF8B7CFF);
  static const green = Color(0xFF3EE08F);
  static const red = Color(0xFFFF5C7A);

  static const accentGradient = LinearGradient(
    colors: [Color(0xFFFFB547), Color(0xFFFF7A59)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.amber,
      secondary: AppColors.cyan,
      surface: AppColors.surface,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHi,
      contentTextStyle: TextStyle(color: AppColors.text),
    ),
  );
}

/// Frosted glass card used across the app.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceHi.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.stroke),
      ),
      child: child,
    );
  }
}
