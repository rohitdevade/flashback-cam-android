import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/screens/camera_screen.dart';

/// ═══════════════════════════════════════════════════════════════════════════════
/// COLD START OPTIMIZED MAIN.DART
///
/// COLD START OPTIMIZATION:
/// This main() function does absolute minimum work before runApp():
///
/// 1. WidgetsFlutterBinding.ensureInitialized() - required for Flutter
/// 2. SystemChrome settings - lightweight, non-blocking
/// 3. runApp() - starts the Flutter engine
///
/// NO heavy work happens here:
/// - NO AdMob SDK initialization
/// - NO Billing client connection
/// - NO Camera initialization
/// - NO Network calls
/// - NO Disk I/O beyond essential Flutter setup
///
/// All heavy work is deferred to AppState via phased initialization.
/// Target: main() to first frame in <500ms
/// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  // Cold start timing
  final startTime = DateTime.now();
  debugPrint('═══════════════════════════════════════════════════════════════');
  debugPrint('🚀 COLD START: main() started');
  debugPrint('═══════════════════════════════════════════════════════════════');

  // Required for Flutter - minimal overhead
  WidgetsFlutterBinding.ensureInitialized();

  // Enable edge-to-edge mode - lightweight system UI configuration
  // This is non-blocking and essential for UI appearance
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  // Set system UI overlay style - lightweight, non-blocking
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  final setupDuration = DateTime.now().difference(startTime);
  debugPrint(
      '⚡ COLD START: Pre-runApp setup complete in ${setupDuration.inMilliseconds}ms');

  // Launch the app - Flutter engine takes over from here
  // Heavy initialization is deferred to AppState.initPhase1/2
  runApp(const FlashbackCamApp());

  debugPrint('🎯 COLD START: runApp() called - Flutter engine starting');
}

class FlashbackCamApp extends StatelessWidget {
  const FlashbackCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('🏗️ COLD START: Building FlashbackCamApp widget tree');

    return ChangeNotifierProvider(
      // COLD START: AppState constructor only starts Phase 1 (lightweight init)
      // Camera and SDKs are initialized AFTER the first frame
      create: (_) {
        debugPrint('📦 COLD START: Creating AppState (Phase 1 starts)');
        return AppState();
      },
      child: MaterialApp(
        title: 'Flashback Cam',
        debugShowCheckedModeBanner: false,
        theme: FlashbackTheme.lightTheme,
        darkTheme: FlashbackTheme.darkTheme,
        themeMode: ThemeMode.dark,
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
