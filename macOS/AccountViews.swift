import SwiftUI

/// Sources page (sidebar): the sources, which one is active, add, rename, switch, remove, choose groups.
struct AccountPage: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var settings: Settings
    @State private var renaming: StoredAccount?
    @State private var newName = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your sources, kept in this Mac\u{2019}s Keychain and never shown.").foregroundStyle(MacTheme.soft)
            ForEach(catalog.accounts) { a in
                let active = a.id == catalog.activeId
                HStack(spacing: 12) {
                    Image(systemName: a.type.icon).font(.system(size: 15)).frame(width: 26, height: 26)
                        .foregroundStyle(active ? Color.green : MacTheme.soft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.system(size: 14, weight: .semibold))
                        Text(a.note.isEmpty ? a.type.title : a.note).font(.system(size: 12)).foregroundStyle(MacTheme.dim)
                    }
                    Spacer()
                    if a.type == .m3u { Button("Choose groups") { catalog.chooseGroups(for: a.id) }.accessibilityIdentifier("src-groups-" + a.id) }
                    Button("Rename") { newName = a.name; renaming = a }.accessibilityIdentifier("src-rename-" + a.id)
                    if active { Text("Active").foregroundStyle(Color.green) } else {
                        Button("Switch") { Task { await catalog.use(a.id, languages: settings.languages) } }
                        Button("Remove", role: .destructive) { catalog.removeAccount(a.id) }
                    }
                }
                .padding(12).frame(maxWidth: 720).background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.tile))
                .accessibilityElement(children: .contain).accessibilityIdentifier("source-" + a.id)
            }
            Button { catalog.addingSource = true } label: { Label("Add a source", systemImage: "plus") }.buttonStyle(MacPill()).padding(.top, 6)
                .accessibilityIdentifier("src-add")
            Spacer()
        }
        .padding(24)
        .alert("Rename source", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let r = renaming { catalog.renameAccount(r.id, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
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
            Section("Live countries") {
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
