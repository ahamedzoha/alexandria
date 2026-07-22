import SwiftUI
import AppKit

struct LoginView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var isSheet = false
    var onDone: (() -> Void)?

    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            Text(isSheet ? "Add Server" : "Alexandria")
                .font(.largeTitle.bold())
            Text("Connect to your audiobookshelf server")
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                TextField("https://abs.example.com", text: $server)
                    .textFieldStyle(.roundedBorder)
                TextField("Name (optional)", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
            }
            .frame(width: 320)

            if let error = app.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(width: 320)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                if isSheet {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                Button(action: connect) {
                    Group {
                        if app.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(isSheet ? "Add" : "Connect")
                        }
                    }
                    .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(server.isEmpty || username.isEmpty || app.isLoading)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [.blue.opacity(0.16), .purple.opacity(0.12), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private func connect() {
        Task {
            let ok = await app.addServer(name: name, url: server, username: username, password: password)
            if ok {
                onDone?()
                if isSheet { dismiss() }
            }
        }
    }
}
