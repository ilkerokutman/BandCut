import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setFullScreen(false);
    await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const BandCutApp());
}

/// Root widget for the BandCut rehearsal-splitter app.
class BandCutApp extends StatelessWidget {
  const BandCutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BandCut',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
