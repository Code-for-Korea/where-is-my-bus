import 'package:flutter/material.dart';

/// 암묵적 애니메이션(AnimatedContainer 등)에 쓰는 공용 duration/curve.
/// prefers-reduced-motion(OS 설정)이 켜져 있으면 즉시 전환(0ms)한다.
/// apple-design 스킬 §1(응답성)·§14(접근성) 참고.
Duration motionDuration(BuildContext context, Duration base) =>
    MediaQuery.of(context).disableAnimations ? Duration.zero : base;

const motionCurve = Curves.easeOutCubic;
