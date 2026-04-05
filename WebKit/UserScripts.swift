//
//  UserScripts.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-15.
//

import WebKit

/// Collection of user scripts injected into WKWebView
enum UserScripts {

    /// Message handler name for console log bridging
    static let consoleLogHandler = "consoleLog"

    /// Creates all user scripts to be injected into the WebView
    static func createAllScripts() -> [WKUserScript] {
        var scripts: [WKUserScript] = [
            createIMEFixScript(),
            createTooltipFixScript()
        ]

        #if DEBUG
        scripts.insert(createConsoleLogBridgeScript(), at: 0)
        #endif

        return scripts
    }

    /// Creates a script that bridges console.log to native Swift
    private static func createConsoleLogBridgeScript() -> WKUserScript {
        WKUserScript(
            source: consoleLogBridgeSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    /// Creates the IME fix script that resolves the double-enter issue
    /// when using input method editors (e.g., Chinese, Japanese, Korean input)
    private static func createIMEFixScript() -> WKUserScript {
        WKUserScript(
            source: imeFixSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    /// Creates a script that fixes tooltip positioning issues in WebKit
    /// Google's tooltips use `offset-distance` and positioning that may not work correctly in older WebKit
    private static func createTooltipFixScript() -> WKUserScript {
        WKUserScript(
            source: tooltipFixSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    // MARK: - Script Sources

    /// JavaScript to bridge console.log to native Swift via WKScriptMessageHandler
    private static let consoleLogBridgeSource = """
    (function() {
        const originalLog = console.log;
        console.log = function(...args) {
            originalLog.apply(console, args);
            try {
                const message = args.map(arg => {
                    if (typeof arg === 'object') {
                        return JSON.stringify(arg, null, 2);
                    }
                    return String(arg);
                }).join(' ');
                window.webkit.messageHandlers.\(consoleLogHandler).postMessage(message);
            } catch (e) {}
        };
    })();
    """

    /// JavaScript to fix IME Enter issue on Gemini
    /// When using IME (e.g., Chinese/Japanese input), pressing Enter to confirm
    /// the IME composition should NOT send the message. This script intercepts
    /// Enter keydown events during and immediately after IME composition,
    /// preventing them from reaching Gemini's send handler.
    private static let imeFixSource = """
    (function() {
        'use strict';

        let imeActive = false;
        let imeEverUsed = false;
        let compositionEndTime = 0;
        const BUFFER_TIME = 300;

        function isInIMEWindow() {
            return imeActive || (Date.now() - compositionEndTime < BUFFER_TIME);
        }

        document.addEventListener('compositionstart', function() {
            imeActive = true;
            imeEverUsed = true;
        }, true);

        document.addEventListener('compositionend', function() {
            imeActive = false;
            compositionEndTime = Date.now();
        }, true);

        document.addEventListener('keydown', function(e) {
            if (!imeEverUsed) return;
            if (e.key !== 'Enter' || e.shiftKey || e.ctrlKey || e.altKey) return;

            if (isInIMEWindow() || e.isComposing || e.keyCode === 229) {
                e.stopImmediatePropagation();
                e.preventDefault();
            }
        }, true);

        document.addEventListener('beforeinput', function(e) {
            if (!imeEverUsed) return;
            if (e.inputType !== 'insertParagraph' && e.inputType !== 'insertLineBreak') return;

            if (isInIMEWindow()) {
                e.stopImmediatePropagation();
                e.preventDefault();
            }
        }, true);
    })();
    """

    /// CSS to fix tooltip positioning issues in WebKit
    /// - `offset-distance` may not be supported, causing tooltips to render at wrong positions
    /// - WebKit may calculate `position: absolute` differently within `inline-flex` containers
    /// - `transform-origin` defaults may differ between engines
    private static let tooltipFixSource = """
    (function() {
        const style = document.createElement('style');
        style.textContent = `
            .LGKDTe {
                offset-distance: unset !important;
                top: 50% !important;
                left: 100% !important;
                transform: translateY(-50%) translateX(8px) scale(1) !important;
                transform-origin: left center !important;
            }
            .LGKDTe.BQmez {
                transform: translateY(-50%) translateX(8px) scale(0.8) !important;
                opacity: 0 !important;
            }
            .LGKDTe.ko8QQ {
                transform: translateY(-50%) translateX(8px) scale(1) !important;
                opacity: 1 !important;
            }
            .LcPLZc {
                top: 50% !important;
                left: 0 !important;
                transform: translateY(-50%) translateX(-4px) !important;
            }
            .ITIRGe {
                caret-color: auto !important;
            }
            .CEpIFc {
                display: none !important;
            }
        `;
        document.head.appendChild(style);
    })();
    """

}
