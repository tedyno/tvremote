import SwiftUI

/// App tile icon: a favicon for known apps (cached by URLSession), otherwise a
/// fallback tile with the app's first letter.
struct AppIconView: View {
    let appName: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url = AppDomains.iconURL(for: appName) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView().tint(Theme.textDim)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                Text(String(appName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundColor(Theme.textDim)
            )
    }
}
