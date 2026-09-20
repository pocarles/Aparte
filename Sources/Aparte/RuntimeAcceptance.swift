import AppKit
import AparteCore
import ServiceManagement
@preconcurrency import Carbon

@MainActor
enum RuntimeAcceptance {
    static func run() -> Int32 {
        if ProcessInfo.processInfo.arguments.contains("--preview-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        var passed: [String] = []
        var failed: [String] = []

        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() {
                passed.append(name)
            } else {
                failed.append(name)
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AparteRuntimeAcceptance-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("aparte.md")
        defer { try? FileManager.default.removeItem(at: root) }

        if ProcessInfo.processInfo.arguments.contains("--exercise-default-store") {
            do {
                let defaultStore = try PersistenceStore()
                let originalData = try? Data(contentsOf: defaultStore.fileURL)
                defer {
                    if let originalData {
                        try? originalData.write(to: defaultStore.fileURL, options: .atomic)
                    } else {
                        try? FileManager.default.removeItem(at: defaultStore.fileURL)
                    }
                }

                let marker = "# Sandbox container check \(UUID().uuidString)"
                try defaultStore.save(marker)
                let savedMarker = try defaultStore.load()
                check(savedMarker == marker, "default-application-support-write")
                check(
                    defaultStore.fileURL.path.contains("/Containers/com.pocarles.aparte/Data/Library/Application Support/Aparte/aparte.md"),
                    "default-store-is-sandbox-container"
                )
            } catch {
                failed.append("default-store-error:\(String(describing: error))")
            }
        }

        do {
            let store = try PersistenceStore(fileURL: fileURL)
            let document = try DocumentController(store: store)
            let defaultsName = "AparteRuntimeAcceptance-\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: defaultsName) else { return 1 }
            defer { defaults.removePersistentDomain(forName: defaultsName) }
            let loginService = AcceptanceLoginService()
            let preferences = PreferencesController(hotKeyController: nil, launchAtLoginService: loginService)
            check(preferences.launchAtLoginState == .disabled, "login-default-disabled")
            _ = preferences.setLaunchAtLoginEnabled(true)
            check(preferences.launchAtLoginEnabled && loginService.registerCalls == 1, "login-enable-uses-service")
            _ = preferences.setLaunchAtLoginEnabled(false)
            check(preferences.launchAtLoginState == .disabled && loginService.unregisterCalls == 1, "login-disable-uses-service")
            loginService.registrationNeedsApproval = true
            _ = preferences.setLaunchAtLoginEnabled(true)
            check(preferences.launchAtLoginRequiresApproval && !preferences.launchAtLoginEnabled, "login-approval-is-not-enabled")
            _ = preferences.toggleLaunchAtLogin()
            check(preferences.launchAtLoginState == .disabled, "login-pending-can-be-disabled")
            loginService.shouldFail = true
            if case .failure = preferences.setLaunchAtLoginEnabled(true) {
                check(preferences.launchAtLoginState == .disabled, "login-failure-keeps-system-state")
            } else { failed.append("login-failure-keeps-system-state") }

            var openedLoginItems = 0
            let settings = PreferencesController(hotKeyController: nil, launchAtLoginService: loginService,
                                                 openLoginItems: { openedLoginItems += 1 })
            loginService.shouldFail = false
            settings.showSettings()
            let settingsWindow = settings.window
            func settingsContentFits() -> Bool {
                guard let content = settings.window?.contentView,
                      let stack = content.subviews.first as? NSStackView else { return false }
                content.layoutSubtreeIfNeeded()
                let visible = stack.arrangedSubviews.filter { !$0.isHidden }
                func visibleControls(_ views: [NSView]) -> [NSView] {
                    views.filter { !$0.isHidden }.flatMap { view in
                        [view] + ((view as? NSStackView).map { visibleControls($0.arrangedSubviews) } ?? [])
                    }
                }
                let controls = visibleControls(visible)
                let frames = controls.map { $0.convert($0.bounds, to: content) }
                guard let bottom = frames.map(\.minY).min(), let top = frames.map(\.maxY).max() else { return false }
                let topMargin = content.bounds.height - top
                // Native controls have OS-specific alignment insets. Require a
                // compact margin and full visibility, not identical frame pixels.
                let compact = (12...40).contains(bottom) && (12...40).contains(topMargin)
                let contained = frames.allSatisfy { content.bounds.insetBy(dx: -0.5, dy: -0.5).contains($0) }
                let labelsFit = controls.allSatisfy { view in
                    guard let label = view as? NSTextField, let cell = label.cell else { return true }
                    let needed = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: label.bounds.width, height: 10_000)).height
                    return label.bounds.height >= needed - 1
                }
                let fits = compact && contained && labelsFit
                if !fits {
                    print("Settings layout: content=\(content.bounds.size), bottom=\(bottom), top=\(topMargin), contained=\(contained), labelsFit=\(labelsFit)")
                }
                return fits
            }
            check(settingsContentFits(), "settings-window-fits-visible-content")
            check(settingsWindow?.title == "Settings" && settingsWindow?.isVisible == true
                  && settingsWindow?.level == .normal && !(settingsWindow is NSPanel), "settings-is-normal-visible-window")
            check(settingsWindow?.styleMask.contains(.closable) == true && !settings.isCapturingShortcut,
                  "settings-opens-without-capturing-keys")
            check(settings.shortcutButton?.isEnabled == false, "settings-unavailable-hotkey-is-disabled")
            settings.closeSettings()
            loginService.status = .enabled
            settings.showSettings()
            check(settings.window === settingsWindow && settings.window?.isVisible == true, "settings-reuses-window-on-reopen")
            check(settings.loginButton?.state == .on, "settings-refreshes-login-on-reopen")
            settings.loginButton?.performClick(nil)
            check(settings.launchAtLoginState == .disabled && settings.loginButton?.state == .off,
                  "settings-login-control-disables-service")
            loginService.registrationNeedsApproval = true
            settings.loginButton?.performClick(nil)
            check(settings.loginButton?.state == .mixed && settings.loginApprovalButton?.isHidden == false,
                  "settings-login-approval-is-visible")
            check(settingsContentFits(), "settings-window-fits-approval-content")
            settings.loginApprovalButton?.performClick(nil)
            check(openedLoginItems == 1, "settings-opens-system-login-items")
            settings.loginButton?.performClick(nil)
            check(settings.launchAtLoginState == .disabled && settings.loginApprovalButton?.isHidden == true,
                  "settings-pending-login-can-be-disabled")
            loginService.shouldFail = true
            settings.loginButton?.performClick(nil)
            check(settings.loginButton?.state == .off && settings.loginStatusLabel?.textColor == .systemRed
                  && settings.lastLaunchAtLoginError != nil, "settings-login-error-stays-visible-with-system-state")
            check(settingsContentFits(), "settings-window-fits-error-content")
            loginService.shouldFail = false
            _ = settings.setLaunchAtLoginEnabled(false)
            loginService.status = .notFound
            settings.showSettings()
            check(settings.loginButton?.isEnabled == false && settings.loginStatusLabel?.stringValue.contains("unavailable") == true,
                  "settings-unavailable-login-is-explained")
            check(settingsContentFits(), "settings-window-fits-wrapped-unavailable-content")
            loginService.status = .notRegistered
            settings.closeSettings()
            check(settings.window?.isVisible == false, "settings-closes-window")

            defaults.set(-1, forKey: "Aparte.globalShortcut.keyCode")
            defaults.set(-1, forKey: "Aparte.globalShortcut.modifiers")
            let hotKey = HotKeyController(action: {}, defaults: defaults)
            defer { hotKey.invalidate() }
            check(hotKey.currentShortcut == HotKeyController.defaultShortcut, "invalid-saved-shortcut-does-not-crash")
            check(HotKeyController.displayName(for: .init(keyCode: UInt32(kVK_Space),
                                                          modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))) == "⌃⌥⇧⌘Space",
                  "shortcut-display-uses-standard-modifier-order")
            let candidate = HotKeyController.Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
            if case .success = hotKey.updateShortcut(candidate) {
                check(hotKey.activeShortcut == candidate, "shortcut-registers-new-choice")
                check(defaults.integer(forKey: "Aparte.globalShortcut.keyCode") == Int(candidate.keyCode), "shortcut-choice-persists")
                let invalid = HotKeyController.Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: 0)
                if case .failure = hotKey.updateShortcut(invalid) {
                    check(hotKey.activeShortcut == candidate, "invalid-shortcut-preserves-active-choice")
                } else { failed.append("invalid-shortcut-preserves-active-choice") }
                let systemChord = HotKeyController.Shortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey))
                if case let .failure(error) = hotKey.updateShortcut(systemChord) {
                    check(error == .reservedShortcut(systemChord) && hotKey.activeShortcut == candidate
                          && error.localizedDescription.hasPrefix("⌘Q"), "system-chord-is-refused")
                } else { failed.append("system-chord-is-refused") }
                check(!HotKeyController.isReserved(HotKeyController.defaultShortcut)
                      && !HotKeyController.isReserved(candidate), "ordinary-chords-are-not-reserved")
                var reserved: EventHotKeyRef?
                let reservedKey = HotKeyController.Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: candidate.modifiers)
                let reservedStatus = RegisterEventHotKey(reservedKey.keyCode, reservedKey.modifiers, EventHotKeyID(signature: 0x54535431, id: 42), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &reserved)
                if reservedStatus == noErr, let reserved {
                    defer { UnregisterEventHotKey(reserved) }
                    if case .failure = hotKey.updateShortcut(reservedKey) {
                        check(hotKey.activeShortcut == candidate && hotKey.currentShortcut == candidate, "shortcut-conflict-preserves-active-choice")
                        check(defaults.integer(forKey: "Aparte.globalShortcut.keyCode") == Int(candidate.keyCode), "shortcut-conflict-does-not-persist")
                    } else { failed.append("shortcut-conflict-preserves-active-choice") }
                } else { failed.append("shortcut-conflict-test-registration") }
                hotKey.invalidate()
                let reopenedHotKey = HotKeyController(action: {}, defaults: defaults)
                check(reopenedHotKey.activeShortcut == candidate, "shortcut-restores-on-relaunch")
                reopenedHotKey.invalidate()
            } else { failed.append("shortcut-registers-new-choice") }

            let recordingDefaultsName = "AparteSettingsAcceptance-\(UUID().uuidString)"
            let recordingDefaults = UserDefaults(suiteName: recordingDefaultsName)!
            defer { recordingDefaults.removePersistentDomain(forName: recordingDefaultsName) }
            let recordingHotKey = HotKeyController(action: {}, defaults: recordingDefaults)
            let recorder = PreferencesController(hotKeyController: recordingHotKey, launchAtLoginService: loginService)
            recorder.showSettings()
            let recordingWindow = recorder.window!
            let previousShortcut = recordingHotKey.currentShortcut
            recorder.shortcutButton?.performClick(nil)
            check(recorder.isCapturingShortcut, "settings-starts-integrated-shortcut-recording")
            let invalidRecording = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: recordingWindow.windowNumber, context: nil, characters: "j", charactersIgnoringModifiers: "j",
                isARepeat: false, keyCode: UInt16(kVK_ANSI_J))!
            check(recorder.handleShortcutEvent(invalidRecording) && recorder.isCapturingShortcut
                  && recordingHotKey.currentShortcut == previousShortcut && recorder.shortcutStatusLabel?.textColor == .systemRed,
                  "settings-invalid-shortcut-keeps-recording-and-existing-choice")
            let escapeRecording = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: recordingWindow.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53)!
            check(recorder.handleShortcutEvent(escapeRecording) && !recorder.isCapturingShortcut
                  && recordingWindow.isVisible && recordingHotKey.currentShortcut == previousShortcut,
                  "settings-escape-cancels-capture-without-closing-window")
            recorder.shortcutButton?.performClick(nil)
            let recordedEvent = NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [.command, .option, .control, .shift], timestamp: 0,
                windowNumber: recordingWindow.windowNumber, context: nil, characters: "j", charactersIgnoringModifiers: "j",
                isARepeat: false, keyCode: UInt16(kVK_ANSI_J))!
            check(recorder.handleShortcutEvent(recordedEvent) && !recorder.isCapturingShortcut
                  && recordingHotKey.currentShortcut == candidate && recordingWindow.isVisible,
                  "settings-records-and-saves-shortcut-in-place")
            recorder.resetButton?.performClick(nil)
            check(recordingHotKey.currentShortcut == HotKeyController.defaultShortcut, "settings-resets-shortcut-to-option-space")
            check(recorder.resetButton?.isEnabled == (recordingHotKey.currentShortcut != HotKeyController.defaultShortcut),
                  "settings-reset-disabled-at-default")
            recorder.shortcutButton?.performClick(nil)
            recorder.closeSettings()
            check(!recorder.isCapturingShortcut && !recorder.handleShortcutEvent(recordedEvent), "settings-close-stops-capture")
            recorder.showSettings()
            check(recorder.window === recordingWindow && !recorder.isCapturingShortcut, "settings-reopen-does-not-restart-capture")
            recordingWindow.cancelOperation(nil)
            check(!recordingWindow.isVisible, "settings-escape-outside-capture-closes-window")
            recorder.showSettings()
            let closeSettingsEvent = shortcutEvent("w", modifiers: [.command], window: recordingWindow)
            check(recordingWindow.performKeyEquivalent(with: closeSettingsEvent) && !recordingWindow.isVisible,
                  "settings-command-w-closes-window")
            recordingHotKey.invalidate()

            let optionsTarget = AcceptanceOptionsTarget()
            let pad = PadWindowController(document: document, defaults: defaults,
                                          optionsMenu: { MenuBarController.makeOptionsMenu(target: optionsTarget) })
            optionsTarget.pad = pad
            let previousMenu = NSApp.mainMenu
            NSApp.mainMenu = MainMenu.make(target: optionsTarget)
            defer { NSApp.mainMenu = previousMenu }
            let previewKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let handled = MainActor.assumeIsolated {
                    guard NSApp.modalWindow == nil else { return false }
                    if event.keyCode == 53, pad.dismissTransientUI() { return true }
                    return pad.performOptionsKeyEquivalent(event)
                }
                return handled ? nil : event
            }
            defer { if let previewKeys { NSEvent.removeMonitor(previewKeys) } }
            let overlays = FocusOverlayController()
            if ProcessInfo.processInfo.arguments.contains("--measure-idle-only") {
                pad.setMarkdownForRuntimeCheck("# A short draft\n\nWrite, copy, and carry on. Your words stay on this Mac.")
                pad.show()
                pad.toggleCounts()
                drainRunLoop(for: 0.3)
                pad.hide()
                document.saveNow()
                print("APARTE_IDLE_READY")
                fflush(stdout)
                drainRunLoop(for: 45)
                return 0
            }
            var escapeDismissed = false
            pad.onDismiss = {
                escapeDismissed = true
                pad.hide()
                overlays.hide()
            }

            NSApp.activate(ignoringOtherApps: true)
            overlays.show()
            pad.show()
            drainRunLoop(for: 0.25)

            let initial = pad.runtimeSnapshot()
            let expectedSize = pad.expectedSizeForRuntimeCheck()
            check(initial.isVisible, "panel-visible")
            check(
                abs(initial.size.width - expectedSize.width) < 1 &&
                    abs(initial.size.height - expectedSize.height) < 1,
                "panel-1032x816-or-screen-fitted"
            )
            check(initial.editorOwnsFocus, "editor-first-responder")
            check(initial.editorHasSymmetricHorizontalPadding, "editor-symmetric-horizontal-padding")
            check(textColumnWidth(pad.editorForRuntimeCheck) <= 620.5, "text-column-capped-near-620")
            check(initial.level == .popUpMenu, "panel-above-overlays")
            check(overlays.runtimeWindowCount == NSScreen.screens.count, "overlay-per-screen")
            check(overlays.runtimeWindowsArePassive, "overlays-passive-no-blur-window")

            let footerButtons = pad.actionButtonsForRuntimeCheck
            check(footerButtons.count == 4 && footerButtons.map(\.title) == ["Copy", "Save", "Clear", "Snapshot"],
                  "footer-has-four-feedback-buttons")
            check(footerButtons.allSatisfy {
                ($0.toolTip?.isEmpty == false) && (($0.accessibilityLabel() as? String)?.isEmpty == false)
            }, "footer-buttons-have-tooltip-and-accessibility-label")
            if let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
                                                 timestamp: 0, windowNumber: pad.editorForRuntimeCheck.window?.windowNumber ?? 0,
                                                 context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) {
                func renderedButton(_ button: NSButton) -> Data? {
                    guard let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { return nil }
                    button.cacheDisplay(in: button.bounds, to: bitmap)
                    return bitmap.representation(using: .png, properties: [:])
                }
                for (index, button) in footerButtons.enumerated() {
                    let originalAppearance = button.appearance
                    for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                        button.appearance = NSAppearance(named: appearance)
                        button.mouseExited(with: event)
                        button.highlight(false)
                        let idle = renderedButton(button)
                        button.mouseEntered(with: event)
                        let hovered = renderedButton(button)
                        button.highlight(true)
                        let pressed = renderedButton(button)
                        check(idle != nil && hovered != idle && pressed != hovered, "footer-\(index)-\(name)-renders-distinct-hover-and-press")
                        button.highlight(false)
                        button.mouseExited(with: event)
                        check(renderedButton(button) == idle, "footer-\(index)-\(name)-returns-to-idle-after-pointer-exit")
                    }
                    button.appearance = originalAppearance
                    check(button.acceptsFirstResponder && !button.mouseDownCanMoveWindow, "footer-\(index)-keeps-keyboard-access-and-does-not-drag-pad")
                    let initialFrames = footerButtons.map(\.frame)
                    let successTitle = ["Copied", "Saved", "Cleared", "Copied"][index]
                    for (title, symbol) in [(successTitle, "checkmark"),
                                            ("Empty", "exclamationmark.circle"), ("Failed", "exclamationmark.circle")] {
                        button.acknowledge(title, symbol: symbol, detail: "The action failed.")
                        button.superview?.layoutSubtreeIfNeeded()
                        check(footerButtons.map(\.frame) == initialFrames, "footer-\(index)-\(title)-feedback-keeps-all-button-frames")
                    }
                    check(button.accessibilityValue() as? String == "The action failed.", "footer-\(index)-feedback-has-accessible-detail")
                    button.resetFeedback()
                    button.superview?.layoutSubtreeIfNeeded()
                    check(footerButtons.map(\.frame) == initialFrames && button.accessibilityValue() == nil,
                          "footer-\(index)-reset-keeps-layout-and-clears-accessible-detail")
                }
                check(pad.runtimeSnapshot().editorOwnsFocus, "footer-hover-and-feedback-preserve-editor-focus")
            } else { failed.append("footer-pointer-event-created") }

            let markdown = """
            # Runtime acceptance

            A **bold** and *italic* line with <u>underlining</u> and a [link](https://example.com).

            - First item
            1. Second item
            """
            pad.setMarkdownForRuntimeCheck(markdown)
            pad.selectForRuntimeCheck(NSRange(location: 0, length: 7))
            drainRunLoop(for: 0.05)
            check(pad.runtimeSnapshot().formattingBarIsVisible, "selection-formatting-bar")

            document.saveNow()
            check(document.lastSaveError == nil, "autosave-no-error")
            let savedMarkdown = try store.load()
            check(savedMarkdown == markdown, "markdown-written-cleanly")

            let restored = try DocumentController(store: store)
            check(restored.markdown == markdown, "markdown-restored-on-relaunch")

            pad.setMarkdownForRuntimeCheck("Link target")
            pad.applyLinkForRuntimeCheck(URL(string: "https://example.com")!, range: NSRange(location: 0, length: 4))
            drainRunLoop(for: 0.05)
            check(document.markdown == "[Link](https://example.com) target", "selected-text-link-applies")

            let recoverableMarkdown = "# Recoverable\n\nClear this in one undoable edit."
            pad.setMarkdownForRuntimeCheck(recoverableMarkdown)
            pad.clearForRuntimeCheck()
            drainRunLoop(for: 0.05)
            check(document.markdown.isEmpty, "clear-empties-document")
            check(footerButtons[2].title == "Cleared" && pad.runtimeSnapshot().editorOwnsFocus, "clear-acknowledges-success-and-keeps-editor-focus")
            pad.undoForRuntimeCheck()
            drainRunLoop(for: 0.05)
            check(document.markdown == recoverableMarkdown, "single-undo-restores-cleared-document")

            check(pad.hasRecovery, "clear-retains-recovery")
            let reopenedDocument = try DocumentController(store: store)
            let reopenedRecovery = try reopenedDocument.loadRecovery()
            check(reopenedRecovery?.string == MarkdownCodec.render(recoverableMarkdown).string, "recovery-survives-new-controller")
            pad.clearForRuntimeCheck()
            drainRunLoop(for: 0.05)
            pad.restoreLastCleared()
            check(document.markdown == recoverableMarkdown, "restore-last-cleared-text")
            drainRunLoop(for: 0.05)
            pad.undoForRuntimeCheck()
            check(document.markdown.isEmpty, "restore-is-undoable")
            pad.clearForRuntimeCheck()
            let recoveryAfterEmptyClear = try store.loadRecovery()
            check(recoveryAfterEmptyClear == recoverableMarkdown, "empty-clear-preserves-recovery")
            check(footerButtons[2].title == "Empty", "empty-clear-acknowledged")
            pad.saveMarkdownAs()
            check(footerButtons.count == 4 && footerButtons[1].title == "Empty" && pad.runtimeSnapshot().editorOwnsFocus,
                  "empty-save-acknowledged-without-losing-focus")
            try document.discardRecovery()
            check(!pad.hasRecovery && document.markdown.isEmpty, "discard-keeps-current-pad")

            let editor = pad.editorForRuntimeCheck
            pad.setMarkdownForRuntimeCheck("Hello **world** 👩🏽‍💻")
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            check(!pad.showsCounts, "counter-defaults-hidden")
            pad.toggleCounts()
            check(pad.countForRuntimeCheck == "2 words · 13 characters", "counter-counts-composed-characters")
            check(pad.countIsVisibleForRuntimeCheck, "counter-is-laid-out-and-visible")
            editor.setSelectedRange(NSRange(location: 6, length: 5))
            check(pad.countForRuntimeCheck == "Selection: 1 word · 5 characters", "counter-follows-selection")
            let clipboard = NSPasteboard.withUniqueName()
            defer { clipboard.releaseGlobally() }
            pad.copyAllForRuntimeCheck(to: clipboard)
            check(footerButtons.first?.title == "Copied" && clipboard.string(forType: .string) == editor.string,
                  "footer-copy-acknowledges-written-clipboard")
            check(editor.selectedRange() == NSRange(location: 6, length: 5) && pad.runtimeSnapshot().editorOwnsFocus,
                  "footer-copy-preserves-selection-and-editor-focus")
            let copiedText = clipboard.string(forType: .string)
            pad.setMarkdownForRuntimeCheck("")
            pad.copyAllForRuntimeCheck(to: clipboard)
            check(footerButtons.first?.title == "Empty" && clipboard.string(forType: .string) == copiedText,
                  "empty-copy-acknowledged-without-overwriting-clipboard")
            drainRunLoop(for: 1)
            pad.setMarkdownForRuntimeCheck("A second copy")
            pad.copyAllForRuntimeCheck(to: clipboard)
            drainRunLoop(for: 1.8)
            check(footerButtons.first?.title == "Copied" && clipboard.string(forType: .string) == "A second copy",
                  "repeated-copy-feedback-outlasts-the-previous-reset")
            drainRunLoop(for: 0.3)
            check(footerButtons.map(\.title) == ["Copy", "Save", "Clear", "Snapshot"], "footer-feedback-resets-without-polling")
            pad.setMarkdownForRuntimeCheck("Hello **world** 👩🏽‍💻")
            editor.setSelectedRange(NSRange(location: 6, length: 5))
            editor.copyPlainText(to: clipboard)
            check(clipboard.string(forType: .string) == "world" && clipboard.data(forType: .rtf) == nil, "copy-plain-selection-without-formatting")
            editor.copyAllPreservingSelection(to: clipboard)
            check(clipboard.string(forType: .string) == editor.string && clipboard.data(forType: .html) != nil && clipboard.data(forType: .rtf) == nil, "copy-all-rich-and-plain")
            check(editor.selectedRange() == NSRange(location: 6, length: 5), "copy-all-preserves-selection")
            editor.setSelectedRange(NSRange(location: 3, length: 0))
            editor.copyPlainText(to: clipboard)
            check(clipboard.string(forType: .string) == editor.string && editor.selectedRange().location == 3, "copy-plain-whole-pad-preserves-cursor")

            for markdown in ["- world", "7. world", "# world"] {
                pad.setMarkdownForRuntimeCheck(markdown)
                editor.setSelectedRange((editor.string as NSString).range(of: "wor"))
                editor.copySelection(to: clipboard)
                check(clipboard.string(forType: .string) == "wor"
                      && clipboard.string(forType: .html)?.contains("<li") == false
                      && clipboard.string(forType: .html)?.contains("<h1>") == false,
                      "partial-block-formatted-copy-\(markdown.prefix(1))")
                editor.copyPlainText(to: clipboard)
                check(clipboard.string(forType: .string) == "wor", "partial-block-plain-copy-\(markdown.prefix(1))")
                editor.copyMarkdown(to: clipboard)
                let copied = clipboard.string(forType: .string) ?? ""
                check(!copied.hasPrefix("- ") && !copied.hasPrefix("7. ") && !copied.hasPrefix("# ")
                      && MarkdownCodec.render(copied).string == "wor", "partial-block-markdown-copy-\(markdown.prefix(1))")
                if markdown.hasPrefix("#") {
                    check(copied == "wor", "partial-heading-markdown-has-no-structural-bold")
                    editor.copySelection(to: clipboard)
                    check(clipboard.string(forType: .html)?.contains("<strong>") == false,
                          "partial-heading-html-has-no-structural-bold")
                }
                editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
                editor.copyMarkdown(to: clipboard)
                check(clipboard.string(forType: .string) == markdown, "whole-block-markdown-copy-\(markdown.prefix(1))")
            }
            pad.setMarkdownForRuntimeCheck("")
            let clipboardBeforeEmptyMarkdown = clipboard.changeCount
            editor.copyMarkdown(to: clipboard)
            check(clipboard.changeCount == clipboardBeforeEmptyMarkdown, "empty-markdown-copy-preserves-pasteboard")

            for marker in ["- ", "* ", "+ ", "• ", "12. "] {
                editor.replaceAll(with: NSAttributedString(string: marker + "Item", attributes: AparteTypography.baseAttributes))
                editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
                let kind: AparteListKind = marker == "12. " ? .ordered : .unordered
                editor.applyList(kind)
                check(editor.string == "Item" && document.markdown == "Item", "list-action-toggles-off-\(marker)")
                editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
                editor.applyList(kind)
                check(editor.string == (kind == .unordered ? "• Item" : "1. Item"),
                      "list-action-reapplies-canonical-marker-\(marker)")
                editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
                editor.applyHeading(level: 1)
                check(editor.string == "Item" && document.markdown == "# Item", "heading-replaces-list-\(marker)")
                editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
                editor.applyList(.unordered)
                check(editor.string == "• Item" && document.markdown == "- Item"
                      && editor.attributedString().attribute(.aparteHeadingLevel, at: 0, effectiveRange: nil) == nil,
                      "list-replaces-heading-\(marker)")
            }
            pad.setMarkdownForRuntimeCheck("- One\n- Two\n- Three")
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.applyList(.ordered)
            check(editor.string == "1. One\n2. Two\n3. Three", "list-conversion-numbers-all-selected-paragraphs")
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.applyList(.ordered)
            check(editor.string == "One\nTwo\nThree", "numbered-list-reapplication-toggles-off")
            pad.setMarkdownForRuntimeCheck("One\n")
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.applyList(.unordered)
            check(editor.string == "One\n• ", "list-action-at-empty-final-paragraph")
            pad.setMarkdownForRuntimeCheck("# *word*")
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.applyList(.unordered)
            check(document.markdown == "- *word*", "heading-to-list-preserves-inline-italic")
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.applyHeading(level: 1)
            check(document.markdown == "# *word*", "list-to-heading-preserves-inline-italic")
            editor.setSelectedRange(NSRange(location: 0, length: 3))
            editor.copyMarkdown(to: clipboard)
            check(clipboard.string(forType: .string) == "*wor*", "partial-heading-copy-preserves-inline-italic")

            pad.setMarkdownForRuntimeCheck("# Item")
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.applyHeading(level: 1)
            check(editor.string == "Item" && document.markdown == "Item", "heading-toggles-off")

            editor.replaceAll(with: NSAttributedString(string: "word", attributes: AparteTypography.baseAttributes))
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.toggleBold(nil)
            let boldedMarkdown = document.markdown
            drainRunLoop(for: 0.05)
            pad.undoForRuntimeCheck()
            check(boldedMarkdown == "**word**" && document.markdown == "word", "bold-is-undoable")

            editor.replaceAll(with: NSAttributedString(string: "word", attributes: AparteTypography.baseAttributes))
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.applyHeading(level: 1)
            let headingMarkdown = document.markdown
            drainRunLoop(for: 0.05)
            pad.undoForRuntimeCheck()
            check(headingMarkdown == "# word" && document.markdown == "word", "heading-is-one-undo-step")

            pad.setMarkdownForRuntimeCheck("One\nTwo")
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.applyList(.unordered)
            let listedMarkdown = document.markdown
            drainRunLoop(for: 0.05)
            pad.undoForRuntimeCheck()
            check(listedMarkdown == "- One\n- Two" && document.markdown == "One\n\nTwo", "list-is-one-undo-step")

            editor.replaceAll(with: NSAttributedString(string: "word", attributes: AparteTypography.baseAttributes))
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.toggleBold(nil)
            editor.insertText("x", replacementRange: editor.selectedRange())
            check(document.markdown == "word**x**", "caret-bold-applies-to-typing")

            pad.setMarkdownForRuntimeCheck("# word")
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.toggleBold(nil)
            let boldHeadingMarkdown = document.markdown
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.toggleBold(nil)
            check(boldHeadingMarkdown == "# **word**" && document.markdown == "# word", "heading-inline-bold-round-trips")

            editor.replaceAll(with: NSAttributedString(string: "• Item", attributes: AparteTypography.baseAttributes))
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            editor.deleteBackward(nil)
            check(editor.string == "Item" && document.markdown == "Item", "backspace-after-marker-removes-it")

            editor.replaceAll(with: NSAttributedString(string: "• Item", attributes: AparteTypography.baseAttributes))
            editor.setSelectedRange(NSRange(location: 0, length: 2))
            editor.delete(nil)
            check(document.markdown == "Item", "deleted-marker-is-not-a-list")

            editor.replaceAll(with: NSAttributedString(string: "hello world", attributes: AparteTypography.baseAttributes))
            editor.setSelectedRange(NSRange(location: 6, length: 5))
            editor.cutSelection(to: clipboard)
            check(clipboard.string(forType: .string) == "world" && clipboard.data(forType: .rtf) == nil
                  && editor.string == "hello ", "cut-writes-normalized-clipboard")

            editor.replaceAll(with: NSAttributedString(string: "Item", attributes: AparteTypography.baseAttributes))
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            editor.applyList(.unordered)
            check(editor.selectedRange() == NSRange(location: 4, length: 0), "block-command-keeps-caret-on-content")

            editor.replaceAll(with: NSAttributedString(string: "Item", attributes: AparteTypography.baseAttributes))
            editor.setSelectedRange(NSRange(location: 2, length: 2))
            editor.applyList(.unordered)
            check(editor.selectedRange() == NSRange(location: 4, length: 2), "block-command-keeps-partial-selection")

            pad.setMarkdownForRuntimeCheck("**bold** plain")
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            editor.applyList(.unordered)
            editor.insertText("x", replacementRange: editor.selectedRange())
            check(document.markdown == "- **boxld** plain", "block-command-continues-inline-traits")

            pad.setMarkdownForRuntimeCheck("First paragraph")
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.insertNewline(nil)
            editor.insertText("Second paragraph", replacementRange: editor.selectedRange())
            check(editor.string == "First paragraph\nSecond paragraph", "return-creates-one-paragraph-boundary")
            let paragraphStyle = editor.attributedString().attribute(.paragraphStyle, at: 16, effectiveRange: nil) as? NSParagraphStyle
            check(paragraphStyle?.paragraphSpacing == AparteTypography.paragraphSpacing, "return-applies-visible-paragraph-spacing")
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.insertNewline(nil)
            let withOneBreak = editor.string
            editor.insertNewline(nil)
            check(withOneBreak == "First paragraph\nSecond paragraph\n" && editor.string == withOneBreak,
                  "return-on-empty-paragraph-adds-no-row")
            let footerParagraphSelection = NSRange(location: 6, length: 5)
            editor.setSelectedRange(footerParagraphSelection)
            clipboard.clearContents()
            pad.copyAllForRuntimeCheck(to: clipboard)
            check(footerButtons.first?.title == "Copied"
                  && clipboard.string(forType: .string) == "First paragraph\n\nSecond paragraph",
                  "footer-paragraph-copy-acknowledges-email-ready-clipboard")
            check(clipboard.string(forType: .html)?.contains("<p>First paragraph</p><p>Second paragraph</p>") == true,
                  "footer-paragraph-copy-includes-rich-html")
            check(editor.selectedRange() == footerParagraphSelection && pad.runtimeSnapshot().editorOwnsFocus,
                  "footer-paragraph-copy-preserves-selection-and-editor-focus")
            let paragraphSelection = NSRange(location: 0, length: editor.string.utf16.count)
            editor.setSelectedRange(paragraphSelection)
            editor.copySelection(to: clipboard)
            check(clipboard.string(forType: .string) == "First paragraph\n\nSecond paragraph", "selection-copy-is-email-ready")
            let copiedHTML = clipboard.string(forType: .html) ?? ""
            check(copiedHTML.contains("<p>First paragraph</p><p>Second paragraph</p>") && !copiedHTML.contains("font-") && clipboard.data(forType: .rtf) == nil,
                  "rich-copy-inherits-destination-typography")
            check(editor.selectedRange() == paragraphSelection && pad.runtimeSnapshot().editorOwnsFocus,
                  "paragraph-copy-preserves-selection-and-focus")
            editor.setSelectedRange(NSRange(location: 3, length: 0))
            editor.copyPlainText(to: clipboard)
            check(clipboard.string(forType: .string) == "First paragraph\n\nSecond paragraph" && clipboard.data(forType: .html) == nil,
                  "plain-copy-has-ready-to-send-paragraphs")

            let beforeZoom = document.markdown
            let beforeFonts = editor.attributedString()
            pad.zoomIn()
            drainRunLoop(for: 0.05)
            check(abs(pad.zoomForRuntimeCheck - 1.1) < 0.01, "zoom-in-changes-display")
            check(textColumnWidth(editor) <= 620.5, "zoomed-text-column-stays-capped")
            let wideFrame = editor.window?.frame ?? .zero
            editor.window?.setContentSize(NSSize(width: 768, height: wideFrame.height))
            drainRunLoop(for: 0.05)
            let narrowColumn = textColumnWidth(editor)
            let narrowWidth = editor.enclosingScrollView?.contentView.bounds.width ?? 0
            let oldColumn = narrowWidth * (1 - 2 * 0.2)
            check(narrowColumn + 1 >= oldColumn, "narrow-pad-keeps-proportional-column")
            editor.window?.setFrame(wideFrame, display: true)
            drainRunLoop(for: 0.05)
            if let clip = editor.enclosingScrollView?.contentView {
                check(editor.frame.width <= clip.bounds.width + 1, "zoom-reflows-without-horizontal-clipping")
            }
            check(document.markdown == beforeZoom && editor.attributedString().isEqual(to: beforeFonts), "zoom-preserves-document-and-copy-formatting")
            pad.zoomOut()
            check(abs(pad.zoomForRuntimeCheck - 1) < 0.01, "zoom-out")
            pad.zoomIn()
            pad.resetZoom()
            check(pad.zoomForRuntimeCheck == 1, "zoom-reset")
            for _ in 0..<9 { pad.zoomIn() }
            let atMaximumZoom = !pad.canZoomIn && pad.canZoomOut
            pad.resetZoom()
            check(atMaximumZoom && pad.isDefaultZoom && pad.canZoomIn, "zoom-limits-reported")
            pad.selectForRuntimeCheck(NSRange(location: 0, length: 5))
            drainRunLoop(for: 0.05)
            if pad.runtimeSnapshot().formattingBarIsVisible {
                pad.zoomIn()
                pad.resetZoom()
                drainRunLoop(for: 0.05)
                check(pad.runtimeSnapshot().formattingBarIsVisible, "zoom-keeps-formatting-bar")
            } else { failed.append("zoom-keeps-formatting-bar") }
            pad.selectForRuntimeCheck(NSRange(location: 0, length: 0))
            pad.shortcutHint = "⌥Space shows or hides Aparte. Escape closes it."
            check(pad.editorForRuntimeCheck.placeholderHint == pad.shortcutHint, "placeholder-hint-follows-shortcut")
            pad.toggleCounts()
            check(!pad.showsCounts && !defaults.bool(forKey: "showWordCount"), "counter-can-be-disabled")

            for (source, expected) in [("- Café 👩🏽‍💻", "• Café 👩🏽‍💻\n• "), ("7. First", "7. First\n8. ")] {
                pad.setMarkdownForRuntimeCheck(source)
                let original = editor.string
                editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                editor.undoManager?.removeAllActions()
                editor.insertNewline(nil)
                check(editor.string == expected, "list-return-\(source.prefix(1))")
                drainRunLoop(for: 0.05)
                pad.undoForRuntimeCheck()
                check(editor.string == original, "list-return-single-undo-\(source.prefix(1))")
                editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                editor.insertNewline(nil)
                editor.insertNewline(nil)
                editor.insertText("Plain paragraph", replacementRange: editor.selectedRange())
                check(!document.markdown.contains("- Plain paragraph") && !document.markdown.contains("8. Plain paragraph"), "empty-list-exit-\(source.prefix(1))")
            }

            // Inserted as text, not through Return, so list continuation does
            // not turn the following paragraph into another item.
            editor.replaceAll(with: NSAttributedString(string: "Before\n- one\n- two\nAfter", attributes: AparteTypography.baseAttributes))
            let listed = editor.attributedString()
            let oneLocation = (editor.string as NSString).range(of: "one").location
            let twoLocation = (editor.string as NSString).range(of: "two").location
            let afterLocation = (editor.string as NSString).range(of: "After").location
            func spacing(at location: Int) -> CGFloat {
                (listed.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing ?? -1
            }
            check(spacing(at: oneLocation) == AparteTypography.listItemSpacing
                  && spacing(at: twoLocation) == AparteTypography.paragraphSpacing
                  && spacing(at: afterLocation) == spacing(at: 0),
                  "gap-after-list-equals-paragraph-gap")
            let reloaded = ParagraphFormatting.editorText(from: listed)
            check(reloaded.string == listed.string
                  && spacing(at: twoLocation) == (reloaded.attribute(.paragraphStyle, at: twoLocation, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing,
                  "live-spacing-matches-reload")

            editor.replaceAll(with: NSAttributedString(string: "- foo", attributes: AparteTypography.baseAttributes))
            let handTyped = editor.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            check(handTyped?.paragraphSpacing == AparteTypography.paragraphSpacing && (handTyped?.headIndent ?? 0) > 0,
                  "hand-typed-marker-is-a-list-item")

            editor.replaceAll(with: NSAttributedString(string: "Best,", attributes: AparteTypography.baseAttributes))
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.insertLineBreak(nil)
            editor.insertText("Ada", replacementRange: editor.selectedRange())
            check(editor.string.contains("\u{2028}") && document.markdown == "Best,  \nAda", "shift-return-inserts-soft-break")

            let longMarkdown = (1...120)
                .map { "Paragraph \($0): enough text to exercise the native scroll view." }
                .joined(separator: "\n\n")
            pad.setMarkdownForRuntimeCheck(longMarkdown)
            drainRunLoop(for: 0.1)
            check(pad.runtimeSnapshot().editorCanScroll, "long-document-is-scrollable")
            let snapshotSelection = editor.selectedRange()
            let snapshotScroll = editor.enclosingScrollView?.contentView.bounds.origin
            let snapshotMarkdown = document.markdown
            let snapshotBoard = NSPasteboard.withUniqueName()
            defer { snapshotBoard.releaseGlobally() }
            pad.snapshotForRuntimeCheck(to: snapshotBoard)
            let visibleTextHeight = editor.enclosingScrollView?.contentView.bounds.height ?? 0
            if let png = snapshotBoard.data(forType: .png),
               let rep = NSBitmapImageRep(data: png) {
                check(CGFloat(rep.pixelsHigh) > visibleTextHeight, "snapshot-includes-scrolled-text")
            } else {
                failed.append("snapshot-includes-scrolled-text")
            }
            check(footerButtons.last?.title == "Copied" && document.markdown == snapshotMarkdown
                  && editor.selectedRange() == snapshotSelection
                  && editor.enclosingScrollView?.contentView.bounds.origin == snapshotScroll,
                  "snapshot-leaves-document-selection-and-scroll")
            check(pad.scrollToEndForRuntimeCheck(), "long-document-scrolls-to-end")
            pad.zoomIn()
            drainRunLoop(for: 0.05)
            check(pad.scrollToEndForRuntimeCheck(), "zoomed-document-scrolls-to-end")
            pad.resetZoom()

            let selectionBeforeOptions = editor.selectedRange()
            let textBeforeOptions = editor.string
            let countsBeforeOptions = pad.showsCounts
            pad.presentOptions(MenuBarController.makeOptionsMenu(target: optionsTarget))
            if let overlay = pad.optionsOverlayForRuntimeCheck {
                check(overlay.window === editor.window && overlay.bounds.contains(overlay.card.frame), "options-card-stays-inside-pad")
                check(!overlay.card.hasAmbiguousLayout, "options-card-layout-is-unambiguous")
                check(overlay.hasUsableContentLayoutForRuntimeCheck, "options-content-has-visible-width")
                check(overlay.shortcutsClearScrollbarForRuntimeCheck, "shortcut-hints-reserve-scrollbar-space")
                overlay.toggleGroupForRuntimeCheck("Formatting")
                check(overlay.expandedGroupsForRuntimeCheck == ["Formatting"], "opening-formatting-closes-text-size")
                overlay.toggleGroupForRuntimeCheck("Editing")
                check(overlay.expandedGroupsForRuntimeCheck == ["Editing"], "opening-editing-closes-formatting")
                check(overlay.shortcutsClearScrollbarForRuntimeCheck, "expanded-shortcuts-clear-scrollbar")
                overlay.toggleGroupForRuntimeCheck("Editing")
                check(overlay.expandedGroupsForRuntimeCheck.isEmpty, "expanded-group-can-close")
                overlay.toggleGroupForRuntimeCheck("Text size")
                check(!pad.runtimeSnapshot().formattingBarIsVisible, "options-hide-formatting-bar")
                var focusStaysInCard = true
                for _ in 0..<14 {
                    pad.simulateKeyForRuntimeCheck(keyCode: 48, characters: "\t")
                    focusStaysInCard = focusStaysInCard && (editor.window?.firstResponder as? NSView)?.isDescendant(of: overlay) == true
                }
                check(focusStaysInCard, "options-keyboard-focus-stays-in-card")
                let disabled = overlay.actionButtons.first { $0.title == "Restore last cleared text" }
                check(disabled?.isEnabled == false, "options-validate-disabled-actions")
                disabled?.performClick(nil)
                check(pad.isOptionsMenuOpen, "disabled-option-keeps-card-open")
                let countButton = overlay.actionButtons.first { $0.title == "Show word and character count" }
                countButton?.performClick(nil)
                check(!pad.isOptionsMenuOpen && pad.isVisible && pad.showsCounts != countsBeforeOptions,
                      "choosing-option-closes-card-and-runs-action")
                check(optionsTarget.actionCount == 1 && optionsTarget.actionRanAfterDismissal, "option-runs-once-after-dismissal")
            } else { failed.append("options-card-created") }
            pad.toggleCounts()
            pad.presentOptions(MenuBarController.makeOptionsMenu(target: optionsTarget))
            if let overlay = pad.optionsOverlayForRuntimeCheck,
               let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 8, y: 8),
                                             modifierFlags: [], timestamp: 0, windowNumber: editor.window!.windowNumber,
                                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                let hit = overlay.hitTest(NSPoint(x: 8, y: 8))
                check(hit === overlay, "outside-click-is-intercepted-before-editor")
                hit?.mouseDown(with: event)
                check(!pad.isOptionsMenuOpen && pad.isVisible, "outside-click-closes-only-card")
            }
            pad.presentOptions(MenuBarController.makeOptionsMenu(target: optionsTarget))
            pad.simulateEscapeForRuntimeCheck()
            check(!pad.isOptionsMenuOpen && pad.isVisible && !escapeDismissed, "escape-closes-only-options-card")
            check(editor.selectedRange() == selectionBeforeOptions && editor.string == textBeforeOptions && pad.runtimeSnapshot().editorOwnsFocus,
                  "options-preserve-draft-selection-and-restore-focus")
            check(editor.window?.contentView?.accessibilityChildren()?.contains { ($0 as? NSView) === editor.enclosingScrollView } == true,
                  "closing-options-restores-editor-accessibility")
            pad.presentOptions(MenuBarController.makeOptionsMenu(target: optionsTarget))
            pad.hide()
            pad.show()
            check(!pad.isOptionsMenuOpen, "hiding-pad-clears-options-card")

            let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                                 styleMask: .titled, backing: .buffered, defer: false)
            sheet.isReleasedWhenClosed = false
            pad.window.beginSheet(sheet)
            drainRunLoop(for: 0.05)
            pad.hide()
            drainRunLoop(for: 0.1)
            check(pad.window.attachedSheet == nil, "hide-ends-attached-sheet")
            sheet.close()
            pad.show()
            pad.window.makeFirstResponder(editor)

            func leaves(_ menu: NSMenu) -> [NSMenuItem] {
                menu.items.flatMap { item in
                    if let submenu = item.submenu { return leaves(submenu) }
                    return item.isSeparatorItem ? [] : [item]
                }
            }
            let commandItems = leaves(MenuBarController.makeOptionsMenu(target: optionsTarget))
            check(commandItems.filter { item in !MenuCommand.updates.contains { $0.action == item.action } }
                .allSatisfy { !MenuCommand.shortcutLabel(for: $0).isEmpty }, "every-writing-action-has-shortcut-hint")
            let localItems = commandItems.filter { !$0.keyEquivalent.isEmpty }
            let bindings = localItems.map { "\($0.keyEquivalentModifierMask.rawValue):\($0.keyEquivalent)" }
            check(Set(bindings).count == bindings.count, "writing-shortcuts-have-no-duplicates")
            let mainItems = leaves(MainMenu.make(target: optionsTarget))
            let applicationMenu = MainMenu.make(target: optionsTarget)
            check(!applicationMenu.items.contains { $0.submenu?.title == "Settings" }, "settings-has-no-top-level-menu")
            let applicationSettings = applicationMenu.items.first?.submenu?.items.filter { $0.action == #selector(AppDelegate.showSettings) } ?? []
            check(applicationSettings.count == 1, "settings-is-in-aparte-application-menu")
            for menu in [applicationMenu, MenuBarController.makeOptionsMenu(target: optionsTarget),
                         MenuBarController.makeOptionsMenu(target: optionsTarget, forPad: false)] {
                let items = leaves(menu)
                let settingsItems = items.filter { $0.action == #selector(AppDelegate.showSettings) }
                check(settingsItems.count == 1 && settingsItems[0].title == "Settings…"
                      && settingsItems[0].keyEquivalent == "," && settingsItems[0].keyEquivalentModifierMask == [.command],
                      "settings-one-standard-command-per-menu")
                check(!items.contains { $0.title.hasPrefix("Keyboard shortcut") || $0.title.hasPrefix("Launch at login") },
                      "settings-menus-omit-scattered-preference-actions")
            }
            #if APARTE_DIRECT_UPDATES
            let updaterDelegate = AppDelegate()
            let updaterProbe = AcceptanceUpdater()
            updaterDelegate.updateController = updaterProbe
            for menu in [MainMenu.make(target: updaterDelegate), MenuBarController.makeOptionsMenu(target: updaterDelegate),
                         MenuBarController.makeOptionsMenu(target: updaterDelegate, forPad: false)] {
                let updateItems = leaves(menu).filter { $0.action == #selector(AppDelegate.checkForUpdates) }
                check(updateItems.count == 1 && updateItems[0].title == "Check for Updates…", "direct-menu-has-update-command")
                if let item = updateItems.first {
                    updaterProbe.canCheckForUpdates = false
                    check(!updaterDelegate.validateMenuItem(item), "update-command-disabled-while-unavailable")
                    updaterDelegate.checkForUpdates()
                    check(updaterProbe.checks == 0, "disabled-update-command-does-not-check")
                    updaterProbe.canCheckForUpdates = true
                    check(updaterDelegate.validateMenuItem(item), "update-command-enabled-when-available")
                }
            }
            settings.updateController = updaterProbe
            settings.onCheckForUpdates = { updaterDelegate.checkForUpdates() }
            updaterProbe.canCheckForUpdates = false
            settings.showSettings()
            check(settings.updateButton?.isEnabled == false, "settings-update-disabled-when-unavailable")
            updaterProbe.canCheckForUpdates = true
            settings.showSettings()
            check(settings.updateButton?.isEnabled == true && settings.updateButton?.title == "Check for Updates…",
                  "settings-direct-update-button-is-available")
            settings.updateButton?.performClick(nil)
            check(updaterProbe.checks == 1, "settings-update-button-dispatches-once")
            updaterProbe.canCheckForUpdates = false
            settings.updateButton?.performClick(nil)
            check(updaterProbe.checks == 1, "settings-update-button-revalidates-before-dispatch")
            updaterProbe.canCheckForUpdates = true
            updaterProbe.checks = 0
            settings.closeSettings()
            updaterDelegate.checkForUpdates()
            check(updaterProbe.checks == 1, "update-command-dispatches-once-without-network-in-acceptance")
            #else
            func buttonTitles(_ view: NSView) -> [String] {
                (view as? NSButton).map { [$0.title] } ?? view.subviews.flatMap(buttonTitles)
            }
            check(!buttonTitles(settings.window!.contentView!).contains("Check for Updates…"), "settings-non-direct-omits-updater")
            check(MenuCommand.updates.isEmpty && !mainItems.contains { $0.title == "Check for Updates…" }
                  && !commandItems.contains { $0.title == "Check for Updates…" }, "non-direct-menus-omit-updater")
            #endif
            check(localItems.allSatisfy { option in mainItems.contains { $0.action == option.action && $0.keyEquivalent == option.keyEquivalent && $0.keyEquivalentModifierMask == option.keyEquivalentModifierMask } },
                  "displayed-shortcuts-match-main-menu-bindings")

            let probe = AcceptanceShortcutProbe()
            let probeMenu = NSMenu()
            probeMenu.autoenablesItems = false
            for item in localItems {
                let binding = NSMenuItem(title: item.title, action: #selector(AcceptanceShortcutProbe.record(_:)), keyEquivalent: item.keyEquivalent)
                binding.keyEquivalentModifierMask = item.keyEquivalentModifierMask
                binding.target = probe
                probeMenu.addItem(binding)
            }
            let commandMenu = NSApp.mainMenu
            NSApp.mainMenu = probeMenu
            for item in localItems {
                let event = shortcutEvent(item.keyEquivalent, modifiers: item.keyEquivalentModifierMask, window: editor.window!)
                probe.lastTitle = nil
                check(probeMenu.performKeyEquivalent(with: event) && probe.lastTitle == item.title,
                      "native-shortcut-dispatch-\(item.title)")
            }
            NSApp.mainMenu = commandMenu
            probeMenu.removeAllItems()

            pad.show()
            check(focusEditorForShortcutChecks(editor), "shortcut-checks-start-with-editor-focus")
            pad.setMarkdownForRuntimeCheck("Keyboard checks")
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            let headingEvent = shortcutEvent("1", modifiers: [.command, .option], window: editor.window!)
            check(NSApp.mainMenu?.performKeyEquivalent(with: headingEvent) == true && document.markdown.hasPrefix("# "), "heading-shortcut-applies-formatting")
            pad.setMarkdownForRuntimeCheck("Keyboard checks")
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            let countsBeforeKey = pad.showsCounts
            let countsEvent = shortcutEvent("w", modifiers: [.command, .shift], window: editor.window!)
            check(NSApp.mainMenu?.performKeyEquivalent(with: countsEvent) == true && pad.showsCounts != countsBeforeKey, "count-shortcut-works-with-card-closed")
            pad.presentOptions(MenuBarController.makeOptionsMenu(target: optionsTarget))
            check(pad.performOptionsKeyEquivalent(countsEvent) && !pad.isOptionsMenuOpen && pad.showsCounts == countsBeforeKey,
                  "count-shortcut-closes-card-and-applies-once")
            pad.presentOptions(MenuBarController.makeOptionsMenu(target: optionsTarget))
            let boldEvent = shortcutEvent("b", modifiers: [.command], window: editor.window!)
            check(pad.performOptionsKeyEquivalent(boldEvent) && !pad.isOptionsMenuOpen && document.markdown.contains("**"),
                  "formatting-shortcut-works-from-collapsed-group")
            pad.presentOptions(MenuBarController.makeOptionsMenu(target: optionsTarget))
            let closeEvent = shortcutEvent("/", modifiers: [.command], window: editor.window!)
            check(pad.performOptionsKeyEquivalent(closeEvent) && !pad.isOptionsMenuOpen && pad.isVisible, "options-shortcut-closes-without-reopening")
            let linkEvent = shortcutEvent("k", modifiers: [.command], window: editor.window!)
            check(NSApp.mainMenu?.performKeyEquivalent(with: linkEvent) == true && pad.linkIsVisibleForRuntimeCheck,
                  "link-shortcut-opens-link-editor")
            check(pad.dismissTransientUI() && !pad.linkIsVisibleForRuntimeCheck && pad.isVisible,
                  "link-cancel-keeps-pad-open")
            let clearEvent = shortcutEvent("\u{7f}", modifiers: [.command, .option], window: editor.window!)
            check(NSApp.mainMenu?.performKeyEquivalent(with: clearEvent) == true && editor.string.isEmpty && pad.hasRecovery,
                  "clear-shortcut-creates-recovery")
            optionsTarget.allowRecovery = true
            let restoreEvent = shortcutEvent("r", modifiers: [.command, .shift], window: editor.window!)
            check(NSApp.mainMenu?.performKeyEquivalent(with: restoreEvent) == true && editor.string == "Keyboard checks", "restore-shortcut-recovers-cleared-text")
            optionsTarget.allowRecovery = false

            if ProcessInfo.processInfo.arguments.contains("--preview-writing-tools") {
                pad.setMarkdownForRuntimeCheck("# A little space to write\n\nWrite, copy, and carry on. Your words stay on this Mac.\n\n- A draft for tomorrow\n- A thought worth keeping")
                editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                pad.toggleCounts()
                pad.zoomIn()
                editor.scrollToBeginningOfDocument(nil)
                if ProcessInfo.processInfo.arguments.contains("--preview-compact") {
                    editor.window?.setContentSize(NSSize(width: 1_032, height: 600))
                }
                runInteractivePreview(for: 120)
            }

            if ProcessInfo.processInfo.arguments.contains("--preview-shortcut") || ProcessInfo.processInfo.arguments.contains("--preview-settings") {
                pad.hide()
                overlays.hide()
                let previewHotKey = HotKeyController(action: {}, defaults: defaults)
                let recorder = PreferencesController(hotKeyController: previewHotKey, launchAtLoginService: loginService)
                recorder.showSettings()
                runInteractivePreview(for: 45)
                print("Recorder choice: \(previewHotKey.shortcutDescription)")
                recorder.closeSettings()
                previewHotKey.invalidate()
            }

            pad.simulateEscapeForRuntimeCheck()
            drainRunLoop(for: 0.2)
            check(escapeDismissed && !pad.runtimeSnapshot().isVisible, "escape-dismisses")
            check(overlays.runtimeWindowCount == 0, "escape-removes-overlays")

            var reliable = true
            for _ in 0..<20 {
                overlays.show()
                pad.show()
                pad.hide()
                overlays.hide()
                reliable = reliable && !pad.runtimeSnapshot().isVisible && overlays.runtimeWindowCount == 0
            }
            drainRunLoop(for: 0.3)
            check(reliable, "twenty-show-hide-cycles")
            if ProcessInfo.processInfo.arguments.contains("--measure-idle") {
                print("APARTE_IDLE_READY")
                fflush(stdout)
                drainRunLoop(for: 45)
            }
        } catch {
            failed.append("unexpected-error:\(String(describing: error))")
        }

        let report: [String: Any] = [
            "passed": passed,
            "failed": failed,
            "manualStillRequired": [
                "global Option-Space invocation from another app",
                "visual quality on each connected display",
                "light and dark appearance review",
                "real rich paste through the UI",
                "Desktop save and file comparison through the system panel",
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let output = String(data: data, encoding: .utf8) {
            print(output)
        }
        return failed.isEmpty ? 0 : 1
    }

    private static func runInteractivePreview(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let event = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
                NSApp.updateWindows()
            }
        }
    }

    /// On-screen width of the text column. Magnification scales document points.
    private static func textColumnWidth(_ editor: NSTextView) -> CGFloat {
        let zoom = editor.enclosingScrollView?.magnification ?? 1
        let container = editor.textContainer?.containerSize.width ?? 0
        return container * zoom
    }

    private static func focusEditorForShortcutChecks(_ editor: NSTextView) -> Bool {
        guard let window = editor.window else { return false }
        let deadline = Date().addingTimeInterval(2)
        repeat {
            // This harness runs outside NSApplication.run(). Rapid hide/show and
            // menu replacement can leave activation events queued. Process them
            // before checking the native responder chain, and reacquire focus if
            // a deferred deactivation overtook the previous activation request.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(editor)
            runInteractivePreview(for: 0.05)
            if NSApp.isActive && NSApp.keyWindow === window && window.firstResponder === editor {
                return true
            }
        } while Date() < deadline
        return false
    }

    private static func shortcutEvent(_ key: String, modifiers: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        let codes: [String: Int] = ["a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "h": kVK_ANSI_H,
                                  "i": kVK_ANSI_I, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "q": kVK_ANSI_Q,
                                  "r": kVK_ANSI_R, "s": kVK_ANSI_S, "u": kVK_ANSI_U, "v": kVK_ANSI_V,
                                  "w": kVK_ANSI_W, "x": kVK_ANSI_X, "z": kVK_ANSI_Z, "1": kVK_ANSI_1,
                                  "7": kVK_ANSI_7, "8": kVK_ANSI_8, "&": kVK_ANSI_7, "*": kVK_ANSI_8, "0": kVK_ANSI_0, "+": kVK_ANSI_Equal,
                                  "-": kVK_ANSI_Minus, "/": kVK_ANSI_Slash, ",": kVK_ANSI_Comma, "\u{7f}": kVK_Delete]
        let shifted: [String: String] = ["7": "&", "8": "*"]
        let characters = modifiers.contains(.shift) ? shifted[key] ?? key.uppercased() : key
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, characters: characters,
                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(codes[key.lowercased()] ?? 0))!
    }

    private static func drainRunLoop(for seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

#if APARTE_DIRECT_UPDATES
@MainActor
private final class AcceptanceUpdater: UpdateChecking {
    var canCheckForUpdates = false
    var checks = 0
    func checkForUpdates() { checks += 1 }
}
#endif

@MainActor
private final class AcceptanceOptionsTarget: NSObject, NSMenuItemValidation {
    weak var pad: PadWindowController?
    var actionCount = 0
    var actionRanAfterDismissal = false
    var allowRecovery = false

    @objc func toggleCounts() {
        actionCount += 1
        actionRanAfterDismissal = pad?.isOptionsMenuOpen == false
        pad?.toggleCounts()
    }
    @objc func zoomIn() { pad?.zoomIn() }
    @objc func zoomOut() { pad?.zoomOut() }
    @objc func resetZoom() { pad?.resetZoom() }
    @objc func copyPlainText() { pad?.copyPlainText() }
    @objc func copyMarkdown() { pad?.copyMarkdown() }
    @objc func copyAll() { }
    @objc func clearPad() { pad?.clearPad() }
    @objc func toggleOptions() { pad?.toggleOptions() }
    @objc func showSettings() { }
    @objc func showAbout() { }
    @objc func hidePad() { pad?.hide() }
    @objc func togglePad() { }
    @objc func saveMarkdownAs() { }
    @objc func restoreLastCleared() { if allowRecovery { pad?.restoreLastCleared() } }
    @objc func discardRecovery() { }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleCounts) { menuItem.state = pad?.showsCounts == true ? .on : .off }
        if menuItem.action == #selector(restoreLastCleared) { return allowRecovery }
        return menuItem.action != #selector(discardRecovery)
    }
}

@MainActor
private final class AcceptanceShortcutProbe: NSObject {
    var lastTitle: String?
    @objc func record(_ sender: NSMenuItem) { lastTitle = sender.title }
}

private final class AcceptanceLoginService: PreferencesController.LaunchAtLoginService {
    var status: SMAppService.Status = .notRegistered
    var registrationNeedsApproval = false
    var shouldFail = false
    var registerCalls = 0
    var unregisterCalls = 0

    func register() throws {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        registerCalls += 1
        status = registrationNeedsApproval ? .requiresApproval : .enabled
    }

    func unregister() throws {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        unregisterCalls += 1
        status = .notRegistered
    }
}
