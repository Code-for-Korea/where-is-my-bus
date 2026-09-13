import 'language_settings.dart';

/// 자체 구현 로컬라이제이션 (한/영 2개 언어).
///
/// intl/ARB 코드생성 파이프라인 대신 record 타입으로 문자열 쌍을 직접 정의한다.
/// 참고: xenoNote/Dev_knowledge/setup/flutter_app_polish_patterns.md §11.
/// 언어가 3개 이상으로 늘어나면 표준 flutter gen-l10n/ARB(§11-1)로 전환을 검토할 것.
class AppStrings {
  AppStrings._();

  static String _t(({String ko, String en}) pair) =>
      LanguageSettings.current == AppLanguage.ko ? pair.ko : pair.en;

  // ---- 공통 ----
  static String get appName => _t((ko: '로컬버스 알리미', en: 'Where is My BUS'));
  static String get poweredBy => _t((ko: 'powered by', en: 'powered by'));

  // ---- 0. 스플래시 ----
  static String get splashSubtitle => _t((ko: '운전자용', en: 'Driver'));
  static String get splashLoading => _t((ko: '불러오는 중…', en: 'Loading…'));

  // ---- 1. 온보딩 ----
  static String get onboardingSubtitle =>
      _t((ko: '운행 시작 전, 발급받은 정보를 등록하세요', en: 'Before you start, register the info you were given'));
  static String get serverUrlFieldLabel => _t((ko: '서버 주소 (adminUrl)', en: 'Server address (adminUrl)'));
  static String get serverUrlFieldHint =>
      _t((ko: '운영자에게 전달받은 주소를 정확히 입력하세요.', en: 'Enter the address your operator gave you exactly.'));
  static String get pinFieldLabel => _t((ko: 'PIN', en: 'PIN'));
  static String get registerButton => _t((ko: '등록하고 시작하기', en: 'Register and start'));
  static String get qrScanComingSoon => _t((ko: 'QR로 스캔 (준비 중)', en: 'Scan QR (coming soon)'));
  static String get pinInvalidError =>
      _t((ko: 'PIN이 올바르지 않습니다. 운영자에게 다시 확인해 주세요.', en: 'Invalid PIN. Please check with your operator.'));

  // ---- 2. 메인 ----
  static String get trackingActiveState => _t((ko: '운행 중', en: 'On duty'));
  static String get trackingActiveAction => _t((ko: '탭하면 운행정지', en: 'Tap to stop'));
  static String get trackingIdleState => _t((ko: '정지됨', en: 'Stopped'));
  static String get trackingIdleAction => _t((ko: '탭하면 운행시작', en: 'Tap to start'));
  // 메인화면 안내문 — 지속추적 토글 자체는 설정화면으로 옮기고, 메인엔 동작 설명 + 운영 팁만 노출.
  static String get mainTrackingNotice => _t((
        ko: '앱을 나가도 위치 전송이 지속됩니다. 단, 원활한 버스위치 정보 전송을 위해서는 기기를 전원에 연결하고, 운행중에는 앱 화면을 켜두시길 권장합니다.',
        en: 'Location keeps sending even after you leave the app. For reliable transmission, keep the device connected to power and the screen on while driving.',
      ));
  /// 차량 번호가 들어가는 캡션 — 한/영 어순이 달라 템플릿을 분리한다.
  static String vehicleCaption(String busNumber) =>
      _t((ko: '$busNumber번 차량', en: 'Bus No. $busNumber'));
  static String get sendingOkCaption => _t((ko: '30초 이내 최신 위치 전송됨', en: 'Last position sent within 30s'));
  static String get sendingStoppedCaption => _t((ko: '위치가 전송되지 않고 있어요', en: 'Position is not being sent'));
  static String get nextStopLabel => _t((ko: '다음', en: 'Next'));
  static String get etaMinutesUnit => _t((ko: '분', en: 'min'));

