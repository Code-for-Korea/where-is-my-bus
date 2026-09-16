import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_colors.dart';
import '../driver_registration.dart';
import '../l10n/app_strings.dart';
import '../widgets/bus_icon.dart';
import 'main_screen.dart';

/// 1. 온보딩 — adminUrl + PIN을 한 화면에서 함께 입력. mvp-spec 참고.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _urlController = TextEditingController();
  final _pinController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _urlController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await DriverRegistration.register(url: _urlController.text, pin: _pinController.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(18)),
                child: const BusIcon(size: 28, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(AppStrings.appName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: p.ink)),
              const SizedBox(height: 4),
              Text(
                AppStrings.onboardingSubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: p.inkFaint),
              ),
              const SizedBox(height: 22),
              _Field(
                label: AppStrings.serverUrlFieldLabel,
                controller: _urlController,
                hint: AppStrings.serverUrlFieldHint,
              ),
              const SizedBox(height: 16),
              _Field(
                label: AppStrings.pinFieldLabel,
                controller: _pinController,
                large: true,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.arrow_forward, size: 17),
                  label: Text(AppStrings.registerButton, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                // QR 스캔은 후순위 기능(admin의 QR 생성 화면이 먼저 필요) — mvp-spec 참고, 버튼만 자리 표시.
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.inkDim,
                    side: BorderSide(color: p.border, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  onPressed: null,
                  icon: const Icon(Icons.qr_code, size: 15),
                  label: Text(AppStrings.qrScanComingSoon, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller, this.hint, this.large = false});

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.inkDim)),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          style: TextStyle(
            fontSize: large ? 20 : 15,
            letterSpacing: large ? 4 : 0,
            color: p.ink,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: p.panelMuted,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: p.border, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: p.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: p.accent, width: 1.5),
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: TextStyle(fontSize: 11, color: p.inkFaint)),
        ],
      ],
    );
  }
}
