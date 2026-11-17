import Foundation
import Testing
@testable import TingCore

@Suite struct ConverterTests {
    /// Tuesday, 17 November 2026, 14:30:00 in Berlin (UTC+1).
    static let now = Date(timeIntervalSince1970: 1_794_922_200)
    static let berlin = TimeZone(identifier: "Europe/Berlin")!

    func value(_ query: String) -> String? {
        Converter.evaluate(query, now: Self.now, timeZone: Self.berlin)?.value
    }

    @Test(arguments: [
        ("1 yd to m", "0.9144"),
        ("5 yards to meters", "4.572"),
        ("1 mile in km", "1.609344"),
        ("10 km to mi", "6.213711922"),
        ("6 ft in cm", "182.88"),
        ("5ft to m", "1.524"),
        ("5 in to cm", "12.7"),
        ("2 ft in in", "24"),
        ("1 lb to kg", "0.45359237"),
        ("1 kg to lbs", "2.204622622"),
        ("100 f to c", "37.77777778"),
        ("-40 c to f", "-40"),
        ("0 c to k", "273.15"),
        ("1,5 l to ml", "1500"),
        ("1 gal to l", "3.785411784"),
        ("60 mph to km/h", "96.56064"),
        ("1 gb to mb", "1000"),
        ("1 gib to mib", "1024"),
        ("8 bits to bytes", "1"),
        ("90 min to h", "1.5"),
        ("2 days to hours", "48"),
        ("1 kwh to kj", "3600"),
        ("1 atm to kpa", "101.325"),
        ("180 deg to rad", "3.141592654"),
        ("1 sq ft to m2", "0.09290304"),
        ("1 acre to ha", "0.4046856422"),
        ("1 fl oz to ml", "29.57352956"),
        ("255 to hex", "0xff"),
        ("255 in bin", "0b11111111"),
        ("0xff to dec", "255"),
        ("0b1010 to oct", "0o12"),
        ("-10 to hex", "-0xa"),
        ("0xff", "255"),
        ("0b101", "5"),
        ("0o17", "15"),
        ("1700000000 to date", "2023-11-14 23:13:20"),
        ("1700000000000 to date", "2023-11-14 23:13:20"),
        ("1700000000 to utc", "2023-11-14 22:13:20 UTC"),
        ("1700000000 to iso", "2023-11-14T23:13:20+01:00"),
        ("2023-11-14 23:13:20 to unix", "1700000000"),
        ("2026-01-01 to unix", "1767222000"),
        ("now to unix", "1794922200"),
        ("now to ms", "1794922200000"),
        ("now + 2 days", "2026-11-19 14:30:00"),
        ("now - 90 min", "2026-11-17 13:00:00"),
        ("now + 1d 2h", "2026-11-18 16:30:00"),
        ("today + 3 weeks", "2026-12-08"),
        ("tomorrow + 1 month", "2026-12-18"),
        ("yesterday - 1y", "2025-11-16"),
        ("2026-01-31 + 1 month", "2026-02-28"),
        ("10:00 + 45m", "2026-11-17 10:45:00"),
        ("in 2 hours", "2026-11-17 16:30:00"),
        ("3 days ago", "2026-11-14 14:30:00"),
        ("2026-12-25 - today", "38 days"),
        ("today - 2026-12-25", "-38 days"),
        ("now - today", "14 hours 30 minutes"),
        ("2026-03-30 - 2026-03-29", "1 day"),
    ] as [(String, String)])
    func values(query: String, expected: String) {
        #expect(value(query) == expected, "\(query)")
    }

    @Test(arguments: [
        "", "Notes", "42", "2+2", "now", "today", "1 yd", "yard to meters", "5 m to kg", "5 m to parsecs",
        "foo to bar", "go to market", "255 to hexagon", "0x", "0xzz", "0b12", "1.5 to hex", "now + 2", "now + 2 apples",
        "now + 1.5 days", "today - 1", "2026-02-30 to unix", "2026-13-01 to unix", "25:00 + 1h", "in 2", "ago",
        "99999999999999999999 to hex", "now + 100000000 years", "1700000000 to nowhere",
    ])
    func notConversions(query: String) {
        #expect(value(query) == nil, "\(query)")
    }

    @Test func displayAndDetail() throws {
        let length = try #require(Converter.evaluate("5 yd to m"))
        #expect(length.display == "4.572 m")
        #expect(length.detail == "5 yd · Return copies 4.572")
        let hex = try #require(Converter.evaluate("255 to hex"))
        #expect(hex.detail == "255 · 0b11111111 · 0o377")
        let later = try #require(Converter.evaluate("now + 2 days", now: Self.now, timeZone: Self.berlin))
        #expect(later.detail == "Thursday · in 2 days")
        let day = try #require(Converter.evaluate("today + 1d", now: Self.now, timeZone: Self.berlin))
        #expect(day.detail == "Wednesday · tomorrow")
        let unix = try #require(Converter.evaluate("1700000000 to unix", now: Self.now, timeZone: Self.berlin))
        #expect(unix.detail == "Tuesday, 14 November 2023, 23:13:20")
        let span = try #require(Converter.evaluate("2026-12-25 - today", now: Self.now, timeZone: Self.berlin))
        #expect(span.detail == "5 weeks 3 days")
    }

    @Test func limits() {
        #expect(Converter.evaluate(String(repeating: "1", count: 115) + " to hex") == nil, "longer than 120 characters")
    }
}
