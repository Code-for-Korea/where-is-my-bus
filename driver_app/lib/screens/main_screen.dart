import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_colors.dart';
import '../driver_registration.dart';
import '../l10n/app_strings.dart';
import '../tracking_controller.dart';
import '../widgets/icon_chip_button.dart';
import '../widgets/info_modal.dart';
import '../widgets/track_button.dart';
import 'settings_screen.dart';

/// 2. 메인 — 운행 시작/정지 버튼, 배정 노선, 서버가 보는 위치(이전·현재·다음 정류장), 안내문. mvp-spec 참고.
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
    TrackingController.lastError.addListener(_showErrorIfAny);
    DriverRegistration.revision.addListener(_onRegistrationChanged);
    // 화면이 열릴 때 서버의 최신 차량 번호·배정 노선을 받아오고, 열린 운행이 있으면 위치 전송을 재개한다.
    TrackingController.syncWithServer();
  }

  @override
  void dispose() {
    TrackingController.lastError.removeListener(_showErrorIfAny);
    DriverRegistration.revision.removeListener(_onRegistrationChanged);
    super.dispose();
  }

  void _onRegistrationChanged() {
    if (mounted) setState(() {});
  }

  void _showErrorIfAny() {
    final message = TrackingController.lastError.value;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
                child: SingleChildScrollView(
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
                        _RouteChip(routeName: DriverRegistration.routeName),
                        if (tracking) ...[
                          const SizedBox(height: 14),
                          ValueListenableBuilder<TripPosition?>(
                            valueListenable: TrackingController.position,
                            builder: (context, position, _) => _PositionPanel(position: position),
                          ),
                        ],
                      ],
                    ),
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

/// 관리자가 이 차량에 배정한 노선. 배정이 없으면 운행을 시작할 수 없다는 경고를 항상 보여준다.
class _RouteChip extends StatelessWidget {
  const _RouteChip({required this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    final assigned = routeName != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(color: assigned ? p.trackingSoft : p.warnSoft, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(assigned ? Icons.route_outlined : Icons.warning_amber_rounded, size: 18, color: assigned ? p.tracking : p.warn),
          const SizedBox(width: 7),
          Flexible(
            child: assigned
                ? Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${AppStrings.routeLabel} · ',
                          style: TextStyle(fontWeight: FontWeight.w600, color: p.inkFaint, fontSize: 15),
                        ),
                        TextSpan(
                          text: routeName,
                          style: TextStyle(fontWeight: FontWeight.bold, color: p.ink, fontSize: 15),
                        ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  )
                : Text(
                    AppStrings.noRouteBanner,
                    style: TextStyle(fontWeight: FontWeight.w700, color: p.warn, fontSize: 13.5),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 서버가 이 버스를 어디로 보고 있는지: 이전 · 현재(정차 중) · 다음 정류장. 운전자가 "시스템이 내 위치를 제대로 보고 있나"
/// 확인하는 용도다. 정류장에서 막 출발했으면 현재는 "이동 중"이다.
class _PositionPanel extends StatelessWidget {
  const _PositionPanel({required this.position});

  final TripPosition? position;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    final known = position != null;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(color: p.panelMuted, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text(
            AppStrings.positionTitle,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.inkFaint),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PositionCell(label: AppStrings.positionPrevious, name: position?.previous),
              _PositionCell(
                label: AppStrings.positionCurrent,
                name: known ? (position!.current ?? AppStrings.positionMoving) : null,
                highlight: position?.current != null,
              ),
              _PositionCell(label: AppStrings.positionNext, name: position?.next),
            ],
          ),
        ],
      ),
    );
  }
}

class _PositionCell extends StatelessWidget {
  const _PositionCell({required this.label, required this.name, this.highlight = false});

  final String label;
  final String? name;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: highlight ? p.tracking : p.inkFaint,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name ?? AppStrings.positionNone,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              color: highlight ? p.tracking : p.ink,
            ),
          ),
        ],
      ),
    );
  }
}
