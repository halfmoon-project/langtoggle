import AVFoundation

/// 키캡 소리. 세 축 모두 짧게 다듬은 실제 녹음을 쓰고, 파일을 읽지 못하면 파형을 합성한다.
///
/// 폴백 합성음은 몇 ms 간격으로 이어지는 타격 여러 개다. 청축을 예로 들면
/// 누를 때 (1) 클릭 재킷이 튀는 아주 짧고 밝은 딸깍, (2) 5ms 뒤 키캡이 바닥에 닿는 둔탁한 소리가
/// 겹치고, 뗄 때는 재킷이 제자리로 돌아오며 한 번 더 난다 — 청축이 "찰칵찰칵" 인 이유다.
/// 그래서 `Voice` 는 `Hit` 의 묶음이고, 시작 시각(at)이 다른 타격을 쌓아서 만든다.
///
/// 소리를 하나 더 넣으려면 `profiles` 에 한 벌 더한다 — 우클릭 메뉴는 이 표를 그대로 따라간다.
/// sample 이 있으면 `assets/sounds/<sample>.aifc` 를 누름·뗌에 재사용하되 Voice.peak 로 음량을 맞춘다.
enum Sound {
    /// 타격 하나. at 만큼 늦게 시작한다. hz 는 울리는 몸통, ring 은 그 위에 얹는 배음,
    /// decay 는 감쇠 시간(초), noise 는 섞는 잡음의 양(0 이면 순수 톤 — 딱딱한 전자음이 된다),
    /// level 은 같은 Voice 안에서의 비중이다.
    struct Hit {
        var at: Double = 0
        let hz, ring, decay, noise, level: Double
    }

    /// 한 방. peak 는 다 쌓은 뒤 맞추는 최고 진폭이다.
    struct Voice {
        let peak: Float
        let hits: [Hit]
    }

    /// 소리 한 벌.
    struct Profile {
        let id, name: String
        let sample: String?
        let down, up: Voice
    }

    /// 메뉴에 이 순서로 뜬다. 첫 줄이 기본값이다.
    /// 축 이름을 붙인 건 취향을 설명하기 제일 짧은 말이라서다 — 실제 스위치의 구조를 그대로 옮겼다.
    static let profiles = [
        // 청축: 밝고 짧은 클릭 재킷 + 바닥 타격. 뗄 때도 재킷이 한 번 더 튄다.
        Profile(id: "blue", name: "청축 — 찰칵찰칵",
                sample: "blue",
                down: Voice(peak: 0.5, hits: [
                    Hit(hz: 4300, ring: 7200, decay: 0.0022, noise: 0.5, level: 1),
                    Hit(at: 0.0055, hz: 300, ring: 620, decay: 0.011, noise: 0.28, level: 0.6),
                ]),
                up: Voice(peak: 0.34, hits: [
                    Hit(hz: 3600, ring: 6000, decay: 0.0018, noise: 0.42, level: 1),
                    Hit(at: 0.0045, hz: 850, ring: 1600, decay: 0.005, noise: 0.3, level: 0.45),
                ])),
        // 갈축: 클릭 재킷이 없다. 걸림(택타일) 소리가 옅게 나고 바닥 타격이 주인공이다.
        Profile(id: "brown", name: "갈축 — 도각도각",
                sample: "brown",
                down: Voice(peak: 0.42, hits: [
                    Hit(hz: 2400, ring: 4200, decay: 0.003, noise: 0.35, level: 0.55),
                    Hit(at: 0.005, hz: 280, ring: 560, decay: 0.013, noise: 0.25, level: 1),
                ]),
                up: Voice(peak: 0.24, hits: [
                    Hit(hz: 1500, ring: 2900, decay: 0.004, noise: 0.3, level: 0.5),
                    Hit(at: 0.004, hz: 700, ring: 1400, decay: 0.006, noise: 0.25, level: 0.8),
                ])),
        // 적축: 리니어. 걸림도 클릭도 없이 바닥과 천장에 닿는 소리만 난다.
        Profile(id: "red", name: "적축 — 툭툭",
                sample: "red",
                down: Voice(peak: 0.4, hits: [
                    Hit(hz: 1800, ring: 3400, decay: 0.0015, noise: 0.3, level: 0.25),
                    Hit(hz: 230, ring: 480, decay: 0.016, noise: 0.22, level: 1),
                ]),
                up: Voice(peak: 0.2, hits: [
                    Hit(hz: 900, ring: 1900, decay: 0.005, noise: 0.3, level: 1),
                ])),
    ]

