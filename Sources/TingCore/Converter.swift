import Foundation

/// The converter of launcha, next to the calculator. Pure logic on Foundation: `Measurement`
/// units, the Gregorian calendar and `String(_:radix:)`; no table of its own factors.
///
/// - Units: `5 yd to m`, `100 f in c`, `3.5 gb to mib`, `60 mph to km/h`.
/// - Number bases: `255 to hex`, `0xff to bin`; a bare `0xff`, `0b101` or `0o17` gives its decimal.
/// - Unix time: `1700000000 to date` (13 digits: milliseconds), `now to unix`, `2026-01-01 to iso`.
/// - Dates: `now + 2 days`, `today - 3 weeks`, `in 90 min`, `2 days ago`, `2026-12-25 - today`.
///
/// `to`, `in`, `as`, `into`, `=` and `->` join a value and its target. A query is a conversion
/// only when one of these forms matches it in full.
public enum Converter {
    public struct Result: Equatable, Sendable {
        /// The text Return copies.
        public var value: String
        /// The text launcha shows.
        public var display: String
        /// The second line, such as the weekday or the other number bases.
        public var detail: String

        public init(value: String, display: String? = nil, detail: String) {
            self.value = value
            self.display = display ?? value
            self.detail = detail
        }
    }

    /// Longer queries are not read.
    public static let maxLength = 120

    static let connectors: Set<String> = ["to", "in", "into", "as", "=", "->", "→"]

    /// The conversion of `query`, or `nil` when it is not one. `now` and `timeZone` are for dates.
    public static func evaluate(_ query: String, now: Date = Date(), timeZone: TimeZone = .current) -> Result? {
        guard query.count <= maxLength else { return nil }
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        let dates = Dates(now: now, timeZone: timeZone)
        // The last connector first: `5 ft in in` is feet to inches.
        if words.count >= 3 {
            for i in stride(from: words.count - 2, through: 1, by: -1) where connectors.contains(words[i]) {
                let left = words[..<i].joined(separator: " ")
                let right = words[(i + 1)...].joined(separator: " ")
                if let result = convert(left, to: right, dates) { return result }
            }
        }
        let text = words.joined(separator: " ")
        if let number = Integer(text), number.radix != 10 { return number.result(in: 10) }
        return dates.arithmetic(text)
    }

    static func convert(_ left: String, to right: String, _ dates: Dates) -> Result? {
        if let radix = radixNames[right] { return Integer(left)?.result(in: radix) }
        if let format = dateFormats[right], let moment = dates.timestamp(left) ?? dates.moment(left)?.moment {
            return dates.show(moment, format)
        }
        return units(left, to: right)
    }

    // MARK: Number bases

    static let radixNames: [String: Int] = [
        "hex": 16, "hexadecimal": 16, "dec": 10, "decimal": 10,
        "bin": 2, "binary": 2, "oct": 8, "octal": 8,
    ]

    /// An integer: decimal digits, or `0x`, `0b`, `0o` and the digits of that base; a sign is allowed.
    struct Integer {
        var negative: Bool
        var magnitude: UInt64
        var radix: Int

        init?(_ text: String) {
            var rest = Substring(text)
            negative = rest.first == "-" || rest.first == "−"
            if negative || rest.first == "+" { rest = rest.dropFirst() }
            radix = 10
            for (prefix, base) in [("0x", 16), ("0b", 2), ("0o", 8)] where rest.hasPrefix(prefix) {
                radix = base
                rest = rest.dropFirst(2)
                break
            }
            guard !rest.isEmpty, rest.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  let value = UInt64(rest, radix: radix) else { return nil }
            magnitude = value
        }

        func text(_ base: Int) -> String {
            let sign = negative && magnitude != 0 ? "-" : ""
            let prefix = [16: "0x", 2: "0b", 8: "0o"][base] ?? ""
            return sign + prefix + String(magnitude, radix: base)
        }

