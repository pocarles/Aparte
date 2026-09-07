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

            defaults.set(-1, forKey: "Aparte.globalShortcut.keyCode")
            defaults.set(-1, forKey: "Aparte.globalShortcut.modifiers")
            let hotKey = HotKeyController(action: {}, defaults: defaults)
            defer { hotKey.invalidate() }
            check(hotKey.currentShortcut == HotKeyController.defaultShortcut, "invalid-saved-shortcut-does-not-crash")
            let candidate = HotKeyController.Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
            if case .success = hotKey.updateShortcut(candidate) {
                check(hotKey.activeShortcut == candidate, "shortcut-registers-new-choice")
                check(defaults.integer(forKey: "Aparte.globalShortcut.keyCode") == Int(candidate.keyCode), "shortcut-choice-persists")
                let invalid = HotKeyController.Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: 0)
                if case .failure = hotKey.updateShortcut(invalid) {
                    check(hotKey.activeShortcut == candidate, "invalid-shortcut-preserves-active-choice")
                } else { failed.append("invalid-shortcut-preserves-active-choice") }
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
            check(initial.level == .popUpMenu, "panel-above-overlays")
            check(overlays.runtimeWindowCount == NSScreen.screens.count, "overlay-per-screen")
            check(overlays.runtimeWindowsArePassive, "overlays-passive-no-blur-window")

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
            editor.copyPlainText(to: clipboard)
            check(clipboard.string(forType: .string) == "world" && clipboard.data(forType: .rtf) == nil, "copy-plain-selection-without-formatting")
            editor.copyAllPreservingSelection(to: clipboard)
            check(clipboard.string(forType: .string) == editor.string && clipboard.data(forType: .rtf) != nil, "copy-all-rich-and-plain")
            check(editor.selectedRange() == NSRange(location: 6, length: 5), "copy-all-preserves-selection")
            editor.setSelectedRange(NSRange(location: 3, length: 0))
            editor.copyPlainText(to: clipboard)
            check(clipboard.string(forType: .string) == editor.string && editor.selectedRange().location == 3, "copy-plain-whole-pad-preserves-cursor")

            let beforeZoom = document.markdown
            let beforeFonts = editor.attributedString()
            pad.zoomIn()
            drainRunLoop(for: 0.05)
            check(abs(pad.zoomForRuntimeCheck - 1.1) < 0.01, "zoom-in-changes-display")
            if let clip = editor.enclosingScrollView?.contentView {
                check(editor.frame.width <= clip.bounds.width + 1, "zoom-reflows-without-horizontal-clipping")
            }
            check(document.markdown == beforeZoom && editor.attributedString().isEqual(to: beforeFonts), "zoom-preserves-document-and-copy-formatting")
            pad.zoomOut()
            check(abs(pad.zoomForRuntimeCheck - 1) < 0.01, "zoom-out")
            pad.zoomIn()
            pad.resetZoom()
            check(pad.zoomForRuntimeCheck == 1, "zoom-reset")
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

            let longMarkdown = (1...120)
                .map { "Paragraph \($0): enough text to exercise the native scroll view." }
                .joined(separator: "\n\n")
            pad.setMarkdownForRuntimeCheck(longMarkdown)
            drainRunLoop(for: 0.1)
            check(pad.runtimeSnapshot().editorCanScroll, "long-document-is-scrollable")
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

            func leaves(_ menu: NSMenu) -> [NSMenuItem] {
                menu.items.flatMap { item in
                    if let submenu = item.submenu { return leaves(submenu) }
                    return item.isSeparatorItem ? [] : [item]
                }
            }
            let commandItems = leaves(MenuBarController.makeOptionsMenu(target: optionsTarget))
            check(commandItems.allSatisfy { !MenuCommand.shortcutLabel(for: $0).isEmpty }, "every-menu-action-has-shortcut-hint")
            let localItems = commandItems.filter { !$0.keyEquivalent.isEmpty }
            let bindings = localItems.map { "\($0.keyEquivalentModifierMask.rawValue):\($0.keyEquivalent)" }
            check(Set(bindings).count == bindings.count, "writing-shortcuts-have-no-duplicates")
            let mainItems = leaves(MainMenu.make(target: optionsTarget))
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
            NSApp.activate(ignoringOtherApps: true)
            let activationDeadline = Date().addingTimeInterval(2)
            while !pad.runtimeSnapshot().isKey && Date() < activationDeadline {
                runInteractivePreview(for: 0.05)
            }
            check(pad.runtimeSnapshot().isKey && pad.runtimeSnapshot().editorOwnsFocus, "shortcut-checks-start-with-editor-focus")
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

            if ProcessInfo.processInfo.arguments.contains("--preview-shortcut") {
                pad.hide()
                overlays.hide()
                let previewHotKey = HotKeyController(action: {}, defaults: defaults)
                let recorder = PreferencesController(hotKeyController: previewHotKey, launchAtLoginService: loginService)
                recorder.showShortcutRecorder()
                runInteractivePreview(for: 45)
                print("Recorder choice: \(previewHotKey.shortcutDescription)")
                recorder.closeShortcutRecorder()
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
    @objc func configureShortcut() { }
    @objc func toggleLaunchAtLogin() { }
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
