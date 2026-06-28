import SwiftUI

/// The apps grid: tap to launch, long-press to toggle favorite.
struct AppsDrawerView: View {
    @ObservedObject var model: RemoteViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                if model.apps.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().tint(Theme.accent)
                        Text(model.connected ? "Loading apps…" : "TV not connected")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.apps) { app in
                            appTile(app)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if model.apps.isEmpty { await model.loadApps() }
        }
    }

    private func appTile(_ app: TVApp) -> some View {
        let isFav = model.isFavorite(app.appId)
        return PressableButton(
            action: { model.launch(app.appId) },
            onLongPress: { model.toggleFavorite(app.appId) }
        ) {
            VStack(spacing: 6) {
                AppIconView(appName: app.name, size: 40)
                Text(app.name)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 16).fill(isFav ? Theme.accentFaint : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isFav ? Theme.accent.opacity(0.4) : Theme.lineSoft, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if isFav {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.accent)
                        .padding(6)
                }
            }
        }
    }
}