        func result(in base: Int) -> Result {
            let others = [10, 16, 2, 8].filter { $0 != base }.map(text)
            return Result(value: text(base), detail: others.joined(separator: " · "))
        }
    }

    // MARK: Units

    /// `5 yd` to `m`: both units of one kind (length, mass…), converted by Foundation.
    static func units(_ left: String, to right: String) -> Result? {
        var scanner = Scanner(left)
        guard let amount = scanner.number(signed: true), let from = unit(scanner.rest),
              let to = unit(right), sameKind(from, to) else { return nil }
        let value = to.converter.value(fromBaseUnitValue: from.converter.baseUnitValue(fromValue: amount))
        guard let number = format(value), let source = format(amount) else { return nil }
        return Result(value: number, display: "\(number) \(to.symbol)",
                      detail: "\(source) \(from.symbol) · Return copies \(number)")
    }

    /// Units of one kind share a base unit: metres for every length, `UnitLength` or its private subclass.
    static func sameKind(_ a: Dimension, _ b: Dimension) -> Bool {
        type(of: a).baseUnit().symbol == type(of: b).baseUnit().symbol
    }

    /// A unit by name, symbol or plural, with spaces ignored: `fl oz`, `km/h`, `square feet`.
    static func unit(_ name: String) -> Dimension? {
        let key = name.replacingOccurrences(of: " ", with: "")
        if let unit = unitNames[key] { return unit }
        if key.count > 2, key.hasSuffix("s") { return unitNames[String(key.dropLast())] }
        return nil
    }

