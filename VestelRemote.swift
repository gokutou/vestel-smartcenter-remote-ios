import SwiftUI
import Network
import Darwin
#if canImport(UIKit)
import UIKit
@MainActor private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
#else
@MainActor private func hideKeyboard() {}
#endif

// MARK: - Key codes (Vestel/Toshiba SmartCenter)

enum VKey: Int {
    case n0 = 1000, n1 = 1001, n2 = 1002, n3 = 1003, n4 = 1004
    case n5 = 1005, n6 = 1006, n7 = 1007, n8 = 1008, n9 = 1009
    case back = 1010, aspect = 1011, power = 1012, mute = 1013
    case lang = 1015, volUp = 1016, volDown = 1017, info = 1018
    case down = 1019, up = 1020, left = 1021, right = 1022
    case stop = 1024, play = 1025, rewind = 1027, forward = 1028
    case subtitle = 1031, close = 1037, fav = 1040, epg = 1047
    case menu = 1048, pause = 1049, yellow = 1050, rec = 1051
    case blue = 1052, ok = 1053, green = 1054, red = 1055
    case source = 1056, mirror = 1057, teletext = 1058
    case youtube = 1062, home = 1063, netflix = 1064
    case browser = 1065, settings = 1066, ambilight = 1067
    case multiView = 1068, rakuten = 1073
}

// MARK: - TV client

@MainActor
final class VestelTV: ObservableObject {
    @Published var tvIP: String?
    @Published var status: String = "hazır"
    @Published var scanning = false

    let port: UInt16 = 56789
    private var permissionBrowser: NWBrowser?

    private var endpoint: URL? {
        tvIP.flatMap { URL(string: "http://\($0):\(port)/apps/SmartCenter") }
    }

    func setManualIP(_ ip: String) {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        tvIP = trimmed
        status = "manuel: \(trimmed)"
    }

    // MARK: Commands

    private func post(_ body: String) async {
        guard let url = endpoint else { status = "TV seçili değil"; return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("vestel smart center", forHTTPHeaderField: "application_name")
        req.setValue("text/plain; charset=ISO-8859-1", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .isoLatin1)
        do { _ = try await URLSession.shared.data(for: req) }
        catch { status = "gönderim hatası: \(error.localizedDescription)" }
    }

    func key(_ k: VKey) async {
        await post("<?xml version='1.0' ?><remote><key code='\(k.rawValue)'/></remote>")
    }

    func char(_ c: Character) async {
        let code = c.unicodeScalars.first.map { Int($0.value) } ?? 0
        await post("<?xml version='1.0' ?><keyboard><key value='\(code)'/></keyboard>")
    }

    func type(_ text: String) async {
        for c in text { await char(c) }
    }

    func openApp(_ name: String) async {
        let u = "http://www.portaltv.tv/swf/\(name)/\(name).swf"
        await post("<?xml version='1.0' ?><browserseturl><load url='\(u)' page='RC'/></browserseturl>")
    }

    // MARK: Mouse / touchpad
    // Format captured from the official app (relative deltas over the same HTTP endpoint):
    //   <?xml version='1.0' ?><mouseevent><event_data dx='5' dy='-22' button='0'/></mouseevent>
    // button=0 -> move only. click is a hypothesis (button 1 = down, 0 = up) — confirm by
    // capturing one tap from the official touchpad if it doesn't register.

    func mouse(dx: Int, dy: Int, button: Int = 0) async {
        await post("<?xml version='1.0' ?><mouseevent><event_data dx='\(dx)' dy='\(dy)' button='\(button)'/></mouseevent>")
    }

    func click() async {
        await mouse(dx: 0, dy: 0, button: 1)            // press
        try? await Task.sleep(nanoseconds: 60_000_000)  // brief hold
        await mouse(dx: 0, dy: 0, button: 0)            // release
    }

    // MARK: Discovery (unicast subnet scan)

    func discover() async {
        triggerLocalNetworkPrompt()
        guard let base = Self.localIPv4Prefix() else { status = "Wi-Fi IPv4 yok"; return }

        scanning = true
        status = "taranıyor \(base).0/24…"
        defer { scanning = false }

        let found = await withTaskGroup(of: String?.self) { group -> String? in
            let maxInFlight = 40
            var next = 1
            func enqueue() {
                guard next <= 254 else { return }
                let ip = "\(base).\(next)"; next += 1
                group.addTask { await Self.portOpen(ip, port: 56789, timeout: 0.8) ? ip : nil }
            }
            for _ in 0..<maxInFlight { enqueue() }
            for await result in group {
                if let ip = result { group.cancelAll(); return ip }
                enqueue()
            }
            return nil
        }

        if let ip = found { tvIP = ip; status = "TV bulundu: \(ip)" }
        else { status = "Bu ağda TV bulunamadı" }
    }

    private func triggerLocalNetworkPrompt() {
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: NWParameters())
        browser.start(queue: .global())
        permissionBrowser = browser
    }

