import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'safety_status.dart';

/// Builds the application [ThemeData] from the design tokens.
///
/// Material defaults that would render text below 14sp are raised to
/// [AppTypography.minimumFontSize] (NFR-US-04).
ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    secondary: AppColors.interactive,
    onSecondary: AppColors.onPrimary,
    error: Color(0xFFD92D20),
    onError: AppColors.onPrimary,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.borderControl,
    outlineVariant: AppColors.border,
    surfaceContainerHighest: AppColors.canvas,
  );

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
  );
  const minimumControl = Size(AppSizes.touchTarget, AppSizes.touchTarget);

  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: color, width: width),
      );

  final critical = SafetyStatus.critical.palette;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    canvasColor: AppColors.surface,
    dividerColor: AppColors.border,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    textTheme: const TextTheme(
      displayLarge: AppTypography.display,
      displayMedium: AppTypography.display,
      displaySmall: AppTypography.display,
      headlineLarge: AppTypography.headline,
      headlineMedium: AppTypography.headline,
      headlineSmall: AppTypography.headline,
      titleLarge: AppTypography.title,
      titleMedium: AppTypography.subtitle,
      titleSmall: AppTypography.bodyStrong,
      bodyLarge: AppTypography.body,
      // Kept at 14 so existing unstyled text does not reflow.
      bodyMedium: AppTypography.caption,
      bodySmall: AppTypography.caption,
      labelLarge: AppTypography.label,
      labelMedium: AppTypography.label,
      labelSmall: AppTypography.label,
    ).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textSecondary,
        minimumSize: minimumControl,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        textStyle: AppTypography.label,
        shape: controlShape,
        elevation: 0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textSecondary,
        minimumSize: minimumControl,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        textStyle: AppTypography.label,
        shape: controlShape,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        disabledForegroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.borderControl),
        minimumSize: minimumControl,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        textStyle: AppTypography.label,
        shape: controlShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.interactive,
        minimumSize: minimumControl,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        textStyle: AppTypography.label,
        shape: controlShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: minimumControl),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: AppTypography.body.copyWith(color: AppColors.textSecondary),
      labelStyle: AppTypography.label.copyWith(
        color: AppColors.textSecondary,
      ),
      helperStyle: AppTypography.caption.copyWith(
        color: AppColors.textSecondary,
      ),
      errorStyle: AppTypography.caption.copyWith(color: critical.text),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      border: inputBorder(AppColors.borderControl),
      enabledBorder: inputBorder(AppColors.borderControl),
      focusedBorder: inputBorder(AppColors.interactive, 2),
      errorBorder: inputBorder(critical.strong),
      focusedErrorBorder: inputBorder(critical.strong, 2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: AppTypography.body.copyWith(color: AppColors.onInk),
      actionTextColor: SafetyStatus.pending.palette.onInk,
      shape: controlShape,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      titleTextStyle: AppTypography.title.copyWith(
        color: AppColors.textPrimary,
      ),
      contentTextStyle: AppTypography.body.copyWith(
        color: AppColors.textSecondary,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      dragHandleColor: AppColors.borderControl,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.onPrimary
            : AppColors.borderControl,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.interactive
            : AppColors.canvas,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.interactive
            : AppColors.borderControl,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.interactive,
      linearTrackColor: AppColors.border,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      textStyle: AppTypography.body.copyWith(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      textStyle: AppTypography.caption.copyWith(color: AppColors.onInk),
    ),
  );
}
