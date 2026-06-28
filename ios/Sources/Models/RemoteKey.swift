import Foundation

/// Samsung remote key codes sent over the WebSocket control channel.
enum RemoteKey {
    static let power = "KEY_POWER"

    static let up = "KEY_UP"
    static let down = "KEY_DOWN"
    static let left = "KEY_LEFT"
    static let right = "KEY_RIGHT"
    static let enter = "KEY_ENTER"

    static let volUp = "KEY_VOLUP"
    static let volDown = "KEY_VOLDOWN"
    static let mute = "KEY_MUTE"

    static let back = "KEY_RETURN"
    static let home = "KEY_HOME"
    static let menu = "KEY_MENU"

    static let play = "KEY_PLAY"
    static let pause = "KEY_PAUSE"
    static let stop = "KEY_STOP"

    static func digit(_ n: Int) -> String { "KEY_\(n)" }

    /// Keys that benefit from press-and-hold — the TV ramps its own repeat
    /// (faster seeking / volume) exactly like the physical remote.
    static let holdable: Set<String> = [up, down, left, right, volUp, volDown]
}