    /// 고른 소리. 끄면 nil 이다. 모르는 id 가 저장돼 있으면(프리셋을 지웠거나 구버전 설정)
    /// 조용해지는 대신 기본 소리로 떨어진다 — 껐다고 착각할 자리를 안 만든다.
    static var current: Profile? {
        guard let id = UserDefaults.standard.string(forKey: "sound") else { return profiles[0] }
        guard id != off else { return nil }
        return profiles.first { $0.id == id } ?? profiles[0]
    }

    static let off = "off"

    static func select(_ id: String) { UserDefaults.standard.set(id, forKey: "sound") }

    static func down() { if let p = current { play(buffer(p, down: true)) } }
    static func up() { if let p = current { play(buffer(p, down: false)) } }

    /// 설정과 무관하게 한 벌을 들려준다 — 두 방을 한 노드에 줄 세워 톡탁 하고 이어 난다.
    /// 메뉴에서 고르는 즉시 부르는 자리라 재우지 않는다(메뉴가 멈춘다).
    static func preview(_ p: Profile) {
        play(buffer(p, down: true), buffer(p, down: false))
    }

    /// 전부 한 번씩(--click). 프리셋 숫자를 고칠 때 귀로 비교하는 자리다.
    static func demo() {
        for p in profiles {
            print(p.name)
            preview(p)
            usleep(700_000)  // 소리는 다른 스레드에서 난다 — 다 나기 전에 끝내지 않으려고 기다린다.
        }
    }

    // MARK: 합성

    /// 44.1k 모노 고정. 출력 장치가 48k 로 바뀌어도 믹서가 변환해 줘서 파형을 다시 구울 일이 없다.
    static let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    /// 타격 하나가 차지하는 길이. 6τ 면 -52dB 라 사실상 끝난 소리다.
    static func length(_ h: Hit) -> Int { Int(format.sampleRate * (h.at + h.decay * 6)) }

