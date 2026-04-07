//
//  AppDelegate.swift
//  GeminiDesktop
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator = AppCoordinator()
    var mainWindow: NSWindow?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[GeminiDesktop] applicationDidFinishLaunching called")

        setupMenu()

        // Main window
        let mainWindowView = MainWindowView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: mainWindowView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppCoordinator.Constants.mainWindowTitle
        window.backgroundColor = .white
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.contentView = hostingView
        window.minSize = NSSize(width: 1280, height: 800)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MainWindow")
        NSLog("[GeminiDesktop] Window created, frame: \(window.frame)")
        window.makeKeyAndOrderFront(nil)
        NSLog("[GeminiDesktop] Window visible: \(window.isVisible)")
        mainWindow = window

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
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        return true
    }

    // MARK: - Menu

    private func setupMenu() {
        let mainMenu = NSMenu()

        // App menu ("Gemini")
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Gemini")
        appMenu.addItem(withTitle: "About Gemini", action: #selector(showAboutPanel), keyEquivalent: "")
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
        appMenu.addItem(NSMenuItem.separator())
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

        // Reload page with new language URL
        coordinator.webViewModel.loadHome()
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
        coordinator.webViewModel.cleanup()
        NotificationCenter.default.removeObserver(self)
    }

    func openMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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

// MARK: - NSWindowDelegate for settings

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
        if window == settingsWindow {
            settingsWindow = nil
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == mainWindow {
            NSApp.terminate(nil)
            return false
        }
        return true
    }
}
