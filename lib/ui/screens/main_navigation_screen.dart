import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import 'cached_screen.dart';
import 'import_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final _pages = const [
    LibraryScreen(),
    CachedScreen(),
    ImportScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          BottomNavigationBar(
            currentIndex: _currentIndex,
            type: BottomNavigationBarType.fixed,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.music_note_rounded),
                activeIcon: Icon(Icons.music_note_rounded, color: AppTheme.primaryAccent),
                label: 'Медиатека',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.offline_pin_rounded),
                activeIcon: Icon(Icons.offline_pin_rounded, color: AppTheme.primaryAccent),
                label: 'Оффлайн',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.add_circle_outline_rounded),
                activeIcon: Icon(Icons.add_circle_rounded, color: AppTheme.primaryAccent),
                label: 'Добавить',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings_rounded, color: AppTheme.primaryAccent),
                label: 'Настройки',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
