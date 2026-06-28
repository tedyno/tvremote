import Foundation
import Darwin

/// Sends Wake-on-LAN magic packets over UDP broadcast, mirroring the Go
/// server's `sendWol`: 3 bursts to the limited broadcast, the subnet broadcast
/// and the unicast host, on ports 9 and 7.
enum WakeOnLAN {
    static func wake(mac: String, host: String) {
        guard let packet = magicPacket(mac: mac) else { return }
        let targets = ["255.255.255.255", subnetBroadcast(host), host]
        let ports: [UInt16] = [9, 7]

        Task.detached(priority: .utility) {
            for _ in 0..<3 {
                for target in targets {
                    for port in ports {
                        send(packet, to: target, port: port)
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    /// 6 bytes of 0xFF followed by the 6-byte MAC repeated 16 times.
    static func magicPacket(mac: String) -> Data? {
        let parts = mac.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        var hw = [UInt8]()
        for part in parts {
            guard let byte = UInt8(part, radix: 16) else { return nil }
            hw.append(byte)
        }
        var packet = Data(repeating: 0xff, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: hw) }
        return packet
    }

    static func subnetBroadcast(_ ip: String) -> String {
        if let dot = ip.lastIndex(of: ".") {
            return String(ip[..<dot]) + ".255"
        }
        return "255.255.255.255"
    }

    private static func send(_ packet: Data, to host: String, port: UInt16) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        // inet_pton handles 255.255.255.255 correctly (inet_addr would alias it
        // to INADDR_NONE), so prefer it for the broadcast target.
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return }

        _ = packet.withUnsafeBytes { raw in
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, raw.baseAddress, packet.count, 0, sa,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