    static let unitNames: [String: Dimension] = {
        var names: [String: Dimension] = [:]
        func add(_ unit: Dimension, _ aliases: String...) { for alias in aliases { names[alias] = unit } }
        func linear(_ coefficient: Double) -> UnitConverter { UnitConverterLinear(coefficient: coefficient) }
        // Foundation rounds some US and imperial factors (a pound is 0.453592 kg there);
        // those units are defined here with their exact legal factors.
        // Length
        add(UnitLength.meters, "m", "meter", "metre")
        add(UnitLength.kilometers, "km", "kilometer", "kilometre")
        add(UnitLength.centimeters, "cm", "centimeter", "centimetre")
        add(UnitLength.millimeters, "mm", "millimeter", "millimetre")
        add(UnitLength.micrometers, "µm", "um", "micrometer", "micron")
        add(UnitLength.nanometers, "nm", "nanometer")
        add(UnitLength.inches, "in", "inch", "inches", "\"")
        add(UnitLength.feet, "ft", "foot", "feet", "'")
        add(UnitLength.yards, "yd", "yard")
        add(UnitLength.miles, "mi", "mile")
        add(UnitLength.nauticalMiles, "nmi", "nauticalmile")
        add(UnitLength.lightyears, "ly", "lightyear")
        add(UnitLength.astronomicalUnits, "au")
        // Mass
        add(UnitMass.kilograms, "kg", "kilogram", "kilo")
        add(UnitMass.grams, "g", "gram", "gramme")
        add(UnitMass.milligrams, "mg", "milligram")
        add(UnitMass.metricTons, "t", "tonne")
        add(UnitMass(symbol: "ton", converter: linear(907.18474)), "ton")
        add(UnitMass(symbol: "lb", converter: linear(0.45359237)), "lb", "pound")
        add(UnitMass(symbol: "oz", converter: linear(0.028349523125)), "oz", "ounce")
        add(UnitMass(symbol: "st", converter: linear(6.35029318)), "st", "stone")
        add(UnitMass.carats, "ct", "carat")
        // Temperature
        add(UnitTemperature.celsius, "c", "°c", "degc", "celsius")
        add(UnitTemperature.fahrenheit, "f", "°f", "degf", "fahrenheit")
        add(UnitTemperature.kelvin, "k", "kelvin")
        // Volume
        add(UnitVolume.liters, "l", "liter", "litre")
        add(UnitVolume.milliliters, "ml", "milliliter", "millilitre")
        add(UnitVolume.centiliters, "cl", "centiliter", "centilitre")
        add(UnitVolume.deciliters, "dl", "deciliter", "decilitre")
        add(UnitVolume.cubicMeters, "m3", "m³", "cubicmeter", "cubicmetre")
        add(UnitVolume.cubicCentimeters, "cm3", "cm³", "cc")
        add(UnitVolume(symbol: "in³", converter: linear(0.016387064)), "in3", "in³", "cubicinch", "cubicinches")
        add(UnitVolume(symbol: "ft³", converter: linear(28.316846592)), "ft3", "ft³", "cubicfoot", "cubicfeet")
        add(UnitVolume(symbol: "gal", converter: linear(3.785411784)), "gal", "gallon")
        add(UnitVolume.imperialGallons, "impgal", "imperialgallon")
        add(UnitVolume(symbol: "qt", converter: linear(0.946352946)), "qt", "quart")
        add(UnitVolume(symbol: "pt", converter: linear(0.473176473)), "pt", "pint")
        add(UnitVolume.cups, "cup")
        add(UnitVolume(symbol: "fl oz", converter: linear(0.0295735295625)), "floz", "fluidounce")
        add(UnitVolume(symbol: "tbsp", converter: linear(0.01478676478125)), "tbsp", "tablespoon")
        add(UnitVolume(symbol: "tsp", converter: linear(0.00492892159375)), "tsp", "teaspoon")
        // Area
        add(UnitArea.squareMeters, "m2", "m²", "sqm", "squaremeter", "squaremetre")
        add(UnitArea.squareKilometers, "km2", "km²", "sqkm", "squarekilometer", "squarekilometre")
        add(UnitArea.squareCentimeters, "cm2", "cm²", "sqcm", "squarecentimeter", "squarecentimetre")
        add(UnitArea.squareFeet, "ft2", "ft²", "sqft", "squarefoot", "squarefeet")
        add(UnitArea.squareInches, "in2", "in²", "sqin", "squareinch", "squareinches")
        add(UnitArea.squareYards, "yd2", "yd²", "sqyd", "squareyard")
        add(UnitArea.squareMiles, "mi2", "mi²", "sqmi", "squaremile")
        add(UnitArea.acres, "ac", "acre")
        add(UnitArea.hectares, "ha", "hectare")
        // Speed
        add(UnitSpeed.metersPerSecond, "m/s", "mps")
        add(UnitSpeed(symbol: "km/h", converter: linear(1 / 3.6)), "km/h", "kmh", "kph")
        add(UnitSpeed.milesPerHour, "mph", "mi/h")
        add(UnitSpeed(symbol: "kn", converter: linear(1852 / 3600)), "kn", "kt", "knot")
        // Duration
        add(UnitDuration.milliseconds, "ms", "millisecond")
        add(UnitDuration.seconds, "s", "sec", "second")
        add(UnitDuration.minutes, "min", "minute")
        add(UnitDuration.hours, "h", "hr", "hour")
        add(UnitDuration(symbol: "d", converter: linear(86_400)), "d", "day")
        add(UnitDuration(symbol: "wk", converter: linear(604_800)), "wk", "week")
        // Information
        add(UnitInformationStorage.bits, "bit")
        add(UnitInformationStorage.bytes, "b", "byte")
        add(UnitInformationStorage.kilobytes, "kb", "kilobyte")
        add(UnitInformationStorage.megabytes, "mb", "megabyte")
        add(UnitInformationStorage.gigabytes, "gb", "gigabyte")
        add(UnitInformationStorage.terabytes, "tb", "terabyte")
        add(UnitInformationStorage.petabytes, "pb", "petabyte")
        add(UnitInformationStorage.kibibytes, "kib", "kibibyte")
        add(UnitInformationStorage.mebibytes, "mib", "mebibyte")
        add(UnitInformationStorage.gibibytes, "gib", "gibibyte")
        add(UnitInformationStorage.tebibytes, "tib", "tebibyte")
        add(UnitInformationStorage.kilobits, "kbit", "kilobit")
        add(UnitInformationStorage.megabits, "mbit", "megabit")
        add(UnitInformationStorage.gigabits, "gbit", "gigabit")
        // Energy and power
        add(UnitEnergy.joules, "j", "joule")
        add(UnitEnergy.kilojoules, "kj", "kilojoule")
        add(UnitEnergy.calories, "cal", "calorie")
        add(UnitEnergy.kilocalories, "kcal", "kilocalorie")
        add(UnitEnergy.kilowattHours, "kwh")
        add(UnitEnergy(symbol: "Wh", converter: linear(3_600)), "wh")
        add(UnitPower.watts, "w", "watt")
        add(UnitPower.kilowatts, "kw", "kilowatt")
        add(UnitPower(symbol: "hp", converter: linear(745.69987158227022)), "hp", "horsepower")
        // Pressure
        add(UnitPressure.newtonsPerMetersSquared, "pa", "pascal")
        add(UnitPressure.hectopascals, "hpa", "hectopascal")
        add(UnitPressure.kilopascals, "kpa", "kilopascal")
        add(UnitPressure.bars, "bar")
        add(UnitPressure.millibars, "mbar", "millibar")
        add(UnitPressure(symbol: "psi", converter: linear(6894.757293168)), "psi")
        add(UnitPressure(symbol: "mmHg", converter: linear(133.322387415)), "mmhg")
        add(UnitPressure(symbol: "atm", converter: linear(101_325)), "atm")
        // Angle
        add(UnitAngle.degrees, "°", "deg", "degree")
        add(UnitAngle.radians, "rad", "radian")
        add(UnitAngle.gradians, "grad", "gradian")
        add(UnitAngle.revolutions, "rev", "turn", "revolution")
        return names
    }()

