import 'package:flutter/material.dart';
import 'package:graphical_bsdgames/screens/hangman/hangman_screen.dart';
import 'package:graphical_bsdgames/screens/tetris/tetris_screen.dart';
import 'package:graphical_bsdgames/screens/boggle/boggle_screen.dart';
import 'package:graphical_bsdgames/screens/atc/atc_screen.dart';
import 'package:graphical_bsdgames/widgets/game_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final games = [
      _GameEntry(
        title: 'Hangman',
        description: 'Guess the word before the man is hanged',
        icon: Icons.person_outline,
        destination: const HangmanScreen(),
      ),
      _GameEntry(
        title: 'Boggle',
        description: 'Find as many words as you can in the grid',
        icon: Icons.grid_on,
        destination: const BoggleScreen(),
      ),
      _GameEntry(
        title: 'Tetris',
        description: 'Stack the falling blocks',
        icon: Icons.view_quilt,
        destination: const TetrisScreen(),
      ),
      _GameEntry(
        title: 'ATC',
        description: 'Guide aircraft safely through your airspace',
        icon: Icons.flight,
        destination: const AtcScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Graphical BSDGames')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 600 ? 2 : 1;
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.4,
            ),
            itemCount: games.length,
            itemBuilder: (context, i) {
              final g = games[i];
              return GameTile(
                title: g.title,
                description: g.description,
                icon: g.icon,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => g.destination),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _GameEntry {
  final String title;
  final String description;
  final IconData icon;
  final Widget destination;

  const _GameEntry({
    required this.title,
    required this.description,
    required this.icon,
    required this.destination,
  });
}
