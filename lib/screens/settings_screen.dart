import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' hide AppState;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
  String _appVersion = '';

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
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    }
  }

  void _loadBannerAd() {
    final appState = context.read<AppState>();
    if (appState.isPro) return; // Don't show ads for pro users

    _bannerAd = appState.adService.createSettingsBannerAd();
    if (_bannerAd == null) return; // No consent for ads

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
    final isTrialActive = appState.isTrialActive;
    final trialDaysRemaining = appState.trialDaysRemaining;
    final isPaidPro =
        appState.subscriptionService.isPro; // Paid Pro only (not trial)
    final monthlyPrice =
        appState.subscriptionService.getProductDetails('monthly')?.price ??
            '\$9.99';

    String planName = 'Free Plan';
    String planSubtitle = 'Limited to 1080p 30fps • 10s buffer • Ads';
    bool canUpgradeToLifetime = false;
    bool showUpgradeButton = true;
    bool isProOrTrial = isPro || isTrialActive;

    if (isTrialActive) {
      planName = 'Trial Plan';
      planSubtitle = trialDaysRemaining == 1
          ? '1 day left • Then $monthlyPrice/month'
          : '$trialDaysRemaining days left • Then $monthlyPrice/month';
      showUpgradeButton = true; // Show upgrade button during trial
    } else if (isPaidPro && proTier != null) {
      showUpgradeButton = false;
      final tierLower = proTier.toLowerCase();
      switch (tierLower) {
        case 'trial':
          // Google Play free trial (stored as 'trial' tier)
          planName = 'Free Trial';
          final expiresAt =
              appState.subscriptionService.currentUser.proExpiresAt;
          if (expiresAt != null) {
            final daysLeft = expiresAt.difference(DateTime.now()).inDays;
            planSubtitle = daysLeft == 1
                ? '1 day left • Then $monthlyPrice/month'
                : '$daysLeft days left • Then $monthlyPrice/month';
          } else {
            planSubtitle = 'Free trial • Then $monthlyPrice/month';
          }
          showUpgradeButton = true;
          canUpgradeToLifetime = true;
          break;
        case 'monthly':
          planName = 'Monthly Plan';
          planSubtitle = 'All features unlocked • No ads';
          canUpgradeToLifetime = true;
          break;
        case 'yearly':
          planName = 'Yearly Plan';
          planSubtitle = 'All features unlocked • No ads';
          canUpgradeToLifetime = true;
          break;
        case 'lifetime':
          planName = 'Lifetime Plan';
          planSubtitle = 'All features unlocked • No ads';
          break;
        default:
          planName = 'Pro Active';
          planSubtitle = 'All features unlocked • No ads';
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
                    gradient: isProOrTrial
                        ? LinearGradient(
                            colors: isTrialActive
                                ? [AppColors.neonGreen, AppColors.electricBlue]
                                : [AppColors.electricBlue, AppColors.neonCyan],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isProOrTrial ? null : AppColors.glassLight,
                    border: Border.all(
                      color: isTrialActive
                          ? AppColors.neonGreen
                          : (isPro ? AppColors.proGold : AppColors.glassBorder),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    isTrialActive
                        ? Icons.timer
                        : (isPro
                            ? Icons.workspace_premium
                            : Icons.lock_outline),
                    color:
                        isProOrTrial ? Colors.white : AppColors.textSecondary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            planName,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (isTrialActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.neonGreen.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ACTIVE',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: AppColors.neonGreen,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        planSubtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isTrialActive
                                  ? AppColors.neonGreen
                                  : AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (showUpgradeButton && !isPaidPro) ...[
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
                        isTrialActive ? 'Keep Pro Forever' : 'Upgrade to Pro',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.deepCharcoal,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (isPaidPro) ...[
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
          // Ad Privacy Preferences (GDPR/UMP consent)
          FutureBuilder<bool>(
            future: appState.adService.isPrivacyOptionsRequired(),
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return Column(
                children: [
                  _buildSettingTile(
                    icon: Icons.ads_click_outlined,
                    title: 'Ad Preferences',
                    subtitle: 'Manage personalized ad settings',
                    onTap: () => _showAdPrivacyOptions(context, appState),
                  ),
                  const Divider(height: 1, color: AppColors.glassBorder),
                ],
              );
            },
          ),
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
          // Show Manage Subscription only for Pro users
          if (appState.isPro) ...[
            _buildSettingTile(
              icon: Icons.subscriptions_outlined,
              title: 'Manage Subscription',
              subtitle: 'Cancel or modify in Google Play',
              onTap: () => _openSubscriptionManagement(),
              trailing: const Icon(Icons.open_in_new,
                  color: AppColors.textSecondary, size: 20),
            ),
            const Divider(height: 1, color: AppColors.glassBorder),
          ],
          _buildSettingTile(
            icon: Icons.info_outline,
            title: 'App Version',
            subtitle: _appVersion.isEmpty ? 'Loading...' : _appVersion,
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

    // Show all resolutions, mark unsupported ones
    final options = <String>['1080P', '4K'];
    final supports4K = _capabilities['supports4K'] == true;

    final normalized = settings.resolution.toUpperCase();
    final currentIndex = options.indexOf(normalized);
    final initialIndex = currentIndex >= 0 ? currentIndex : 0;

    _showPickerWithSupport(
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
      supportedIndices: supports4K ? [0, 1] : [0],
      unsupportedMessage:
          '4K recording is not supported by your device camera.',
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

    // Show all FPS options, mark unsupported ones
    final currentResolution = settings.resolution.toUpperCase();
    bool supports60fps = false;

    if (currentResolution == '1080P') {
      supports60fps = _capabilities['supports1080p60fps'] == true;
    } else if (currentResolution == '4K') {
      supports60fps = _capabilities['supports4K60fps'] == true;
    }

    final options = <String>['30 fps', '60 fps'];
    final fpsValues = <int>[30, 60];

    final currentIndex = fpsValues.indexOf(settings.fps);

    _showPickerWithSupport(
      context,
      'Frame Rate',
      options,
      currentIndex,
      (index) {
        final fps = fpsValues[index];
        if (!isPro && fps == 60) {
          _showProUpgrade(context);
          return;
        }
        appState.updateSettings(settings.copyWith(fps: fps));
      },
      supportedIndices: supports60fps ? [0, 1] : [0],
      unsupportedMessage:
          '60fps recording at $currentResolution is not supported by your device camera.',
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

  void _showPickerWithSupport(
    BuildContext context,
    String title,
    List<String> options,
    int currentIndex,
    Function(int) onSelect, {
    required List<int> supportedIndices,
    String? unsupportedMessage,
  }) {
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
              final isSupported = supportedIndices.contains(index);

              return Opacity(
                opacity: isSupported ? 1.0 : 0.4,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: !isSupported
                      ? const Icon(Icons.block,
                          color: AppColors.textSecondary, size: 20)
                      : null,
                  title: Text(
                    option,
                    style: TextStyle(
                      color: isSelected && isSupported
                          ? AppColors.electricBlue
                          : (isSupported
                              ? AppColors.textPrimary
                              : AppColors.textSecondary),
                      fontWeight: isSelected && isSupported
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: isSelected && isSupported
                      ? const Icon(Icons.check, color: AppColors.electricBlue)
                      : null,
                  onTap: () {
                    if (!isSupported) {
                      Navigator.pop(context);
                      _showUnsupportedDialog(
                          context, option, unsupportedMessage);
                      return;
                    }
                    Navigator.pop(context);
                    onSelect(index);
                  },
                ),
              );
            }).toList(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showUnsupportedDialog(
      BuildContext context, String option, String? message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.charcoal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.warningOrange, size: 24),
            const SizedBox(width: 12),
            Text(
              'Not Supported',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          message ?? '$option is not supported by your device.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                color: AppColors.electricBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

  /// Show ad privacy options using UMP consent form
  Future<void> _showAdPrivacyOptions(
      BuildContext context, AppState appState) async {
    try {
      await appState.adService.showPrivacyOptionsForm();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ad preferences updated'),
            backgroundColor: AppColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update ad preferences: $e'),
            backgroundColor: AppColors.recordRed,
          ),
        );
      }
    }
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
                    _buildPolicyHeader('Rochenterprises.in'),
                    const SizedBox(height: 4),
                    _buildPolicyHeader('Privacy Policy'),
                    const SizedBox(height: 16),
                    _buildPolicyText('Effective Date: 2025/29/11'),
                    _buildPolicyText('Developer: Roch Enterprises'),
                    _buildPolicyText('Email: support@rochenterprises.in'),
                    _buildPolicyText('App Name: Flashback Cam'),
                    const SizedBox(height: 20),
                    _buildPolicyText(
                        'Roch Enterprises ("we", "our", "us") respects your privacy. This Privacy Policy explains how Flashback Cam collects, uses, and protects information across all countries, including compliance with GDPR, CCPA/CPRA, COPPA, and Google Play policies.'),
                    const SizedBox(height: 12),
                    _buildPolicyText(
                        'Flashback Cam is a camera app that allows users to record video and save past moments using a buffer system. All media processing happens on your device only.'),
                    const SizedBox(height: 24),

                    // Section 1
                    _buildPolicySection('1. WHAT INFORMATION WE COLLECT'),
                    _buildPolicyText(
                        'Flashback Cam collects the minimum data required to operate.'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('A. Information You Provide'),
                    _buildPolicyText(
                        'We do not collect personal data such as:\n• Photos\n• Videos\n• Audio\n• Contacts\n• Messages\n• Files\n\nAll captured media remains on your device, never uploaded to our servers.'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection(
                        'B. Information Collected Automatically'),
                    _buildPolicyText(
                        'Through third-party SDKs (AdMob, Google Play Services, Billing):\n• Device model & OS version\n• App usage statistics\n• Crash logs & diagnostics\n• Approximate region (not precise location)\n• Advertising ID (resettable)\n• Purchase tokens (for verifying subscriptions)'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('C. We DO NOT collect:'),
                    _buildPolicyText(
                        '• Facial recognition data\n• Biometric data\n• Precise GPS location\n• Health information\n• Payment card numbers\n• User-generated media content'),
                    const SizedBox(height: 20),

                    // Section 2
                    _buildPolicySection('2. CAMERA & MICROPHONE TRANSPARENCY'),
                    _buildPolicyText(
                        'Flashback Cam requires:\n\n📷 Camera Permission – To show live preview and record video.\n\n🎤 Microphone Permission – To record audio along with video.\n\n💾 Storage Access – To save videos on your device.'),
                    const SizedBox(height: 12),
                    _buildPolicyText(
                        'Flashback Cam does NOT:\n• Record automatically\n• Record in background\n• Record when screen is off\n• Upload camera feed to servers\n• Transmit any media or audio off-device'),
                    const SizedBox(height: 20),

                    // Section 3
                    _buildPolicySection('3. BUFFER RECORDING TRANSPARENCY'),
                    _buildPolicyText(
                        'Flashback Cam includes a rolling video buffer feature.\n\n• The buffer activates only when you tap "Start Buffer."\n• It temporarily stores the last N seconds of video so you can save recent moments.'),
                    const SizedBox(height: 12),
                    _buildPolicyText(
                        'Flashback Cam does NOT:\n• Start buffer automatically\n• Save buffer without user action\n• Store buffer on remote servers\n• Record anything without visible UI\n• Record secretly or silently'),
                    const SizedBox(height: 12),
                    _buildPolicyText(
                        'All buffer data:\n• Is stored temporarily\n• Exists inside your device memory or local storage\n• Is deleted automatically when overwritten\n• Never leaves your device'),
                    const SizedBox(height: 20),

                    // Section 4
                    _buildPolicySection('4. HOW WE USE YOUR INFORMATION'),
                    _buildPolicyText(
                        'We use collected data for:\n• App functionality\n• Subscription validation\n• Crash and performance analytics\n• Showing ads (if user consents)\n• Security and fraud prevention\n• Improving app performance\n\nWe do not sell or rent personal data.'),
                    const SizedBox(height: 20),

                    // Section 5
                    _buildPolicySection(
                        '5. DATA SHARING & THIRD-PARTY SERVICES'),
                    _buildPolicyText(
                        'Flashback Cam uses the following services:'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('Google AdMob'),
                    _buildPolicyText(
                        'Used for displaying ads. May collect:\n• Advertising ID\n• Device identifiers\n• Ad interaction data'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('Google Play Billing'),
                    _buildPolicyText('Used for subscriptions and purchases.'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('Google Play Services / Firebase'),
                    _buildPolicyText(
                        'Used for:\n• Crash logs\n• Analytics\n• Diagnostics\n\nThese providers process data according to their own privacy policies.'),
                    const SizedBox(height: 12),
                    _buildPolicyText(
                        'We never share:\n• Photos\n• Videos\n• Audio\n• Buffer recordings\n• Personal files'),
                    const SizedBox(height: 20),

                    // Section 6
                    _buildPolicySection('6. INTERNATIONAL DATA COMPLIANCE'),
                    _buildPolicyText(
                        'Flashback Cam complies with data regulations in:'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('GDPR (EU)'),
                    _buildPolicyText(
                        'EU users have:\n• Right to access\n• Right to deletion\n• Right to restrict processing\n• Right to withdraw consent\n• Right to data portability\n\nTo exercise rights, contact: support@rochenterprises.in'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('CCPA / CPRA (California)'),
                    _buildPolicyText(
                        'California users have:\n• Right to know what data is collected\n• Right to deletion of data collected\n• Right to opt-out of data selling (we do not sell data)\n• Right to non-discrimination\n\nTo exercise rights, contact: support@rochenterprises.in'),
                    const SizedBox(height: 12),
                    _buildPolicySubsection('COPPA'),
                    _buildPolicyText(
                        'Flashback Cam is not directed to children under 13 and does not knowingly collect personal data from children.'),
                    const SizedBox(height: 20),

                    // Section 7
                    _buildPolicySection('7. CONSENT MANAGEMENT (EU UMP)'),
                    _buildPolicyText(
                        'Flashback Cam may use Google\'s UMP (User Messaging Platform) for consent in applicable regions.\n\nEU/EEA users may see a consent dialog asking:\n• To allow personalized ads\n• To allow non-personalized ads\n• Or to manage preferences later\n\nAds will not load where required until consent is obtained or a legitimate basis is established.'),
                    const SizedBox(height: 20),

                    // Section 8
                    _buildPolicySection('8. DATA SECURITY'),
                    _buildPolicyText(
                        'We protect data through:\n• Device-level OS encryption\n• No media uploads to our servers\n• Secure communication channels (HTTPS) with Google services\n• Relying on trusted billing and ad providers (Google)\n\nHowever, no system is 100% secure. By using the app, you accept the inherent risks of online services and mobile platforms.'),
                    const SizedBox(height: 20),

                    // Section 9
                    _buildPolicySection('9. DATA RETENTION'),
                    _buildPolicyText(
                        '• Video recordings: Stored only on your device, until you delete them.\n• Buffer files: Temporary and auto-deleted when overwritten or when you stop buffering.\n• Crash/analytics data: Retained per Google\'s retention policies.\n• Subscription data: Retained by Google Play for billing and legal compliance.\n\nWe do not store media content on our own servers.'),
                    const SizedBox(height: 20),

                    // Section 10
                    _buildPolicySection(
                        '10. NO DARK PATTERNS (EU DSA COMPLIANT)'),
                    _buildPolicyText(
                        'Flashback Cam complies with the EU Digital Services Act principles regarding fair design.\n\nWe do not:\n• Hide cancel buttons\n• Force you into subscriptions\n• Use fake countdown timers\n• Use misleading labels on buttons\n• Make it difficult to cancel or refuse paid features\n\nSubscription prices, terms, and renewal conditions are always clearly displayed.'),
                    const SizedBox(height: 20),

                    // Section 11
                    _buildPolicySection(
                        '11. SUBSCRIPTIONS & BILLING DISCLOSURE'),
                    _buildPolicyText(
                        '• Subscriptions renew automatically unless cancelled in time.\n• Free trials, if available, convert automatically to paid subscriptions at the end of the trial period unless cancelled.\n• Cancellation is managed via Google Play → Payments & Subscriptions → Subscriptions.\n• We do not process or store payment card details; all payments are handled by Google Play.'),
                    const SizedBox(height: 20),

                    // Section 12
                    _buildPolicySection('12. USER CONTROLS & YOUR RIGHTS'),
                    _buildPolicyText(
                        'You can:\n• Withdraw ad consent (where applicable) via consent dialog or device settings.\n• Reset your Advertising ID via system settings.\n• Delete videos and recordings directly from your device.\n• Uninstall the app to stop data collection and use.\n• Request information about or deletion of non-media data (such as logs) that might be associated with your usage, subject to technical feasibility and legal requirements.\n\nTo submit a request or question, contact: support@rochenterprises.in'),
                    const SizedBox(height: 20),

                    // Section 13
                    _buildPolicySection('13. CHILDREN\'S PRIVACY'),
                    _buildPolicyText(
                        'Flashback Cam is not designed for children under the age of 13.\n\nWe do not knowingly collect personal data from children. If you believe a child has provided us with information, please contact us at support@rochenterprises.in and we will take appropriate action.'),
                    const SizedBox(height: 20),

                    // Section 14
                    _buildPolicySection('14. CONTACT INFORMATION'),
                    _buildPolicyText(
                        'For privacy questions, legal requests, or support:\n\nRoch Enterprises\n📧 Email: support@rochenterprises.in'),
                    const SizedBox(height: 20),

                    // Section 15
                    _buildPolicySection('15. CHANGES TO THIS PRIVACY POLICY'),
                    _buildPolicyText(
                        'We may update this Privacy Policy from time to time.\n\nAny changes will be posted at:\nhttps://sites.google.com/rochenterprises.in/privacy-policy\n\nThe "Effective Date" at the top will be updated.\n\nContinued use of Flashback Cam after changes are posted means you accept the updated policy.'),
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
                    _buildPolicyText('Effective Date: 2025/28/11'),
                    _buildPolicyText('Company: Roch Enterprises'),
                    _buildPolicyText('Email: support@rochenterprises.in'),
                    const SizedBox(height: 24),
                    _buildPolicySection('1. ABOUT THE APP'),
                    _buildPolicyText(
                        'Flashback Cam ("App") is a video recording application that allows users to:\n\n• Record videos\n• Use buffer recording to save past moments\n• Save media locally\n• Access advanced features via subscription\n\nFlashback Cam does not upload media to servers.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('2. ELIGIBILITY (UPDATED TO 18+)'),
                    _buildPolicyText(
                        'You must be:\n\n✔ 18 years of age or older\n\nto download or use Flashback Cam.\n\nBy installing the App, you confirm that:\n• You are at least 18 years old\n• You have the legal capacity to enter agreements\n• You agree to follow all local laws related to recording\n\nFlashback Cam is not intended for minors under any circumstances.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('3. LICENSE TO USE THE APP'),
                    _buildPolicyText(
                        'We grant you a limited, non-exclusive license to use the App for personal use.\n\nYou may not:\n• Reverse engineer the app\n• Use it for unlawful surveillance\n• Modify the App or its code\n• Bypass subscription features'),
                    const SizedBox(height: 20),
                    _buildPolicySection('4. USER-GENERATED CONTENT'),
                    _buildPolicyText(
                        'All videos you create:\n• Belong to you\n• Remain only on your device\n• Are not collected by us\n\nYou are responsible for complying with local recording laws.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('5. BUFFER RECORDING DISCLOSURE'),
                    _buildPolicyText(
                        'Flashback Cam\'s buffer system:\n• Activates only when you tap "Start Buffer"\n• Stores temporary video locally\n• Never records secretly or in background\n• Is automatically overwritten\n\nWe never access buffer content.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('6. SUBSCRIPTIONS & BILLING'),
                    _buildPolicyText(
                        'Covers:\n• Monthly / Yearly / Lifetime plans\n• Free trials (e.g., 7 days)\n• Auto-renewal\n• Cancellation through Google Play\n• Refunds handled by Google Play'),
                    const SizedBox(height: 20),
                    _buildPolicySection('7. ADVERTISEMENTS'),
                    _buildPolicyText(
                        '• Free version displays ads\n• Ads delivered via Google AdMob\n• EU users receive GDPR consent dialog\n• Ads removed with Pro subscription'),
                    const SizedBox(height: 20),
                    _buildPolicySection('8. PERMISSIONS'),
                    _buildPolicyText(
                        'App needs:\n• Camera\n• Microphone\n• Storage access\n\nNothing is recorded automatically or uploaded.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('9. PROHIBITED USES'),
                    _buildPolicyText(
                        'You agree not to:\n• Record illegally or without consent\n• Violate privacy laws\n• Disassemble or hack the App\n• Remove copyright notices\n• Misuse Pro features'),
                    const SizedBox(height: 20),
                    _buildPolicySection('10. DISCLAIMERS'),
                    _buildPolicyText(
                        'The App is provided "AS IS."\n\nWe do not guarantee:\n• Error-free operation\n• Compatibility with all devices\n• Continuous buffer reliability\n• Zero data loss'),
                    const SizedBox(height: 20),
                    _buildPolicySection('11. LIMITATION OF LIABILITY'),
                    _buildPolicyText(
                        'Roch Enterprises is not liable for:\n• Lost videos\n• Illegal use of the app\n• Device or data damage\n• Indirect damages\n\nYour sole remedy is uninstalling the App.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('12. INTELLECTUAL PROPERTY'),
                    _buildPolicyText(
                        'All app content and design belong to Roch Enterprises.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('13. TERMINATION'),
                    _buildPolicyText(
                        'We may suspend or terminate usage for violation of these Terms.\n\nYou may stop using the App at any time by uninstalling it.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('14. PRIVACY POLICY'),
                    _buildPolicyText(
                        'The Privacy Policy governs how data is handled:\n\n👉 https://rochenterprises.in/flashbackcam/privacy'),
                    const SizedBox(height: 20),
                    _buildPolicySection('15. GOVERNING LAW'),
                    _buildPolicyText(
                        'These Terms are governed by:\n• Your country\'s consumer protection laws\n• Indian law (company jurisdiction)\n\nEU users maintain their EU consumer rights.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('16. CHANGES TO TERMS'),
                    _buildPolicyText(
                        'We may update these Terms; continued use signifies acceptance.'),
                    const SizedBox(height: 20),
                    _buildPolicySection('17. CONTACT US'),
                    _buildPolicyText(
                        'Roch Enterprises\n📧 support@rochenterprises.in'),
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

  /// Open Google Play subscription management page
  Future<void> _openSubscriptionManagement() async {
    const subscriptionUrl =
        'https://play.google.com/store/account/subscriptions';
    final uri = Uri.parse(subscriptionUrl);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open subscription management'),
              backgroundColor: AppColors.recordRed,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.recordRed,
          ),
        );
      }
    }
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
