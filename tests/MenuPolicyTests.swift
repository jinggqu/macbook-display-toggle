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

        print("Menu policy tests passed.")
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
}
