import 'package:flutter/material.dart';
import 'package:graphical_bsdgames/screens/home_screen.dart';
import 'package:graphical_bsdgames/theme/app_theme.dart';

void main() {
  runApp(const BsdGamesApp());
}

class BsdGamesApp extends StatelessWidget {
  const BsdGamesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Graphical BSDGames',
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