    nonisolated private static func portOpen(_ host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        final class Once: @unchecked Sendable {
            private let lock = NSLock(); private var done = false
            func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
        }
        let once = Once()
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let conn = NWConnection(host: NWEndpoint.Host(host),
                                    port: NWEndpoint.Port(rawValue: port)!,
                                    using: .tcp)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.claim() { conn.cancel(); cont.resume(returning: true) }
                case .failed, .cancelled: if once.claim() { cont.resume(returning: false) }
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() { conn.cancel(); cont.resume(returning: false) }
            }
        }
    }

    nonisolated private static func localIPv4Prefix() -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return nil }
        defer { freeifaddrs(ifap) }
        var ptr = ifap
        while let p = ptr {
            let ifa = p.pointee
            if ifa.ifa_addr.pointee.sa_family == sa_family_t(AF_INET),
               String(cString: ifa.ifa_name) == "en0" {
                var addr = ifa.ifa_addr.pointee
                let saLen = socklen_t(addr.sa_len)
                let ip = withUnsafePointer(to: &addr) { sa -> String in
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(sa, saLen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    let len = host.firstIndex(of: 0) ?? host.count
                    return String(decoding: host[..<len].map { UInt8(bitPattern: $0) }, as: UTF8.self)
                }
                let parts = ip.split(separator: ".")
                if parts.count == 4 { return parts.prefix(3).joined(separator: ".") }
            }
            ptr = ifa.ifa_next
        }
        return nil
    }
}

// MARK: - Press-and-hold button (auto-repeat)

struct HoldButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var pressing = false
    @State private var task: Task<Void, Never>?

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    var body: some View {
        label()
            .opacity(pressing ? 0.5 : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        action()
                        task = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(nanoseconds: 120_000_000)
                            }
                        }
                    }
                    .onEnded { _ in
                        pressing = false
                        task?.cancel(); task = nil
                    }
            )
    }
}

// MARK: - Touchpad (full-screen, drag = cursor, tap = click)

struct TrackpadView: View {
    @ObservedObject var tv: VestelTV

    private let sendInterval: TimeInterval = 0.033   // ~30 Hz, matches the official app's cadence

    // Saved on the device — set it once with the slider and it sticks across launches.
    @AppStorage("trackpadSensitivity") private var sensitivity: Double = 1.3

