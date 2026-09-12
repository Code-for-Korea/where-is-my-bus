import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 목업(로컬버스 알리미)의 버스 로고 — lucide "bus" 아이콘 SVG를 그대로 사용.
/// Material의 Icons.directions_bus는 모양이 달라서, 스플래시/온보딩 브랜드 글리프와
/// 운행 중 상태 아이콘에서 목업과 동일한 모양이 필요해 이 위젯으로 통일한다.
class BusIcon extends StatelessWidget {
  const BusIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  static const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
<path d="M8 6v6"/><path d="M15 6v6"/><path d="M2 12h19.6"/>
<path d="M18 18h3s.5-1.7.8-2.8c.1-.4.2-.8.2-1.2 0-.4-.1-.8-.2-1.2l-1.4-5C20.1 6.8 19.1 6 18 6H4a2 2 0 0 0-2 2v10h3"/>
<circle cx="7" cy="18" r="2"/><path d="M9 18h5"/><circle cx="16" cy="18" r="2"/>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    // Material 아이콘(Icons.*)은 글리프 안에 여백이 내장돼 있지만 이 SVG는 24x24 꽉 채워
    // 그려서, 같은 size 값이면 Material 아이콘보다 시각적으로 커 보인다. 82%로 줄여서 맞춘다.
    final glyphSize = size * 0.82;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: SvgPicture.string(
          _svg,
          width: glyphSize,
          height: glyphSize,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
  }
}
