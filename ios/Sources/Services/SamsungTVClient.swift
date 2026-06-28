import Foundation
import Combine

enum TVError: Error {
    case notConnected
    case timeout
}

/// Talks to a Samsung TV directly from the phone — the native replacement for
/// the Go server. Opens the `samsung.remote.control` WebSocket (accepting the
/// TV's self-signed cert), persists the pairing token, sends keys / launches
/// apps, and reads power state + the installed-app list over the TV's REST API.
@MainActor
final class SamsungTVClient: NSObject, ObservableObject {
    enum ConnectionState { case disconnected, connecting, connected }

    @Published private(set) var state: ConnectionState = .disconnected

    private let appName: String
    private var host: String?
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?

    // App-list requests waiting on an `ed.installedApp.get` reply (coalesced).
    private var appsWaiters: [Int: CheckedContinuation<[TVApp], Error>] = [:]
    private var waiterSeq = 0

    private var reconnectDelay: TimeInterval = 5
    private let maxReconnectDelay: TimeInterval = 60
    private var intentionalClose = false

    init(appName: String = "TVRemote") {
        self.appName = appName
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: - Connection

    func connect(host: String) {
        if self.host != host { disconnectInternal(); self.host = host }
        intentionalClose = false
        guard state == .disconnected else { return }
        openSocket()
    }

    func disconnect() {
        intentionalClose = true
        disconnectInternal()
    }

    private func disconnectInternal() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .disconnected
        failWaiters(with: TVError.notConnected)
    }

    private func openSocket() {
        guard let host else { return }
        state = .connecting

        let encodedName = Data(appName.utf8).base64EncodedString()
        var urlString = "wss://\(host):8002/api/v2/channels/samsung.remote.control?name=\(encodedName)"
        if let token = TokenStore.token(for: host), !token.isEmpty {
            urlString += "&token=\(token)"
        }
        guard let url = URL(string: urlString) else { state = .disconnected; return }

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop(on: task)
    }

    private func receiveLoop(on task: URLSessionWebSocketTask) {
        Task { [weak self] in
            while true {
                do {
                    let message = try await task.receive()
                    guard let self, self.task === task else { return }
                    switch message {
                    case .string(let text): self.handle(text: text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) { self.handle(text: text) }
                    @unknown default: break
                    }
                } catch {
                    guard let self, self.task === task else { return }
                    self.handleDisconnect()
                    return
                }
            }
        }
    }

    private func handleDisconnect() {
        task = nil
        state = .disconnected
        failWaiters(with: TVError.notConnected)
        guard !intentionalClose, host != nil else { return }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.intentionalClose, self.state == .disconnected else { return }
            self.openSocket()
        }
    }

    // MARK: - Incoming messages

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let event = root["event"] as? String
        let payload = root["data"] as? [String: Any]

        if let token = payload?["token"] as? String, let host {
            TokenStore.set(token, for: host)
        }

        switch event ?? "" {
        case "ms.channel.connect":
            state = .connected
            reconnectDelay = 5
        case "ed.installedApp.get":
            let raw = (payload?["data"] as? [[String: Any]]) ?? []
            let apps = raw.compactMap { dict -> TVApp? in
                guard let id = dict["appId"] as? String,
                      let name = dict["name"] as? String else { return nil }
                return TVApp(appId: id, name: name)
            }
            let waiters = appsWaiters
            appsWaiters = [:]
            waiters.values.forEach { $0.resume(returning: apps) }
        default:
            break
        }
    }

    private func failWaiters(with error: Error) {
        let waiters = appsWaiters
        appsWaiters = [:]
        waiters.values.forEach { $0.resume(throwing: error) }
    }

    // MARK: - Sending commands

    private func send(_ object: [String: Any]) {
        guard let task, state == .connected,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(text)) { _ in }
    }

    /// Cmd "Click" = single press; "Press"/"Release" = hold, letting the TV ramp
    /// its own repeat just like the physical remote.
    func sendKey(_ key: String, cmd: String = "Click") {
        send([
            "method": "ms.remote.control",
            "params": [
                "Cmd": cmd,
                "DataOfCmd": key,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey",
            ],
        ])
    }

    func pressKey(_ key: String) { sendKey(key, cmd: "Press") }
    func releaseKey(_ key: String) { sendKey(key, cmd: "Release") }

    func launchApp(_ appId: String) {
        send([
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": ["appId": appId, "action_type": "DEEP_LINK"],
            ],
        ])
    }

    /// Requests the installed-app list. Concurrent callers are coalesced onto a
    /// single TV request, and each call independently times out.
    func requestApps(timeout: TimeInterval = 5) async throws -> [TVApp] {
        guard state == .connected else { throw TVError.notConnected }
        let id = waiterSeq
        waiterSeq += 1
        let shouldSend = appsWaiters.isEmpty

        return try await withCheckedThrowingContinuation { continuation in
            appsWaiters[id] = continuation
            if shouldSend {
                send([
                    "method": "ms.channel.emit",
                    "params": ["event": "ed.installedApp.get", "to": "host"],
                ])
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self, let waiter = self.appsWaiters.removeValue(forKey: id) else { return }
                waiter.resume(throwing: TVError.timeout)
            }
        }
    }

    // MARK: - REST queries (power state / active app)

    /// The WS stays "connected" even in standby, so power state comes from REST.
    func powerState(host: String) async -> String {
        guard let url = URL(string: "http://\(host):8001/api/v2/") else { return "off" }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, _) = try? await session.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = root["device"] as? [String: Any],
              (device["PowerState"] as? String) == "on"
        else { return "off" }
        return "on"
    }

    /// Returns the first visible app's name (foreground app), checking all apps
    /// in parallel so the wait is ~one timeout, not N.
    func activeApp(host: String, apps: [TVApp]) async -> String? {
        let session = self.session!
        let names: [Int: String] = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, app) in apps.enumerated() {
                group.addTask {
                    guard let url = URL(string: "http://\(host):8001/api/v2/applications/\(app.appId)")
                    else { return (index, nil) }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 0.8
                    guard let (data, _) = try? await session.data(for: request),
                          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          (root["visible"] as? Bool) == true,
                          let name = root["name"] as? String
                    else { return (index, nil) }
                    return (index, name)
                }
            }
            var result: [Int: String] = [:]
            for await (index, name) in group {
                if let name { result[index] = name }
            }
            return result
        }
        for index in apps.indices where names[index] != nil {
            return names[index]
        }
        return nil
    }
}

// MARK: - Accept the TV's self-signed TLS certificate

extension SamsungTVClient: URLSessionDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