    @State private var lastSentTranslation: CGSize = .zero
    @State private var lastSend = Date.distantPast
    @State private var moved = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Sürükle: imleç hareketi   •   Dokun: tıkla")
                .font(.footnote).foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 18)
                .fill(.quaternary)
                .overlay(
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 40)).foregroundStyle(.tertiary)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if abs(value.translation.width) > 6 || abs(value.translation.height) > 6 {
                                moved = true
                            }
                            let now = Date()
                            guard now.timeIntervalSince(lastSend) >= sendInterval else { return }
                            let dx = (value.translation.width  - lastSentTranslation.width)  * CGFloat(sensitivity)
                            let dy = (value.translation.height - lastSentTranslation.height) * CGFloat(sensitivity)
                            guard abs(dx) >= 1 || abs(dy) >= 1 else { return }
                            lastSentTranslation = value.translation
                            lastSend = now
                            let ix = Int(dx.rounded()), iy = Int(dy.rounded())
                            Task { await tv.mouse(dx: ix, dy: iy) }
                        }
                        .onEnded { value in
                            let dx = (value.translation.width  - lastSentTranslation.width)  * CGFloat(sensitivity)
                            let dy = (value.translation.height - lastSentTranslation.height) * CGFloat(sensitivity)
                            if abs(dx) >= 1 || abs(dy) >= 1 {
                                Task { await tv.mouse(dx: Int(dx.rounded()), dy: Int(dy.rounded())) }
                            }
                            if !moved { Task { await tv.click() } }   // tap = click
                            moved = false
                            lastSentTranslation = .zero
                            lastSend = Date.distantPast
                        }
                )

            VStack(spacing: 4) {
                HStack {
                    Text("Hassasiyet")
                    Spacer()
                    Text(String(format: "%.1f×", sensitivity))
                        .font(.footnote.monospaced()).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                    Slider(value: $sensitivity, in: 0.4...4.0, step: 0.1)
                    Image(systemName: "hare.fill").foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button { Task { await tv.click() } } label: {
                    Label("Tıkla", systemImage: "cursorarrow.click")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                Button { Task { await tv.key(.back) } } label: {
                    Label("Geri", systemImage: "chevron.backward")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .navigationTitle("Touchpad")
    }
}

// MARK: - UI

@main
struct VestelRemoteApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @StateObject private var tv = VestelTV()
    @State private var manualIP = ""
    @State private var keyboardText = ""

    private func press(_ k: VKey) { hideKeyboard(); Task { await tv.key(k) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    connection
                    Divider()
                    row([(.power, "power", Color.red), (.source, "rectangle.on.rectangle", .primary), (.mute, "speaker.slash.fill", .primary)])
                    row([(.back, "chevron.backward", .primary), (.volDown, "speaker.minus.fill", .primary), (.volUp, "speaker.plus.fill", .primary), (.home, "house.fill", .primary)])
                    dpad
                    trackpadLink
                    row([(.rewind, "backward.fill", .primary), (.play, "play.fill", .primary), (.pause, "pause.fill", .primary), (.stop, "stop.fill", .primary), (.forward, "forward.fill", .primary), (.rec, "record.circle", .red)])
                    colors
                    apps
                    row([(.info, "info.circle", .primary), (.subtitle, "captions.bubble", .primary), (.epg, "list.bullet.rectangle", .primary), (.fav, "star", .primary)])
                    row([(.menu, "line.3.horizontal", .primary), (.aspect, "aspectratio", .primary), (.teletext, "text.bubble", .primary), (.lang, "globe", .primary)])
                    keyboard
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Vestel Remote")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Bitti") { hideKeyboard() }
                }
            }
            .task { await tv.discover() }
        }
    }

    private var trackpadLink: some View {
        NavigationLink {
            TrackpadView(tv: tv)
        } label: {
            Label("Touchpad (fare modu)", systemImage: "hand.point.up.left")
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.bordered)
        .disabled(tv.tvIP == nil)
    }

    // Connection / discovery with retry state
    private var connection: some View {
        VStack(spacing: 10) {
            if tv.scanning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(tv.status).font(.footnote).foregroundStyle(.secondary)
                }
            } else if let ip = tv.tvIP {
                HStack(spacing: 8) {
                    Image(systemName: "tv").foregroundStyle(.green)
                    Text(ip).font(.footnote.monospaced())
                    Spacer()
                    Button { Task { await tv.discover() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button { Task { await tv.discover() } } label: {
                    Label(tv.status == "hazır" ? "TV ara" : "TV bulunamadı — Tekrar tara",
                          systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            HStack {
                TextField("Manuel IP", text: $manualIP)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                Button("Bağlan") { hideKeyboard(); tv.setManualIP(manualIP) }
            }
        }
    }

    private var dpad: some View {
        VStack(spacing: 8) {
            HoldButton(action: { press(.up) }) { padLabel("chevron.up") }
            HStack(spacing: 8) {
                HoldButton(action: { press(.left) }) { padLabel("chevron.left") }
                Button { press(.ok) } label: {
                    Text("OK").font(.headline).frame(width: 64, height: 64)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                HoldButton(action: { press(.right) }) { padLabel("chevron.right") }
            }
            HoldButton(action: { press(.down) }) { padLabel("chevron.down") }
        }
        .frame(maxWidth: .infinity)
    }

    private func padLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title2)
            .frame(width: 64, height: 52)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var colors: some View {
        HStack(spacing: 10) {
            colorBtn(.red, .red); colorBtn(.green, .green)
            colorBtn(.yellow, .yellow); colorBtn(.blue, .blue)
        }
    }

    private var apps: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                appBtn("Netflix") { press(.netflix) }
                appBtn("YouTube") { press(.youtube) }
                appBtn("Prime") { hideKeyboard(); Task { await tv.openApp("amazon") } }
            }
            HStack(spacing: 8) {
                appBtn("Browser") { press(.browser) }
                appBtn("Rakuten") { press(.rakuten) }
                appBtn("Settings") { press(.settings) }
            }
        }
    }

    private var keyboard: some View {
        HStack {
            TextField("TV'de yaz…", text: $keyboardText)
                .textFieldStyle(.roundedBorder)
            Button("Gönder") {
                let t = keyboardText; keyboardText = ""
                hideKeyboard()
                Task { await tv.type(t) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(tv.tvIP == nil)
        }
    }

    // Helpers
    private func row(_ items: [(VKey, String, Color)]) -> some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.0) { item in
                Button { press(item.0) } label: {
                    Image(systemName: item.1)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(item.2)
            }
        }
    }

    private func colorBtn(_ k: VKey, _ color: Color) -> some View {
        Button { press(k) } label: {
            RoundedRectangle(cornerRadius: 8).fill(color).frame(maxWidth: .infinity, minHeight: 34)
        }
    }

    private func appBtn(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(tv.tvIP == nil)
    }
}

extension VKey: Identifiable { var id: Int { rawValue } }
