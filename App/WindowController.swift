//
//  WindowController.swift
//  GeminiDesktop
//
//  Created by alexcding on 2026-04-13.
//

import AppKit
import SwiftUI

/// Manages a single Gemini window with its own WebViewModel and Coordinator
class WindowController {
    let window: NSWindow
    let coordinator: AppCoordinator
    let webViewModel: WebViewModel

    private var titleObserver: NSObjectProtocol?

    init(windowNumber: Int = 1) {
        // Create independent WebViewModel
        self.webViewModel = WebViewModel()

        // Create independent Coordinator
        self.coordinator = AppCoordinator(webViewModel: webViewModel)

        // Create window
        let mainWindowView = MainWindowView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: mainWindowView)

        // Window size: minimum size (1250x750) - this is content size
        let contentSize = NSSize(width: 1250, height: 750)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Set unique title for this window
        window.title = windowNumber > 1 ? "Gemini \(windowNumber)" : "Gemini"
        window.backgroundColor = .white
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.contentView = hostingView
        window.minSize = contentSize

        // Force content size after all style settings
        window.setContentSize(contentSize)

        // Get screen visible frame for centering
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowFrame = window.frame

        // Calculate centered position
        let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2

        // Apply offset for subsequent windows
        var finalX = x
        var finalY = y
        if windowNumber > 1 {
            let offset: CGFloat = CGFloat(windowNumber - 1) * 30
            finalX += offset
            finalY -= offset
        }

        // Set window position only (size already set via setContentSize)
        window.setFrameOrigin(NSPoint(x: finalX, y: finalY))

        window.makeKeyAndOrderFront(nil)

        self.window = window

        // Observe title changes from WebViewModel
        setupTitleObserver()
    }

    private func setupTitleObserver() {
        titleObserver = NotificationCenter.default.addObserver(
            forName: .windowTitleDidChange,
            object: webViewModel,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let title = notification.userInfo?["title"] as? String else { return }
            self.window.title = title
        }
    }

    deinit {
        if let observer = titleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func cleanup() {
        webViewModel.cleanup()
    }

    func makeKey() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}