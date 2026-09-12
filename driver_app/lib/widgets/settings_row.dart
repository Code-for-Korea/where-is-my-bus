import 'package:flutter/material.dart';

import '../app_colors.dart';

/// 목업의 ".settings-group-title" — 그룹 제목(11px/700/uppercase, inkFaint).
class SettingsGroupTitle extends StatelessWidget {
  const SettingsGroupTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: p.inkFaint),
      ),
    );
  }
}

/// 목업의 ".list-row"(dense: true, 13px inkDim) / ".row-link"(dense: false, 14px/600) —
/// 좌측 라벨 + 우측 값(또는 화살표), 위쪽 보더. 그룹의 첫 줄은 [isFirst]로 보더를 뺀다.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    required this.trailing,
    this.isFirst = false,
    this.onTap,
    this.labelColor,
    this.dense = false,
    this.subtitle,
  });

  final String label;
  final Widget trailing;
  final bool isFirst;
  final VoidCallback? onTap;
  final Color? labelColor;
  final bool dense;
  /// 라벨 아래 붙는 별도 한 줄 설명. 라벨+trailing은 한 줄(같은 Row)에 나란히 두고,
  /// subtitle은 그 아래 전체 폭을 쓰는 독립된 줄로 뺀다 — trailing이 라벨과 같은 줄에서
  /// 정확히 나란히 보이게.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    final labelStyle = dense
        ? TextStyle(fontSize: 13, color: labelColor ?? p.inkDim)
        : TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: labelColor ?? p.ink);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          border: isFirst ? null : Border(top: BorderSide(color: p.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(width: 14),
                Flexible(child: trailing),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!, style: TextStyle(fontSize: 11, color: p.inkFaint)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 목업의 ".list-row .value" — 14px/700 monospace, 말줄임.
class SettingsValueText extends StatelessWidget {
  const SettingsValueText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}
