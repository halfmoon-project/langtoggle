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
    ///
    /// startingUpdater: false 로 만들고 직접 start() 한다. true 로 두면 시작 실패를 에러가 아니라
    /// 모달 경고창으로 알리는데, LSUIElement 앱에서는 그 창이 보이지도 않는 채 프로세스가 붙잡힌다 —
    /// 사용자 눈에는 키캡이 이유 없이 멈춘 걸로 보인다. 피드 주소 오타나 키 불일치 하나면 그 상태가 된다.
    /// 업데이트를 못 하는 것보다 앱이 안 뜨는 게 훨씬 나쁘므로, 실패는 로그로만 남기고 넘어간다.
    static func start() {
        guard available, controller == nil else { return }
        let c = SPUStandardUpdaterController(startingUpdater: false,
                                             updaterDelegate: nil,
                                             userDriverDelegate: nil)
        do {
            try c.updater.start()
        } catch {
            NSLog("LangToggle: 업데이터 시작 실패 — \(error). --check-update 로 확인할 것")
            return
        }
        controller = c
    }

    /// 수동 확인. .accessory 앱이라 활성화를 안 하면 Sparkle 창이 다른 앱 뒤에서 뜬다 —
    /// 여기서만 포커스를 가져온다(키캡 클릭은 여전히 안 뺏는다).
    static func checkNow() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// --check-update. 업데이트가 왜 안 오는지 볼 때 쓴다. UI 없이 피드만 받아 보고
    /// Sparkle 이 뭘 보고 있는지 그대로 찍는다. 번들 안에서 실행해야 Info.plist 가 읽힌다:
    ///   /Applications/LangToggle.app/Contents/MacOS/LangToggle --check-update
    static func probe() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let probe = Probe()
        // startingUpdater: false 로 만들어 직접 시작한다 — true 로 두면 시작 실패를 에러가 아니라
        // 모달 경고창으로 알려서, 백그라운드 앱에서는 보이지도 않는 창에 막혀 그냥 멈춘다.
        let c = SPUStandardUpdaterController(startingUpdater: false,
                                             updaterDelegate: probe, userDriverDelegate: nil)
        let u = c.updater
        print("번들            : \(Bundle.main.bundlePath)")
        print("현재 버전       : \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")")
        print("피드            : \(u.feedURL?.absoluteString ?? "(없음)")")
        do {
            try u.start()
            print("startUpdater    : OK")
        } catch {
            print("startUpdater    : 실패 — \(error)")
            return
        }
        print("자동 확인       : \(u.automaticallyChecksForUpdates)")
        print("확인 주기       : \(u.updateCheckInterval)초")
        print("마지막 확인     : \(u.lastUpdateCheckDate.map(String.init(describing:)) ?? "(없음)")")
        print("확인 가능       : \(u.canCheckForUpdates)")
        print("진행 중인 세션  : \(u.sessionInProgress)")
        print("--- 확인 시작 ---")
        u.checkForUpdateInformation()
        RunLoop.main.run(until: Date().addingTimeInterval(30))
        print("--- 30초 경과, 종료 ---")
    }

    /// probe() 전용 델리게이트.
    private final class Probe: NSObject, SPUUpdaterDelegate {
        func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
            print("appcast 로드됨 — 항목 \(appcast.items.count)개: "
                + appcast.items.map(\.displayVersionString).joined(separator: ", "))
        }

        func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            print("업데이트 발견 — \(item.displayVersionString)  \(item.fileURL?.absoluteString ?? "")")
        }

        func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
            print("업데이트 없음 — \(error.localizedDescription)")
        }

        func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
            print("중단 — \(error.localizedDescription)")
        }
    }
}
