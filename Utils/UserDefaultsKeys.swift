//
//  UserDefaultsKeys.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import Foundation

enum UserAgent {
    static let safari = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
}

enum AppLanguage: String, CaseIterable {
    case chinese = "zh-CN"
    case english = "en"

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    static var current: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: "app_language"),
               let lang = AppLanguage(rawValue: raw) {
                return lang
            }
            return .chinese
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "app_language")
        }
    }
}
