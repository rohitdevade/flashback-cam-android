import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' hide AppState;
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/models/app_settings.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/screens/pro_upgrade_screen.dart';
import 'package:flashback_cam/widgets/glass_container.dart';
import 'package:flashback_cam/widgets/camera_instructions_overlay.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _showDeveloperOptions = false;
  int _versionTapCount = 0;
  Map<String, bool> _capabilities = {};
  bool _isLoadingCapabilities = true;
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
    _loadCapabilities();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    final appState = context.read<AppState>();
    if (appState.isPro) return; // Don't show ads for pro users

    _bannerAd = appState.adService.createSettingsBannerAd();
    _bannerAd!.load().then((_) {
      if (mounted) {
        setState(() => _isBannerAdLoaded = true);
      }
    });
  }

  Future<void> _loadCapabilities() async {
    final appState = context.read<AppState>();
    final capabilities =
        await appState.cameraService.checkDetailedCapabilities();
    if (mounted) {
      setState(() {
        _capabilities = capabilities;
        _isLoadingCapabilities = false;
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final settings = appState.settings;
    final isPro = appState.isPro;

    return Scaffold(
      backgroundColor: AppColors.deepCharcoal,
      body: SafeArea(
        child: Column(
          children: [
            // Custom app bar with glassmorphism
            _buildTopBar(context),

            // Main content
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child:
                    _buildSettingsContent(context, appState, settings, isPro),
              ),
            ),

            // Banner ad at bottom (only for non-pro users)
            if (_isBannerAdLoaded && _bannerAd != null && !isPro)
              Container(
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsContent(BuildContext context, AppState appState,
      AppSettings settings, bool isPro) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recording Settings Section
          _buildSectionHeader('Recording Settings'),
          const SizedBox(height: 16),
          _buildRecordingSection(context, appState, settings, isPro),

          const SizedBox(height: 32),

          // Pro Plan Section
          _buildSectionHeader('Pro Plan'),
          const SizedBox(height: 16),
          _buildProSection(context, appState, isPro),

          const SizedBox(height: 32),

          // Device Capabilities Section (debug mode only)
          if (_showDeveloperOptions) ...[
            _buildSectionHeader('Device Capabilities'),
            const SizedBox(height: 16),
            _buildDeviceCapabilitiesSection(context, appState),
            const SizedBox(height: 32),
          ],

          // Device & Diagnostics Section (debug mode only)
          if (_showDeveloperOptions && appState.deviceCapabilities != null) ...[
            _buildSectionHeader('Device & Diagnostics'),
            const SizedBox(height: 16),
            _buildDiagnosticsSection(context, appState),
            const SizedBox(height: 32),
          ],

          // App Section
          _buildSectionHeader('App'),
          const SizedBox(height: 16),
          _buildAppSection(context, appState),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.electricBlue,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
    );
  }

  Widget _buildRecordingSection(BuildContext context, AppState appState,
      AppSettings settings, bool isPro) {
    return GlassContainer(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          _buildSettingTile(
            icon: Icons.history,
            title: 'Pre-roll Buffer',
            subtitle: '${settings.preRollSeconds} seconds',
            isLocked: !isPro && settings.preRollSeconds > 10,
            onTap: () => _showPreRollPicker(context, appState, settings, isPro),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          _buildSettingTile(
            icon: Icons.video_settings,
            title: 'Resolution',
            subtitle: settings.resolution,
            isLocked: !isPro && settings.resolution.toUpperCase() == '4K',
            onTap: () =>
                _showResolutionPicker(context, appState, settings, isPro),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          _buildSettingTile(
            icon: Icons.speed,
            title: 'Frame Rate',
            subtitle: '${settings.fps} fps',
            isLocked: !isPro && settings.fps == 60,
            onTap: () => _showFpsPicker(context, appState, settings, isPro),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          _buildSettingTile(
            icon: Icons.high_quality,
            title: 'Bitrate',
            subtitle: settings.bitrate,
            onTap: () => _showBitratePicker(context, appState, settings),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          _buildSwitchTile(
            icon: Icons.video_stable,
            title: 'Stabilization',
            subtitle: 'Reduce camera shake',
            value: settings.stabilization,
            onChanged: (value) => appState
                .updateSettings(settings.copyWith(stabilization: value)),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          _buildSwitchTile(
            icon: Icons.grid_on,
            title: 'Show Grid',
            subtitle: 'Display overlay grid lines',
            value: settings.showGrid,
            onChanged: (value) =>
                appState.updateSettings(settings.copyWith(showGrid: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildProSection(BuildContext context, AppState appState, bool isPro) {
    final proTier = appState.subscriptionService.currentUser.proTier;
    String planName = 'Free Plan';
    bool canUpgradeToLifetime = false;

    if (isPro && proTier != null) {
      final tierLower = proTier.toLowerCase();
      switch (tierLower) {
        case 'monthly':
          planName = 'Monthly Plan';
          canUpgradeToLifetime = true;
          break;
        case 'yearly':
          planName = 'Yearly Plan';
          canUpgradeToLifetime = true;
          break;
        case 'lifetime':
          planName = 'Lifetime Plan';
          break;
        default:
          planName = 'Pro Active';
      }
    }

    return GestureDetector(
      onTap: canUpgradeToLifetime
          ? () => _showLifetimeUpgradeDialog(context, appState)
          : null,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isPro
                        ? const LinearGradient(
                            colors: [
                              AppColors.electricBlue,
                              AppColors.neonCyan
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isPro ? null : AppColors.glassLight,
                    border: Border.all(
                      color: isPro ? AppColors.proGold : AppColors.glassBorder,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    isPro ? Icons.workspace_premium : Icons.lock_outline,
                    color: isPro ? Colors.white : AppColors.textSecondary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        planName,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isPro
                            ? 'All features unlocked • No ads'
                            : 'Limited to 1080p 30fps • 10s buffer • Ads',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isPro) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProUpgradeScreen()),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricBlue,
                    foregroundColor: AppColors.deepCharcoal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.flash_on, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Upgrade to Pro',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.deepCharcoal,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.proGold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.proGold),
                    ),
                    child: Text(
                      proTier?.toUpperCase() ?? 'PRO',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.proGold,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                    ),
                  ),
                  if (canUpgradeToLifetime) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: AppColors.proGold,
                    ),
                  ],
                ],
              ),
              if (canUpgradeToLifetime) ...[
                const SizedBox(height: 8),
                Text(
                  'Tap to upgrade to Lifetime',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCapabilitiesSection(
      BuildContext context, AppState appState) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.phone_android,
                color: AppColors.electricBlue,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Your Device Support',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Resolution Support
          _buildCapabilityItem(
            'Resolution',
            [
              _CapabilityStatus('1080P', true, '30fps, 60fps'),
              _CapabilityStatus(
                  '4K',
                  _capabilities['supports4K'] == true,
                  _capabilities['supports4K60fps'] == true
                      ? '30fps, 60fps'
                      : '30fps only'),
            ],
          ),

          const SizedBox(height: 16),

          // Frame Rate Support
          _buildCapabilityItem(
            'Frame Rate',
            [
              _CapabilityStatus('30fps', true, 'All resolutions'),
              _CapabilityStatus('60fps @ 1080P',
                  _capabilities['supports1080p60fps'] == true, ''),
              _CapabilityStatus(
                  '60fps @ 4K', _capabilities['supports4K60fps'] == true, ''),
            ],
          ),

          const SizedBox(height: 16),

          // Codec Support
          _buildCapabilityItem(
            'Video Codec',
            [
              _CapabilityStatus('H.264', true, 'Hardware accelerated'),
              _CapabilityStatus('H.265/HEVC', false, 'Not supported'),
            ],
          ),

          const SizedBox(height: 16),

          // Camera Features
          _buildCapabilityItem(
            'Camera Features',
            [
              _CapabilityStatus('Video Stabilization', true, ''),
              _CapabilityStatus('Flash/Torch', true, ''),
              _CapabilityStatus('Multiple Cameras', true, ''),
            ],
          ),

          const SizedBox(height: 20),

          if (_isLoadingCapabilities)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.electricBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Loading capabilities...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCapabilityItem(
      String title, List<_CapabilityStatus> capabilities) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...capabilities.map((cap) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    cap.supported ? Icons.check_circle : Icons.cancel,
                    color: cap.supported
                        ? AppColors.successGreen
                        : AppColors.textDisabled,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cap.name,
                          style: TextStyle(
                            color: cap.supported
                                ? AppColors.textPrimary
                                : AppColors.textDisabled,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (cap.details.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            cap.details,
                            style: TextStyle(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildDiagnosticsSection(BuildContext context, AppState appState) {
    final capabilities = appState.deviceCapabilities!;

    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device Information',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          _buildDiagnosticRow('RAM Tier', capabilities.toString()),
          const SizedBox(height: 12),
          _buildDiagnosticRow('Buffer Mode', 'RAM-based'),
          const SizedBox(height: 12),
          _buildDiagnosticRow('Supported Resolutions', '720p, 1080p, 4K'),
          const SizedBox(height: 12),
          _buildDiagnosticRow('Supported FPS', '30fps, 60fps'),
          const SizedBox(height: 12),
          _buildDiagnosticRow('Video Codec', 'H.264 (default)'),
        ],
      ),
    );
  }

  Widget _buildAppSection(BuildContext context, AppState appState) {
    return GlassContainer(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          _buildSettingTile(
            icon: Icons.help_outline,
            title: 'How It Works',
            subtitle: 'Learn how to use Flashback Cam',
            onTap: () => _showHowItWorks(context),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          _buildSettingTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'How we handle your data',
            onTap: () => _showInfo(context, 'Privacy Policy'),
            trailing: const Icon(Icons.open_in_new,
                color: AppColors.textSecondary, size: 20),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          _buildSettingTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            subtitle: 'Legal terms and conditions',
            onTap: () => _showInfo(context, 'Terms of Service'),
            trailing: const Icon(Icons.open_in_new,
                color: AppColors.textSecondary, size: 20),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          _buildSettingTile(
            icon: Icons.restore,
            title: 'Restore Purchases',
            subtitle: 'Recover previous purchases',
            onTap: () => _restorePurchases(context, appState),
          ),
          const Divider(height: 1, color: AppColors.glassBorder),
          _buildSettingTile(
            icon: Icons.info_outline,
            title: 'App Version',
            subtitle: '1.0.0',
            onTap: () => _onVersionTap(),
            trailing: _showDeveloperOptions
                ? const Icon(Icons.developer_mode,
                    color: AppColors.electricBlue, size: 20)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    bool isLocked = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isLocked
              ? AppColors.textDisabled.withValues(alpha: 0.1)
              : AppColors.electricBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isLocked ? AppColors.textDisabled : AppColors.electricBlue,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: isLocked ? AppColors.textDisabled : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isLocked
                        ? AppColors.textDisabled
                        : AppColors.textSecondary,
                  ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLocked) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.proGold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.proGold, width: 1),
              ),
              child: Text(
                'PRO',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.proGold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          trailing ??
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
      onTap: isLocked ? () => _showProUpgrade(context) : onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.electricBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: AppColors.electricBlue,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            )
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.electricBlue,
        activeTrackColor: AppColors.electricBlue.withValues(alpha: 0.3),
        inactiveThumbColor: AppColors.textSecondary,
        inactiveTrackColor: AppColors.glassLight,
      ),
    );
  }

  Widget _buildDiagnosticRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w400,
                ),
          ),
        ),
      ],
    );
  }

  void _onVersionTap() {
    _versionTapCount++;
    if (_versionTapCount >= 7 && !_showDeveloperOptions) {
      setState(() {
        _showDeveloperOptions = true;
      });
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Developer options enabled'),
          backgroundColor: AppColors.charcoal,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showProUpgrade(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProUpgradeScreen()),
    );
  }

  void _showPreRollPicker(BuildContext context, AppState appState,
      AppSettings settings, bool isPro) {
    final options = [3, 5, 10, 20, 30];
    final currentIndex = options.indexOf(settings.preRollSeconds);

    _showPicker(
      context,
      'Pre-roll Buffer',
      options.map((e) => '$e seconds').toList(),
      currentIndex,
      (index) {
        final seconds = options[index];
        if (!isPro && seconds > 10) {
          _showProUpgrade(context);
          return;
        }
        appState.updateSettings(settings.copyWith(preRollSeconds: seconds));
      },
    );
  }

  void _showResolutionPicker(BuildContext context, AppState appState,
      AppSettings settings, bool isPro) {
    if (_isLoadingCapabilities) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading capabilities...')),
      );
      return;
    }

    // Build available resolutions based on capabilities
    final options = <String>['1080P'];
    if (_capabilities['supports4K'] == true) {
      options.add('4K');
    }

    final normalized = settings.resolution.toUpperCase();
    final currentIndex = options.indexOf(normalized);
    final initialIndex = currentIndex >= 0 ? currentIndex : 0;

    _showPicker(
      context,
      'Resolution',
      options,
      initialIndex,
      (index) {
        final resolution = options[index];
        if (!isPro && resolution == '4K') {
          _showProUpgrade(context);
          return;
        }
        appState.updateSettings(settings.copyWith(resolution: resolution));
      },
    );
  }

  void _showFpsPicker(BuildContext context, AppState appState,
      AppSettings settings, bool isPro) {
    if (_isLoadingCapabilities) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading capabilities...')),
      );
      return;
    }

    // Determine available FPS based on resolution and capabilities
    final currentResolution = settings.resolution.toUpperCase();
    bool supports60fps = false;

    if (currentResolution == '1080P') {
      supports60fps = _capabilities['supports1080p60fps'] == true;
    } else if (currentResolution == '4K') {
      supports60fps = _capabilities['supports4K60fps'] == true;
    }

    final options = <int>[30];
    if (supports60fps) {
      options.add(60);
    }

    final currentIndex = options.indexOf(settings.fps);

    _showPicker(
      context,
      'Frame Rate',
      options.map((e) => '$e fps').toList(),
      currentIndex,
      (index) {
        final fps = options[index];
        if (!isPro && fps == 60) {
          _showProUpgrade(context);
          return;
        }
        appState.updateSettings(settings.copyWith(fps: fps));
      },
    );
  }

  // Codec picker removed

  void _showBitratePicker(
      BuildContext context, AppState appState, AppSettings settings) {
    final options = ['Auto', 'High', 'Medium', 'Low'];
    final currentIndex = options.indexOf(settings.bitrate);

    _showPicker(
      context,
      'Bitrate',
      options,
      currentIndex,
      (index) {
        final bitrate = options[index];
        appState.updateSettings(settings.copyWith(bitrate: bitrate));
      },
    );
  }

  void _showPicker(
    BuildContext context,
    String title,
    List<String> options,
    int currentIndex,
    Function(int) onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.charcoal,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),

            // Options
            ...options.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;
              final isSelected = index == currentIndex;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(
                  option,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.electricBlue
                        : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: AppColors.electricBlue)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  onSelect(index);
                },
              );
            }).toList(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showHowItWorks(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: CameraInstructionsOverlay(
          onDismiss: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _showInfo(BuildContext context, String title) {
    if (title == 'Privacy Policy') {
      _showPrivacyPolicy(context);
    } else if (title == 'Terms of Service') {
      _showTermsOfService(context);
    }
  }

  void _showPrivacyPolicy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.deepCharcoal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.privacy_tip, color: AppColors.electricBlue),
                  const SizedBox(width: 12),
                  Text(
                    'Privacy Policy',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.glassBorder),
            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPolicyHeader('PRIVACY POLICY — Flashback Cam'),
                    const SizedBox(height: 8),
                    _buildPolicyText('Last Updated: 2025/28/11'),
                    _buildPolicyText('Developer: Roch Enterprises'),
                    _buildPolicyText('App Name: Flashback Cam'),
                    _buildPolicyText(
                        'Contact Email: contact@rochenterprises.in'),
                    const SizedBox(height: 24),
                    _buildPolicySection('1. Introduction'),
                    _buildPolicyText(
                        'Flashback Cam ("we", "our", "us") is a video recording application developed by Roch Enterprises. This Privacy Policy explains what information we collect, how we use it, how it is protected, and your rights as a user.\n\nBy using Flashback Cam, you agree to the practices described in this Privacy Policy.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('2. Information We Collect'),
                    _buildPolicySubsection('2.1 Camera & Microphone'),
                    _buildPolicyText(
                        'The app requires access to:\n• Your device camera to capture video\n• Your microphone to record audio\n\nWe do not collect, store, or upload any photos or videos to our servers. All recordings stay on your device only.'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('2.2 Device Information'),
                    _buildPolicyText(
                        'We may collect non-personal, technical information such as:\n• Device model\n• Operating system version\n• App version\n• Crash logs\n• Performance analytics\n\nThis data is used solely to improve app stability and performance.'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('2.3 Usage Data'),
                    _buildPolicyText(
                        'We may collect anonymous usage data, including:\n• Feature usage (buffer time, recording duration, etc.)\n• App interactions\n• Subscription activity (Pro/Free status)\n\nThis data is anonymous and cannot identify you.'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('2.4 Ads Data (AdMob)'),
                    _buildPolicyText(
                        'Flashback Cam uses Google AdMob, which may collect:\n• Advertising ID\n• Approximate location\n• Device information\n• App interactions\n• Analytics for ad performance\n\nAdMob operates under Google\'s Privacy Policy:\nhttps://policies.google.com/privacy'),
                    const SizedBox(height: 20),
                    _buildPolicySection('3. How We Use Your Information'),
                    _buildPolicyText(
                        'We use collected data to:\n• Provide camera and recording functionality\n• Process videos locally on your device\n• Improve app performance\n• Fix crashes and bugs\n• Show personalized or non-personalized ads (AdMob)\n• Manage subscription status\n\nWe do not sell or trade your personal data.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('4. Data Storage & Security'),
                    _buildPolicyText(
                        '• We do not upload your photos or videos to any server.\n• All recordings remain locally stored on your device.\n• Analytics and crash data are securely processed through Google services.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('5. Data Sharing'),
                    _buildPolicyText(
                        'We do not share your data with third parties, except:\n• Google AdMob (for ads)\n• Google Play Billing (for purchases)\n• Firebase/Google (for crash logs & analytics, if enabled)\n\nWe never sell your information.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('6. Children\'s Privacy'),
                    _buildPolicyText(
                        'Flashback Cam is not intended for children under 13. We do not knowingly collect personal data from minors.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('7. Permissions Explained'),
                    _buildPolicyText(
                        'Flashback Cam requests the following permissions:\n\n📷 Camera\nTo show camera preview and record videos.\n\n🎤 Microphone\nTo record audio for your videos.\n\n💾 Storage / Media Access\nTo save videos and show them in the gallery.\n\n🌐 Internet\nUsed only for:\n• Loading ads\n• Verifying subscriptions\n• Crash analytics\n\nFlashback Cam never records secretly and stops recording when the device is locked.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('8. Subscription & Purchases'),
                    _buildPolicyText(
                        'Flashback Cam offers optional Pro subscriptions. All payments are processed securely by Google Play Billing.\n\nWe do not store your payment details.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('9. Changes to This Policy'),
                    _buildPolicyText(
                        'We may update this Privacy Policy occasionally. If changes are significant, we will notify you within the app.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('10. Contact Us'),
                    _buildPolicyText(
                        'For questions or concerns:\n\n📧 Email: contact@rochenterprises.in\n🏢 Developer: Roch Enterprises'),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTermsOfService(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.deepCharcoal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      color: AppColors.electricBlue),
                  const SizedBox(width: 12),
                  Text(
                    'Terms of Service',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.glassBorder),
            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPolicyHeader('TERMS OF SERVICE — Flashback Cam'),
                    const SizedBox(height: 8),
                    _buildPolicyText('Last Updated: 2025/28/11'),
                    _buildPolicyText('Developer: Roch Enterprises'),
                    const SizedBox(height: 24),
                    _buildPolicySection('1. Acceptance of Terms'),
                    _buildPolicyText(
                        'By downloading or using Flashback Cam, you agree to these Terms of Service.\nIf you do not agree, please uninstall the app immediately.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('2. Use of the App'),
                    _buildPolicyText(
                        'You agree to:\n• Use the app only for lawful purposes\n• Not attempt to reverse engineer or modify the app\n• Not record individuals without consent (where required by law)\n• Not exploit any loopholes or misuse app features'),
                    const SizedBox(height: 20),
                    _buildPolicySection('3. User Content'),
                    _buildPolicyText(
                        'All videos you record using Flashback Cam:\n• Remain your property\n• Are stored only on your device\n• Are not uploaded or transmitted by us\n\nWe are not responsible for loss of user data.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('4. Pro Subscription'),
                    _buildPolicyText(
                        'Flashback Cam offers optional Pro features:\n• Higher resolutions (up to device capability)\n• No ads\n• Extended buffer\n• Faster processing\n• Lifetime unlock'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('Billing & Refunds'),
                    _buildPolicyText(
                        '• Payments are processed by Google Play\n• We do not manage refunds directly\n• Users may request refunds through Google Play support\n• Subscription auto-renews unless canceled'),
                    const SizedBox(height: 20),
                    _buildPolicySection('5. App Updates'),
                    _buildPolicyText(
                        'We may update or modify features at any time.\nUpdates may:\n• Add features\n• Improve performance\n• Fix issues\n• Remove deprecated or unsafe functions\n\nYou agree to use the most current version of the app.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('6. Device Compatibility'),
                    _buildPolicyText(
                        'Flashback Cam supports devices based on:\n• Hardware capability\n• Camera support\n• Operating system version\n• Google Play policies\n\nSome features (like 1080p/4K/60fps) depend on device hardware.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('7. Limitation of Liability'),
                    _buildPolicyText(
                        'Roch Enterprises is not liable for:\n• Data loss\n• Device issues caused by hardware limitations\n• Improper usage\n• Recording done without consent\n• Any damage resulting from misuse\n\nUse the app at your own risk.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('8. Prohibited Activities'),
                    _buildPolicyText(
                        'You must not:\n• Use the app for unlawful surveillance\n• Circumvent subscription or licensing checks\n• Modify or redistribute the app illegally\n• Misuse buffer or background behavior to violate others\' privacy\n\nDoing so may result in termination of your rights to use the app.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('9. Termination'),
                    _buildPolicyText(
                        'We may suspend access if you:\n• Abuse the app\n• Attempt fraud\n• Tamper with subscriptions\n• Violate laws'),
                    const SizedBox(height: 20),
                    _buildPolicySection('10. Contact Information'),
                    _buildPolicyText(
                        'For legal or support queries:\n\n📧 Email: contact@rochenterprises.in\n🏢 Developer: Roch Enterprises'),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyHeader(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.electricBlue,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _buildPolicySection(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildPolicySubsection(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.electricBlue.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  Widget _buildPolicyText(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.6,
          ),
    );
  }

  void _restorePurchases(BuildContext context, AppState appState) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.electricBlue),
      ),
    );

    try {
      final success = await appState.restorePurchases();
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Purchases restored successfully'
              : 'No purchases found'),
          backgroundColor: AppColors.charcoal,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to restore purchases: ${e.toString()}'),
          backgroundColor: AppColors.recordRed,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showLifetimeUpgradeDialog(BuildContext context, AppState appState) {
    final currentTier = appState.subscriptionService.currentUser.proTier;
    final lifetimeProduct =
        appState.subscriptionService.getProductDetails('lifetime');
    final lifetimePrice = lifetimeProduct?.price ?? 'Loading...';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.charcoal,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.glassBorder,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.electricBlue, AppColors.neonCyan],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: Colors.white,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Upgrade to Lifetime',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Switch from your ${currentTier?.toLowerCase()} plan to lifetime access for just $lifetimePrice.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.electricBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.neonGreen, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'One-time payment',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.neonGreen, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Never expires',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.neonGreen, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'All pro features forever',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(
                            color: AppColors.electricBlue, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Cancel',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => _upgradeToLifetime(context, appState),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.electricBlue,
                        foregroundColor: AppColors.deepCharcoal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.flash_on, size: 18),
                          const SizedBox(width: 8),
                          const Text('Upgrade Now'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _upgradeToLifetime(BuildContext context, AppState appState) async {
    Navigator.pop(context); // Close upgrade dialog

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.electricBlue),
              const SizedBox(height: 20),
              Text(
                'Processing upgrade...',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final success = await appState.purchasePro('lifetime');
      Navigator.pop(context); // Close loading dialog

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.neonGreen),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Successfully upgraded to Lifetime! 🎉'),
                ),
              ],
            ),
            backgroundColor: AppColors.charcoal,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Upgrade was canceled or failed'),
            backgroundColor: AppColors.recordRed,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upgrade failed: ${e.toString()}'),
          backgroundColor: AppColors.recordRed,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}

class _CapabilityStatus {
  final String name;
  final bool supported;
  final String details;

  _CapabilityStatus(this.name, this.supported, this.details);
}
