import Cocoa
import Sparkle

/// 자동 업데이트.
///
/// 기본값이 무음이라(Info.plist 의 SUAutomaticallyUpdate) 평소엔 아무것도 안 보인다 — 하루에 한 번
/// 조용히 확인하고, 새 버전이 있으면 받아 뒀다가 다음 실행 때 그걸로 뜬다. 로그인 시 자동 실행을
/// 켜 뒀다면 그 "다음 실행" 이 다음 로그인이라, 사용자 입장에선 어느 날 그냥 새 버전이 돼 있다.
/// 실행 중인 앱을 그 자리에서 갈아치우지 않는 이유는, 아직 메모리에 안 올라온 코드 페이지를
/// 나중에 폴트할 때 터지기 때문이다. Sparkle 이 Autoupdate 라는 별도 프로세스를 두는 이유이기도 하다.
///
/// 우클릭 메뉴의 "업데이트 확인" 은 그걸 기다리기 싫은 사람용 수동 경로다.
enum Updater {
    /// 맨 바이너리로 돌리면 읽을 Info.plist 도 갈아치울 번들도 없다.
    static let available = Bundle.main.bundleIdentifier != nil

    private static var controller: SPUStandardUpdaterController?

    /// 앱이 뜬 뒤 한 번 부른다. 이 시점부터 Sparkle 이 알아서 확인하러 다닌다.
    static func start() {
        guard available, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    /// 수동 확인. .accessory 앱이라 활성화를 안 하면 Sparkle 창이 다른 앱 뒤에서 뜬다 —
    /// 여기서만 포커스를 가져온다(키캡 클릭은 여전히 안 뺏는다).
    static func checkNow() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