    /// Ten significant digits, without trailing zeros; very large or small values as `1e+21`.
    static func format(_ value: Double) -> String? {
        guard value.isFinite else { return nil }
        if value == 0 { return "0" }
        let magnitude = Int(Foundation.floor(Foundation.log10(Swift.abs(value))))
        if magnitude >= 21 || magnitude < -9 { return String(value) }
        guard var source = Calculator.decimal(value) else { return nil }
        var result = Decimal()
        NSDecimalRound(&result, &source, max(0, 9 - magnitude), .plain)
        return result.isZero ? "0" : result.description
    }

    // MARK: Dates

    enum DateFormat { case local, utc, iso, unix, millis }

    static let dateFormats: [String: DateFormat] = [
        "date": .local, "time": .local, "datetime": .local, "local": .local,
        "utc": .utc, "gmt": .utc, "iso": .iso, "iso8601": .iso,
        "unix": .unix, "timestamp": .unix, "epoch": .unix, "ts": .unix, "unixtime": .unix,
        "ms": .millis, "millis": .millis, "milliseconds": .millis,
    ]

    enum Step {
        case seconds(Double)
        case calendar(Calendar.Component, Int)
    }

    /// The units of `now + …`: `m` is a minute here, `mo` a month.
    static let steps: [String: Step] = {
        var steps: [String: Step] = [:]
        func add(_ step: Step, _ names: String...) { for name in names { steps[name] = step } }
        add(.seconds(1), "s", "sec", "secs", "second", "seconds")
        add(.seconds(60), "m", "min", "mins", "minute", "minutes")
        add(.seconds(3_600), "h", "hr", "hrs", "hour", "hours")
        add(.calendar(.day, 1), "d", "day", "days")
        add(.calendar(.day, 7), "w", "wk", "wks", "week", "weeks")
        add(.calendar(.month, 1), "mo", "mon", "month", "months")
        add(.calendar(.year, 1), "y", "yr", "yrs", "year", "years")
        return steps
    }()

