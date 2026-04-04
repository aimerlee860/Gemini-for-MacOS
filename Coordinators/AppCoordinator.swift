//
//  AppCoordinator.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit
import WebKit

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}

class AppCoordinator: ObservableObject {

    @Published var webViewModel = WebViewModel()

    var canGoBack: Bool { webViewModel.canGoBack }
    var canGoForward: Bool { webViewModel.canGoForward }

    init() {}

    // MARK: - Navigation

    func goBack() { webViewModel.goBack() }
    func goForward() { webViewModel.goForward() }
    func goHome() { webViewModel.loadHome() }
    func reload() { webViewModel.reload() }
    func openNewChat() { webViewModel.openNewChat() }

    func openMainWindow() {
        let mainWindow = findMainWindow()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func findMainWindow() -> NSWindow? {
        NSApp.windows.first {
            $0.title == Constants.mainWindowTitle
        }
    }
}

extension AppCoordinator {
    struct Constants {
        static let mainWindowTitle = "Gemini"
    }
}
