import Foundation

/// The values a naming template is expanded against: a timestamp, the app name, a counter and
/// this Mac's host name. `FileNamer` builds one when it writes the file; object keys get one
/// when their upload starts (from the record's timestamp and app, with a freshly drawn counter).
nonisolated struct TemplateContext: Sendable, Equatable {
    var date: Date
    var appName: String?
    var counter: Int
    /// Already normalised (see `TemplateExpander.normalizeHostname`).
    var hostname: String

    init(date: Date = Date(), appName: String? = nil, counter: Int = 0, hostname: String = HostName.local()) {
        self.date = date
        self.appName = appName
        self.counter = counter
        self.hostname = hostname
    }
}

/// The one token engine behind local file names (`FileNamer`) and object keys (`ObjectKeyNamer`).
///
/// Tokens: `{date}` yyyy-MM-dd, `{year}`, `{month}`, `{day}`, `{time}`, `{datetime}`, `{hostname}`,
/// `{app}`, `{counter}`, `{random}` (6 characters) and `{random:N}` (1 to 64). `{time}` and
/// `{datetime}` differ by style: file names use `HH.mm.ss` and a space, object keys use
/// `HH-mm-ss` and an underscore, so a key never contains a space or a dot-separated time.
/// In the object-key style every token value is passed through `keySafe`, so tokens never emit
/// a character outside `[A-Za-z0-9._-]`. Unknown or unterminated `{...}` text is left as literal.
nonisolated struct TemplateExpander: Sendable {
    enum Style: Sendable {
        case fileName
        case objectKey
    }

    enum Token: Equatable, Sendable {
        case date, year, month, day, time, datetime, hostname, app, counter
        case random(length: Int)

        /// `nil` for a name that is not a token.
        init?(name: String) {
            switch name {
            case "date": self = .date
            case "year": self = .year
            case "month": self = .month
            case "day": self = .day
            case "time": self = .time
            case "datetime": self = .datetime
            case "hostname": self = .hostname
            case "app": self = .app
            case "counter": self = .counter
            case "random": self = .random(length: TemplateExpander.defaultRandomLength)
            default:
                guard let match = name.wholeMatch(of: /random:(\d+)/) else { return nil }
                // Any number of digits, clamped as Phase 1's FileNamer did; a number too large for
                // `Int` is simply the maximum.
                let requested = Int(match.output.1) ?? TemplateExpander.randomLengthRange.upperBound
                self = .random(length: min(max(requested, TemplateExpander.randomLengthRange.lowerBound),
                                           TemplateExpander.randomLengthRange.upperBound))
            }
        }
    }

    enum Segment: Equatable, Sendable {
        case literal(String)
        case token(Token)
    }

    /// For settings captions.
    static let tokenList = "{date} {year} {month} {day} {time} {datetime} {hostname} {app} {counter} {random} {random:8}"
    static let defaultRandomLength = 6
    static let randomLengthRange = 1...64

    var randomString: @Sendable (Int) -> String

    init(randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString) {
        self.randomString = randomString
    }

    /// Splits `template` into literal runs and known tokens. `{foo}` and an unterminated `{` are
    /// literals; `{{date}` is a literal `{` followed by the date token.
    static func parse(_ template: String) -> [Segment] {
        var segments: [Segment] = []
        var literal = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            literal += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else {
                literal += rest[open...]
                rest = ""
                break
            }
            let name = String(rest[afterOpen..<close])
            if name.contains("{") {
                literal += "{"
                rest = rest[afterOpen...]
                continue
            }
            if let token = Token(name: name) {
                if !literal.isEmpty {
                    segments.append(.literal(literal))
                    literal = ""
                }
                segments.append(.token(token))
            } else {
                literal += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        literal += rest
        if !literal.isEmpty {
            segments.append(.literal(literal))
        }
        return segments
    }

    /// True when `template` contains `{random}`, `{random:N}` or `{counter}`, the tokens that make
    /// two captures produce different names. Without one, any two captures with the same date,
    /// app and host can produce the same name.
    static func hasCollisionGuard(_ template: String) -> Bool {
        parse(template).contains { segment in
            switch segment {
            case .token(.random), .token(.counter): true
            default: false
            }
        }
    }

    func expand(_ template: String, context: TemplateContext, style: Style) -> String {
        Self.parse(template).map { segment in
            switch segment {
            case .literal(let text): text
            case .token(let token): value(of: token, context: context, style: style)
            }
        }.joined()
    }

    private func value(of token: Token, context: TemplateContext, style: Style) -> String {
        let raw: String
        switch token {
        case .date: raw = Self.format(context.date, "yyyy-MM-dd")
        case .year: raw = Self.format(context.date, "yyyy")
        case .month: raw = Self.format(context.date, "MM")
        case .day: raw = Self.format(context.date, "dd")
        case .time: raw = Self.format(context.date, style == .fileName ? "HH.mm.ss" : "HH-mm-ss")
        case .datetime: raw = Self.format(context.date, style == .fileName ? "yyyy-MM-dd HH.mm.ss" : "yyyy-MM-dd_HH-mm-ss")
        case .hostname: raw = context.hostname
        case .app: raw = context.appName ?? "Screen"
        case .counter: raw = String(context.counter)
        case .random(let length): raw = randomString(length)
        }
        return style == .objectKey ? Self.keySafe(raw) : raw
    }

    static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Characters a token may emit into an object key (`/` is reserved for literal folders).
    static let keySafeCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")

    /// Maps every run of characters outside `keySafeCharacters` to one `-`, then trims `-` and
    /// `.` from both ends (so a value can never be `.` or `..`). An empty result becomes `x`.
    static func keySafe(_ value: String) -> String {
        var output = ""
        var pendingDash = false
        for character in value {
            if keySafeCharacters.contains(character) {
                if pendingDash, !output.isEmpty { output.append("-") }
                pendingDash = false
                output.append(character)
            } else {
                pendingDash = true
            }
        }
        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return trimmed.isEmpty ? "x" : trimmed
    }

    /// `Tims-MacBook-Pro.local` becomes `tims-macbook-pro`. Lowercased and a trailing `.local`
    /// dropped, then reduced to `[a-z0-9.-]`: `_`, spaces, `'`, non-ASCII letters and every other
    /// character become `-`; a run of `.` and `-` collapses to one character (`.` when the run
    /// contains one, so domain labels survive); `.` and `-` are trimmed from both ends. An empty
    /// result becomes `mac`.
    static func normalizeHostname(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasSuffix(".local") {
            name.removeLast(".local".count)
        }
        let alphanumerics = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        var output = ""
        // The separator owed before the next letter or digit; never written at either end.
        var separator: Character?
        for character in name {
            if alphanumerics.contains(character) {
                if let pending = separator, !output.isEmpty {
                    output.append(pending)
                }
                separator = nil
                output.append(character)
            } else {
                separator = character == "." || separator == "." ? "." : "-"
            }
        }
        return output.isEmpty ? "mac" : output
    }
}
