import Foundation

/// Maps a TV app's display name to a web domain, used to fetch a favicon as the
/// app's tile icon (mirrors the Go server's `appDomains` map).
enum AppDomains {
    static let map: [String: String] = [
        "YouTube": "youtube.com",
        "Netflix": "netflix.com",
        "Disney+": "disneyplus.com",
        "Prime Video": "primevideo.com",
        "Apple TV": "tv.apple.com",
        "Apple Music": "music.apple.com",
        "Spotify": "spotify.com",
        "Spotify – hudba a podcasty": "spotify.com",
        "Plex": "plex.tv",
        "Jellyfin": "jellyfin.org",
        "HBO Max": "max.com",
        "O2 TV": "o2tv.cz",
        "O2 TV (Legacy)": "o2tv.cz",
        "Prima+": "primaplus.cz",
        "SkyShowtime": "skyshowtime.com",
        "Rakuten TV": "rakuten.tv",
        "CANAL+ App": "canalplus.com",
        "Skylink CZ": "skylink.cz",
        "MAGENTA TV": "magentatv.cz",
        "MALL.TV": "mall.tv",
        "Lepší.TV / goNET.TV": "lepsi.tv",
        "SWEET.TV": "sweet.tv",
        "JOJ Play": "play.joj.sk",
        "Voyo.sk": "voyo.sk",
        "Oneplay": "oneplay.cz",
        "HbbTV": "hbbtv.org",
    ]

    /// Favicon URL for an app name, or nil if we have no domain mapping.
    static func iconURL(for appName: String) -> URL? {
        guard let domain = map[appName] else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128")
    }
}
