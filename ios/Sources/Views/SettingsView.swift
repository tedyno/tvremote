import SwiftUI

/// Pick a TV (auto-discovered via Bonjour, or entered manually) and optionally
/// set its MAC for Wake-on-LAN power-on.
struct SettingsView: View {
    @ObservedObject var model: RemoteViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var discovery = TVDiscovery()

    @State private var manualHost = ""
    @State private var macInput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if discovery.found.isEmpty {
                        HStack {
                            if discovery.isScanning { ProgressView() }
                            Text(discovery.isScanning ? "Scanning…" : "No TVs found yet")
                                .foregroundColor(Theme.textDim)
                        }
                    }
                    ForEach(discovery.found) { tv in
                        Button {
                            model.select(host: tv.host, name: tv.name)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.name).foregroundColor(Theme.text)
                                    Text(tv.host).font(.caption).foregroundColor(Theme.textDim)
                                }
                                Spacer()
                                if model.host == tv.host {
                                    Image(systemName: "checkmark").foregroundColor(Theme.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Discovered TVs")
                } footer: {
                    Text("Samsung TVs are found automatically over your Wi-Fi. The first time, allow Local Network access when prompted.")
                }

                Section("Manual IP") {
                    TextField("e.g. 192.168.1.10", text: $manualHost)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Use this IP") {
                        let host = manualHost.trimmingCharacters(in: .whitespaces)
                        guard !host.isEmpty else { return }
                        model.select(host: host, name: host)
                        dismiss()
                    }
                    .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section {
                    TextField("AA:BB:CC:DD:EE:FF", text: $macInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onChange(of: macInput) { model.mac = $0 }
                } header: {
                    Text("TV MAC address (Wake-on-LAN)")
                } footer: {
                    Text("Optional. Required to power the TV ON — without it the power button can only turn the TV off.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Theme.accent)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { discovery.start() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            macInput = model.mac
            discovery.start()
        }
        .onDisappear { discovery.stop() }
    }
}
