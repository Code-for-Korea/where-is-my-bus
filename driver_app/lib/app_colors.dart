import 'package:flutter/material.dart';

/// 목업(아티팩트 cd691e97-db15-4998-8b02-6f44744d37bd) CSS 커스텀 프로퍼티(:root)와
/// 1:1 대응하는 색상 토큰. Material3 seed 생성 색상 대신 이 값을 직접 써서 목업과
/// 동일한 색을 낸다.
class AppColors {
  AppColors._();

  static const light = AppPalette(
    frame: Color(0xFFFFFFFF),
    panelMuted: Color(0xFFF7F8FA),
    ink: Color(0xFF12141A),
    inkDim: Color(0xFF6B7280),
    inkFaint: Color(0xFF9AA1AD),
    border: Color(0xFFE6E8EC),
    accent: Color(0xFF4F46E5),
    trackBtn: Color(0xFF2563EB),
    trackBtnIdle: Color(0xFFD3D7DE),
    trackBtnIdleInk: Color(0xFF4B5160),
    tracking: Color(0xFF059669),
    trackingSoft: Color(0xFFE7F7F1),
    // 등록 실패 배너용으로 예약 — register API가 실제로 붙어 실패 케이스가 생기면 사용
    // (driver_registration.dart 참고). 그 전까진 호출부 없음.
    warn: Color(0xFFD97706),
    warnSoft: Color(0xFFFEF3E2),
  );

  static const dark = AppPalette(
    frame: Color(0xFF1A1D26),
    panelMuted: Color(0xFF21252F),
    ink: Color(0xFFF1F2F6),
    inkDim: Color(0xFF9AA1AD),
    inkFaint: Color(0xFF6B7280),
    border: Color(0xFF2C303C),
    accent: Color(0xFF6A63F1),
    trackBtn: Color(0xFF3B82F6),
    trackBtnIdle: Color(0xFF383C47),
    trackBtnIdleInk: Color(0xFFB0B5C0),
    tracking: Color(0xFF34D399),
    trackingSoft: Color(0xFF16302A),
    warn: Color(0xFFF0A734),
    warnSoft: Color(0xFF362A16),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

class AppPalette {
  const AppPalette({
    required this.frame,
    required this.panelMuted,
    required this.ink,
    required this.inkDim,
    required this.inkFaint,
    required this.border,
    required this.accent,
    required this.trackBtn,
    required this.trackBtnIdle,
    required this.trackBtnIdleInk,
    required this.tracking,
    required this.trackingSoft,
    required this.warn,
    required this.warnSoft,
  });

  final Color frame;
  final Color panelMuted;
  final Color ink;
  final Color inkDim;
  final Color inkFaint;
  final Color border;
  final Color accent;
  final Color trackBtn;
  final Color trackBtnIdle;
  final Color trackBtnIdleInk;
  final Color tracking;
  final Color trackingSoft;
  final Color warn;
  final Color warnSoft;
}
