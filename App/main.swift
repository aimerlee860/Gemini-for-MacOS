import AppKit

NSLog("[GeminiDesktop] main.swift executing")

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
NSLog("[GeminiDesktop] About to call app.run()")
app.run()
