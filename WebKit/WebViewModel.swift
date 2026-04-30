//
//  WebViewModel.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-15.
//

import WebKit
import Combine
import Network

private final class FocusFriendlyWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Handles console.log messages from JavaScript
class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? String {
            print("[WebView] \(body)")
        }
    }
}

/// Handles title updates from JavaScript
class TitleHandler: NSObject, WKScriptMessageHandler {
    weak var webViewModel: WebViewModel?
    private var lastTitle: String = ""

    override init() {
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let title = message.body as? String,
              title != lastTitle,
              let webViewModel = webViewModel else { return }
        lastTitle = title
        NotificationCenter.default.post(
            name: .windowTitleDidChange,
            object: webViewModel,
            userInfo: ["title": title]
        )
    }
}

/// Observable wrapper around WKWebView with Gemini-specific functionality
class WebViewModel: ObservableObject {

    // MARK: - Constants

    private static let geminiBaseURL = "https://www.google.com/search?udm=50"
    private static let geminiHost = "www.google.com"
    private static let geminiAppPath = "/search"
    private static let userAgent: String = UserAgent.safari

    // MARK: - Public Properties

    let wkWebView: WKWebView
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false
    @Published private(set) var isAtHome: Bool = true
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var networkError: (message: String, isRetryable: Bool)?

    // MARK: - Private Properties (Error Recovery)

    private var retryCount: Int = 0
    private var retryTimer: Timer?
    private static let maxRetryCount = 3
    private static let retryDelay: TimeInterval = 2.0

    // MARK: - Private Properties

    private var backObserver: NSKeyValueObservation?
    private var forwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?
    private let consoleLogHandler = ConsoleLogHandler()
    private var titleHandler: TitleHandler?
    private var isCleanedUp = false

    // MARK: - Private Properties (Network Monitoring)

    private enum NetInterface {
        case wifi, wiredEthernet, cellular, other, loopback
    }

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.gemini.network-monitor")
    private var lastPathInterfaces: Set<NetInterface> = []
    private var pathChangeWorkItem: DispatchWorkItem?
    private static let pathChangeDebounce: TimeInterval = 1.0

    // MARK: - Initialization

    init() {
        let handler = TitleHandler()
        self.titleHandler = handler
        self.wkWebView = Self.createWebView(consoleLogHandler: consoleLogHandler, titleHandler: handler)
        handler.webViewModel = self
        setupObservers()
        setupNetworkMonitor()
        loadHome()
    }

    deinit {
        cleanup()
    }

    // MARK: - Language

    static func geminiURL(for language: AppLanguage) -> URL {
        let urlString: String
        switch language {
        case .chinese:
            urlString = geminiBaseURL + "&hl=zh-CN"
        case .english:
            urlString = geminiBaseURL
        }
        return URL(string: urlString)!
    }

    // MARK: - Navigation

    func loadHome() {
        isAtHome = true
        canGoBack = false
        let url = Self.geminiURL(for: AppLanguage.current)
        wkWebView.load(URLRequest(url: url))
    }

    func goBack() {
        wkWebView.goBack()
    }

    func goForward() {
        wkWebView.goForward()
    }

    private func resetRetryState() {
        retryCount = 0
        retryTimer?.invalidate()
        retryTimer = nil
        networkError = nil
    }

    func reload() {
        resetRetryState()
        wkWebView.reload()
    }

    func retryAfterError() {
        resetRetryState()
        clearCacheAndReload()
    }

    func handleNetworkError(_ error: Error, isRetryable: Bool) {
        let message: String
        let nsError = error as NSError

        switch nsError.code {
        case NSURLErrorTimedOut:
            message = "连接超时，请检查网络"
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            message = "网络连接已断开"
        case NSURLErrorDNSLookupFailed, NSURLErrorCannotFindHost:
            message = "DNS 解析失败，请检查网络或 VPN 设置"
        case NSURLErrorCannotConnectToHost:
            message = "无法连接到服务器"
        default:
            message = "网络错误：\(error.localizedDescription)"
        }

        if isRetryable && retryCount < Self.maxRetryCount {
            retryCount += 1
            retryTimer?.invalidate()
            retryTimer = nil
            retryTimer = Timer.scheduledTimer(withTimeInterval: Self.retryDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.clearCacheAndReload()
            }
        } else {
            networkError = (message: message, isRetryable: isRetryable)
        }
    }

