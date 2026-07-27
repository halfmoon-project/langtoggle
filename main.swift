import Cocoa
import Carbon
import ServiceManagement

/// 사용자 커스텀 아이콘. 번들 안을 건드리면 ad-hoc 서명이 깨지므로 밖에 둔다.
let overrideDir = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/Application Support/LangToggle")
/// 기본 아이콘. 번들이면 Contents/Resources/assets, 맨 바이너리면 ./assets 로 같이 해석된다.
let bundledDir = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("assets")

// MARK: - Input source

private func str(_ s: TISInputSource, _ key: CFString) -> String {
    guard let p = TISGetInputSourceProperty(s, key) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

private func bool(_ s: TISInputSource, _ key: CFString) -> Bool {
    guard let p = TISGetInputSourceProperty(s, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
}

/// Enabled keyboard sources the user can actually switch to, in system order.
func keyboardSources() -> [TISInputSource] {
    let all = TISCreateInputSourceList(nil, false)!.takeRetainedValue() as! [TISInputSource]
    return all.filter {
        str($0, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String)
            && bool($0, kTISPropertyInputSourceIsSelectCapable)
    }
}

func currentID() -> String {
    str(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID)
}

/// 입력 소스가 표방하는 언어들. 첫 값이 대표 언어다 — "ko", "en", "ja", "zh-Hans" …
private func languages(_ s: TISInputSource) -> [String] {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceLanguages) else { return [] }
    return Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as? [String] ?? []
}

func currentLanguage() -> String {
    languages(TISCopyCurrentKeyboardInputSource().takeRetainedValue()).first ?? "en"
}

/// "zh-Hans" → ["zh-Hans", "zh", "en"]. 지역 태그가 붙어 와도 기본 아이콘을 찾아가고,
/// 매핑이 없는 언어(독일어·프랑스어처럼 라틴 자판)는 en 으로 떨어진다.
func assetChain(_ lang: String) -> [String] {
    var chain = [lang]
    if let base = lang.split(separator: "-").first.map(String.init), base != lang { chain.append(base) }
    if !chain.contains("en") { chain.append("en") }
    return chain
}

/// ponytail: cycles the enabled sources like Cmd+Space. With ABC + 2-Set Korean that IS 한/영.
func toggleLanguage() {
    let sources = keyboardSources()
    guard sources.count > 1 else { return }
    let cur = currentID()
    let i = sources.firstIndex { str($0, kTISPropertyInputSourceID) == cur } ?? 0
    TISSelectInputSource(sources[(i + 1) % sources.count])
}

// MARK: - Self check

if CommandLine.arguments.contains("--dump") {
    let v = IconView(frame: NSRect(x: 0, y: 0, width: 88, height: 88))
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "/tmp/langtoggle-render.png"))
    print("dumped /tmp/langtoggle-render.png")
    exit(0)
}

if CommandLine.arguments.contains("--selftest") {
    let a = currentID()
    toggleLanguage(); usleep(300_000)
    let b = currentID()
    assert(a != b, "toggle did not change input source (stuck on \(a))")
    toggleLanguage(); usleep(300_000)
    assert(currentID() == a, "toggle back failed (\(currentID()) != \(a))")
    print("selftest ok: \(a) <-> \(b)")
    exit(0)
}

// MARK: - Icon

final class IconView: NSView {
    /// 아이콘 PNG 가 하나도 없을 때 그릴 텍스트 배지. build_icons.py 의 GLYPHS 와 같이 고친다.
    /// 전역 let 으로 두면 안 된다 — main.swift 의 전역은 선언 문장이 실행돼야 초기화되는데
    /// --dump 가 그보다 먼저 IconView 를 그려서 초기화 전 메모리를 읽는다. 타입 프로퍼티는 지연 초기화라 안전하다.
    private static let glyphs = [
        "en": "A", "ko": "한", "ja": "あ", "zh": "中", "ru": "Я", "el": "Ω",
        "th": "ก", "ar": "ع", "he": "א", "hi": "अ", "vi": "Ư",
    ]

    private var downAt = NSPoint.zero
    private var images: [String: NSImage?] = [:]
    private var press: CGFloat = 0 { didSet { needsDisplay = true } }
    private var anim: Timer?