    /// A date and whether it has a time of day: `today + 2 days` is a date only.
    struct Moment {
        var date: Date
        var hasTime: Bool
    }

    /// Year 1 to year 9999.
    static let dateRange = Date(timeIntervalSince1970: -62_135_596_800)...Date(timeIntervalSince1970: 253_402_300_799)
    /// Larger counts of days, months or years are not added.
    static let maxCount = 100_000

    struct Dates {
        let now: Date
        let calendar: Calendar

        init(now: Date, timeZone: TimeZone) {
            self.now = now
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            calendar.locale = Locale(identifier: "en_US_POSIX")
            self.calendar = calendar
        }

        /// A Unix time in seconds, or in milliseconds from 12 digits on.
        func timestamp(_ text: String) -> Moment? {
            guard let number = Integer(text), number.radix == 10, number.magnitude <= 1 << 53 else { return nil }
            var seconds = Double(number.magnitude)
            if number.magnitude >= 100_000_000_000 { seconds /= 1000 }
            let date = Date(timeIntervalSince1970: number.negative ? -seconds : seconds)
            return Converter.dateRange.contains(date) ? Moment(date: date, hasTime: true) : nil
        }

        /// A date with any steps: `now`, `2026-12-25 10:00 - 1h`, `in 2 days`, `3 weeks ago`.
        func moment(_ text: String) -> (moment: Moment, steps: Int)? {
            var scanner = Scanner(text)
            if scanner.word("in") {
                var moment = Moment(date: now, hasTime: true)
                guard let count = steps(&scanner, &moment, sign: 1), scanner.isAtEnd else { return nil }
                return (moment, count)
            }
            if text.hasSuffix(" ago") {
                var inner = Scanner(String(text.dropLast(4)))
                var moment = Moment(date: now, hasTime: true)
                guard let count = steps(&inner, &moment, sign: -1), inner.isAtEnd else { return nil }
                return (moment, count)
            }
            guard var moment = base(&scanner) else { return nil }
            var count = 0
            while !scanner.isAtEnd {
                scanner.skipSpaces()
                let sign: Int
                if scanner.take("+") { sign = 1 } else if scanner.take("-") || scanner.take("−") { sign = -1 } else { return nil }
                guard let added = steps(&scanner, &moment, sign: sign) else { return nil }
                count += added
            }
            return (moment, count)
        }

        /// `now + 2 days` and the like, or the time between two dates: `2026-12-25 - today`.
        func arithmetic(_ text: String) -> Result? {
            if let found = moment(text), found.steps > 0 { return show(found.moment, .local) }
            var scanner = Scanner(text)
            guard let first = base(&scanner) else { return nil }
            scanner.skipSpaces()
            guard scanner.take("-") || scanner.take("−") else { return nil }
            scanner.skipSpaces()
            guard let second = base(&scanner), scanner.isAtEnd else { return nil }
            return difference(first, second)
        }

