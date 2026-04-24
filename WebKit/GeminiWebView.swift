//
//  GeminiWebView.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import WebKit

struct GeminiWebView: NSViewRepresentable {
    let webView: WKWebView
    @ObservedObject var webViewModel: WebViewModel

    func makeNSView(context: Context) -> WebViewContainer {
        let container = WebViewContainer(webView: webView, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: WebViewContainer, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(webViewModel: webViewModel)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]
        weak var webViewModel: WebViewModel?

        init(webViewModel: WebViewModel) {
            self.webViewModel = webViewModel
            super.init()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleNavigationError(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleNavigationError(error)
        }

        private func handleNavigationError(_ error: Error) {
            let nsError = error as NSError
            guard nsError.domain == NSURLErrorDomain, nsError.code != NSURLErrorCancelled else { return }

            let isRetryable: Bool = [
                NSURLErrorTimedOut,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorDNSLookupFailed,
                NSURLErrorCannotFindHost,
                NSURLErrorResourceUnavailable,
            ].contains(nsError.code)

            webViewModel?.handleNetworkError(error, isRetryable: isRetryable)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if isExternalURL(url) {
                    NSWorkspace.shared.open(url)
                } else {
                    webView.load(URLRequest(url: url))
                }
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            var destination = downloadsURL.appendingPathComponent(suggestedFilename)

            // Handle duplicate filenames
            var counter = 1
            let fileManager = FileManager.default
            let nameWithoutExtension = destination.deletingPathExtension().lastPathComponent
            let fileExtension = destination.pathExtension

            while fileManager.fileExists(atPath: destination.path) {
                let newName = fileExtension.isEmpty
                    ? "\(nameWithoutExtension) (\(counter))"
                    : "\(nameWithoutExtension) (\(counter)).\(fileExtension)"
                destination = downloadsURL.appendingPathComponent(newName)
                counter += 1
            }

            downloadDestinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            let key = ObjectIdentifier(download)
            guard let destination = downloadDestinations.removeValue(forKey: key) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
            let alert = NSAlert()
            alert.messageText = "Download Failed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = NSAlert()
            alert.messageText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: GeminiWebView.Constants.textFieldWidth, height: GeminiWebView.Constants.textFieldHeight))
            textField.stringValue = defaultText ?? ""
            alert.accessoryView = textField

            completionHandler(alert.runModal() == .alertFirstButtonReturn ? textField.stringValue : nil)
        }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host.contains(GeminiWebView.Constants.trustedHost) ? .grant : .prompt)
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.canChooseFiles = true
            // Activate the app so the file dialog receives focus,
            // especially when triggered from the non-activating floating panel
            NSApp.activate(ignoringOtherApps: true)
            panel.begin { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }

        private static let internalHosts: Set<String> = ["www.google.com", "gemini.google.com", "accounts.google.com"]
        private static let internalSuffixes = [".googleapis.com", ".gstatic.com"]

        private func isExternalURL(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }

            if Self.internalHosts.contains(host) { return false }
            for suffix in Self.internalSuffixes {
                if host.hasSuffix(suffix) { return false }
            }
            return true
        }
    }
}

class WebViewContainer: NSView {
    let webView: WKWebView
    let coordinator: GeminiWebView.Coordinator
    private var windowObserver: NSObjectProtocol?
    private let titlebarDragView = TitlebarDragView()

    init(webView: WKWebView, coordinator: GeminiWebView.Coordinator) {
        self.webView = webView
        self.coordinator = coordinator
        super.init(frame: .zero)
        autoresizesSubviews = true
        setupWindowObserver()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupWindowObserver() {
        // Observe when ANY window becomes key - then check if we should have the webView
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let keyWindow = notification.object as? NSWindow,
                  self.window === keyWindow else { return }
            // Our window became key, attach webView
            self.attachWebView()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && window?.isKeyWindow == true {
            attachWebView()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let char = event.charactersIgnoringModifiers?.lowercased()
            let selector: Selector?
            switch char {
            case "v": selector = NSSelectorFromString("paste:")
            case "c": selector = NSSelectorFromString("copy:")
            case "x": selector = NSSelectorFromString("cut:")
            case "a": selector = NSSelectorFromString("selectAll:")
            default: selector = nil
            }
            if let selector = selector, webView.responds(to: selector) {
                webView.perform(selector, with: nil)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func layout() {
        super.layout()
        if webView.superview === self {
            webView.frame = bounds
        }
        let titlebarHeight: CGFloat = 28
        titlebarDragView.frame = NSRect(
            x: 0,
            y: bounds.height - titlebarHeight,
            width: bounds.width,
            height: titlebarHeight
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let titlebarHeight: CGFloat = 28
        if point.y >= bounds.height - titlebarHeight {
            return titlebarDragView
        }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func attachWebView() {
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        addSubview(webView)
        // 确保 titlebarDragView 在最上层
        titlebarDragView.removeFromSuperview()
        addSubview(titlebarDragView)
    }
}

private final class TitlebarDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }

        // 双击标题栏：最大化/还原
        if event.clickCount == 2 {
            window.zoom(nil)
            return
        }

        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin

        var shouldStop = false
        while !shouldStop {
            guard let dragEvent = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: Date.distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }

            switch dragEvent.type {
            case .leftMouseDragged:
                let current = NSEvent.mouseLocation
                window.setFrameOrigin(NSPoint(
                    x: startOrigin.x + current.x - startMouse.x,
                    y: startOrigin.y + current.y - startMouse.y
                ))
            case .leftMouseUp:
                shouldStop = true
            default:
                break
            }
        }
    }
}


extension GeminiWebView {

    struct Constants {
        static let textFieldWidth: CGFloat = 200
        static let textFieldHeight: CGFloat = 24
        static let trustedHost = "google.com"
    }

}
