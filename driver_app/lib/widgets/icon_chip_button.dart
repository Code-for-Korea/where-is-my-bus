import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../motion.dart';

/// 목업의 ".icon-btn" — 36x36 둥근 사각형 배경 위 아이콘 버튼.
/// 앱바 좌측(뒤로가기)·우측(정보/설정) 버튼에서 공용으로 쓴다. 아이콘이 바뀌면(테마 순환 버튼 등)
/// 순간 전환 대신 회전+페이드로 크로스페이드한다.
class IconChipButton extends StatelessWidget {
  const IconChipButton({super.key, required this.icon, this.onPressed, this.tooltip, this.size = 36});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    final button = Material(
      color: p.panelMuted,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: AnimatedSwitcher(
            duration: motionDuration(context, const Duration(milliseconds: 180)),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: RotationTransition(turns: Tween<double>(begin: 0.75, end: 1).animate(anim), child: child),
            ),
            child: Icon(icon, key: ValueKey(icon), size: size * 0.5, color: p.inkDim),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
