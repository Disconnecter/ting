import Foundation

public enum ScheduleMeetingPlatform: String, CaseIterable, Equatable, Sendable {
    case googleMeet, zoom, microsoftTeams, webex, jitsi, whereby, around, slack
    case goToMeeting, ringCentral, amazonChime, dialpad, blueJeans, demodesk, livestorm, butter, gather

    public var title: String {
        switch self {
        case .googleMeet: "Google Meet"
        case .zoom: "Zoom"
        case .microsoftTeams: "Microsoft Teams"
        case .webex: "Webex"
        case .jitsi: "Jitsi Meet"
        case .whereby: "Whereby"
        case .around: "Around"
        case .slack: "Slack Huddle"
        case .goToMeeting: "GoTo Meeting"
        case .ringCentral: "RingCentral"
        case .amazonChime: "Amazon Chime"
        case .dialpad: "Dialpad"
        case .blueJeans: "BlueJeans"
        case .demodesk: "Demodesk"
        case .livestorm: "Livestorm"
        case .butter: "Butter"
        case .gather: "Gather"
        }
    }
}

public struct ScheduleMeetingLink: Identifiable, Equatable, Sendable {
    public var url: URL
    public var platform: ScheduleMeetingPlatform
    public var id: String { url.absoluteString }

    public init(url: URL, platform: ScheduleMeetingPlatform) {
        self.url = url
        self.platform = platform
    }
}

/// Finds the first known video-meeting URL. Raw event notes are inspected transiently and never retained.
public enum ScheduleMeetingDetector {
    public static func find(eventURL: URL?, location: String?, notes: String?) -> ScheduleMeetingLink? {
        if let eventURL, let platform = platform(for: eventURL) {
            return ScheduleMeetingLink(url: eventURL, platform: platform)
        }
        for text in [location, notes].compactMap({ $0 }) {
            for url in links(in: text) {
                if let platform = platform(for: url) { return ScheduleMeetingLink(url: url, platform: platform) }
            }
        }
        return nil
    }

    public static func platform(for url: URL) -> ScheduleMeetingPlatform? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        if hostMatches(host, ["meet.google.com"]) { return .googleMeet }
        if hostMatches(host, ["zoom.us", "zoom.com", "zoomgov.com"]) { return .zoom }
        if hostMatches(host, ["teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft"]) {
            return .microsoftTeams
        }
        if host == "aka.ms", path.contains("jointeamsmeeting") { return .microsoftTeams }
        if hostMatches(host, ["webex.com", "webexgov.com", "wbx2.com"]) { return .webex }
        if hostMatches(host, ["meet.jit.si", "8x8.vc", "jitsi.net"]) { return .jitsi }
        if hostMatches(host, ["whereby.com"]) { return .whereby }
        if hostMatches(host, ["around.co"]) { return .around }
        if hostMatches(host, ["app.slack.com", "slack.com"]), path.contains("/huddle") { return .slack }
        if hostMatches(host, ["gotomeeting.com", "goto.com"]) { return .goToMeeting }
        if hostMatches(host, ["ringcentral.com"]) { return .ringCentral }
        if hostMatches(host, ["chime.aws"]) { return .amazonChime }
        if hostMatches(host, ["dialpad.com"]) { return .dialpad }
        if hostMatches(host, ["bluejeans.com"]) { return .blueJeans }
        if hostMatches(host, ["demodesk.com"]) { return .demodesk }
        if hostMatches(host, ["livestorm.co"]) { return .livestorm }
        if hostMatches(host, ["butter.us"]) { return .butter }
        if hostMatches(host, ["gather.town"]) { return .gather }
        return nil
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    private static func hostMatches(_ host: String, _ domains: [String]) -> Bool {
        domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
