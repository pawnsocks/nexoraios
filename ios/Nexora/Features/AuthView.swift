import SwiftUI

struct AuthView: View {
    @EnvironmentObject var api: API
    @State private var username = ""
    @State private var password = ""
    @State private var register = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image("Brand").resizable().scaledToFit().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 20))
                Text(register ? "Your next story\nstarts here." : "Welcome back.").font(.largeTitle.bold())
                Text("Anime, at your pace.").foregroundStyle(.secondary)
                TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                SecureField("Password · at least 12 characters", text: $password).textContentType(register ? .newPassword : .password)
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                Button {
                    busy = true; error = nil
                    Task {
                        defer { busy = false }
                        do { try await api.login(username: username.trimmingCharacters(in: .whitespaces), password: password, register: register); password = "" }
                        catch { self.error = error.localizedDescription }
                    }
                } label: {
                    HStack { Spacer(); if busy { ProgressView() } else { Text(register ? "Create account" : "Log in").bold() }; Spacer() }.padding(8)
                }.buttonStyle(.borderedProminent).disabled(busy || username.count < 3 || password.count < 12)
                Button(register ? "Already have an account? Log in" : "New to Nexora? Create an account") { register.toggle(); error = nil }.disabled(busy)
            }.textFieldStyle(.roundedBorder).padding(28).padding(.top, 40)
        }
    }
}
