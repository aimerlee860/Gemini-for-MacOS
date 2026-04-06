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
            GeminiWebView(webView: coordinator.webViewModel.wkWebView)
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .scaleEffect(1.0)
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