    /// 파형. 타격마다 첫 샘플이 곧 최고점이라 어택이 딱 서고, 각 타격이 6τ 지점에서 정확히 0 으로
    /// 끝나 꼬리에 끊긴 자국(원하지 않은 또 한 번의 딸깍)이 안 남는다.
    static func render(_ v: Voice) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let n = v.hits.map(length).max() ?? 0
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        let out = buf.floatChannelData![0]
        let tail = exp(-6.0)
        for h in v.hits {
            // 앞 타격의 여운 위에 다음 타격의 어택이 그대로 얹힌다 — 실제 스위치도 그렇게 겹친다.
            let from = Int(h.at * sr)
            for i in 0..<Int(sr * h.decay * 6) {
                let t = Double(i) / sr
                let env = (exp(-t / h.decay) - tail) / (1 - tail)
                out[from + i] += Float(h.level * (h.noise * Double.random(in: -1...1)
                                                  + sin(2 * .pi * h.hz * t)
                                                  + 0.5 * sin(2 * .pi * h.ring * t)) * env)
            }
        }
        // 클리핑은 귀에 바로 티가 난다 — 타격을 다 쌓은 뒤에 최고점을 맞춘다.
        let loudest = (0..<n).map { abs(out[$0]) }.max() ?? 0
        if loudest > 0 { for i in 0..<n { out[i] *= v.peak / loudest } }
        return buf
    }

    private static var cache: [String: AVAudioPCMBuffer] = [:]

    private static func wave(_ key: String, _ v: Voice) -> AVAudioPCMBuffer {
        if let hit = cache[key] { return hit }
        let made = render(v)
        cache[key] = made
        return made
    }

    /// 녹음은 축마다 한 벌만 두고 누름·뗌에서 목표 음량만 달리한다. 같은 녹음을 두 개 넣어
    /// 번들 크기를 늘리는 것보다 실제 키처럼 뗄 때를 조용하게 만드는 편이 낫다.
    static func buffer(_ p: Profile, down: Bool) -> AVAudioPCMBuffer {
        let voice = down ? p.down : p.up
        let key = p.id + (down ? ".down" : ".up")
        if let sample = p.sample, let recorded = recording(sample, peak: voice.peak, key: key) {
            return recorded
        }
        return wave(key, voice)
    }

    private static func recording(_ name: String, peak: Float, key: String) -> AVAudioPCMBuffer? {
        if let hit = cache[key] { return hit }
        let url = bundledDir.appendingPathComponent("sounds/\(name).aifc")
        guard let file = try? AVAudioFile(forReading: url),
              let made = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                          frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do { try file.read(into: made) } catch { return nil }

        // 원본 녹음마다 레벨이 달라도 프리셋 Voice.peak 가 최종 음량의 한 곳짜리 기준이 된다.
        let channels = Int(made.format.channelCount), n = Int(made.frameLength)
        guard let data = made.floatChannelData else { return nil }
        var loudest: Float = 0
        for channel in 0..<channels {
            for i in 0..<n { loudest = max(loudest, abs(data[channel][i])) }
        }
        if loudest > 0 {
            let gain = peak / loudest
            for channel in 0..<channels {
                for i in 0..<n { data[channel][i] *= gain }
            }
        }
        cache[key] = made
        return made
    }

    // MARK: 재생

    private static let engine = AVAudioEngine()
    /// 재생 노드 넷을 돌려 쓴다. 한 노드에 몰아주면 앞 소리가 끝나야 다음이 나가서, 연타하면
    /// 소리가 점점 뒤로 밀린다(녹음 한 벌이 약 160~180ms다). 돌려 쓰면 겹쳐서 나고,
    /// 앞 소리의 여운 위에 다음 소리가 얹히는 건 실제 키보드도 마찬가지다.
    private static let players = (0..<4).map { _ in AVAudioPlayerNode() }
    private static var next = 0
    private static var idle: Timer?

    /// 한 번의 호출은 노드 하나를 잡는다 — 같이 넘긴 파형들은 그 노드에서 줄 서서 이어 나고(미리듣기),
    /// 다음 호출은 다음 노드로 가서 앞 소리와 겹친다(연타).
    private static func play(_ waves: AVAudioPCMBuffer...) {
        guard start() else { return }
        let player = players[next]
        next = (next + 1) % players.count
        for wave in waves { player.scheduleBuffer(wave, at: nil, options: [], completionHandler: nil) }
        player.play()
        // 조용해지면 엔진을 놓는다 — 안 그러면 블루투스 헤드셋을 종일 깨워 둔 채로 붙잡는다.
        // 3 초면 아무리 늦은 소리도 다 나간 뒤다(가장 긴 한 방도 200ms 미만).
        idle?.invalidate()
        idle = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            players.forEach { $0.stop() }
            engine.stop()
        }
    }

    /// 출력 장치가 바뀌면 엔진이 멈추고 연결도 끊긴다 — 멈춰 있으면 매번 다시 잇고 켠다.
    private static func start() -> Bool {
        if engine.isRunning { return true }
        for p in players {
            if p.engine == nil { engine.attach(p) }
            engine.connect(p, to: engine.mainMixerNode, format: format)
        }
        do {
            try engine.start()
        } catch {
            NSLog("LangToggle: 소리 엔진 시작 실패 — \(error)")
            return false
        }
        return true
    }
}
