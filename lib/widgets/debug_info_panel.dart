import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flashback_cam/models/debug_info.dart';
import 'package:flashback_cam/providers/app_state.dart';

class DebugInfoPanel extends StatefulWidget {
  final DebugInfo debugInfo;
  final VoidCallback onRefresh;
  final ScrollController? scrollController;

  const DebugInfoPanel({
    super.key,
    required this.debugInfo,
    required this.onRefresh,
    this.scrollController,
  });

  @override
  State<DebugInfoPanel> createState() => _DebugInfoPanelState();
}

class _DebugInfoPanelState extends State<DebugInfoPanel> {
  @override
  Widget build(BuildContext context) {
    print(
        '🐛 DebugInfoPanel building with data: ${widget.debugInfo.deviceTier}');

    return Container(
      padding: EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.bug_report, color: Colors.orange, size: 24),
                SizedBox(width: 12),
                Text(
                  'Debug Info (Dev Only)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.refresh, color: Colors.white70),
                  onPressed: widget.onRefresh,
                  tooltip: 'Refresh',
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Divider(color: Colors.white24, height: 1),

          // Content
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: EdgeInsets.all(16),
              children: [
                // Demo Mode Toggle (Debug Only)
                if (kDebugMode) ...[
                  _buildSectionTitle('Demo Mode'),
                  _buildDemoModeToggle(),
                  SizedBox(height: 16),
                ],

                // Device Info Section
                _buildSectionTitle('Device'),
                _buildInfoTile('Device Tier', widget.debugInfo.deviceTier,
                    _getTierIcon(widget.debugInfo.deviceTier)),
                _buildInfoTile(
                    'Buffer Strategy',
                    widget.debugInfo.bufferStrategy,
                    _getStrategyIcon(widget.debugInfo.bufferStrategy)),

                SizedBox(height: 16),

                // Video Settings Section
                _buildSectionTitle('Video Settings'),
                _buildInfoTile('Resolution', widget.debugInfo.videoResolution,
                    Icons.aspect_ratio),
                _buildInfoTile(
                    'FPS', '${widget.debugInfo.videoFps} fps', Icons.speed),
                _buildInfoTile('Video Codec', widget.debugInfo.videoCodec,
                    Icons.video_settings),
                _buildInfoTile('Audio Codec', widget.debugInfo.audioCodec,
                    Icons.audiotrack),
                _buildInfoTile(
                    'Buffer Length',
                    '${widget.debugInfo.selectedBufferSeconds} seconds',
                    Icons.timer),

                SizedBox(height: 16),

                // Last Recording Section
                _buildSectionTitle('Last Recording'),
                _buildInfoTile(
                  'Status',
                  widget.debugInfo.lastRecordingStatus ?? 'N/A',
                  _getStatusIcon(widget.debugInfo.lastRecordingStatus),
                  statusColor:
                      _getStatusColor(widget.debugInfo.lastRecordingStatus),
                ),
                if (widget.debugInfo.lastRecordingPath != null)
                  _buildInfoTile('Path', widget.debugInfo.lastRecordingPath!,
                      Icons.insert_drive_file),

                SizedBox(height: 16),

                // Debug Logs Section
                if (widget.debugInfo.debugLogs.isNotEmpty) ...[
                  _buildSectionTitle(
                      'Recent Logs (${widget.debugInfo.debugLogs.length})'),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widget.debugInfo.debugLogs
                          .map((log) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  log,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Colors.green[300],
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoModeToggle() {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppState.demoMode
            ? Colors.orange.withOpacity(0.15)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppState.demoMode ? Colors.orange : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.videocam,
            color: AppState.demoMode ? Colors.orange : Colors.white54,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Video Preview Mode',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  AppState.demoMode
                      ? 'Active - Restart to use camera'
                      : 'Off - Using real camera',
                  style: TextStyle(
                    color: AppState.demoMode ? Colors.orange : Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: AppState.demoMode,
            onChanged: (value) async {
              await AppState.setDemoMode(value);
              setState(() {});
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value
                          ? '📹 Demo mode enabled. Restart app to apply.'
                          : '📷 Demo mode disabled. Restart app to use camera.',
                    ),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
            activeColor: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon,
      {Color? statusColor}) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: statusColor ?? Colors.white54, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: statusColor ?? Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTierIcon(String tier) {
    switch (tier.toUpperCase()) {
      case 'HIGH':
        return Icons.rocket_launch;
      case 'MID':
        return Icons.devices;
      case 'LOW':
        return Icons.phone_android;
      default:
        return Icons.help_outline;
    }
  }

  IconData _getStrategyIcon(String strategy) {
    switch (strategy.toUpperCase()) {
      case 'RAM':
        return Icons.memory;
      case 'DISK':
        return Icons.storage;
      default:
        return Icons.help_outline;
    }
  }

  IconData _getStatusIcon(String? status) {
    if (status == null) return Icons.info_outline;
    if (status.toLowerCase().contains('success')) return Icons.check_circle;
    if (status.toLowerCase().contains('fail')) return Icons.error;
    return Icons.info_outline;
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.white54;
    if (status.toLowerCase().contains('success')) return Colors.green;
    if (status.toLowerCase().contains('fail')) return Colors.red;
    return Colors.orange;
  }
}
