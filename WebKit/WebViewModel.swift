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

    override init() {
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let title = message.body as? String,
              let webViewModel = webViewModel else { return }
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

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.gemini.network-monitor")
    private var lastPathInterfaces: Set<String> = []

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
        isAtHome = false
        wkWebView.goBack()
    }

    func goForward() {
        wkWebView.goForward()
    }

    func reload() {
        retryCount = 0
        retryTimer?.invalidate()
        retryTimer = nil
        networkError = nil
        wkWebView.reload()
    }

    func retryAfterError() {
        retryCount = 0
        retryTimer?.invalidate()
        retryTimer = nil
        networkError = nil
        clearWebsiteData {
            self.wkWebView.reload()
        }
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
            retryTimer = Timer.scheduledTimer(withTimeInterval: Self.retryDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.clearWebsiteData {
                    self.wkWebView.reload()
                }
            }
        } else {
            networkError = (message: message, isRetryable: isRetryable)
        }
    }

    private func clearWebsiteData(completion: @escaping () -> Void) {
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: Date().addingTimeInterval(-300), completionHandler: completion)
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

            // 检测路由变化：接口集合发生变化（VPN 开关、网卡切换等）
            let routeChanged = newInterfaces != self.lastPathInterfaces

            // 检测网络恢复：从断开变为可用
            let becameReachable = path.status == .satisfied

            self.lastPathInterfaces = newInterfaces

            if routeChanged && becameReachable {
                DispatchQueue.main.async {
                    self.handleNetworkPathChange()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func currentInterfaces(from path: NWPath) -> Set<String> {
        var interfaces: Set<String> = []
        if path.usesInterfaceType(.wifi) { interfaces.insert("wifi") }
        if path.usesInterfaceType(.wiredEthernet) { interfaces.insert("ethernet") }
        if path.usesInterfaceType(.cellular) { interfaces.insert("cellular") }
        if path.usesInterfaceType(.other) { interfaces.insert("other") }
        // TUN/VPN 虚拟网卡通常归为 other 或 loopback
        if path.usesInterfaceType(.loopback) { interfaces.insert("loopback") }
        return interfaces
    }

    private func handleNetworkPathChange() {
        guard !wkWebView.isLoading else { return }
        retryCount = 0
        networkError = nil
        clearWebsiteData { [weak self] in
            self?.wkWebView.reload()
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        guard !isCleanedUp else { return }
        isCleanedUp = true

        retryTimer?.invalidate()
        retryTimer = nil

        pathMonitor.cancel()

        // 通知 JS 清理定时器和 DOM 元素
        wkWebView.evaluateJavaScript("if(window._geminiCursorCleanup)window._geminiCursorCleanup();", completionHandler: nil)

        // 停止所有媒体渲染管线
        wkWebView.pauseAllMediaPlayback()
        // 停止所有加载，中断网络请求
        wkWebView.stopLoading()
        // 清空页面内容，释放 GPU/解码资源
        wkWebView.loadHTMLString("", baseURL: nil)
        // 移除导航和 UI 代理，防止回调到已释放的对象
        wkWebView.navigationDelegate = nil
        wkWebView.uiDelegate = nil

        // 移除 console log handler（防止 WKUserContentController 强持有）
        #if DEBUG
        wkWebView.configuration.userContentController.removeScriptMessageHandler(forName: UserScripts.consoleLogHandler)
        #endif

        // 移除 title handler
        wkWebView.configuration.userContentController.removeScriptMessageHandler(forName: UserScripts.titleUpdateHandler)
        titleHandler = nil

        // 清理 KVO observers — 每步独立执行，避免中途异常跳过后续步骤
        backObserver?.invalidate(); backObserver = nil
        forwardObserver?.invalidate(); forwardObserver = nil
        urlObserver?.invalidate(); urlObserver = nil
        loadingObserver?.invalidate(); loadingObserver = nil
    }
}
