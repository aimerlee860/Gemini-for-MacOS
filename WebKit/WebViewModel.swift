//
//  WebViewModel.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-15.
//

import WebKit
import Combine

/// Handles console.log messages from JavaScript
class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? String {
            print("[WebView] \(body)")
        }
    }
}

/// Observable wrapper around WKWebView with Gemini-specific functionality
class WebViewModel: ObservableObject {

    // MARK: - Constants

    static let geminiURL = URL(string: "https://www.google.com/search?udm=50")!

    private static let geminiHost = "www.google.com"
    private static let geminiAppPath = "/search"
    private static let userAgent: String = UserAgent.safari

    // MARK: - Public Properties

    let wkWebView: WKWebView
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false
    @Published private(set) var isAtHome: Bool = true
    @Published private(set) var isLoading: Bool = true

    // MARK: - Private Properties

    private var backObserver: NSKeyValueObservation?
    private var forwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private let consoleLogHandler = ConsoleLogHandler()

    // MARK: - Initialization

    init() {
        self.wkWebView = Self.createWebView(consoleLogHandler: consoleLogHandler)
        setupObservers()
        loadHome()
    }

    // MARK: - Navigation

    func loadHome() {
        isAtHome = true
        canGoBack = false
        wkWebView.load(URLRequest(url: Self.geminiURL))
    }

    func goBack() {
        isAtHome = false
        wkWebView.goBack()
    }

    func goForward() {
        wkWebView.goForward()
    }

    func reload() {
        wkWebView.reload()
    }

    func openNewChat() {
        let script = """
        (function() {
            const event = new KeyboardEvent('keydown', {
                key: 'O',
                code: 'KeyO',
                keyCode: 79,
                which: 79,
                shiftKey: true,
                metaKey: true,
                bubbles: true,
                cancelable: true,
                composed: true
            });
            document.activeElement.dispatchEvent(event);
            document.dispatchEvent(event);
        })();
        """
        wkWebView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - Private Setup

    private static func createWebView(consoleLogHandler: ConsoleLogHandler) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Add user scripts
        for script in UserScripts.createAllScripts() {
            configuration.userContentController.addUserScript(script)
        }

        // Register console log message handler (debug only)
        #if DEBUG
        configuration.userContentController.add(consoleLogHandler, name: UserScripts.consoleLogHandler)
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.customUserAgent = userAgent
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .white
        }

        return webView
    }

    private func setupObservers() {
        backObserver = wkWebView.observe(\.canGoBack, options: [.new, .initial]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.canGoBack = !self.isAtHome && webView.canGoBack
        }

        forwardObserver = wkWebView.observe(\.canGoForward, options: [.new, .initial]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.canGoForward = webView.canGoForward
        }

        loadingObserver = wkWebView.observe(\.isLoading, options: [.new, .initial]) { [weak self] webView, _ in
            self?.isLoading = webView.isLoading
        }

        urlObserver = wkWebView.observe(\.url, options: .new) { [weak self] webView, _ in
            guard let self = self else { return }
            guard let currentURL = webView.url else { return }

            let isGeminiApp = currentURL.host == Self.geminiHost &&
                              currentURL.path.hasPrefix(Self.geminiAppPath)

            if isGeminiApp {
                self.isAtHome = true
                self.canGoBack = false
            } else {
                self.isAtHome = false
                self.canGoBack = webView.canGoBack
            }
        }
    }
}
