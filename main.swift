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

if CommandLine.arguments.contains("--click") {
    Sound.demo()
    exit(0)
}

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
    // 드래그 → 크기. -O 로 빌드하면 assert 가 지워지니 이 검사는 최적화 없이 돌린다.
    assert(IconView.dragSize(44, dx: 12, dy: 0) == 56, "오른쪽으로 끌면 커진다")
    assert(IconView.dragSize(44, dx: -12, dy: 0) == 32, "왼쪽으로 끌면 줄어든다")
    assert(IconView.dragSize(44, dx: 0, dy: 12) == 56, "아래로 끌면 커진다")
    assert(IconView.dragSize(44, dx: 3, dy: -12) == 32, "많이 움직인 축을 따른다")

    // 클릭 파형. 소리 자체는 귀로 확인하고(--click) 여기선 모양만 본다.
    for p in Sound.profiles {
        for v in [p.down, p.up] {
            let wave = Sound.render(v)
            let s = wave.floatChannelData![0], n = Int(wave.frameLength)
            assert(n == v.hits.map(Sound.length).max(), "\(p.id): 가장 늦게 끝나는 타격까지 담는다")
            assert((0..<n).allSatisfy { abs(s[$0]) <= v.peak + 0.0001 }, "\(p.id): 안 넘친다")
            // 최고점은 타격이 시작하는 자리다 — 어택이 뭉개졌으면 여기서 걸린다.
            let top = (0..<n).max { abs(s[$0]) < abs(s[$1]) }!
            assert(v.hits.contains { abs(Double(top) / 44100 - $0.at) < 0.002 }, "\(p.id): 어택이 선다")
            assert(abs(s[n - 1]) < 0.0001, "\(p.id): 꼬리가 0 으로 끝난다")
        }
    }
    // 소리 고르기. 사용자 설정을 건드리므로 끝나면 되돌려 놓는다.
    let keep = UserDefaults.standard.string(forKey: "sound")
    Sound.select(Sound.off)
    assert(Sound.current == nil, "끄면 무음")
    Sound.select("red")
    assert(Sound.current?.id == "red", "고른 소리를 그대로 돌려준다")
    Sound.select("없어진프리셋")
    assert(Sound.current?.id == Sound.profiles[0].id, "모르는 id 는 무음 말고 기본 소리로")
    if let keep { Sound.select(keep) } else { UserDefaults.standard.removeObject(forKey: "sound") }

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

    /// 크기 한계. 최대는 에셋이 정한다 — 키캡 PNG 가 176px 라 88pt 를 넘기면 레티나에서 뿌옇다.
    static let minSide: CGFloat = 28
    static let maxSide: CGFloat = 88

    /// 커서를 못 바꾸니(백그라운드 앱) 리사이즈 커서 모양을 그려서 대신 보여 준다.
    private static let gripIcon = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                                          accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 64, weight: .bold).applying(.init(paletteColors: [.white])))

    /// 드래그한 거리 → 새 크기. 많이 움직인 축을 1:1 로 따라간다(오른쪽·아래가 확대).
    /// 두 축을 섞어 평균 내면 커서보다 느리게 따라와서 손에 안 붙고, 큰 쪽만 쓰면 한 축으로는 안 줄어든다.
    static func dragSize(_ start: CGFloat, dx: CGFloat, dy: CGFloat) -> CGFloat {
        start + (abs(dx) > abs(dy) ? dx : dy)
    }

    private var hover = false { didSet { if hover != oldValue { needsDisplay = true } } }
    private var poll: Timer?
    private var downAt = NSPoint.zero
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero
    private var inGrip = false
    private var didResize = false
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
            drawGrip(rect)
            return
        }
        // ponytail: text badge fallback when the keycap PNGs are missing
        NSColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1).setFill() // halfmoon gray.800
        let r = bounds.width * 0.16
        NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: r, yRadius: r).fill()
        let text = NSAttributedString(string: chain.lazy.compactMap { Self.glyphs[$0] }.first ?? "A", attributes: [
            .font: NSFont.systemFont(ofSize: bounds.height * 0.45, weight: .semibold),
            .foregroundColor: NSColor(red: 0.973, green: 0.980, blue: 0.988, alpha: 1), // gray.50
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        drawGrip(rect)
    }

    /// 손잡이에 마우스를 올렸을 때만 뜨는 화살표. 평소엔 키캡을 깨끗하게 둔다.
    /// 좌표는 키캡 아트의 오른쪽 옆면 위 — 정확히 모서리에 두면 투명한 여백에 그려진다.
    private func drawGrip(_ rect: NSRect) {
        guard hover, let icon = Self.gripIcon else { return }
        let d = rect.width * 0.24
        icon.draw(in: NSRect(x: rect.minX + rect.width * 0.66 - d / 2,
                             y: rect.minY + rect.height * 0.28 - d / 2, width: d, height: d),
                  from: .zero, operation: .sourceOver, fraction: 0.85)
    }

    // 패널이 key window가 안 되므로, 이게 없으면 첫 클릭이 삼켜진다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // 포커스를 안 뺏는 패널이라 커서는 못 바꾼다 — 백그라운드 앱의 NSCursor.set() 은 무시된다.
    // 창 단위 진입/이탈만 오고 창 안쪽 영역 진입도 mouseMoved 도 안 온다.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    /// 그래서 커서가 손잡이 위에 있는지는 창 안에 들어와 있는 동안만 좌표를 훑어서 안다.
    /// ponytail: 15Hz 폴링. 들어와 있을 때만 돌고 나가면 멈춘다.
    override func mouseEntered(with e: NSEvent) {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1 / 15, repeats: true) { [weak self] t in
            guard let self, let w = window else { return t.invalidate() }
            let m = NSEvent.mouseLocation
            // 이탈 이벤트를 놓쳐도 타이머가 남지 않게 창 밖이면 여기서 정리한다.
            guard w.frame.contains(m) else { return self.mouseExited(with: e) }
            hover = didResize || grip.contains(convert(w.convertPoint(fromScreen: m), from: nil))
        }
    }

    override func mouseExited(with e: NSEvent) {
        poll?.invalidate()
        poll = nil
        hover = false
    }

    /// 우하단 리사이즈 손잡이. 화살표(drawGrip)가 그려지는 자리를 넉넉히 덮는다.
    /// 여기서 끌면 크기가 바뀌고, 그냥 누르면 평소대로 전환된다 —
    /// 안 그러면 키캡 우하단을 눌렀을 때 아무 일도 안 일어난다.
    private var grip: NSRect {
        let g = bounds.width * 0.42
        return NSRect(x: bounds.maxX - g, y: bounds.minY, width: g, height: g)
    }

    override func mouseDown(with e: NSEvent) {
        downAt = e.locationInWindow
        inGrip = grip.contains(convert(e.locationInWindow, from: nil))
        didResize = false
        startFrame = window?.frame ?? .zero
        startMouse = NSEvent.mouseLocation
        setPress(1)
        Sound.down()
    }

    override func mouseDragged(with e: NSEvent) {
        if inGrip {
            // 창이 커지면 locationInWindow 기준이 흔들린다 — 화면 좌표로 계산한다.
            let m = NSEvent.mouseLocation
            if !didResize {
                guard hypot(m.x - startMouse.x, m.y - startMouse.y) > 3 else { return }
                didResize = true
                setPress(0)
                Sound.up()
            }
            resize(to: Self.dragSize(startFrame.height,
                                     dx: m.x - startMouse.x, dy: startMouse.y - m.y),
                   anchor: startFrame)
            return
        }
        let moved = hypot(e.locationInWindow.x - downAt.x, e.locationInWindow.y - downAt.y)
        // performDrag는 마우스를 삼켜서 mouseUp이 안 온다 — 여기서 미리 올려준다.
        if moved > 3 { setPress(0); Sound.up(); window?.performDrag(with: e) }
    }

    /// 키캡이 올라오는 순간마다 한 번씩만 소리를 낸다 — 끌기로 이미 올라왔으면(didResize) 여기선 조용하다.
    override func mouseUp(with e: NSEvent) {
        setPress(0)
        if !didResize { Sound.up(); toggleLanguage() }
        didResize = false  // 끄는 동안 화살표를 붙잡아 두던 플래그 — 여기서 푼다.
    }

    /// 좌상단(anchor 기준)을 고정해 손잡이 쪽으로 자란다. 기본 위치가 화면 우상단이라 그대로 두면
    /// 오른쪽/아래로 삐져나가고, 그 위치가 저장돼 다음 실행 때 화면 밖에서 뜬다.
    private func resize(to s: CGFloat, anchor: NSRect? = nil) {
        guard let w = window else { return }
        let base = anchor ?? w.frame
        let side = min(Self.maxSide, max(Self.minSide, s))
        var f = NSRect(x: base.minX, y: base.maxY - side, width: side, height: side)
        if let vf = w.screen?.visibleFrame {
            f.origin.x = min(f.minX, vf.maxX - side)
            f.origin.y = max(f.minY, vf.minY)
        }
        w.setFrame(f, display: true)
        UserDefaults.standard.set(Double(side), forKey: "side")
    }

    override func rightMouseDown(with e: NSEvent) {
        let menu = NSMenu()
        let login = menu.addItem(withTitle: "로그인 시 자동 실행", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        // 맨 바이너리로 실행하면 등록할 번들이 없다.
        login.isEnabled = Bundle.main.bundleIdentifier != nil
        menu.addItem(.separator())
        // 손잡이(우하단 드래그)는 눈에 잘 안 띈다 — 여기가 크기 조절의 발견 경로다.
        let sizeItem = menu.addItem(withTitle: "크기", action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for (name, s) in [("작게", 32), ("보통", 44), ("크게", 64), ("최대", 88)] {
            let item = sizes.addItem(withTitle: "\(name) (\(s)pt)", action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = s
            item.state = abs((window?.frame.height ?? 0) - CGFloat(s)) < 0.5 ? .on : .off
        }
        menu.setSubmenu(sizes, for: sizeItem)
        // 소리는 Sound.profiles 표를 그대로 옮긴다 — 프리셋을 늘리면 메뉴도 같이 는다.
        let soundItem = menu.addItem(withTitle: "소리", action: nil, keyEquivalent: "")
        let sounds = NSMenu()
        let mute = sounds.addItem(withTitle: "끄기", action: #selector(setSound(_:)), keyEquivalent: "")
        mute.target = self
        mute.representedObject = Sound.off
        mute.state = Sound.current == nil ? .on : .off
        sounds.addItem(.separator())
        for p in Sound.profiles {
            let item = sounds.addItem(withTitle: p.name, action: #selector(setSound(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.id
            item.state = Sound.current?.id == p.id ? .on : .off
        }
        menu.setSubmenu(sounds, for: soundItem)
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

    /// 고르는 즉시 들려준다 — 이름만 보고는 어떤 소리인지 모른다.
    @objc private func setSound(_ sender: NSMenuItem) {
        Sound.select(sender.representedObject as? String ?? Sound.off)
        if let p = Sound.current { Sound.preview(p) }
    }

    @objc private func setSize(_ sender: NSMenuItem) { resize(to: CGFloat(sender.tag)) }

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

// 저장된 크기. 없으면 double(forKey:)가 0 을 주므로 기본값으로 떨어뜨린다.
let saved = UserDefaults.standard.double(forKey: "side")
let side = saved > 0 ? min(IconView.maxSide, max(IconView.minSide, CGFloat(saved))) : 44
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
