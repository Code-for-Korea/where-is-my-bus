import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../l10n/app_strings.dart';
import '../motion.dart';
import 'bus_icon.dart';

const _buttonSize = 210.0;
const _ringSize = 230.0; // 목업 ".ring" — inset -10px = 버튼보다 지름 20px 큼

/// 운행 시작/정지 원형 버튼.
/// - 누르는 즉시(onTapDown) 살짝 눌리는 피드백 → 손을 떼거나 취소하면 원복(apple-design §1).
/// - 상태 전환(정지↔운행중)은 색/아이콘/문구가 순간 전환되지 않고 부드럽게 크로스페이드.
/// - 운행 중일 때 목업의 "pulse-ring"과 같은 확장·페이드 파형을 2.2s 주기로 반복.
class TrackButton extends StatefulWidget {
  const TrackButton({super.key, required this.tracking, required this.onTap});

  final bool tracking;
  final VoidCallback onTap;

  @override
  State<TrackButton> createState() => _TrackButtonState();
}

class _TrackButtonState extends State<TrackButton> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    if (widget.tracking) _pulseController.repeat();
  }

  @override
  void didUpdateWidget(covariant TrackButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tracking == oldWidget.tracking) return;
    if (widget.tracking) {
      _pulseController.repeat();
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    final tracking = widget.tracking;
    final fg = tracking ? Colors.white : p.trackBtnIdleInk;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return SizedBox(
      width: _ringSize,
      height: _ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (tracking) _PulseRing(controller: _pulseController, color: p.trackBtn, reduceMotion: reduceMotion),
          GestureDetector(
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _pressed ? 0.96 : 1,
              duration: motionDuration(context, const Duration(milliseconds: 110)),
              curve: motionCurve,
              child: AnimatedContainer(
                duration: motionDuration(context, const Duration(milliseconds: 260)),
                curve: motionCurve,
                width: _buttonSize,
                height: _buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tracking ? p.trackBtn : p.trackBtnIdle,
                  boxShadow: [
                    BoxShadow(
                      color: (tracking ? p.trackBtn : Colors.black).withValues(alpha: tracking ? 0.35 : 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: motionDuration(context, const Duration(milliseconds: 200)),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
                      child: tracking
                          ? BusIcon(key: const ValueKey(true), size: 40, color: fg)
                          : Icon(Icons.play_arrow, key: const ValueKey(false), size: 40, color: fg),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: motionDuration(context, const Duration(milliseconds: 180)),
                      child: Text(
                        tracking ? AppStrings.trackingActiveState : AppStrings.trackingIdleState,
                        key: ValueKey(tracking),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: fg),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: motionDuration(context, const Duration(milliseconds: 180)),
                      child: Text(
                        tracking ? AppStrings.trackingActiveAction : AppStrings.trackingIdleAction,
                        key: ValueKey(tracking),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: fg.withValues(alpha: 0.85)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.controller, required this.color, required this.reduceMotion});

  final AnimationController controller;
  final Color color;
  final bool reduceMotion;

  // 목업 ring 보더 색이 이미 45% 투명(color-mix)이고, 그 위에 keyframe opacity가 곱해진다.
  static const _baseAlpha = 0.45;

  @override
  Widget build(BuildContext context) {
    // 모션 줄이기 설정: 반복 애니메이션 대신 목업 CSS와 동일하게 정지된 낮은 투명도 링만 표시.
    if (reduceMotion) {
      return _ring(alpha: _baseAlpha * 0.4);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        final scale = 0.94 + 0.24 * t; // 목업 pulse-ring: scale(0.94) → scale(1.18)
        final alpha = _baseAlpha * 0.9 * (1 - t); // 목업 pulse-ring: opacity 0.9 → 0
        return Transform.scale(scale: scale, child: _ring(alpha: alpha));
      },
    );
  }

  Widget _ring({required double alpha}) {
    return Container(
      width: _ringSize,
      height: _ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: alpha), width: 2),
      ),
    );
  }
}
