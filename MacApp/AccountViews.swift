import SwiftUI

/// IPTV account form: name, server, username, password, checked with the provider before it is saved to the
/// Keychain. On first launch it is a sheet over the empty window that cannot be dismissed.
struct AccountSheet: View {
    var firstLaunch = false
    let done: () -> Void
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var status = "The login is checked with your provider before it is saved."
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if firstLaunch { Wordmark(size: 17).padding(.bottom, 6) }
            Text(firstLaunch ? "Add your IPTV account" : "Add an account").font(.system(size: 22, weight: .bold))
            if firstLaunch {
                Text("Nexus TV plays your own provider’s live channels, films and series (Xtream Codes). Enter the details your provider gave you. They stay in this Mac’s Keychain.")
                    .font(.system(size: 13)).foregroundStyle(MacTheme.soft).fixedSize(horizontal: false, vertical: true)
            }
            Form {
                TextField("Name", text: $name, prompt: Text("For you, e.g. Home IPTV")).accessibilityIdentifier("acc-name")
                TextField("Server", text: $server, prompt: Text("http://server:port")).accessibilityIdentifier("acc-server")
                TextField("Username", text: $username).accessibilityIdentifier("acc-user")
                SecureField("Password", text: $password).accessibilityIdentifier("acc-pass")
            }
            .formStyle(.grouped).frame(height: 210)
            Text(status).font(.system(size: 12)).foregroundStyle(MacTheme.soft).accessibilityIdentifier("acc-status")
            HStack {
                Spacer()
                if !firstLaunch { Button("Cancel", action: done).keyboardShortcut(.cancelAction) }
                Button(firstLaunch ? "Check and sign in" : "Check and save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction).disabled(busy).accessibilityIdentifier("acc-save")
            }
        }
        .padding(24).frame(width: 520)
        .interactiveDismissDisabled(firstLaunch)
    }

    private func save() async {
        let a = Account(server: server, username: username, password: password)
        guard a.isComplete else { status = "Server, username and password are all needed."; return }
        busy = true; status = "Checking the login…"
        if let err = await AccountVault.check(a) { status = err; busy = false; return }
        let s = StoredAccount(id: "a\(Int(Date().timeIntervalSince1970))", name: name.isEmpty ? username : name, server: a.base, username: username, password: password)
        if firstLaunch { await catalog.onboard(s, languages: settings.languages) } else { catalog.addAccount(s) }
        busy = false
        done()
    }
}

/// IPTV account page (sidebar): the accounts, which one is active, add, switch, remove.
struct AccountPage: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @State private var adding = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your IPTV logins, kept in this Mac’s Keychain and never shown.").foregroundStyle(MacTheme.soft)
            ForEach(catalog.accounts) { a in
                let active = a.id == catalog.activeId
                HStack(spacing: 12) {
                    Image(systemName: active ? "checkmark.circle.fill" : "person.crop.circle").foregroundStyle(active ? Color.green : MacTheme.soft)
                    Text(a.name).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if active { Text("Active").foregroundStyle(Color.green) } else {
                        Button("Switch") { Task { await catalog.use(a.id, languages: settings.languages) } }
                        Button("Remove", role: .destructive) { catalog.removeAccount(a.id) }
                    }
                }
                .padding(12).frame(maxWidth: 640).background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.tile))
            }
            Button { adding = true } label: { Label("Add an account", systemImage: "plus") }.buttonStyle(MacPill()).padding(.top, 6)
            Spacer()
        }
        .padding(24)
        .sheet(isPresented: $adding) { AccountSheet { adding = false } }
    }
}

/// Settings (sidebar page and ⌘,): countries, languages, online subtitles account.
struct MacSettingsPane: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @ObservedObject private var osub = OpenSubtitles.shared
    @State private var key = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var osStatus = ""
    var body: some View {
        Form {
            Section("Live TV countries") {
                let all = catalog.liveCountries.isEmpty ? Settings.defaultCountries.map { ($0, 0) } : catalog.liveCountries
                ScrollView(.horizontal) {
                    HStack { ForEach(all, id: \.0) { c in
                        Toggle(Countries.name(c.0), isOn: Binding(get: { settings.countries.contains(c.0) }, set: { on in
                            if on { settings.countries.append(c.0) } else if settings.countries.count > 1 { settings.countries.removeAll { $0 == c.0 } }
                        })).toggleStyle(.button)
                    } }
                }
            }
            Section("Film and series languages") {
                HStack { ForEach(["EN", "FR", "MULTI", "", "NL", "DE", "ES", "IT", "AR"], id: \.self) { t in
                    Toggle(Languages.name(t), isOn: Binding(get: { settings.languages.contains(t) }, set: { on in
                        if on { settings.languages.append(t) } else if settings.languages.count > 1 { settings.languages.removeAll { $0 == t } }
                    })).toggleStyle(.button)
                } }
            }
            Section("Online subtitles (OpenSubtitles)") {
                if let a = osub.account {
                    Text("Signed in as \(a.user)" + (osub.left.map { " · \($0) downloads left today" } ?? "")).accessibilityIdentifier("os-status")
                    Button("Sign out") { osub.signOut() }
                } else {
                    SecureField("API key", text: $key)
                    TextField("Username", text: $user)
                    SecureField("Password", text: $pass)
                    Button("Check and save") {
                        Task {
                            osStatus = "Checking…"
                            do { try await osub.signIn(OSAccount(key: key, user: user, pass: pass)); osStatus = "" }
                            catch { osStatus = "OpenSubtitles refused this login (\(error.localizedDescription))." }
                        }
                    }
                    if !osStatus.isEmpty { Text(osStatus).foregroundStyle(MacTheme.soft) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
