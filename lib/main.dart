import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'src/state/sibi_state.dart';
import 'src/ui/dashboard_screen.dart';
import 'src/ui/theme.dart';
import 'src/ml/platform_classifier.dart';
import 'src/ml/classifier_bridge.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Dukung orientasi layar portrait dan landscape untuk kecocokan perangkat mobile & tablet
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final classifier = createClassifier();
  await classifier.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SibiState()),
      ],
      child: SibiTranslateApp(classifier: classifier),
    ),
  );
}

class SibiTranslateApp extends StatelessWidget {
  final PlatformClassifier classifier;
  
  const SibiTranslateApp({super.key, required this.classifier});

  @override
  Widget build(BuildContext context) {
    return Consumer<SibiState>(
      builder: (context, state, child) {
        return MaterialApp(
          title: 'SIBI Translate',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: DashboardScreen(classifier: classifier),
        );
      },
    );
  }
}
