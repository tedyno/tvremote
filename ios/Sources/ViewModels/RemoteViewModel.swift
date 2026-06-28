import Foundation
import Combine
import SwiftUI

@MainActor
final class RemoteViewModel: ObservableObject {
    @Published var apps: [TVApp] = []
    @Published var favorites: [String] = []
    @Published var power: String = "off"          // "on" / "off"
    @Published var activeApp: String?
    @Published var toast: Toast?
    @Published var showApps = false
    @Published var showSettings = false

    // Selected TV (persisted).
    @Published var host: String? { didSet { defaults.set(host, forKey: Keys.host) } }
    @Published var tvName: String? { didSet { defaults.set(tvName, forKey: Keys.tvName) } }
    @Published var mac: String { didSet { defaults.set(mac, forKey: Keys.mac) } }

    let client = SamsungTVClient()

    private let defaults = UserDefaults.standard
    private var pollTask: Task<Void, Never>?

    private enum Keys {
        static let host = "tv-host"
        static let tvName = "tv-name"
        static let mac = "tv-mac"
        static let favorites = "tv-favs"
    }

    var connected: Bool { client.state == .connected }
    var isConfigured: Bool { host != nil }

    init() {
        host = defaults.string(forKey: Keys.host)
        tvName = defaults.string(forKey: Keys.tvName)
        mac = defaults.string(forKey: Keys.mac) ?? ""
        favorites = defaults.stringArray(forKey: Keys.favorites) ?? []
    }

    // MARK: - Lifecycle

    func onAppear() {
        if let host { client.connect(host: host) }
        startPolling()
        if host == nil { showSettings = true }
    }

    func select(host: String, name: String?) {
        self.host = host
        self.tvName = name
        apps = []
        activeApp = nil
        client.connect(host: host)
        Task { await refreshTVInfo() }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshTVInfo()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func refreshTVInfo() async {
        guard let host, connected else {
            power = "off"
            activeApp = nil
            return
        }
        let state = await client.powerState(host: host)
        power = state
        guard state == "on" else { activeApp = nil; return }
        if apps.isEmpty { await loadApps() }
        activeApp = await client.activeApp(host: host, apps: apps)
    }

    func loadApps() async {
        guard connected else { return }
        if let loaded = try? await client.requestApps() {
            apps = loaded
        }
    }

    // MARK: - Commands

    func tap(_ key: String) {
        Haptics.light()
        guard connected else { showToast("TV not connected", .error); return }
        client.sendKey(key)
    }

    func holdBegin(_ key: String) {
        Haptics.light()
        guard connected else { showToast("TV not connected", .error); return }
        client.pressKey(key)
    }

    func holdEnd(_ key: String) {
        guard connected else { return }
        client.releaseKey(key)
    }

    func pressPower() {
        Haptics.light()
        guard let host else { showToast("Select a TV first", .error); showSettings = true; return }
        Task {
            let state = await client.powerState(host: host)
            if state == "off" {
                // The TV won't wake over the WS — only Wake-on-LAN does.
                guard !mac.isEmpty else {
                    showToast("Set the TV's MAC in settings to power on", .error)
                    return
                }
                WakeOnLAN.wake(mac: mac, host: host)
                showToast("Waking TV… give it ~15 s", .info)
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    client.connect(host: host)
                }
            } else if connected {
                client.sendKey(RemoteKey.power)
            }
        }
    }

    func launch(_ appId: String) {
        Haptics.light()
        guard connected else { showToast("TV not connected", .error); return }
        client.launchApp(appId)
        showApps = false
    }

    // MARK: - Favorites

    func isFavorite(_ appId: String) -> Bool { favorites.contains(appId) }

    func toggleFavorite(_ appId: String) {
        Haptics.light()
        if let idx = favorites.firstIndex(of: appId) {
            favorites.remove(at: idx)
        } else {
            favorites.append(appId)
        }
        defaults.set(favorites, forKey: Keys.favorites)
    }

    var favoriteApps: [TVApp] {
        favorites.compactMap { id in apps.first { $0.appId == id } }
    }

    // MARK: - Toasts

    func showToast(_ message: String, _ kind: Toast.Kind) {
        let toast = Toast(message: message, kind: kind)
        self.toast = toast
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Kind { case info, success, error }
    let id = UUID()
    let message: String
    let kind: Kind
}
