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
    // Reentrancy guard: Return can fire both a field's .onSubmit and the
    // default button, so gate the async submit to avoid a double addServer.
    @State private var isSubmitting = false

    @FocusState private var focus: Field?
    private enum Field: Hashable { case server, name, username, password }

    // Unchanged gating contract: server URL + username required, never while loading.
    private var canConnect: Bool { !server.isEmpty && !username.isEmpty && !app.isLoading }

    var body: some View {
        if isSheet {
            sheetBody
        } else {
            windowBody
        }
    }

    // MARK: - Full-screen splash (RootView, isSheet == false)

    private var windowBody: some View {
        ZStack {
            AuthBackground()

            VStack(spacing: 24) {
                windowHeader
                fieldStack
                if let error = app.errorMessage { errorLabel(error) }
                Button(action: connect) {
                    submitButtonLabel("Connect")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)   // Return connects
                .disabled(!canConnect)
            }
            .frame(maxWidth: 360)
            .padding(40)
        }
        // The splash itself always renders dark (intentional brand moment) …
        .environment(\.colorScheme, .dark)
        // … but the window-level preference releases the moment login succeeds,
        // so MainView crossfades in already wearing the system appearance
        // instead of snapping light after the transition ends.
        .preferredColorScheme(app.isLoggedIn ? nil : .dark)
        .onAppear { focus = .server }
    }

    private var windowHeader: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)   // real icon, restrained size, no glow
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Alexandria")
                    .font(.title)               // system title scale, not a 40pt display face
                    .fontWeight(.semibold)
                Text("Connect to your audiobookshelf server")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Sheet (MainView, isSheet == true) — System-Settings-style

    private var sheetBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            fieldStack
                .padding(.horizontal, 24)

            if let error = app.errorMessage {
                errorLabel(error)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            Spacer(minLength: 20)

            Divider()

            // Bottom bar: Cancel (left) then prominent default Add (right).
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)   // Escape cancels
                Button(action: connect) {
                    submitButtonLabel("Add")
                        .frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)      // Return adds
                .disabled(!canConnect)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        // LoginView owns its sheet size; MainView drops its .frame.
        .frame(minWidth: 460, idealWidth: 480, minHeight: 430)
        .onAppear { focus = .server }
    }

    private var sheetHeader: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Server")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Connect to another audiobookshelf server")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared native fields (real labels + roundedBorder controls)

    private var fieldStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeledField("Server URL") {
                TextField("Server URL", text: $server,
                          prompt: Text(verbatim: "https://library.example.com"))
                    .autocorrectionDisabled()
                    .focused($focus, equals: .server)
                    .onSubmit(connect)
            }
            labeledField("Name") {
                TextField("Name", text: $name, prompt: Text("Optional"))
                    .focused($focus, equals: .name)
                    .onSubmit(connect)
            }
            labeledField("Username") {
                TextField("Username", text: $username, prompt: Text("Your username"))
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .username)
                    .onSubmit(connect)
            }
            labeledField("Password") {
                SecureField("Password", text: $password, prompt: Text("Required"))
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .onSubmit(connect)
            }
        }
    }

    private func labeledField<Content: View>(_ label: String,
                                             @ViewBuilder _ field: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)   // the field already carries this label
            field()
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Shared error + submit label

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)   // inline validation, not a red pill
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func submitButtonLabel(_ title: String) -> some View {
        if app.isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        } else {
            Text(title)
        }
    }

    // MARK: - Action (unchanged AppState contract)

    private func connect() {
        guard canConnect, !isSubmitting else { return }
        isSubmitting = true
        Task {
            let ok = await app.addServer(name: name, url: server,
                                         username: username, password: password)
            isSubmitting = false
            if ok {
                onDone?()
                if isSheet { dismiss() }
            }
        }
    }
}

/// Forced-dark login backdrop — a deep neutral field with ONE soft, static
/// glow behind the form, sampled from the system accent rather than any
/// hardcoded brand hue. The dynamic colors resolve dark via the splash's
/// local `.environment(\.colorScheme, .dark)`, so the backdrop stays dark
/// even while the window-level scheme hands off to the system appearance.
private struct AuthBackground: View {
    var body: some View {
        ZStack {
            // Deep neutral base with a hint of vertical depth.
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor),
                         Color(nsColor: .underPageBackgroundColor)],
                startPoint: .top, endPoint: .bottom
            )
            // The one accent glow, centered behind the form.
            RadialGradient(colors: [Color.accentColor.opacity(0.18), .clear],
                           center: UnitPoint(x: 0.5, y: 0.30), startRadius: 0, endRadius: 540)
        }
        .ignoresSafeArea()
    }
}
