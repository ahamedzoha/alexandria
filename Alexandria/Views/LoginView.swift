import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var app
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Alexandria")
                .font(.largeTitle.bold())
            Text("Connect to your audiobookshelf server")
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                TextField("https://abs.example.com", text: $server)
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

            Button(action: connect) {
                if app.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Connect").frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(server.isEmpty || username.isEmpty || app.isLoading)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { server = app.serverURL }
    }

    private func connect() {
        Task { await app.login(server: server, username: username, password: password) }
    }
}
