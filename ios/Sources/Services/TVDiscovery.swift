import Foundation
import Combine
import Darwin

/// Discovers Samsung Smart TVs on the local network via Bonjour/mDNS.
/// Samsung TVs advertise the `_samsungmsf._tcp` service; resolving it yields the
/// TV's IPv4 address, which is all the WebSocket/REST clients need.
///
/// Not `@MainActor`: NetService(Browser) delegate callbacks are delivered on the
/// run loop that scheduled the search — the main run loop here, since `start()`
/// is called from the UI — so `@Published` mutations land on the main thread.
final class TVDiscovery: NSObject, ObservableObject {
    struct TV: Identifiable, Equatable {
        let id: String      // host IP, also stable identity
        let name: String
        let host: String
    }

    @Published private(set) var found: [TV] = []
    @Published private(set) var isScanning = false

    private var browser: NetServiceBrowser?
    private var resolving: [NetService] = []

    func start() {
        guard !isScanning else { return }
        found = []
        resolving = []
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_samsungmsf._tcp.", inDomain: "local.")
        self.browser = browser
        isScanning = true
    }

    func stop() {
        browser?.stop()
        browser = nil
        resolving.forEach { $0.stop() }
        resolving = []
        isScanning = false
    }

    private func add(_ tv: TV) {
        guard !found.contains(where: { $0.host == tv.host }) else { return }
        found.append(tv)
    }

    /// Extracts the first IPv4 address from a resolved service's `addresses`.
    private static func ipv4(from service: NetService) -> String? {
        guard let addresses = service.addresses else { return nil }
        for data in addresses {
            let ip: String? = data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return nil }
                let sa = base.assumingMemoryBound(to: sockaddr.self)
                guard sa.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
                var sin = base.assumingMemoryBound(to: sockaddr_in.self).pointee
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
                return String(cString: buf)
            }
            if let ip { return ip }
        }
        return nil
    }
}

extension TVDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolving.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        if let host = Self.ipv4(from: sender) {
            add(TV(id: host, name: sender.name, host: host))
        }
        resolving.removeAll { $0 === sender }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolving.removeAll { $0 === sender }
    }
}
