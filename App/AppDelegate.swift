//
//  AppDelegate.swift
//  GeminiDesktop
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator = AppCoordinator()
    var mainWindow: NSWindow!
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[GeminiDesktop] applicationDidFinishLaunching called")

        setupMenu()

        // Main window
        let mainWindowView = MainWindowView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: mainWindowView)
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.title = AppCoordinator.Constants.mainWindowTitle
        // mainWindow.titlebarAppearsTransparent = true
        mainWindow.styleMask.insert(.fullSizeContentView)
        mainWindow.titleVisibility = .hidden
        if #available(macOS 11.0, *) {
            mainWindow.titlebarSeparatorStyle = .none
        }
        mainWindow.contentView = hostingView
        mainWindow.minSize = NSSize(width: 1250, height: 750)
        mainWindow.delegate = self
        mainWindow.center()
        mainWindow.setFrameAutosaveName("MainWindow")
        NSLog("[GeminiDesktop] Window created, frame: \(mainWindow.frame)")

        mainWindow.makeKeyAndOrderFront(nil)
        NSLog("[GeminiDesktop] Window visible: \(mainWindow.isVisible)")

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
        appMenu.addItem(withTitle: "Quit Gemini", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func showAboutPanel() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Gemini",
            .applicationVersion: "Version \(version)"
        ])
    }

    // MARK: - Windows

    func openMainWindow() {
        mainWindow.makeKeyAndOrderFront(nil)
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
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
        }
    }
}
