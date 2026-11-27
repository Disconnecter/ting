import Foundation
import Testing
@testable import TingCore

@Suite struct ScheduleMeetingDetectorTests {
    @Test(arguments: [
        ("https://meet.google.com/abc-defg-hij", ScheduleMeetingPlatform.googleMeet),
        ("https://acme.zoom.us/j/123", .zoom),
        ("https://teams.microsoft.com/l/meetup-join/abc", .microsoftTeams),
        ("https://company.webex.com/meet/person", .webex),
        ("https://meet.jit.si/ting", .jitsi),
        ("https://whereby.com/ting", .whereby),
        ("https://around.co/r/ting", .around),
        ("https://app.slack.com/huddle/T123/C456", .slack),
        ("https://meet.goto.com/123456", .goToMeeting),
        ("https://v.ringcentral.com/join/123", .ringCentral),
        ("https://chime.aws/123", .amazonChime),
        ("https://meet.dialpad.com/ting", .dialpad),
        ("https://bluejeans.com/123", .blueJeans),
        ("https://demodesk.com/meeting/ting", .demodesk),
        ("https://app.livestorm.co/p/ting", .livestorm),
        ("https://butter.us/ting", .butter),
        ("https://gather.town/app/ting", .gather),
    ])
    func recognizesKnownPlatforms(_ text: String, _ platform: ScheduleMeetingPlatform) throws {
        let url = try #require(URL(string: text))
        #expect(ScheduleMeetingDetector.platform(for: url) == platform)
    }

    @Test func searchesEventURLThenLocationThenNotes() throws {
        let zoom = try #require(URL(string: "https://acme.zoom.us/j/123"))
        let meeting = ScheduleMeetingDetector.find(
            eventURL: zoom,
            location: "Google Meet https://meet.google.com/location-link",
            notes: "Teams https://teams.microsoft.com/l/meetup-join/notes-link")
        #expect(meeting == ScheduleMeetingLink(url: zoom, platform: .zoom))

        let location = ScheduleMeetingDetector.find(
            eventURL: nil,
            location: "Room 2 · https://meet.google.com/location-link",
            notes: "Backup https://company.webex.com/meet/person")
        #expect(location?.platform == .googleMeet)

        let notes = ScheduleMeetingDetector.find(
            eventURL: nil,
            location: "Room 2",
            notes: "Join with Microsoft Teams: https://teams.microsoft.com/l/meetup-join/notes-link")
        #expect(notes?.platform == .microsoftTeams)
    }

    @Test func rejectsUnknownAndLookalikeHosts() throws {
        for text in ["https://example.com/call", "https://meet.google.com.evil.example/abc", "mailto:a@example.com"] {
            let url = try #require(URL(string: text))
            #expect(ScheduleMeetingDetector.platform(for: url) == nil)
        }
        #expect(ScheduleMeetingDetector.find(eventURL: nil, location: nil,
                                             notes: "Docs: https://example.com/project") == nil)
    }
}
