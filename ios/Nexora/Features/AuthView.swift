import SwiftUI

struct AuthView: View {
    @EnvironmentObject var api: API
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Image("Brand").resizable().scaledToFill().frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR NEXT CHAPTER").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(.pink)
                    Text("Welcome to\nNexora.").font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("Your anime. Your pace. Online or offline.").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text("Sign in").font(.title2.bold())
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    SecureField("Password", text: $password).textContentType(.password)
                    if let error { Text(error).font(.callout).foregroundStyle(.red) }
                    Button(action: signIn) {
                        HStack { Spacer(); if busy { ProgressView() } else { Label("Continue", systemImage: "arrow.right").bold() }; Spacer() }.padding(8)
                    }.buttonStyle(.borderedProminent).disabled(busy || username.count < 3 || password.count < 12)
                }.textFieldStyle(.roundedBorder).padding(24).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Need an account or forgot your password?").font(.subheadline.bold())
                    Text("Open a private support ticket in our Discord. Accounts are created by the Nexora team.").font(.callout).foregroundStyle(.secondary)
                    Link(destination: API.supportURL) { Label("Open Discord support", systemImage: "bubble.left.and.bubble.right") }
                }.padding(.horizontal, 4)
            }.padding(26).padding(.top, 28)
        }.scrollDismissesKeyboard(.interactively)
    }
    private func signIn() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await api.login(username: username.trimmingCharacters(in: .whitespaces), password: password); password = "" }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct PasswordView: View {
    let required: Bool
    @EnvironmentObject var api: API
    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Label(required ? "Make this account yours" : "Secure your account", systemImage: "lock.shield").font(.headline)
                Text(required ? "Replace your start password before watching or downloading." : "Changing your password signs you out on all devices.").foregroundStyle(.secondary)
            }
            Section("Password") {
                SecureField("Current password", text: $current).textContentType(.password)
                SecureField("New password · 12–128 characters", text: $new).textContentType(.newPassword)
                SecureField("Repeat new password", text: $repeated).textContentType(.newPassword)
                if let error { Text(error).foregroundStyle(.red) }
                Button(busy ? "Saving…" : "Save and sign in again") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await api.changePassword(current: current, new: new); current = ""; new = ""; repeated = "" }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy || current.isEmpty || new.count < 12 || new.count > 128 || new != repeated || new == current)
            }
            Section {
                Link("Contact support", destination: API.supportURL)
                if required { Button("Back to sign in") { api.clearSession() } }
            }
        }.navigationTitle("Change password").navigationBarBackButtonHidden(required)
    }
}
