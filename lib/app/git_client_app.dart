import 'package:flutter/material.dart';

import '../features/workbench/presentation/workbench_screen.dart';
import 'theme/app_theme.dart';

class GitClientApp extends StatelessWidget {
  const GitClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GitClient',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const WorkbenchScreen(),
    );
  }
}
