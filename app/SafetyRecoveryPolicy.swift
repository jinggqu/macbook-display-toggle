enum SafetyRecoveryAction: Equatable {
    case stop
    case retry
    case restore
}

enum SafetyRecoveryPolicy {
    static func action(
        recoveryArmed: Bool,
        noExternalDisplayConfirmed: Bool
    ) -> SafetyRecoveryAction {
        guard recoveryArmed else {
            return .stop
        }
        return noExternalDisplayConfirmed ? .restore : .retry
    }
}

enum PreferredDisplayAction: Equatable {
    case stop
    case retry
    case turnOff
}

enum PreferredDisplayPolicy {
    static func action(
        prefersBuiltInDisplayOff: Bool,
        statusAvailable: Bool,
        builtInDisplayActive: Bool,
        activeExternalDisplayCount: UInt32
    ) -> PreferredDisplayAction {
        guard prefersBuiltInDisplayOff else {
            return .stop
        }
        guard statusAvailable else {
            return .retry
        }
        guard builtInDisplayActive else {
            return .stop
        }
        return activeExternalDisplayCount > 0 ? .turnOff : .retry
    }
}
