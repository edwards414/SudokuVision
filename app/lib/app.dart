import 'package:flutter/cupertino.dart';

import 'data/sudoku_repository.dart';
import 'pages/camera_page.dart';
import 'pages/review_page.dart';
import 'pages/settings_page.dart';
import 'pages/solution_page.dart';
import 'widgets/repository_scope.dart';

class SudokuVisionApp extends StatefulWidget {
  const SudokuVisionApp({super.key, SudokuRepository? repository})
      : _repository = repository;

  final SudokuRepository? _repository;

  @override
  State<SudokuVisionApp> createState() => _SudokuVisionAppState();
}

class _SudokuVisionAppState extends State<SudokuVisionApp> {
  late final SudokuRepository _repository = widget._repository ?? SudokuRepository();

  @override
  void dispose() {
    if (widget._repository == null) _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryScope(
      repository: _repository,
      child: const CupertinoApp(
        debugShowCheckedModeBanner: false,
        title: 'Sudoku Vision',
        theme: CupertinoThemeData(
          brightness: Brightness.light,
          primaryColor: CupertinoColors.activeBlue,
        ),
        home: HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final CupertinoTabController _tabs = CupertinoTabController();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _switchTo(int index) {
    setState(() => _tabs.index = index);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      controller: _tabs,
      tabBar: CupertinoTabBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.camera),
            label: '相機',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.square_grid_3x2),
            label: '辨識',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.checkmark_seal),
            label: '解答',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: '設定',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) {
            return switch (index) {
              0 => const CameraPage(),
              1 => ReviewPage(onSolved: () => _switchTo(2)),
              2 => const SolutionPage(),
              _ => const SettingsPage(),
            };
          },
        );
      },
    );
  }
}
