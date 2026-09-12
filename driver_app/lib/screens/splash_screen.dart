import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../driver_registration.dart';
import '../l10n/app_strings.dart';
import '../widgets/bus_icon.dart';
import 'main_screen.dart';
import 'onboarding_screen.dart';

/// 0. 스플래시 — 저장된 등록 정보가 있으면 메인, 없으면 온보딩으로.
/// 앱 전역 테마(시스템/라이트/다크 설정)를 그대로 따른다.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _proceed();
  }

  Future<void> _proceed() async {
    await Future.delayed(const Duration(seconds: 3));
    await DriverRegistration.load();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DriverRegistration.isRegistered ? const MainScreen() : const OnboardingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Scaffold(
      backgroundColor: p.frame,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(26)),
                      child: const BusIcon(size: 42, color: Colors.white),
                    ),
                    const SizedBox(height: 18),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: p.ink),
                        children: [
                          TextSpan(text: AppStrings.appName),
                          const TextSpan(text: ' · '),
                          TextSpan(text: AppStrings.splashSubtitle, style: TextStyle(color: p.accent)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: p.accent),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 26),
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
  }
}
