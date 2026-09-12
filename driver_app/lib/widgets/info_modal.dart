import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../l10n/app_strings.dart';

/// 프로젝트 소개 모달 — 메인/설정 화면 앱바 (i) 아이콘에서 공용으로 연다.
/// 앱 전역 테마(시스템/라이트/다크 설정)를 그대로 따른다.
Future<void> showInfoModal(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.of(context).frame,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (context) {
      final p = AppColors.of(context);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(AppStrings.infoModalTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink)),
                  IconButton(
                    icon: Icon(Icons.close, color: p.inkFaint),
                    onPressed: () => Navigator.pop(context),
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
                ],
              ),
              Text(
                AppStrings.infoModalBody,
                style: TextStyle(fontSize: 13.5, height: 1.7, color: p.inkDim),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.trackBtn,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  // TODO: 등록된 서버의 /about 페이지를 외부 브라우저로 열기 — url_launcher 필요, 서버 주소 확정 후 연결
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(AppStrings.infoModalLinkLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Text(AppStrings.poweredBy, style: TextStyle(fontSize: 11, color: p.inkFaint)),
                    const SizedBox(height: 4),
                    Text('CODE FOR KOREA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.ink)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
