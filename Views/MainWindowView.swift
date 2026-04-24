//
//  MainWindowContent.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit

struct MainWindowView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var isLoading = true

    var body: some View {
        ZStack {
            GeminiWebView(webView: coordinator.webViewModel.wkWebView, webViewModel: coordinator.webViewModel)
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .scaleEffect(1.0)
                    .allowsHitTesting(false)
            }

            if let error = coordinator.webViewModel.networkError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(error.message)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if error.isRetryable {
                        Button("重试") {
                            coordinator.webViewModel.retryAfterError()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .ignoresSafeArea()
        .onReceive(coordinator.webViewModel.$isLoading) { loading in
            isLoading = loading
        }
        .onAppear {
            isLoading = coordinator.webViewModel.isLoading
        }
    }
}
