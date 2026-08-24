import AppKit
import CoreGraphics
import OSLog

private func resultMessage(_ result: DTDResult) -> String {
    String(cString: dtd_result_message(result))
}

private func displayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard !flags.contains(.beginConfigurationFlag), let userInfo else {
        return
    }

    let delegate = Unmanaged<AppDelegate>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    // Core Graphics advises against changing display configuration inside
    // the callback. Leave it first, then recover on the main queue.
    DispatchQueue.main.async {
        delegate.displayConfigurationDidChange(
            display: display,
            flags: flags
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.squareLength
    )
    private let contextMenu = NSMenu()
    private let logger = Logger(
        subsystem: "io.github.jinggqu.macbook-display-toggle",
        category: "display"
    )
    private var lastState = DTDDisplayState()
    private var lastResult = DTD_SUCCESS
    private var isRecovering = false
    private var knownBuiltInDisplayID: CGDirectDisplayID =
        kCGNullDirectDisplay
    private var safetyRecoveryArmed = false
    private var safetyWatchdogTimer: Timer?
    private var activeExternalDisplayIDs = Set<CGDirectDisplayID>()
    private var externalDisplayTrackingInitialized = false
    private var recoverySequence = 0
    private var recoveryWorkItem: DispatchWorkItem?
    private let recoveryRetryDelays: [TimeInterval] = [
        0.0, 0.2, 0.5, 1.0, 2.0,
    ]
    private var prefersBuiltInDisplayOff = false
    private var preferredStateSequence = 0
    private var preferredStateWorkItem: DispatchWorkItem?
    private let preferredStateRetryDelays: [TimeInterval] = [
        0.75, 1.5, 3.0,
    ]
    private let defaults = UserDefaults.standard
    private let builtInDisplayIDKey = "LastKnownBuiltInDisplayID"
    private let recoveryArmedKey = "SafetyRecoveryArmed"
    private let preferredOffKey = "PrefersBuiltInDisplayOff"

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.accessory)

        let savedDisplayID = defaults.integer(forKey: builtInDisplayIDKey)
        if savedDisplayID > 0 {
            knownBuiltInDisplayID = CGDirectDisplayID(savedDisplayID)
        }
        safetyRecoveryArmed = defaults.bool(forKey: recoveryArmedKey)
        prefersBuiltInDisplayOff = defaults.bool(forKey: preferredOffKey)
        updateSafetyWatchdog()
        contextMenu.autoenablesItems = false
        contextMenu.delegate = self
        statusItem.menu = contextMenu

        let callbackResult = CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        if callbackResult != .success {
            showError(
                title: "Display monitoring unavailable",
                message: "The app can still toggle the display, but its icon " +
                    "may not update after displays are connected or removed. " +
                    "CGError \(callbackResult.rawValue)."
            )
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        synchronizeActiveExternalDisplays()
        refreshState(allowSafetyRecovery: true)
        schedulePreferredStateReapply()
        rebuildContextMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        safetyWatchdogTimer?.invalidate()
        safetyWatchdogTimer = nil
        cancelSafetyRecoveryAttempts()
        cancelPreferredStateAttempts()
        restoreBuiltInDisplay()
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func turnOn(_ sender: Any?) {
        _ = sender
        setBuiltInDisplay(enabled: true)
    }

    @objc private func turnOff(_ sender: Any?) {
        _ = sender
        setBuiltInDisplay(enabled: false)
    }

    @objc private func quit(_ sender: Any?) {
        _ = sender
        restoreBuiltInDisplay()
        NSApp.terminate(nil)
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        _ = notification
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshState(allowSafetyRecovery: true)
            self?.schedulePreferredStateReapply()
        }
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        _ = notification
        displayConfigurationDidChange(display: nil, flags: [])
    }

    func displayConfigurationDidChange(
        display: CGDirectDisplayID?,
        flags: CGDisplayChangeSummaryFlags
    ) {
        if let display {
            updateTrackedExternalDisplays(display: display, flags: flags)
        }
        refreshState(allowSafetyRecovery: false)
        scheduleSafetyRecoveryAttempts()
        schedulePreferredStateReapply()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === contextMenu else {
            return
        }
        refreshState(allowSafetyRecovery: true)
        rebuildContextMenu()
    }

    private func setBuiltInDisplay(enabled: Bool) {
        cancelPreferredStateAttempts()
        var state = DTDDisplayState()
        var result = dtd_set_builtin_display_enabled(enabled, &state)
        if result != DTD_SUCCESS && enabled &&
            knownBuiltInDisplayID != kCGNullDirectDisplay {
            result = dtd_restore_builtin_display(
                knownBuiltInDisplayID,
                &state
            )
        }
        if result == DTD_SUCCESS {
            updatePreferredState(prefersOff: !enabled)
            rememberDisplayState(state)
            synchronizeActiveExternalDisplays()
        }
        if result != DTD_SUCCESS {
            logger.error(
                "Manual display change failed enabled=\(enabled, privacy: .public) result=\(result.rawValue, privacy: .public) cgError=\(state.cg_error, privacy: .public)"
            )
        }
        handle(result: result, state: state)
    }

    private func handle(result: DTDResult, state: DTDDisplayState) {
        lastResult = result
        lastState = state
        updateStatusItem()

        guard result != DTD_SUCCESS else {
            return
        }

        var message = resultMessage(result)
        if state.cg_error != 0 {
            message += " (CGError \(state.cg_error))."
        } else {
            message += "."
        }

        if result == DTD_ERROR_NO_ACTIVE_EXTERNAL_DISPLAY {
            message += " Connect and activate an external display first."
        } else if result == DTD_ERROR_CONFIGURATION {
            message += " Try reopening the lid, reconnecting the external " +
                "display, logging out, or rebooting."
        }

        showError(title: "MacBook Display Toggle", message: message)
    }

    private func refreshState(allowSafetyRecovery: Bool) {
        var state = DTDDisplayState()
        let result = dtd_get_display_state(&state)
        lastResult = result
        lastState = state

        if result == DTD_SUCCESS {
            rememberDisplayState(state)
        }

        updateStatusItem()

        if allowSafetyRecovery {
            scheduleSafetyRecoveryAttempts()
        }
    }

    private func rememberDisplayState(_ state: DTDDisplayState) {
        if state.builtin_display_id != kCGNullDirectDisplay {
            knownBuiltInDisplayID = state.builtin_display_id
            defaults.set(
                Int(state.builtin_display_id),
                forKey: builtInDisplayIDKey
            )
        }
        safetyRecoveryArmed = !state.builtin_display_active
        defaults.set(safetyRecoveryArmed, forKey: recoveryArmedKey)
        updateSafetyWatchdog()
        if !safetyRecoveryArmed {
            cancelSafetyRecoveryAttempts()
        }
    }

    private func updateSafetyWatchdog() {
        if safetyRecoveryArmed {
            guard safetyWatchdogTimer == nil else {
                return
            }
            safetyWatchdogTimer = Timer.scheduledTimer(
                withTimeInterval: 3.0,
                repeats: true
            ) { [weak self] _ in
                self?.safetyWatchdogDidFire()
            }
            safetyWatchdogTimer?.tolerance = 0.75
        } else {
            safetyWatchdogTimer?.invalidate()
            safetyWatchdogTimer = nil
        }
    }

    private func safetyWatchdogDidFire() {
        guard recoveryWorkItem == nil, safetyRecoveryArmed else {
            return
        }

        var externalCount: UInt32 = 0
        let countResult = dtd_get_active_external_display_count(
            &externalCount
        )
        let trackedNoExternal = externalDisplayTrackingInitialized &&
            activeExternalDisplayIDs.isEmpty
        let liveNoExternal = countResult == DTD_SUCCESS && externalCount == 0
        guard trackedNoExternal || liveNoExternal else {
            return
        }

        logger.notice(
            "Safety watchdog detected no hardware external display"
        )
        scheduleSafetyRecoveryAttempts()
    }

    private func synchronizeActiveExternalDisplays() {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else {
            return
        }

        if count == 0 {
            activeExternalDisplayIDs.removeAll()
            externalDisplayTrackingInitialized = true
            return
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var actualCount = count
        let result = ids.withUnsafeMutableBufferPointer { buffer in
            CGGetActiveDisplayList(count, buffer.baseAddress, &actualCount)
        }
        guard result == .success else {
            return
        }

        activeExternalDisplayIDs = Set(
            ids.prefix(Int(actualCount)).filter {
                dtd_is_hardware_external_display($0)
            }
        )
        externalDisplayTrackingInitialized = true
    }

    private func updateTrackedExternalDisplays(
        display: CGDirectDisplayID,
        flags: CGDisplayChangeSummaryFlags
    ) {
        if flags.contains(.removeFlag) || flags.contains(.disabledFlag) {
            activeExternalDisplayIDs.remove(display)
            externalDisplayTrackingInitialized = true
        } else if flags.contains(.addFlag) ||
            flags.contains(.enabledFlag) {
            if dtd_is_hardware_external_display(display) {
                activeExternalDisplayIDs.insert(display)
            } else {
                activeExternalDisplayIDs.remove(display)
            }
            externalDisplayTrackingInitialized = true
        }
    }

    private func scheduleSafetyRecoveryAttempts() {
        guard safetyRecoveryArmed,
              knownBuiltInDisplayID != kCGNullDirectDisplay else {
            return
        }

        recoverySequence += 1
        scheduleSafetyRecoveryAttempt(index: 0, sequence: recoverySequence)
    }

    private func scheduleSafetyRecoveryAttempt(
        index: Int,
        sequence: Int
    ) {
        guard index < recoveryRetryDelays.count,
              sequence == recoverySequence else {
            return
        }

        recoveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.runSafetyRecoveryAttempt(index: index, sequence: sequence)
        }
        recoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + recoveryRetryDelays[index],
            execute: workItem
        )
    }

    private func runSafetyRecoveryAttempt(index: Int, sequence: Int) {
        guard sequence == recoverySequence, !isRecovering else {
            return
        }
        recoveryWorkItem = nil

        var externalCount: UInt32 = 0
        let countResult = dtd_get_active_external_display_count(
            &externalCount
        )
        let trackedNoExternal = externalDisplayTrackingInitialized &&
            activeExternalDisplayIDs.isEmpty
        let liveNoExternal = countResult == DTD_SUCCESS && externalCount == 0
        let action = SafetyRecoveryPolicy.action(
            recoveryArmed: safetyRecoveryArmed,
            noExternalDisplayConfirmed: trackedNoExternal || liveNoExternal
        )
        if action == .stop {
            return
        }
        if action == .retry {
            scheduleSafetyRecoveryAttempt(
                index: index + 1,
                sequence: sequence
            )
            return
        }

        isRecovering = true
        var recoveredState = DTDDisplayState()
        let recoveryResult = dtd_restore_builtin_display(
            knownBuiltInDisplayID,
            &recoveredState
        )
        isRecovering = false

        if recoveryResult == DTD_SUCCESS {
            logger.notice(
                "Built-in display restored automatically displayID=\(recoveredState.builtin_display_id, privacy: .public)"
            )
        } else {
            logger.error(
                "Automatic restore failed attempt=\(index + 1, privacy: .public) result=\(recoveryResult.rawValue, privacy: .public) cgError=\(recoveredState.cg_error, privacy: .public)"
            )
        }

        lastResult = recoveryResult
        lastState = recoveredState
        if recoveryResult == DTD_SUCCESS {
            rememberDisplayState(recoveredState)
            synchronizeActiveExternalDisplays()
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.5
            ) { [weak self] in
                self?.refreshState(allowSafetyRecovery: false)
            }
        } else {
            if index + 1 < recoveryRetryDelays.count {
                scheduleSafetyRecoveryAttempt(
                    index: index + 1,
                    sequence: sequence
                )
            } else {
                logger.error(
                    "Direct recovery exhausted; restoring permanent display configuration"
                )
                CGRestorePermanentDisplayConfiguration()
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 1.0
                ) { [weak self] in
                    self?.refreshState(allowSafetyRecovery: true)
                }
            }
        }
        updateStatusItem()
    }

    private func cancelSafetyRecoveryAttempts() {
        recoverySequence += 1
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
    }

    private func updatePreferredState(prefersOff: Bool) {
        prefersBuiltInDisplayOff = prefersOff
        defaults.set(prefersOff, forKey: preferredOffKey)
        if !prefersOff {
            cancelPreferredStateAttempts()
        }
    }

    private func schedulePreferredStateReapply() {
        guard prefersBuiltInDisplayOff else {
            cancelPreferredStateAttempts()
            return
        }

        preferredStateSequence += 1
        schedulePreferredStateAttempt(
            index: 0,
            sequence: preferredStateSequence
        )
    }

    private func schedulePreferredStateAttempt(
        index: Int,
        sequence: Int
    ) {
        guard index < preferredStateRetryDelays.count,
              sequence == preferredStateSequence else {
            return
        }

        preferredStateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.runPreferredStateAttempt(index: index, sequence: sequence)
        }
        preferredStateWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + preferredStateRetryDelays[index],
            execute: workItem
        )
    }

    private func runPreferredStateAttempt(index: Int, sequence: Int) {
        guard sequence == preferredStateSequence,
              prefersBuiltInDisplayOff else {
            return
        }
        preferredStateWorkItem = nil

        if isRecovering {
            schedulePreferredStateAttempt(
                index: index + 1,
                sequence: sequence
            )
            return
        }

        var state = DTDDisplayState()
        let stateResult = dtd_get_display_state(&state)
        let action = PreferredDisplayPolicy.action(
            prefersBuiltInDisplayOff: prefersBuiltInDisplayOff,
            statusAvailable: stateResult == DTD_SUCCESS,
            builtInDisplayActive: state.builtin_display_active,
            activeExternalDisplayCount: state.active_external_display_count
        )

        if action == .stop {
            return
        }
        if action == .retry {
            schedulePreferredStateAttempt(
                index: index + 1,
                sequence: sequence
            )
            return
        }

        isRecovering = true
        var resultingState = DTDDisplayState()
        let result = dtd_set_builtin_display_enabled(
            false,
            &resultingState
        )
        isRecovering = false

        if result == DTD_SUCCESS {
            logger.notice(
                "Remembered Off state restored after external display connected"
            )
        } else {
            logger.error(
                "Remembered Off state restore failed attempt=\(index + 1, privacy: .public) result=\(result.rawValue, privacy: .public) cgError=\(resultingState.cg_error, privacy: .public)"
            )
        }

        lastResult = result
        lastState = resultingState
        if result == DTD_SUCCESS {
            rememberDisplayState(resultingState)
            synchronizeActiveExternalDisplays()
        } else {
            schedulePreferredStateAttempt(
                index: index + 1,
                sequence: sequence
            )
        }
        updateStatusItem()
    }

    private func cancelPreferredStateAttempts() {
        preferredStateSequence += 1
        preferredStateWorkItem?.cancel()
        preferredStateWorkItem = nil
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if lastResult != DTD_SUCCESS {
            button.image = symbol(named: "exclamationmark.triangle")
            button.alphaValue = 1.0
            button.toolTip = resultMessage(lastResult)
            button.setAccessibilityLabel("Display status unavailable")
            return
        }

        let isOn = lastState.builtin_display_active
        let preferredSymbol = isOn ? "laptopcomputer" : "laptopcomputer.slash"
        button.image = symbol(named: preferredSymbol) ??
            symbol(named: "laptopcomputer")
        button.alphaValue = 1.0

        let stateText = isOn ? "On" : "Off"
        button.toolTip = "Built-in display: \(stateText)"
        button.setAccessibilityLabel("Built-in display \(stateText)")
    }

    private func symbol(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 15,
            weight: .regular
        )
        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func rebuildContextMenu() {
        contextMenu.removeAllItems()

        if lastResult == DTD_SUCCESS {
            let stateText = lastState.builtin_display_active ? "On" : "Off"
            addInformationalItem("Built-in display: \(stateText)")
            addInformationalItem(
                "Active external displays: " +
                    "\(lastState.active_external_display_count)"
            )
        } else {
            addInformationalItem("Status unavailable")
        }
        addInformationalItem("Version \(applicationVersion)")

        contextMenu.addItem(.separator())
        let availability = MenuPolicy.availability(
            statusAvailable: lastResult == DTD_SUCCESS,
            builtInDisplayActive: lastState.builtin_display_active,
            activeExternalDisplayCount:
                lastState.active_external_display_count
        )

        let onItem = contextMenu.addItem(
            withTitle: "Turn Built-in Display On",
            action: #selector(turnOn(_:)),
            keyEquivalent: ""
        )
        onItem.target = self
        onItem.isEnabled = availability.canTurnOn
        if !onItem.isEnabled {
            onItem.toolTip = lastResult == DTD_SUCCESS
                ? "The built-in display is already on."
                : "Display status is unavailable."
        }

        let offItem = contextMenu.addItem(
            withTitle: "Turn Built-in Display Off",
            action: #selector(turnOff(_:)),
            keyEquivalent: ""
        )
        offItem.target = self
        offItem.isEnabled = availability.canTurnOff
        if !offItem.isEnabled {
            if lastResult != DTD_SUCCESS {
                offItem.toolTip = "Display status is unavailable."
            } else if !lastState.builtin_display_active {
                offItem.toolTip = "The built-in display is already off."
            } else {
                offItem.toolTip =
                    "Connect and activate an external display first."
            }
        }

        contextMenu.addItem(.separator())
        let quitItem = contextMenu.addItem(
            withTitle: "Quit and Restore Built-in Display",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
    }

    private func addInformationalItem(_ title: String) {
        let item = contextMenu.addItem(
            withTitle: title,
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
    }

    private func restoreBuiltInDisplay() {
        var state = DTDDisplayState()
        let result = dtd_get_display_state(&state)
        if result == DTD_SUCCESS && state.builtin_display_active {
            rememberDisplayState(state)
            return
        }

        if result == DTD_SUCCESS {
            if dtd_set_builtin_display_enabled(true, &state) == DTD_SUCCESS {
                rememberDisplayState(state)
            }
        } else if knownBuiltInDisplayID != kCGNullDirectDisplay {
            if dtd_restore_builtin_display(
                knownBuiltInDisplayID,
                &state
            ) == DTD_SUCCESS {
                rememberDisplayState(state)
            } else {
                CGRestorePermanentDisplayConfiguration()
            }
        }
    }

    private var applicationVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }

    private func showError(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
