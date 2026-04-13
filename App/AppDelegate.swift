//
//  AppDelegate.swift
//  GeminiDesktop
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowControllers: [WindowController] = []
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[GeminiDesktop] applicationDidFinishLaunching called")

        setupMenu()

        // Create first window
        createNewWindow()

        // Observe open main window notification
        NotificationCenter.default.addObserver(
            forName: .openMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if windowControllers.isEmpty {
            createNewWindow()
        } else {
            // Restore all minimized windows instead of just one
            for controller in windowControllers {
                controller.window.deminiaturize(nil)
            }
            // Activate the app
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    // MARK: - Dock Menu

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dockMenu = NSMenu()

        // List all windows with their titles first
        // Use window index instead of window reference to avoid retaining released windows
        for (index, controller) in windowControllers.enumerated() {
            let title = controller.window.title
            let item = dockMenu.addItem(
                withTitle: title,
                action: #selector(selectWindow(_:)),
                keyEquivalent: ""
            )
            // Store index as representedObject instead of window reference
            item.tag = index
        }

        // New Window option at the bottom
        if windowControllers.count > 0 {
            dockMenu.addItem(NSMenuItem.separator())
        }
        dockMenu.addItem(withTitle: "New Window", action: #selector(createNewWindow), keyEquivalent: "")

        return dockMenu
    }

    @objc private func selectWindow(_ sender: NSMenuItem) {
        // Find window by index stored in tag
        let index = sender.tag
        guard index >= 0 && index < windowControllers.count else { return }
        let window = windowControllers[index].window
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu

    private func setupMenu() {
        let mainMenu = NSMenu()

        // App menu ("Gemini")
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Gemini")
        appMenu.addItem(withTitle: "About Gemini", action: #selector(showAboutPanel), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "New Window", action: #selector(createNewWindow), keyEquivalent: "n")
        appMenu.addItem(NSMenuItem.separator())
        // Language submenu inside Gemini menu
        let langMenuItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu(title: "Language")
        for language in AppLanguage.allCases {
            let item = langMenu.addItem(
                withTitle: language.displayName,
                action: #selector(switchLanguage(_:)),
                keyEquivalent: ""
            )
            item.representedObject = language.rawValue
            if language == AppLanguage.current {
                item.state = .on
            }
        }
        langMenuItem.submenu = langMenu
        appMenu.addItem(langMenuItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Gemini", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func switchLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else { return }

        AppLanguage.current = language

        // Update menu item check marks
        if let langMenu = sender.menu {
            for item in langMenu.items {
                item.state = (item.representedObject as? String == rawValue) ? .on : .off
            }
        }

        // Reload all windows with new language
        for controller in windowControllers {
            controller.webViewModel.loadHome()
        }
    }

    @objc private func showAboutPanel() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Gemini",
            .applicationVersion: "Version \(version)"
        ])
    }

    // MARK: - Windows

    func applicationWillTerminate(_ notification: Notification) {
        for controller in windowControllers {
            controller.cleanup()
        }
        windowControllers.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    @objc func createNewWindow() {
        let windowNumber = windowControllers.count + 1
        let controller = WindowController(windowNumber: windowNumber)
        controller.window.delegate = self
        windowControllers.append(controller)
        NSLog("[GeminiDesktop] Window created, total windows: \(windowControllers.count)")
    }

    private func closeWindow(_ window: NSWindow) {
        // Find the controller for this window
        guard let index = windowControllers.firstIndex(where: { $0.window === window }) else {
            // Not a Gemini window, let system handle it
            window.close()
            return
        }

        let controller = windowControllers[index]
        controller.cleanup()
        windowControllers.remove(at: index)

        if windowControllers.isEmpty {
            // Last window closed, quit app
            NSApp.terminate(nil)
        }
    }

    func openMainWindow() {
        if windowControllers.isEmpty {
            createNewWindow()
        } else {
            // Restore all minimized windows
            for controller in windowControllers {
                controller.window.deminiaturize(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Use first window's coordinator for settings
        guard let coordinator = windowControllers.first?.coordinator else { return }
        let settingsView = SettingsView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minSize = NSSize(width: 1250, height: 750)
        return NSSize(
            width: max(frameSize.width, minSize.width),
            height: max(frameSize.height, minSize.height)
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
        } else {
            // Find controller immediately before window is released
            guard let index = windowControllers.firstIndex(where: { $0.window === window }) else { return }
            let controller = windowControllers[index]
            // Schedule cleanup using weak reference to controller
            DispatchQueue.main.async { [weak self, weak controller] in
                guard let self = self, let controller = controller else { return }
                // Verify controller is still in our list
                guard let currentIndex = self.windowControllers.firstIndex(where: { $0 === controller }) else { return }
                controller.cleanup()
                self.windowControllers.remove(at: currentIndex)
                if self.windowControllers.isEmpty {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === settingsWindow {
            return true
        }
        // Allow Gemini windows to close, cleanup will be handled in windowWillClose
        return true
    }
}