    private func clearCache(completion: @escaping () -> Void) {
        let dataTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
        ]
        WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: Date().addingTimeInterval(-60), completionHandler: completion)
    }

    private func clearCacheAndReload() {
        clearCache { [weak self] in
            self?.wkWebView.reload()
        }
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

    private static func createWebView(consoleLogHandler: ConsoleLogHandler, titleHandler: TitleHandler) -> WKWebView {
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

        // Register title update handler
        configuration.userContentController.add(titleHandler, name: UserScripts.titleUpdateHandler)

        let webView = FocusFriendlyWebView(frame: .zero, configuration: configuration)
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
            guard let self = self else { return }
            self.isLoading = webView.isLoading
            if !webView.isLoading && self.networkError != nil {
                self.networkError = nil
                self.retryCount = 0
            }
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

    // MARK: - Network Monitoring

    private func setupNetworkMonitor() {
        let initialPath = pathMonitor.currentPath
        lastPathInterfaces = currentInterfaces(from: initialPath)

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self, !self.isCleanedUp else { return }

            let newInterfaces = self.currentInterfaces(from: path)
            let routeChanged = newInterfaces != self.lastPathInterfaces
            let becameReachable = path.status == .satisfied

            self.lastPathInterfaces = newInterfaces

            if routeChanged && becameReachable {
                DispatchQueue.main.async {
                    self.scheduleNetworkPathChange()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func currentInterfaces(from path: NWPath) -> Set<NetInterface> {
        var interfaces: Set<NetInterface> = []
        if path.usesInterfaceType(.wifi) { interfaces.insert(.wifi) }
        if path.usesInterfaceType(.wiredEthernet) { interfaces.insert(.wiredEthernet) }
        if path.usesInterfaceType(.cellular) { interfaces.insert(.cellular) }
        if path.usesInterfaceType(.other) { interfaces.insert(.other) }
        if path.usesInterfaceType(.loopback) { interfaces.insert(.loopback) }
        return interfaces
    }

    private func scheduleNetworkPathChange() {
        pathChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.handleNetworkPathChange()
        }
        pathChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pathChangeDebounce, execute: workItem)
    }

    private func handleNetworkPathChange() {
        guard !wkWebView.isLoading else { return }
        resetRetryState()
        wkWebView.reload()
    }

    // MARK: - Cleanup

    func cleanup() {
        guard !isCleanedUp else { return }
        isCleanedUp = true

        retryTimer?.invalidate()
        retryTimer = nil

        pathChangeWorkItem?.cancel()
        pathChangeWorkItem = nil

        pathMonitor.cancel()

        // Notify JS to clean up timers and DOM elements
        wkWebView.evaluateJavaScript("if(window._geminiCursorCleanup)window._geminiCursorCleanup();", completionHandler: nil)

        // Stop all media rendering pipelines
        wkWebView.pauseAllMediaPlayback()
        // Stop loading and abort network requests
        wkWebView.stopLoading()
        // Clear page content to release GPU/decoder resources
        wkWebView.loadHTMLString("", baseURL: nil)
        // Remove navigation and UI delegates to prevent callbacks to deallocated objects
        wkWebView.navigationDelegate = nil
        wkWebView.uiDelegate = nil

        // Remove console log handler to prevent WKUserContentController strong reference
        #if DEBUG
        wkWebView.configuration.userContentController.removeScriptMessageHandler(forName: UserScripts.consoleLogHandler)
        #endif

        // Remove title handler
        wkWebView.configuration.userContentController.removeScriptMessageHandler(forName: UserScripts.titleUpdateHandler)
        titleHandler = nil

        // Clean up KVO observers — each step runs independently to avoid skipping on exception
        backObserver?.invalidate(); backObserver = nil
        forwardObserver?.invalidate(); forwardObserver = nil
        urlObserver?.invalidate(); urlObserver = nil
        loadingObserver?.invalidate(); loadingObserver = nil
    }
}
