import 'package:flutter/material.dart';
import 'package:flashback_cam/models/debug_info.dart';

class DebugInfoPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    print('🐛 DebugInfoPanel building with data: ${debugInfo.deviceTier}');

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
                  onPressed: onRefresh,
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
              controller: scrollController,
              padding: EdgeInsets.all(16),
              children: [
                // Device Info Section
                _buildSectionTitle('Device'),
                _buildInfoTile('Device Tier', debugInfo.deviceTier,
                    _getTierIcon(debugInfo.deviceTier)),
                _buildInfoTile('Buffer Strategy', debugInfo.bufferStrategy,
                    _getStrategyIcon(debugInfo.bufferStrategy)),

                SizedBox(height: 16),

                // Video Settings Section
                _buildSectionTitle('Video Settings'),
                _buildInfoTile('Resolution', debugInfo.videoResolution,
                    Icons.aspect_ratio),
                _buildInfoTile('FPS', '${debugInfo.videoFps} fps', Icons.speed),
                _buildInfoTile(
                    'Video Codec', debugInfo.videoCodec, Icons.video_settings),
                _buildInfoTile(
                    'Audio Codec', debugInfo.audioCodec, Icons.audiotrack),
                _buildInfoTile('Buffer Length',
                    '${debugInfo.selectedBufferSeconds} seconds', Icons.timer),

                SizedBox(height: 16),

                // Last Recording Section
                _buildSectionTitle('Last Recording'),
                _buildInfoTile(
                  'Status',
                  debugInfo.lastRecordingStatus ?? 'N/A',
                  _getStatusIcon(debugInfo.lastRecordingStatus),
                  statusColor: _getStatusColor(debugInfo.lastRecordingStatus),
                ),
                if (debugInfo.lastRecordingPath != null)
                  _buildInfoTile('Path', debugInfo.lastRecordingPath!,
                      Icons.insert_drive_file),

                SizedBox(height: 16),

                // Debug Logs Section
                if (debugInfo.debugLogs.isNotEmpty) ...[
                  _buildSectionTitle(
                      'Recent Logs (${debugInfo.debugLogs.length})'),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: debugInfo.debugLogs
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
