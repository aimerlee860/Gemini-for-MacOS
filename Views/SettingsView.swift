import SwiftUI
import WebKit

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var showingResetAlert = false
    @State private var isClearing = false

    var body: some View {
        Form {
            Section("Privacy") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Reset Website Data")
                        Text("Clears cookies, cache, and login sessions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Reset") { showingResetAlert = true }
                        .disabled(isClearing)
                }
            }
        }
        .padding()
        .frame(width: 400, height: 120)
        .alert(isPresented: $showingResetAlert) {
            Alert(
                title: Text("Reset Website Data?"),
                message: Text("This will clear all cookies, cache, and login sessions. You will need to sign in to Gemini again."),
                primaryButton: .cancel(),
                secondaryButton: .destructive(Text("Reset"), action: clearWebsiteData)
            )
        }
    }

    private func clearWebsiteData() {
        isClearing = true
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: types) { records in
            dataStore.removeData(ofTypes: types, for: records) {
                DispatchQueue.main.async { isClearing = false }
            }
        }
    }
}
