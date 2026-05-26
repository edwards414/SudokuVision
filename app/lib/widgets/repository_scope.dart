import 'package:flutter/widgets.dart';

import '../data/sudoku_repository.dart';

class RepositoryScope extends InheritedNotifier<SudokuRepository> {
  const RepositoryScope({
    super.key,
    required SudokuRepository repository,
    required super.child,
  }) : super(notifier: repository);

  static SudokuRepository of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RepositoryScope>();
    assert(scope != null, 'RepositoryScope missing in widget tree');
    return scope!.notifier!;
  }
}
