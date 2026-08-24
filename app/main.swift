import AppKit
import CoreGraphics

private func resultMessage(_ result: DTDResult) -> String {
    String(cString: dtd_result_message(result))
}

private func displayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    _ = display
    guard !flags.contains(.beginConfigurationFlag), let userInfo else {
        return
    }

    let delegate = Unmanaged<AppDelegate>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    // Core Graphics advises against changing display configuration inside
    // the callback. Let WindowServer settle, then recover on the main queue.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        delegate.displayConfigurationDidChange()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.squareLength
    )
    private let contextMenu = NSMenu()
    private var lastState = DTDDisplayState()
    private var lastResult = DTD_SUCCESS
    private var isRecovering = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

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

        refreshState(allowSafetyRecovery: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        restoreBuiltInDisplay()
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        _ = sender
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleBuiltInDisplay()
        }
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
        }
    }

    func displayConfigurationDidChange() {
        refreshState(allowSafetyRecovery: true)
    }

    private func toggleBuiltInDisplay() {
        var state = DTDDisplayState()
        let stateResult = dtd_get_display_state(&state)
        guard stateResult == DTD_SUCCESS else {
            handle(result: stateResult, state: state)
            return
        }

        setBuiltInDisplay(enabled: !state.builtin_display_active)
    }

    private func setBuiltInDisplay(enabled: Bool) {
        var state = DTDDisplayState()
        let result = dtd_set_builtin_display_enabled(enabled, &state)
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

        if allowSafetyRecovery && result == DTD_SUCCESS &&
            !state.builtin_display_active &&
            state.active_external_display_count == 0 && !isRecovering {
            isRecovering = true
            var recoveredState = DTDDisplayState()
            let recoveryResult = dtd_set_builtin_display_enabled(
                true,
                &recoveredState
            )
            isRecovering = false
            lastResult = recoveryResult
            lastState = recoveredState
        }

        updateStatusItem()
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
        button.alphaValue = isOn ? 1.0 : 0.55

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

    private func showContextMenu() {
        refreshState(allowSafetyRecovery: true)
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

        contextMenu.addItem(.separator())
        let onItem = contextMenu.addItem(
            withTitle: "Turn Built-in Display On",
            action: #selector(turnOn(_:)),
            keyEquivalent: ""
        )
        onItem.target = self

        let offItem = contextMenu.addItem(
            withTitle: "Turn Built-in Display Off",
            action: #selector(turnOff(_:)),
            keyEquivalent: ""
        )
        offItem.target = self
        offItem.isEnabled = lastResult == DTD_SUCCESS &&
            lastState.builtin_display_active &&
            lastState.active_external_display_count > 0

        contextMenu.addItem(.separator())
        let quitItem = contextMenu.addItem(
            withTitle: "Quit and Restore Built-in Display",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self

        if let button = statusItem.button {
            contextMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.minY),
                in: button
            )
        }
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
        guard dtd_get_display_state(&state) == DTD_SUCCESS,
              !state.builtin_display_active else {
            return
        }
        _ = dtd_set_builtin_display_enabled(true, &state)
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
