import SwiftUI

struct RemoteView: View {
    @StateObject private var model = RemoteViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 14) {
                header
                topRow
                favorites
                numpad
                mainControls
                navRow
                mediaRow
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 440)

            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.toast)
        .onAppear { model.onAppear() }
        .sheet(isPresented: $model.showApps) {
            AppsDrawerView(model: model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(model.tvName ?? "Samsung Remote")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
            Spacer()
            Button { model.showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textDim)
            }
            Circle()
                .fill(model.connected ? Theme.accent : Theme.red)
                .frame(width: 9, height: 9)
                .shadow(color: model.connected ? Theme.accent : Theme.red, radius: 5)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    private var topRow: some View {
        HStack {
            PressableButton(action: model.pressPower) {
                Image(systemName: "power")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.red)
                    .frame(width: 54, height: 54)
                    .overlay(Circle().stroke(Theme.red.opacity(0.4), lineWidth: 1))
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(model.power == "on" ? Theme.accent : Theme.red)
                    .frame(width: 6, height: 6)
                Text(nowPlayingText)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Spacer()

            PressableButton(action: { model.showApps = true }) {
                Text("Apps")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(width: 54, height: 54)
                    .overlay(Circle().stroke(Theme.accent.opacity(0.4), lineWidth: 1))
            }
        }
        .padding(.horizontal, 4)
    }

    private var nowPlayingText: String {
        if !model.connected { return "TV not connected" }
        if model.power == "off" { return "TV off" }
        return model.activeApp ?? "TV on"
    }

    @ViewBuilder
    private var favorites: some View {
        if model.favoriteApps.isEmpty {
            Text("Long-press an app in the list to add a favorite")
                .font(.system(size: 12))
                .foregroundColor(Theme.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(model.favoriteApps) { app in
                    PressableButton(action: { model.launch(app.appId) }) {
                        HStack(spacing: 8) {
                            AppIconView(appName: app.name, size: 22)
                            Text(app.name)
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 0.81, green: 0.99, blue: 0.93))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                    }
                }
            }
        }
    }

    private var numpad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(1...9, id: \.self) { n in
                PressableButton(action: { model.tap(RemoteKey.digit(n)) }) {
                    Text("\(n)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.lineSoft, lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var mainControls: some View {
        HStack(spacing: 14) {
            // Volume column
            VStack(spacing: 6) {
                holdButton(RemoteKey.volUp, systemImage: "plus", width: 56, height: 58)
                PressableButton(action: { model.tap(RemoteKey.mute) }) {
                    Text("MUTE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textDim)
                        .frame(width: 56, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.line, lineWidth: 1))
                }
                holdButton(RemoteKey.volDown, systemImage: "minus", width: 56, height: 58)
            }

            dpad
        }
        .padding(.horizontal, 4)
    }

    private var dpad: some View {
        let cell: CGFloat = 64
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: cell, height: cell)
                holdButton(RemoteKey.up, systemImage: "chevron.up", width: cell, height: cell)
                Color.clear.frame(width: cell, height: cell)
            }
            GridRow {
                holdButton(RemoteKey.left, systemImage: "chevron.left", width: cell, height: cell)
                PressableButton(action: { model.tap(RemoteKey.enter) }) {
                    Text("OK")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(Color(red: 0, green: 0.08, blue: 0.05))
                        .frame(width: cell, height: cell)
                        .background(Circle().fill(Theme.accent))
                        .shadow(color: Theme.accent.opacity(0.5), radius: 13)
                }
                holdButton(RemoteKey.right, systemImage: "chevron.right", width: cell, height: cell)
            }
            GridRow {
                Color.clear.frame(width: cell, height: cell)
                holdButton(RemoteKey.down, systemImage: "chevron.down", width: cell, height: cell)
                Color.clear.frame(width: cell, height: cell)
            }
        }
    }

    private var navRow: some View {
        HStack(spacing: 10) {
            navButton("Back", key: RemoteKey.back)
            navButton("Home", key: RemoteKey.home)
            navButton("Menu", key: RemoteKey.menu)
        }
        .padding(.horizontal, 4)
    }

    private var mediaRow: some View {
        HStack(spacing: 8) {
            mediaButton("play.fill", key: RemoteKey.play)
            mediaButton("pause.fill", key: RemoteKey.pause)
            mediaButton("stop.fill", key: RemoteKey.stop)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Button builders

    private func holdButton(_ key: String, systemImage: String, width: CGFloat, height: CGFloat) -> some View {
        PressableButton(
            holdable: true,
            holdBegin: { model.holdBegin(key) },
            holdEnd: { model.holdEnd(key) }
        ) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.text)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        }
    }

    private func navButton(_ title: String, key: String) -> some View {
        PressableButton(action: { model.tap(key) }) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Theme.textDim)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        }
    }

    private func mediaButton(_ systemImage: String, key: String) -> some View {
        PressableButton(action: { model.tap(key) }) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundColor(Theme.textDim)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        }
    }
}

struct ToastView: View {
    let toast: Toast

    private var color: Color {
        switch toast.kind {
        case .info, .success: return Theme.accent
        case .error: return Theme.red
        }
    }

    var body: some View {
        Text(toast.message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.4), lineWidth: 1))
    }
}
