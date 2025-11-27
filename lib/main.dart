import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/screens/camera_screen.dart';

void main() {
  print('===== MAIN STARTED =====');

  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );

  // Hide system UI overlays for full-screen camera experience
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
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
            data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
            child: child!,
          );
        },
      ),
    );
  }
}
