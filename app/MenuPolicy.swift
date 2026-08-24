struct MenuAvailability: Equatable {
    let canTurnOn: Bool
    let canTurnOff: Bool
}

enum MenuPolicy {
    static func availability(
        statusAvailable: Bool,
        builtInDisplayActive: Bool,
        activeExternalDisplayCount: UInt32
    ) -> MenuAvailability {
        guard statusAvailable else {
            return MenuAvailability(canTurnOn: false, canTurnOff: false)
        }

        return MenuAvailability(
            canTurnOn: !builtInDisplayActive,
            canTurnOff: builtInDisplayActive &&
                activeExternalDisplayCount > 0
        )
    }
}
