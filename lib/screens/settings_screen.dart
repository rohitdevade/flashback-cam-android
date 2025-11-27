import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flashback_cam/providers/app_state.dart';
import 'package:flashback_cam/models/app_settings.dart';
import 'package:flashback_cam/theme.dart';
import 'package:flashback_cam/screens/pro_upgrade_screen.dart';
import 'package:flashback_cam/widgets/glass_container.dart';

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

          // Device Capabilities Section
          _buildSectionHeader('Device Capabilities'),
          const SizedBox(height: 16),
          _buildDeviceCapabilitiesSection(context, appState),

          const SizedBox(height: 32),

          // Pro Plan Section
          _buildSectionHeader('Pro Plan'),
          const SizedBox(height: 16),
          _buildProSection(context, appState, isPro),

          const SizedBox(height: 32),

          // Device & Diagnostics Section
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
                            : 'Limited to 1080p • 10s buffer • Ads',
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

  void _showInfo(BuildContext context, String title) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                color: AppColors.electricBlue,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'This would open the $title in a web view or external browser.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
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
                'Switch from your ${currentTier?.toLowerCase()} plan to lifetime access for just \$15.00.',
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