        /// now, today, tomorrow, yesterday, `2026-12-25`, `2026-12-25 10:30`, `10:30` (today).
        func base(_ scanner: inout Scanner) -> Moment? {
            let start = scanner.index
            if let word = scanner.letters() {
                let today = calendar.startOfDay(for: now)
                switch word {
                case "now": return Moment(date: now, hasTime: true)
                case "today": return Moment(date: today, hasTime: false)
                case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: today).map { Moment(date: $0, hasTime: false) }
                case "yesterday": return calendar.date(byAdding: .day, value: -1, to: today).map { Moment(date: $0, hasTime: false) }
                default: scanner.index = start; return nil
                }
            }
            guard let first = scanner.digits() else { return nil }
            var parts = calendar.dateComponents([.year, .month, .day], from: now)
            var hasTime = false
            if first.count == 4, scanner.take("-") {
                guard let month = scanner.digits(), month.count <= 2, scanner.take("-"),
                      let day = scanner.digits(), day.count <= 2 else { scanner.index = start; return nil }
                parts = DateComponents(year: Int(first), month: Int(month), day: Int(day))
                let beforeTime = scanner.index
                if scanner.take(" ") || scanner.take("t"), let hour = scanner.digits(), hour.count <= 2,
                   scanner.take(":"), time(&scanner, hour: hour, into: &parts) {
                    hasTime = true
                } else {
                    scanner.index = beforeTime
                }
            } else if first.count <= 2, scanner.take(":"), time(&scanner, hour: first, into: &parts) {
                hasTime = true
            } else {
                scanner.index = start
                return nil
            }
            guard let date = calendar.date(from: parts), Converter.dateRange.contains(date) else { return nil }
            // No rollover: 2026-02-30 is not a date.
            let check = calendar.dateComponents([.year, .month, .day], from: date)
            guard check.year == parts.year, check.month == parts.month, check.day == parts.day else { return nil }
            return Moment(date: date, hasTime: hasTime)
        }

        /// The `30` or `30:15` after `hour:`.
        private func time(_ scanner: inout Scanner, hour: String, into parts: inout DateComponents) -> Bool {
            guard let minute = scanner.digits(), minute.count == 2,
                  let h = Int(hour), let m = Int(minute), h < 24, m < 60 else { return false }
            var second = 0
            if scanner.take(":") {
                guard let s = scanner.digits(), s.count == 2, let value = Int(s), value < 60 else { return false }
                second = value
            }
            parts.hour = h
            parts.minute = m
            parts.second = second
            return true
        }

        /// One or more `2 days`, `1d 12h` steps, added to `moment`. `nil` for anything else.
        func steps(_ scanner: inout Scanner, _ moment: inout Moment, sign: Int) -> Int? {
            var count = 0
            while true {
                let start = scanner.index
                scanner.skipSpaces()
                guard let amount = scanner.number(signed: false) else { scanner.index = start; break }
                scanner.skipSpaces()
                guard let name = scanner.letters(), let step = Converter.steps[name] else { return nil }
                switch step {
                case .seconds(let factor):
                    moment.date.addTimeInterval(Double(sign) * amount * factor)
                    moment.hasTime = true
                case .calendar(let component, let factor):
                    guard amount == amount.rounded(), amount <= Double(Converter.maxCount),
                          let date = calendar.date(byAdding: component, value: sign * Int(amount) * factor, to: moment.date)
                    else { return nil }
                    moment.date = date
                }
                guard Converter.dateRange.contains(moment.date) else { return nil }
                count += 1
            }
            return count > 0 ? count : nil
        }

