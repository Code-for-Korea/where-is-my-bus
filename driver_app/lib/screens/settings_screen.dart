import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_colors.dart';
import '../driver_registration.dart';
import '../l10n/app_strings.dart';
import '../l10n/language_settings.dart';
import '../theme_settings.dart';
import '../tracking_controller.dart';
import '../widgets/icon_chip_button.dart';
import '../widgets/info_modal.dart';
import '../widgets/settings_row.dart';
import 'onboarding_screen.dart';
import 'status_screen.dart';

/// 3. 설정 — 표시(언어/테마), 단말 등록 정보(읽기전용 + 재등록), 상태보기, 위치 추적 고정값.
/// mvp-spec 참고.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: p.inkDim), onPressed: () => Navigator.pop(context)),
        title: Text(AppStrings.settingsTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 22),
            child: IconChipButton(
              icon: Icons.info_outline,
              tooltip: AppStrings.infoButtonHint,
              onPressed: () => showInfoModal(context),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          SettingsGroupTitle(AppStrings.displayGroup),
          SettingsRow(
            isFirst: true,
            dense: true,
            label: AppStrings.languageLabel,
            trailing: _LanguageSelect(),
          ),
          SettingsRow(
            dense: true,
            label: AppStrings.themeLabel,
            trailing: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeSettings.mode,
              builder: (context, mode, _) => IconChipButton(
                size: 34,
                tooltip: AppStrings.themeCycleHint,
                icon: _themeIcon(mode),
                onPressed: ThemeSettings.cycle,
              ),
            ),
          ),
          SettingsGroupTitle(AppStrings.deviceRegistrationGroup),
          SettingsRow(
            isFirst: true,
            dense: true,
            label: AppStrings.deviceIdLabel,
            trailing: SettingsValueText(DriverRegistration.deviceId ?? ''),
          ),
          SettingsRow(
            dense: true,
            label: AppStrings.serverUrlLabel,
            trailing: SettingsValueText(DriverRegistration.adminUrl ?? ''),
          ),
          SettingsRow(
            label: AppStrings.statusViewLabel,
            trailing: Icon(Icons.chevron_right, size: 16, color: p.inkFaint),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatusScreen())),
          ),
          // 지속추적 하나뿐인 그룹이라 그룹 제목은 생략 — 대신 위 그룹과의 간격만 확보.
          const SizedBox(height: 18),
          SettingsRow(
            isFirst: true,
            dense: true,
            label: AppStrings.keepTrackingLabel,
            subtitle: AppStrings.keepTrackingSub,
            // 기본 Switch가 접근성용 여백까지 포함해 다른 설정 요소(34px 아이콘칩 등)보다
            // 눈에 띄게 큼 — shrinkWrap으로 그 여백만 제거해 비율을 맞춘다.
            trailing: ValueListenableBuilder<bool>(
              valueListenable: TrackingController.keepTracking,
              builder: (context, keepTracking, _) => Switch(
                value: keepTracking,
                onChanged: (value) => TrackingController.setKeepTracking(value),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          // 지속추적 바로 위 SettingsRow와 똑같은 행 스타일(라벨+trailing, 보더)을 쓰면
          // 조작 불가능한 참고값인데도 실제 토글처럼 보여서 어색했다 — 행이 아니라
          // 캡션 한 줄로 격을 낮춰서 "그냥 정보"라는 걸 분명히 한다.
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
            child: Text(
              '${AppStrings.locationValuesLabel} · ${AppStrings.fixedValuePill} HIGH · 30m · 30s',
              style: TextStyle(fontSize: 11, color: p.inkFaint),
            ),
          ),
          // 거의 안 쓰는 옵션이라 맨 아래 — 그룹 제목 없이 독립된 줄로.
          const SizedBox(height: 18),
          SettingsRow(
            isFirst: true,
            label: AppStrings.reregisterLabel,
            labelColor: p.accent,
            trailing: Icon(Icons.chevron_right, size: 16, color: p.inkFaint),
            onTap: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              (route) => false,
            ),
          ),
          const _AppVersionFooter(),
        ],
      ),
    );
  }

  IconData _themeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
        ThemeMode.system => Icons.brightness_auto_outlined,
      };
}

/// 설정화면 하단 앱 버전 — tiny-cloud(SettingsOverlay) 표기 방식 참고:
/// 중앙 정렬, 옅은 색, "v{version}" 형식.
class _AppVersionFooter extends StatelessWidget {
  const _AppVersionFooter();

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final version = snapshot.data?.version;
          if (version == null) return const SizedBox.shrink();
          return Center(
            child: Text(
              'v$version',
              style: TextStyle(fontSize: 12, color: p.inkFaint, letterSpacing: 1.5),
            ),
          );
        },
      ),
    );
  }
}

/// 목업의 ".lang-select" — panel-muted 배경의 둥근 드롭다운.
class _LanguageSelect extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
      decoration: BoxDecoration(color: p.panelMuted, borderRadius: BorderRadius.circular(9)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppLanguage>(
          // "시스템 기본값"은 선택지에서 제외 — 최초엔 시스템 언어로 자동감지된 현재 값을 보여주고,
          // 고르면 그때부터 명시적 override로 고정(LanguageSettings.current 참고).
          value: LanguageSettings.current,
          isDense: true,
          icon: Icon(Icons.expand_more, size: 15, color: p.inkFaint),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink),
          dropdownColor: p.frame,
          onChanged: (value) => LanguageSettings.setLanguage(value),
          items: [
            DropdownMenuItem(value: AppLanguage.ko, child: Text(AppStrings.languageKoOption)),
            DropdownMenuItem(value: AppLanguage.en, child: Text(AppStrings.languageEnOption)),
          ],
        ),
      ),
    );
  }
}
