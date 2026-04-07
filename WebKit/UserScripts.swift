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
            createTooltipFixScript(),
            createCursorFixScript()
        ]

        if AppLanguage.current == .chinese {
            scripts.append(createLanguageHintScript())
        }

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

    /// Creates a script that repositions Google's custom caret (.CEpIFc) on cursor movement.
    /// Google's custom caret has a color-changing animation but doesn't update position on arrow keys in WebKit.
    /// This script uses a mirror div to measure cursor position and repositions the caret element.
    private static func createCursorFixScript() -> WKUserScript {
        WKUserScript(
            source: cursorFixSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    /// Creates a script that prepends a language hint to user messages
    /// to ensure Gemini always responds in Chinese
    private static func createLanguageHintScript() -> WKUserScript {
        WKUserScript(
            source: languageHintSource,
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
                caret-color: transparent !important;
            }
            .CEpIFc {
                display: none !important;
            }
        `;
        document.head.appendChild(style);
    })();
    """

    /// JavaScript to render a custom blue caret for the textarea.
    /// Hides the native thin caret and Google's broken custom caret,
    /// draws our own 2px blue bar that tracks cursor position.
    private static let cursorFixSource = """
    (function() {
        'use strict';

        var caretEl = null;
        var lastFocused = null;
        var rafPending = false;

        function ensureCaret() {
            if (caretEl) return;
            caretEl = document.createElement('div');
            caretEl.style.cssText =
                'position:fixed;width:2px;background:#4285f4;' +
                'pointer-events:none;z-index:10000;display:none;border-radius:1px';

            caretEl.style.background = '#4285f4';

            var style = document.createElement('style');
            style.textContent = '@keyframes _gc_blink{0%,100%{opacity:1}50%{opacity:0}}';
            document.head.appendChild(style);
            caretEl.style.animation = '_gc_blink 1.06s step-end infinite';

            var colors = ['#4285f4', '#ea4335', '#fbbc04', '#34a853'];
            var colorIdx = 0;
            setInterval(function() {
                colorIdx = (colorIdx + 1) % colors.length;
                if (caretEl) caretEl.style.background = colors[colorIdx];
            }, 1060);

            document.body.appendChild(caretEl);
        }

        function measureCursor(textarea) {
            var cs = getComputedStyle(textarea);
            var mirror = document.createElement('div');

            mirror.style.cssText =
                'position:absolute;visibility:hidden;white-space:pre-wrap;' +
                'word-wrap:break-word;overflow:hidden;' +
                'width:' + textarea.clientWidth + 'px;' +
                'font:' + cs.font + ';' +
                'line-height:' + cs.lineHeight + ';' +
                'letter-spacing:' + cs.letterSpacing + ';' +
                'padding-top:' + cs.paddingTop + ';' +
                'padding-right:' + cs.paddingRight + ';' +
                'padding-bottom:' + cs.paddingBottom + ';' +
                'padding-left:' + cs.paddingLeft + ';' +
                'border-top:' + cs.borderTop + ';' +
                'border-right:' + cs.borderRight + ';' +
                'border-bottom:' + cs.borderBottom + ';' +
                'border-left:' + cs.borderLeft + ';' +
                'box-sizing:' + cs.boxSizing;

            var pos = textarea.selectionStart;
            var text = textarea.value;
            mirror.textContent = text.substring(0, pos);

            var marker = document.createElement('span');
            marker.textContent = '\\u200b';
            mirror.appendChild(marker);
            mirror.appendChild(document.createTextNode(text.substring(pos)));

            document.body.appendChild(mirror);
            var mRect = mirror.getBoundingClientRect();
            var kRect = marker.getBoundingClientRect();
            document.body.removeChild(mirror);

            return {
                x: kRect.left - mRect.left - textarea.scrollLeft,
                y: kRect.top - mRect.top - textarea.scrollTop,
                h: kRect.height || parseFloat(cs.lineHeight) || 20
            };
        }

        function updateCaret() {
            if (!lastFocused || !caretEl) return;
            var rect = lastFocused.getBoundingClientRect();
            var c = measureCursor(lastFocused);
            caretEl.style.left = (rect.left + c.x) + 'px';
            caretEl.style.top = (rect.top + c.y) + 'px';
            caretEl.style.height = c.h + 'px';
            caretEl.style.display = 'block';
        }

        function scheduleUpdate() {
            if (rafPending) return;
            rafPending = true;
            requestAnimationFrame(function() {
                rafPending = false;
                updateCaret();
            });
        }

        function hideCaret() {
            if (caretEl) caretEl.style.display = 'none';
            lastFocused = null;
        }

        document.addEventListener('focus', function(e) {
            if (e.target && e.target.classList && e.target.classList.contains('ITIRGe')) {
                lastFocused = e.target;
                ensureCaret();
                scheduleUpdate();
            }
        }, true);

        document.addEventListener('blur', function(e) {
            if (e.target === lastFocused) hideCaret();
        }, true);

        document.addEventListener('selectionchange', function() {
            if (lastFocused) scheduleUpdate();
        });

        document.addEventListener('scroll', function(e) {
            if (e.target === lastFocused) scheduleUpdate();
        }, true);
    })();
    """

    /// Language hint prefix prepended to every user message
    private static let languageHintPrefix = "请始终使用中文回复。"

    /// JavaScript to prepend a language hint to user messages in the Gemini web interface.
    /// Intercepts the Enter key (outside IME composition) and modifies the textarea content
    /// to include a language instruction before the message is sent.
    private static let languageHintSource = """
    (function() {
        'use strict';

        var LANG_PREFIX = '\(languageHintPrefix)';

        function isTextarea(el) {
            return el && el.classList && el.classList.contains('ITIRGe');
        }

        function prependLanguageHint(textarea) {
            var text = textarea.value.trim();
            if (!text) return;
            if (text.indexOf(LANG_PREFIX) === 0) return;

            var newValue = LANG_PREFIX + '\\n' + text;

            // Use nativeInputValueSetter to bypass React's controlled input
            var nativeSet = Object.getOwnPropertyDescriptor(
                window.HTMLTextAreaElement.prototype, 'value'
            ).set;
            nativeSet.call(textarea, newValue);

            // Dispatch events so React/web framework picks up the change
            textarea.dispatchEvent(new Event('input', { bubbles: true }));
            textarea.dispatchEvent(new Event('change', { bubbles: true }));
        }

        // Track IME state to avoid interfering with IME composition
        var imeActive = false;
        document.addEventListener('compositionstart', function() { imeActive = true; }, true);
        document.addEventListener('compositionend', function() { imeActive = false; }, true);

        // Intercept Enter key to prepend language hint before send
        document.addEventListener('keydown', function(e) {
            if (e.key !== 'Enter') return;
            if (e.shiftKey || e.ctrlKey || e.altKey || e.metaKey) return;
            if (imeActive || e.isComposing || e.keyCode === 229) return;

            var textarea = e.target;
            if (!isTextarea(textarea)) return;

            // Delay to let IME fix script process first, then modify content
            var captured = textarea;
            setTimeout(function() {
                if (captured.value.trim()) {
                    prependLanguageHint(captured);
                }
            }, 10);
        }, true);
    })();
    """

}
