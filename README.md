# Gemini for macOS (Unofficial)

An **unofficial macOS desktop app** for Google Gemini, built as a lightweight native wrapper.

> **Disclaimer:**
> This project is **not affiliated with, endorsed by, or sponsored by Google**.
> "Gemini" is a trademark of **Google LLC**.
> This app does not modify, scrape, or redistribute Gemini content — it simply loads the official website.

---

## Features

- Native macOS desktop experience with unified titlebar
- Lightweight WebKit wrapper
- Safari 17.6 user agent
- Camera & microphone support
- Reset website data (cookies, cache, sessions)

---

## System Requirements

- **macOS 12.0** (Monterey) or later

---

## Build from Source

```bash
git clone https://github.com/alexcding/gemini-desktop-mac.git
cd gemini-desktop-mac
sh build.sh
open build/Gemini.app
```

Or open `GeminiDesktop.xcodeproj` in Xcode and build from there.

---

## Project Structure

```
App/            App lifecycle and delegate
Coordinators/   Navigation and window coordination
Views/          SwiftUI views (main window, settings)
WebKit/         WKWebView wrapper, view model, user scripts
Utils/          Shared constants and types
Resources/      Assets, icons, Info.plist
```

---

## License

Open source — see repository for details.
