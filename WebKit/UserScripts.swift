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

    /// Message handler name for title sync
    static let titleUpdateHandler = "titleUpdate"

    /// Creates all user scripts to be injected into the WebView
    static func createAllScripts() -> [WKUserScript] {
        var scripts: [WKUserScript] = [
            createIMEFixScript(),
            createTooltipFixScript(),
            createInputFocusAssistScript(),
            createCursorFixScript(),
            createCopyToastFixScript(),
            createUndoPasteScript(),
            createTitleSyncScript()
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

    /// Creates a script that helps AI Mode's animated input plate receive focus reliably.
    /// Google inserts click-catcher layers and full-screen overlays during transitions;
    /// on WebKit this can leave the textarea unfocused after the first click.
    private static func createInputFocusAssistScript() -> WKUserScript {
        WKUserScript(
            source: inputFocusAssistSource,
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

    /// Creates a script that fixes the broken copy toast notification
    /// Gemini shows a "Copied" toast when clicking the copy button on code blocks.
    /// In older WebKit, this toast renders as a large black area in the bottom-left corner.
    /// This script detects and removes these broken toast elements.
    private static func createCopyToastFixScript() -> WKUserScript {
        WKUserScript(
            source: copyToastFixSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    /// Creates a script that adds undo-paste functionality (Cmd+Z after paste).
    /// Saves textarea state before paste and restores it on Cmd+Z,
    /// allowing users to remove pasted text while keeping previously typed content.
    private static func createUndoPasteScript() -> WKUserScript {
        WKUserScript(
            source: undoPasteSource,
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

    /// Creates a script that monitors document title changes and sends updates to native code
    /// Used for showing conversation titles in Dock and window list
    private static func createTitleSyncScript() -> WKUserScript {
        WKUserScript(
            source: titleSyncSource,
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

    /// JavaScript to keep AI Mode's textarea focusable during input plate transitions.
    /// - Disables pointer interception on the full-screen transition veil (.umNuof)
    /// - When the user clicks the input plate or its proxy layer (.jUiaTd), explicitly focuses the textarea
    /// - Retries briefly because Gemini mutates classes/DOM during the expand animation
    private static let inputFocusAssistSource = """
    (function() {
        'use strict';

        var style = document.createElement('style');
        style.textContent = `
            .umNuof {
                pointer-events: none !important;
            }
        `;
        document.head.appendChild(style);

        function isTextarea(el) {
            return !!(el && el.classList && el.classList.contains('ITIRGe'));
        }

        function isFocusableTextarea(el) {
            return isTextarea(el) && !el.disabled && !el.hidden && el.offsetParent !== null;
        }

        function getTextareaFrom(node) {
            if (!node || !node.closest) return null;

            var container = node.closest('.AgWCw, .jUiaTd, .Txyg0d');
            if (!container) return null;

            return container.querySelector('textarea.ITIRGe');
        }

        function focusTextarea(textarea) {
            if (!isFocusableTextarea(textarea)) return false;

            try {
                textarea.focus({ preventScroll: true });
            } catch (e) {
                textarea.focus();
            }

            if (typeof textarea.selectionStart === 'number' &&
                typeof textarea.selectionEnd === 'number' &&
                textarea.selectionStart === 0 &&
                textarea.selectionEnd === 0 &&
                textarea.value.length > 0) {
                var end = textarea.value.length;
                textarea.setSelectionRange(end, end);
            }

            return document.activeElement === textarea;
        }

        function scheduleFocus(textarea) {
            if (!textarea) return;
            focusTextarea(textarea);

            requestAnimationFrame(function() {
                focusTextarea(textarea);
            });

            setTimeout(function() {
                focusTextarea(textarea);
            }, 80);

            setTimeout(function() {
                focusTextarea(textarea);
            }, 220);
        }

        document.addEventListener('mousedown', function(e) {
            var textarea = getTextareaFrom(e.target);
            if (!textarea || isTextarea(e.target)) return;
            scheduleFocus(textarea);
        }, true);

        document.addEventListener('click', function(e) {
            var textarea = getTextareaFrom(e.target);
            if (!textarea || isTextarea(e.target)) return;
            scheduleFocus(textarea);
        }, true);
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
        var needsFollowUp = false;
        var colorTimer = null;
        var sizeObserver = null;
        var styleObserver = null;
        var pollTimer = null;
        var cachedStyle = null;
        var cachedFor = null;

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
            colorTimer = setInterval(function() {
                colorIdx = (colorIdx + 1) % colors.length;
                if (caretEl) caretEl.style.background = colors[colorIdx];
            }, 1060);

            document.body.appendChild(caretEl);
        }

        // 暴露清理函数，供 native 端在 cleanup 时调用
        window._geminiCursorCleanup = function() {
            if (colorTimer) { clearInterval(colorTimer); colorTimer = null; }
            if (sizeObserver) { sizeObserver.disconnect(); sizeObserver = null; }
            if (styleObserver) { styleObserver.disconnect(); styleObserver = null; }
            if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
            if (caretEl) { caretEl.remove(); caretEl = null; }
            lastFocused = null;
        };

        function measureCursor(textarea) {
            var mirror = document.createElement('div');

            if (cachedFor !== textarea) {
                var cs = getComputedStyle(textarea);
                cachedStyle =
                    'position:absolute;visibility:hidden;white-space:pre-wrap;' +
                    'word-wrap:break-word;overflow:hidden;' +
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
                    'box-sizing:' + cs.boxSizing + ';' +
                    'word-break:' + cs.wordBreak + ';' +
                    'overflow-wrap:' + cs.overflowWrap + ';' +
                    'tab-size:' + cs.tabSize + ';' +
                    '-webkit-line-break:' + cs.webkitLineBreak;
                cachedFor = textarea;
            }

            mirror.style.cssText = cachedStyle + ';width:' + textarea.clientWidth + 'px';

            var lineHeight = parseFloat(mirror.style.lineHeight) || 20;

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
                h: kRect.height || lineHeight
            };
        }

        function updateCaret() {
            if (!lastFocused || !caretEl) return;
            var rect = lastFocused.getBoundingClientRect();
            var c = measureCursor(lastFocused);

            var maxX = Math.max(0, rect.width - 2);
            var maxY = Math.max(0, rect.height - c.h);
            var left = rect.left + Math.max(0, Math.min(c.x, maxX));
            var top = rect.top + Math.max(0, Math.min(c.y, maxY));

            caretEl.style.left = left + 'px';
            caretEl.style.top = top + 'px';
            caretEl.style.height = Math.min(c.h, Math.max(0, rect.height)) + 'px';
            caretEl.style.display = 'block';
        }

        function scheduleUpdate() {
            if (rafPending) {
                needsFollowUp = true;
                return;
            }
            rafPending = true;
            requestAnimationFrame(function() {
                rafPending = false;
                updateCaret();
                if (needsFollowUp) {
                    needsFollowUp = false;
                    scheduleUpdate();
                }
            });
        }

        function hideCaret() {
            if (caretEl) caretEl.style.display = 'none';
            if (sizeObserver) { sizeObserver.disconnect(); sizeObserver = null; }
            if (styleObserver) { styleObserver.disconnect(); styleObserver = null; }
            cachedStyle = null;
            cachedFor = null;
            lastFocused = null;
        }

        function observeTextareaSize(textarea) {
            if (sizeObserver) {
                sizeObserver.disconnect();
                sizeObserver = null;
            }
            if (styleObserver) {
                styleObserver.disconnect();
                styleObserver = null;
            }

            if (!textarea) return;

            if (typeof ResizeObserver === 'function') {
                sizeObserver = new ResizeObserver(function() {
                    if (lastFocused === textarea) scheduleUpdate();
                });
                sizeObserver.observe(textarea);
            }

            styleObserver = new MutationObserver(function() {
                if (lastFocused === textarea) scheduleUpdate();
            });
            styleObserver.observe(textarea, { attributes: true, attributeFilter: ['style', 'class'] });
        }

        document.addEventListener('focus', function(e) {
            if (e.target && e.target.classList && e.target.classList.contains('ITIRGe')) {
                lastFocused = e.target;
                ensureCaret();
                observeTextareaSize(e.target);
                scheduleUpdate();
                if (pollTimer) clearInterval(pollTimer);
                pollTimer = setInterval(function() {
                    if (!lastFocused || !caretEl || caretEl.style.display === 'none') return;
                    var r = lastFocused.getBoundingClientRect();
                    var cl = parseFloat(caretEl.style.left) || 0;
                    var ct = parseFloat(caretEl.style.top) || 0;
                    if (cl < r.left || cl > r.right || ct < r.top || ct > r.bottom) {
                        scheduleUpdate();
                    }
                }, 200);
            }
        }, true);

        document.addEventListener('blur', function(e) {
            if (e.target === lastFocused) {
                hideCaret();
                if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
            }
        }, true);

        document.addEventListener('selectionchange', function() {
            if (lastFocused) scheduleUpdate();
        });

        document.addEventListener('scroll', function(e) {
            if (e.target === lastFocused) scheduleUpdate();
        }, true);

        document.addEventListener('input', function(e) {
            if (e.target === lastFocused) {
                scheduleUpdate();
                setTimeout(function() { scheduleUpdate(); }, 100);
                setTimeout(function() { scheduleUpdate(); }, 400);
            }
        }, true);

        document.addEventListener('transitionend', function(e) {
            if (e.target === lastFocused) scheduleUpdate();
        }, true);

        window.addEventListener('resize', function() {
            if (lastFocused) scheduleUpdate();
        });
    })();
    """

    /// Language hint prefix prepended to every user message
    private static let languageHintPrefix = "请始终使用中文回复。"

    /// JavaScript to fix broken copy toast notifications in WebKit.
    /// Hides Google's native broken toast (renders as black area in old WebKit),
    /// and replaces the copy button icon with a checkmark on click.
    private static let copyToastFixSource = """
    (function() {
        'use strict';

        // 1. Hide broken Google toast overlays
        var style = document.createElement('style');
        style.textContent = `
            .FbxdMb, .Mh0NNb, .YkhnNb, .XN2Ckf, [role="status"][aria-live="polite"],
            .OIaSO, .uMiyFe, .HKhOze, .bM6rCd {
                display: none !important;
            }
            ._gc_copy_check {
                display: inline-flex;
                align-items: center;
                justify-content: center;
                width: 18px;
                height: 18px;
                font-size: 16px;
                line-height: 1;
                color: inherit;
            }
        `;
        document.head.appendChild(style);

        // 2. On copy button click, extract code and copy to clipboard
        document.addEventListener('click', function(e) {
            var btn = e.target.closest('button');
            if (!btn) return;

            var label = (btn.getAttribute('aria-label') || '').toLowerCase();
            if (label.indexOf('copy code') === -1) return;

            // Find the code block - walk up to find code-container, then find code/pre element
            var codeText = '';
            var container = btn.closest('[class*="code"], [class*="code-block"], pre, code');

            // Try multiple selectors to find the code content
            var codeEl = null;
            if (container) {
                codeEl = container.querySelector('code') || container.querySelector('pre') || container;
            }

            // If not found, try finding pre/code in siblings or parent's children
            if (!codeEl || !codeEl.textContent) {
                var parent = btn.parentElement;
                while (parent && !codeEl) {
                    codeEl = parent.querySelector('code') || parent.querySelector('pre');
                    if (codeEl && codeEl.textContent) break;
                    parent = parent.parentElement;
                }
            }

            if (codeEl) {
                codeText = codeEl.textContent || '';
            }

            // Copy to clipboard
            if (codeText) {
                navigator.clipboard.writeText(codeText).catch(function() {
                    // Fallback for older browsers
                    var ta = document.createElement('textarea');
                    ta.value = codeText;
                    ta.style.position = 'fixed';
                    ta.style.opacity = '0';
                    document.body.appendChild(ta);
                    ta.select();
                    document.execCommand('copy');
                    document.body.removeChild(ta);
                });
            }

            // Save original content
            var originalHTML = btn.innerHTML;

            // Replace with checkmark
            btn.innerHTML = '<span class="_gc_copy_check">\\u2713</span>';

            // Restore on mouseleave
            var restored = false;
            function restore() {
                if (restored) return;
                restored = true;
                btn.innerHTML = originalHTML;
                btn.removeEventListener('mouseleave', restore);
            }
            btn.addEventListener('mouseleave', restore);

            // Fallback: restore after 3s even if mouseleave didn't fire
            setTimeout(restore, 1000);
        }, true);

        // 3. MutationObserver to hide remaining broken toast elements
        var observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                mutation.addedNodes.forEach(function(node) {
                    if (node.nodeType !== Node.ELEMENT_NODE) return;
                    var el = node;
                    var cs = window.getComputedStyle(el);
                    if ((cs.position === 'fixed' || cs.position === 'absolute') &&
                        (cs.backgroundColor === 'rgb(0, 0, 0)' ||
                         cs.backgroundColor === 'rgba(0, 0, 0, 1)' ||
                         cs.backgroundColor === 'rgb(32, 33, 36)' ||
                         cs.backgroundColor === 'rgb(50, 50, 50)') &&
                        el.offsetHeight < 100) {
                        var rect = el.getBoundingClientRect();
                        if (rect.bottom > window.innerHeight * 0.7 && rect.height < 80) {
                            el.style.display = 'none';
                        }
                    }
                    var children = el.querySelectorAll ?
                        el.querySelectorAll('[role="status"], [aria-live]') : [];
                    children.forEach(function(child) {
                        child.style.display = 'none';
                    });
                });
            });
        });

        observer.observe(document.body || document.documentElement, {
            childList: true,
            subtree: true
        });
    })();
    """

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

    /// JavaScript to add undo-paste functionality.
    /// Intercepts paste via `beforeinput`, saves textarea state,
    /// and restores it on Cmd+Z. Invalidates if user types after paste.
    private static let undoPasteSource = """
    (function() {
        'use strict';

        var savedPaste = null;

        document.addEventListener('beforeinput', function(e) {
            if (e.inputType !== 'insertFromPaste') return;
            if (!e.target.classList || !e.target.classList.contains('ITIRGe')) return;

            savedPaste = {
                textarea: e.target,
                value: e.target.value,
                selectionStart: e.target.selectionStart,
                selectionEnd: e.target.selectionEnd
            };
        }, true);

        document.addEventListener('input', function(e) {
            if (savedPaste && savedPaste.textarea === e.target &&
                e.inputType !== 'insertFromPaste') {
                savedPaste = null;
            }
        }, true);

        document.addEventListener('keydown', function(e) {
            if (e.key !== 'z' || !e.metaKey || e.shiftKey || e.ctrlKey || e.altKey) return;
            if (!savedPaste) return;
            if (e.target !== savedPaste.textarea) return;

            e.preventDefault();
            e.stopImmediatePropagation();

            var textarea = e.target;
            var nativeSet = Object.getOwnPropertyDescriptor(
                window.HTMLTextAreaElement.prototype, 'value'
            ).set;
            nativeSet.call(textarea, savedPaste.value);
            textarea.setSelectionRange(savedPaste.selectionStart, savedPaste.selectionEnd);

            textarea.dispatchEvent(new Event('input', { bubbles: true }));

            savedPaste = null;
        }, true);
    })();
    """

    /// JavaScript to sync document title to native code for Dock/window list display
    private static let titleSyncSource = """
    (function() {
        'use strict';

        var MAX_TITLE_LENGTH = 10;

        function cleanTitle(rawTitle) {
            // Remove common suffixes
            var suffixes = [' - Google Search', ' - Google 搜索', ' - Google'];
            var cleaned = rawTitle;
            for (var i = 0; i < suffixes.length; i++) {
                if (cleaned.endsWith(suffixes[i])) {
                    cleaned = cleaned.slice(0, cleaned.length - suffixes[i].length);
                }
            }
            // Trim
            cleaned = cleaned.trim();
            // Truncate if too long
            if (cleaned.length > MAX_TITLE_LENGTH) {
                cleaned = cleaned.slice(0, MAX_TITLE_LENGTH) + '...';
            }
            // Fallback to 'Gemini' if empty
            return cleaned || 'Gemini';
        }

        function sendTitle() {
            var rawTitle = document.title || 'Gemini';
            var title = cleanTitle(rawTitle);
            try {
                window.webkit.messageHandlers.\(titleUpdateHandler).postMessage(title);
            } catch (e) {}
        }

        // Initial send
        if (document.readyState === 'complete') {
            sendTitle();
        } else {
            document.addEventListener('load', sendTitle);
        }

        // Poll for title changes (handles SPA navigation and history conversations)
        var lastTitle = document.title;
        setInterval(function() {
            var currentTitle = document.title;
            if (currentTitle !== lastTitle) {
                lastTitle = currentTitle;
                sendTitle();
            }
        }, 500);

        // Also observe title element changes
        var titleEl = document.querySelector('title');
        if (titleEl) {
            var observer = new MutationObserver(sendTitle);
            observer.observe(titleEl, { childList: true, characterData: true, subtree: true });
        }

        // Observe head for title element insertion
        var head = document.head || document.querySelector('head');
        if (head) {
            var headObserver = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeName === 'TITLE') {
                            var titleObserver = new MutationObserver(sendTitle);
                            titleObserver.observe(node, { childList: true, characterData: true, subtree: true });
                            sendTitle();
                        }
                    });
                });
            });
            headObserver.observe(head, { childList: true });
        }
    })();
    """
}