    /// 눌린 정도 0(올라옴) → 1(눌림). 누를 땐 즉각 내려가고, 뗄 땐 감쇠 진동으로 튕겨 올라온다.
    /// ponytail: 60fps 타이머 한 개. CASpringAnimation은 커스텀 스칼라엔 못 붙는다.
    private func setPress(_ target: CGFloat) {
        anim?.invalidate()
        let from = press, t0 = Date(), dur = target > 0 ? 0.05 : 0.32
        anim = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            let x = min(1, Date().timeIntervalSince(t0) / dur)
            let e = target > 0 ? x : 1 - exp(-7 * x) * cos(9 * x)  // 뗄 때만 오버슈트
            press = from + (target - from) * CGFloat(e)
            if x >= 1 { press = target; t.invalidate() }
        }
    }

    private func image(_ name: String) -> NSImage? {
        if let cached = images[name] { return cached }
        // 매핑 없는 언어면 그릴 때마다 디스크를 두드리게 되므로 실패도 캐시한다.
        let found = [overrideDir, bundledDir].lazy
            .compactMap { NSImage(contentsOf: $0.appendingPathComponent("\(name).png")) }
            .first
        images[name] = found
        return found
    }

    override func draw(_ dirty: NSRect) {
        // 눌리면 살짝 작아지면서 아래로 가라앉는다 — 3/4 뷰에서 키캡이 눌리는 방향.
        let rect = bounds
            .insetBy(dx: bounds.width * 0.05 * press, dy: bounds.height * 0.05 * press)
            .offsetBy(dx: 0, dy: -bounds.height * 0.05 * press)
        // 바디는 모든 언어가 공유하고, 그 위에 언어별 글리프 레이어만 갈아 끼운다.
        let chain = assetChain(currentLanguage())
        let body = image("keycap")
        let glyph = chain.lazy.compactMap { self.image($0) }.first
        if body != nil || glyph != nil {
            body?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            glyph?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }
        // ponytail: text badge fallback when the keycap PNGs are missing
        NSColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1).setFill() // halfmoon gray.800
        NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        let text = NSAttributedString(string: chain.lazy.compactMap { Self.glyphs[$0] }.first ?? "A", attributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor(red: 0.973, green: 0.980, blue: 0.988, alpha: 1), // gray.50
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }

    // 패널이 key window가 안 되므로, 이게 없으면 첫 클릭이 삼켜진다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        downAt = e.locationInWindow
        setPress(1)
    }

    override func mouseDragged(with e: NSEvent) {
        let moved = hypot(e.locationInWindow.x - downAt.x, e.locationInWindow.y - downAt.y)
        // performDrag는 마우스를 삼켜서 mouseUp이 안 온다 — 여기서 미리 올려준다.
        if moved > 3 { setPress(0); window?.performDrag(with: e) }
    }

    override func mouseUp(with e: NSEvent) {
        setPress(0)
        toggleLanguage()
    }

    override func rightMouseDown(with e: NSEvent) {
        let menu = NSMenu()
        let login = menu.addItem(withTitle: "로그인 시 자동 실행", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        // 맨 바이너리로 실행하면 등록할 번들이 없다.
        login.isEnabled = Bundle.main.bundleIdentifier != nil
        menu.addItem(.separator())
        menu.addItem(withTitle: "아이콘 새로고침", action: #selector(reloadImage), keyEquivalent: "").target = self
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.popUp(positioning: nil, at: e.locationInWindow, in: self)
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("LangToggle: 로그인 항목 토글 실패 — \(error)")
        }
        // 사용자가 시스템 설정에서 껐던 적이 있으면 수동 승인이 필요하다.
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc private func reloadImage() {
        images.removeAll()
        needsDisplay = true
    }
}

// MARK: - Floating panel

// 로그인 항목 + 더블클릭이면 키캡이 두 개 겹친다. (맨 바이너리는 bundleIdentifier가 없어 해당 없음)
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let side: CGFloat = 44
let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
panel.isFloatingPanel = true
panel.level = .floating
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
panel.contentView = IconView()

if let saved = UserDefaults.standard.string(forKey: "origin") {
    panel.setFrameOrigin(NSPointFromString(saved))
} else if let screen = NSScreen.main?.visibleFrame {
    panel.setFrameOrigin(NSPoint(x: screen.maxX - side - 20, y: screen.maxY - side - 20))
}
panel.orderFrontRegardless()

NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in
    UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "origin")
}
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: .main
) { _ in panel.contentView?.needsDisplay = true }

app.run()
