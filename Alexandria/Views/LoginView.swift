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
    @State private var appear = false

    private var canConnect: Bool { !server.isEmpty && !username.isEmpty && !app.isLoading }

    var body: some View {
        ZStack {
            AnimatedAuroraBackground()

            VStack(spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                    .scaleEffect(appear ? 1 : 0.85)

                VStack(spacing: 4) {
                    Text(isSheet ? "Add Server" : "Alexandria")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Connect to your audiobookshelf server")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(spacing: 12) {
                    LoginField(icon: "link", placeholder: "https://abs.example.com", text: $server)
                    LoginField(icon: "tag", placeholder: "Name (optional)", text: $name)
                    LoginField(icon: "person", placeholder: "Username", text: $username)
                    LoginField(icon: "lock", placeholder: "Password", isSecure: true, text: $password, onSubmit: connect)
                }
                .frame(width: 340)

                if let error = app.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.red.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(width: 340)
                }

                HStack(spacing: 12) {
                    if isSheet {
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    connectButton
                }
                .frame(width: 340)
                .padding(.top, 4)
            }
            .padding(48)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.12)))
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 28)
            .animation(.spring(response: 0.7, dampingFraction: 0.85), value: appear)
        }
        .onAppear { appear = true }
    }

    private var connectButton: some View {
        Button(action: connect) {
            Group {
                if app.isLoading {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Text(isSheet ? "Add" : "Connect").fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [.blue, .purple, .pink],
                               startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
            .foregroundStyle(.white)
            .opacity(canConnect ? 1 : 0.5)
            .shadow(color: .purple.opacity(canConnect ? 0.5 : 0), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!canConnect)
    }

    private func connect() {
        guard canConnect else { return }
        Task {
            let ok = await app.addServer(name: name, url: server, username: username, password: password)
            if ok {
                onDone?()
                if isSheet { dismiss() }
            }
        }
    }
}

/// A friendly icon + field row on a glass pill.
private struct LoginField: View {
    let icon: String
    let placeholder: String
    var isSecure = false
    @Binding var text: String
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
    }
}
