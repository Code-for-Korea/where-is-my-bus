import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../l10n/app_strings.dart';
import '../tracking_controller.dart';
import '../widgets/settings_row.dart';

/// 4. 상태보기 — 현재 추적 상태 요약 + 시작/정지 로그. mvp-spec 참고.
class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: p.inkDim), onPressed: () => Navigator.pop(context)),
        title: Text(AppStrings.statusTitle),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: TrackingController.isTracking,
        builder: (context, tracking, _) => ValueListenableBuilder<bool>(
          valueListenable: TrackingController.keepTracking,
          builder: (context, keepTracking, _) => ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatusCard(
                      label: AppStrings.trackingStatusLabel,
                      value: tracking ? AppStrings.trackingActiveState : AppStrings.trackingIdleState,
                      ok: tracking,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatusCard(label: AppStrings.lastSentLabel, value: _lastSentLabel()),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _StatusCard(
                      label: AppStrings.lastCoordLabel,
                      value: tracking ? TrackingController.lastCoord : AppStrings.lastSentNever,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatusCard(
                      label: AppStrings.keepTrackingStatusLabel,
                      value: keepTracking ? AppStrings.onValue : AppStrings.offValue,
                      ok: keepTracking,
                    ),
                  ),
                ],
              ),
              SettingsGroupTitle(AppStrings.logsGroup),
              ValueListenableBuilder<List<TrackingLogEntry>>(
                valueListenable: TrackingController.logs,
                builder: (context, logEntries, _) {
                  if (logEntries.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(AppStrings.noLogsYet, style: TextStyle(fontSize: 12.5, color: p.inkFaint)),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < logEntries.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            border: i == 0 ? null : Border(top: BorderSide(color: p.border)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 66,
                                child: Text(
                                  _formatTime(logEntries[i].time),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: p.inkFaint,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 5, right: 8),
                                // 시작 = 성공(그린), 정지 = 중립 상태 변경일 뿐이라 별도 강조 없음.
                                child: CircleAvatar(
                                  radius: 3.5,
                                  backgroundColor: logEntries[i].started ? p.tracking : p.inkFaint,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  logEntries[i].started ? AppStrings.logTrackingStarted : AppStrings.logTrackingStopped,
                                  style: TextStyle(fontSize: 12.5, color: p.ink),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _lastSentLabel() {
    final lastSentAt = TrackingController.lastSentAt;
    if (lastSentAt == null) return AppStrings.lastSentNever;
    return AppStrings.lastSentSecondsAgo(DateTime.now().difference(lastSentAt).inSeconds);
  }

  String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.label, required this.value, this.ok = false});

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(color: p.panelMuted, borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: p.inkFaint, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: ok ? p.tracking : p.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
