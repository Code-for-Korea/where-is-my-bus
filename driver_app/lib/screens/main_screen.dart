import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../driver_registration.dart';
import '../l10n/app_strings.dart';
import '../motion.dart';
import '../tracking_controller.dart';
import '../widgets/icon_chip_button.dart';
import '../widgets/info_modal.dart';
import '../widgets/track_button.dart';
import 'settings_screen.dart';

/// 2. 메인 — 운행 시작/정지 버튼, 다음 정류장 확인용 칩, 지속추적 스위치. mvp-spec 참고.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  void initState() {
    super.initState();
    TrackingController.load();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    final busNumber = DriverRegistration.busNumber ?? '';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 22,
        title: Text(AppStrings.appName, style: TextStyle(fontWeight: FontWeight.w800, color: p.ink)),
        actions: [
          IconChipButton(
            icon: Icons.info_outline,
            tooltip: AppStrings.infoButtonHint,
            onPressed: () => showInfoModal(context),
          ),
          const SizedBox(width: 8),
          IconChipButton(
            icon: Icons.settings_outlined,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 22),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ValueListenableBuilder<bool>(
                  valueListenable: TrackingController.isTracking,
                  builder: (context, tracking, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TrackButton(tracking: tracking, onTap: TrackingController.toggleTracking),
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(fontSize: 13, color: p.inkDim),
                            children: [
                              TextSpan(
                                text: AppStrings.vehicleCaption(busNumber),
                                style: TextStyle(fontWeight: FontWeight.bold, color: p.ink),
                              ),
                              TextSpan(text: ' · '),
                              TextSpan(
                                text: tracking ? AppStrings.sendingOkCaption : AppStrings.sendingStoppedCaption,
                                style: TextStyle(
                                  color: tracking ? p.tracking : p.inkDim,
                                  fontWeight: tracking ? FontWeight.w700 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 14),
                      AnimatedOpacity(
                        opacity: tracking ? 1 : 0,
                        duration: motionDuration(context, const Duration(milliseconds: 220)),
                        curve: motionCurve,
                        child: IgnorePointer(
                          ignoring: !tracking,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                            constraints: const BoxConstraints(maxWidth: 300),
                            decoration: BoxDecoration(color: p.trackingSoft, borderRadius: BorderRadius.circular(99)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on_outlined, size: 18, color: p.tracking),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${AppStrings.nextStopLabel} · ',
                                          style: TextStyle(fontWeight: FontWeight.w600, color: p.inkFaint, fontSize: 15),
                                        ),
                                        TextSpan(
                                          text: TrackingController.nextStopName,
                                          style: TextStyle(fontWeight: FontWeight.bold, color: p.ink, fontSize: 15),
                                        ),
                                        TextSpan(
                                          text: ' · ${TrackingController.nextStopEtaMinutes}${AppStrings.etaMinutesUnit}',
                                          style: TextStyle(fontWeight: FontWeight.w700, color: p.tracking, fontSize: 15),
                                        ),
                                      ],
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 지속추적 토글 자체는 설정화면으로 옮김(항상 켜둘 값이라 세션마다 결정할 게 아님) —
            // 여기는 동작 설명 + 운영 팁만 안내. warn(amber)은 "에러인가?" 오해를 살 수 있어서
            // info 톤(중립 배경 + accent 아이콘, 굵은 ink 텍스트)으로 눈에 띄되 경고처럼 안 보이게.
            Container(
              margin: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: p.panelMuted, borderRadius: BorderRadius.circular(16)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: p.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppStrings.mainTrackingNotice,
                      style: TextStyle(fontSize: 11.5, height: 1.5, fontWeight: FontWeight.w600, color: p.inkDim),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