        func show(_ moment: Moment, _ format: DateFormat) -> Result {
            let local = formatter(moment.hasTime ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd").string(from: moment.date)
            let long = formatter(moment.hasTime ? "EEEE, d MMMM yyyy, HH:mm:ss" : "EEEE, d MMMM yyyy").string(from: moment.date)
            switch format {
            case .local:
                let weekday = formatter("EEEE").string(from: moment.date)
                return Result(value: local, detail: "\(weekday) · \(relative(moment))")
            case .utc:
                let utc = formatter("yyyy-MM-dd HH:mm:ss", timeZone: TimeZone(identifier: "UTC")!).string(from: moment.date)
                return Result(value: utc + " UTC", detail: long)
            case .iso:
                let iso = ISO8601DateFormatter()
                iso.timeZone = calendar.timeZone
                return Result(value: iso.string(from: moment.date), detail: long)
            case .unix:
                return Result(value: String(Int64(moment.date.timeIntervalSince1970.rounded(.down))), detail: long)
            case .millis:
                return Result(value: String(Int64((moment.date.timeIntervalSince1970 * 1000).rounded(.down))), detail: long)
            }
        }

        /// `in 2 days`, `3 hours ago`, `tomorrow`.
        func relative(_ moment: Moment) -> String {
            if !moment.hasTime {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: moment.date).day ?? 0
                switch days {
                case 0: return "today"
                case 1: return "tomorrow"
                case -1: return "yesterday"
                default: return days > 0 ? "in " + Converter.count(days, "day") : Converter.count(-days, "day") + " ago"
                }
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.unitsStyle = .full
            return formatter.localizedString(for: moment.date, relativeTo: now)
        }

        /// `38 days`, `-2 days 3 hours`; the detail gives weeks.
        func difference(_ first: Moment, _ second: Moment) -> Result {
            let (earlier, later) = first.date < second.date ? (first.date, second.date) : (second.date, first.date)
            let units: [(Calendar.Component, String)] = [(.day, "day"), (.hour, "hour"), (.minute, "minute"), (.second, "second")]
            let parts = calendar.dateComponents(Set(units.map(\.0)), from: earlier, to: later)
            let words = units.compactMap { component, name -> String? in
                let value = parts.value(for: component) ?? 0
                return value == 0 ? nil : Converter.count(value, name)
            }
            let sign = first.date < second.date ? "-" : ""
            let value = words.isEmpty ? "0 days" : sign + words.joined(separator: " ")
            let days = parts.day ?? 0
            var detail = "Return copies the result"
            if days >= 7 {
                detail = Converter.count(days / 7, "week") + (days % 7 == 0 ? "" : " " + Converter.count(days % 7, "day"))
            }
            return Result(value: value, detail: detail)
        }

        private func formatter(_ pattern: String, timeZone: TimeZone? = nil) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = timeZone ?? calendar.timeZone
            formatter.dateFormat = pattern
            return formatter
        }
    }

    static func count(_ value: Int, _ word: String) -> String {
        "\(value) \(word)\(value == 1 ? "" : "s")"
    }

    // MARK: Scanner

    struct Scanner {
        let chars: [Character]
        var index = 0

        init(_ text: String) { chars = Array(text) }

        var isAtEnd: Bool { index == chars.count }
        /// The text after the scanner, without its leading spaces.
        var rest: String { String(chars[index...]).trimmingCharacters(in: .whitespaces) }

        mutating func skipSpaces() {
            while index < chars.count, chars[index] == " " { index += 1 }
        }

        mutating func take(_ char: Character) -> Bool {
            guard index < chars.count, chars[index] == char else { return false }
            index += 1
            return true
        }

        /// A whole word followed by a space: `in` of `in 2 days`.
        mutating func word(_ word: String) -> Bool {
            let end = index + word.count
            guard end < chars.count, String(chars[index..<end]) == word, chars[end] == " " else { return false }
            index = end
            return true
        }

        mutating func digits() -> String? {
            let start = index
            while index < chars.count, chars[index].isASCII, chars[index].isNumber { index += 1 }
            return index > start ? String(chars[start..<index]) : nil
        }

        mutating func letters() -> String? {
            let start = index
            while index < chars.count, chars[index].isLetter { index += 1 }
            return index > start ? String(chars[start..<index]) : nil
        }

        /// `12`, `1.5`, `1,5`, `.5`; with `signed`, a leading `-` or `+`.
        mutating func number(signed: Bool) -> Double? {
            let start = index
            var text = ""
            if signed, index < chars.count, chars[index] == "-" || chars[index] == "−" || chars[index] == "+" {
                if chars[index] != "+" { text = "-" }
                index += 1
            }
            let whole = digits() ?? ""
            var fraction = ""
            if index + 1 < chars.count, chars[index] == "." || chars[index] == ",", chars[index + 1].isASCII, chars[index + 1].isNumber {
                index += 1
                fraction = digits() ?? ""
            }
            guard !whole.isEmpty || !fraction.isEmpty, let value = Double(text + (whole.isEmpty ? "0" : whole) + "." + (fraction.isEmpty ? "0" : fraction))
            else { index = start; return nil }
            return value
        }
    }
}
