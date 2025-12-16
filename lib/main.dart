import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/screens/camera_screen.dart';

void main() {
  print('===== MAIN STARTED =====');

  WidgetsFlutterBinding.ensureInitialized();

  // Enable edge-to-edge mode (configured in Android styles.xml for Android 15+)
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  // Set only the icon brightness for system UI
  // Colors are now handled by Android theme (non-deprecated approach)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.light,
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
