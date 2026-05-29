import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFF1B6CA8);

  static ThemeData get dark => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );
}
