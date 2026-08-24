@main
struct MenuPolicyTests {
    static func main() {
        check(
            statusAvailable: false,
            builtInDisplayActive: false,
            externalCount: 1,
            expected: MenuAvailability(canTurnOn: false, canTurnOff: false)
        )
        check(
            statusAvailable: true,
            builtInDisplayActive: true,
            externalCount: 0,
            expected: MenuAvailability(canTurnOn: false, canTurnOff: false)
        )
        check(
            statusAvailable: true,
            builtInDisplayActive: true,
            externalCount: 1,
            expected: MenuAvailability(canTurnOn: false, canTurnOff: true)
        )
        check(
            statusAvailable: true,
            builtInDisplayActive: false,
            externalCount: 1,
            expected: MenuAvailability(canTurnOn: true, canTurnOff: false)
        )
        check(
            statusAvailable: true,
            builtInDisplayActive: false,
            externalCount: 0,
            expected: MenuAvailability(canTurnOn: true, canTurnOff: false)
        )
        checkRecovery(
            armed: false,
            noExternalConfirmed: true,
            expected: .stop
        )
        checkRecovery(
            armed: true,
            noExternalConfirmed: false,
            expected: .retry
        )
        checkRecovery(
            armed: true,
            noExternalConfirmed: true,
            expected: .restore
        )
        checkPreferredState(
            prefersOff: false,
            statusAvailable: true,
            builtInActive: true,
            externalCount: 1,
            expected: .stop
        )
        checkPreferredState(
            prefersOff: true,
            statusAvailable: false,
            builtInActive: true,
            externalCount: 1,
            expected: .retry
        )
        checkPreferredState(
            prefersOff: true,
            statusAvailable: true,
            builtInActive: true,
            externalCount: 0,
            expected: .retry
        )
        checkPreferredState(
            prefersOff: true,
            statusAvailable: true,
            builtInActive: false,
            externalCount: 1,
            expected: .stop
        )
        checkPreferredState(
            prefersOff: true,
            statusAvailable: true,
            builtInActive: true,
            externalCount: 1,
            expected: .turnOff
        )

        print("Policy tests passed.")
    }

    private static func check(
        statusAvailable: Bool,
        builtInDisplayActive: Bool,
        externalCount: UInt32,
        expected: MenuAvailability
    ) {
        let actual = MenuPolicy.availability(
            statusAvailable: statusAvailable,
            builtInDisplayActive: builtInDisplayActive,
            activeExternalDisplayCount: externalCount
        )
        precondition(actual == expected, "Unexpected menu availability")
    }

    private static func checkRecovery(
        armed: Bool,
        noExternalConfirmed: Bool,
        expected: SafetyRecoveryAction
    ) {
        let actual = SafetyRecoveryPolicy.action(
            recoveryArmed: armed,
            noExternalDisplayConfirmed: noExternalConfirmed
        )
        precondition(actual == expected, "Unexpected recovery decision")
    }

    private static func checkPreferredState(
        prefersOff: Bool,
        statusAvailable: Bool,
        builtInActive: Bool,
        externalCount: UInt32,
        expected: PreferredDisplayAction
    ) {
        let actual = PreferredDisplayPolicy.action(
            prefersBuiltInDisplayOff: prefersOff,
            statusAvailable: statusAvailable,
            builtInDisplayActive: builtInActive,
            activeExternalDisplayCount: externalCount
        )
        precondition(actual == expected, "Unexpected preferred-state action")
    }
}
