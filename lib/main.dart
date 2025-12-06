import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/screens/camera_screen.dart';

void main() {
  print('===== MAIN STARTED =====');

  WidgetsFlutterBinding.ensureInitialized();

  // Use edge-to-edge mode for Android 15+ compatibility
  // This replaces deprecated setStatusBarColor/setNavigationBarColor APIs
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  // Configure system UI overlay style for edge-to-edge
  // On Android 15+, these are hints rather than hard settings
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    // Use transparent to let content draw behind system bars
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    // For Android 15+ edge-to-edge, navigation bar should be transparent
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  print('===== ABOUT TO RUN APP =====');
  runApp(const FlashbackCamApp());
}

class FlashbackCamApp extends StatelessWidget {
  const FlashbackCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('===== BUILDING FLASHBACK CAM APP =====');

    return ChangeNotifierProvider(
      create: (_) {
        print('===== CREATING APP STATE =====');
        return AppState();
      },
      child: MaterialApp(
        title: 'Flashback Cam',
        debugShowCheckedModeBanner: false,
        theme: FlashbackTheme.lightTheme,
        darkTheme: FlashbackTheme.darkTheme,
        themeMode: ThemeMode.dark, // Default to dark theme as per spec
        home: const CameraScreen(),
        routes: {
          '/camera': (context) => const CameraScreen(),
        },
        // Global error handling
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
            ),
            child: child!,
          );
        },
      ),
    );
  }
}
