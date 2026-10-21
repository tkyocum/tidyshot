/// Whether a parsed URL command may run (spec 2.9, URL security). Pure.
nonisolated enum URLCommandGate {
    enum Decision: Equatable, Sendable {
        case run
        /// The notification body.
        case refuse(String)
    }

    static let disabledMessage = "URL commands are off. Turn them on in Settings > General."

    /// Off refuses everything. On, a command that captures without a selection
    /// (`URLCommand.capturesWithoutSelection`) also needs `allowSilent`; every other command,
    /// restore included, runs. The action plays no part (decision 4). `sender` is named in the
    /// refusal when it is known and not empty once cleaned.
    static func decision(for command: URLCommand, enabled: Bool, allowSilent: Bool, sender: String? = nil) -> Decision {
        guard enabled else { return .refuse(disabledMessage) }
        guard command.capturesWithoutSelection, !allowSilent else { return .run }
        let name = sender.map(URLCommand.displayed).flatMap { $0.isEmpty ? nil : $0 }
        let from = name.map { " from \($0)" } ?? ""
        return .refuse("\(command.kind.rawValue)\(from) captures without a selection. Allow it in Settings > General > URL commands.")
    }
}