  // ---- 3. 설정 ----
  static String get settingsTitle => _t((ko: '설정', en: 'Settings'));
  static String get deviceRegistrationGroup => _t((ko: '단말 등록 정보', en: 'Device registration'));
  static String get deviceIdLabel => _t((ko: '기기 식별자', en: 'Device ID'));
  static String get serverUrlLabel => _t((ko: '서버 주소', en: 'Server address'));
  static String get reregisterLabel => _t((ko: 'PIN으로 재등록', en: 'Re-register with PIN'));
  static String get statusViewLabel => _t((ko: '상태보기 (로그)', en: 'Status (logs)'));
  static String get displayGroup => _t((ko: '표시', en: 'Display'));
  static String get languageLabel => _t((ko: '언어', en: 'Language'));
  static String get languageKoOption => _t((ko: '한국어', en: 'Korean'));
  static String get languageEnOption => _t((ko: 'English', en: 'English'));
  static String get themeLabel => _t((ko: '테마', en: 'Theme'));
  static String get themeCycleHint =>
      _t((ko: '테마 전환 (시스템/라이트/다크 순환)', en: 'Switch theme (cycles system/light/dark)'));
  static String get infoButtonHint => _t((ko: '이 프로젝트에 대해', en: 'About this project'));
  static String get keepTrackingLabel => _t((ko: '지속 추적', en: 'Keep tracking'));
  // "계속 전송"은 보장이 아니라 최선노력(best-effort) — 기기가 강제 종료하면 중단될 수 있어
  // 단정적 문구 대신 힌트를 남긴다. ISSUE.md "지속추적 문구" 참고.
  static String get keepTrackingSub => _t((
        ko: '앱을 나가도 전송을 이어가요 · 기기가 종료하면 중단될 수 있어요',
        en: 'Keeps sending after you leave the app — may stop if the OS closes it',
      ));
  static String get locationValuesLabel => _t((ko: '정확도 / 거리 필터 / 주기', en: 'Accuracy / distance filter / interval'));
  static String get fixedValuePill => _t((ko: '고정값', en: 'Fixed'));

  // ---- 프로젝트 소개 모달 ----
  static String get infoModalTitle => _t((ko: '로컬버스 알리미란?', en: 'What is Where is My BUS?'));
  static String get infoModalBody => _t((
        ko: '우리는 버스가 언제 올지... 막연히 기다려야하는 시골버스의 불편함을 기술로 해결하고 싶었습니다. 이 앱은 그 오픈소스 프로젝트의 운전자용 위치 전송 도구입니다.',
        en: "We wanted technology to fix the frustration of waiting for a rural bus with no idea when it'll show up. This app is that open-source project's driver-side location tool.",
      ));
  static String get infoModalLinkLabel => _t((ko: '자세히 보기', en: 'Learn more'));

  // ---- 4. 상태보기 ----
  static String get statusTitle => _t((ko: '상태보기', en: 'Status'));
  static String get trackingStatusLabel => _t((ko: '추적 상태', en: 'Tracking status'));
  static String get lastSentLabel => _t((ko: '마지막 전송', en: 'Last sent'));
  static String get lastCoordLabel => _t((ko: '최근 좌표', en: 'Last position'));
  static String get keepTrackingStatusLabel => _t((ko: '지속 추적', en: 'Keep tracking'));
  static String get onValue => _t((ko: '켜짐', en: 'On'));
  static String get offValue => _t((ko: '꺼짐', en: 'Off'));
  static String get logsGroup => _t((ko: '로그', en: 'Logs'));
  static String get logTrackingStarted => _t((ko: '추적 시작', en: 'Tracking started'));
  static String get logTrackingStopped => _t((ko: '추적 정지', en: 'Tracking stopped'));
  static String get noLogsYet => _t((ko: '아직 기록이 없습니다', en: 'No logs yet'));
  static String lastSentSecondsAgo(int seconds) => _t((ko: '$seconds초 전', en: '${seconds}s ago'));
  static String get lastSentNever => _t((ko: '—', en: '—'));
}
