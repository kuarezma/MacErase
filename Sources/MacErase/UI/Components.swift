import AppKit
import SwiftUI

extension Color {
    static let brandA = Color(red: 0.36, green: 0.40, blue: 1.00)
    static let brandB = Color(red: 0.62, green: 0.33, blue: 0.98)
}

extension ShapeStyle where Self == LinearGradient {
    static var brand: LinearGradient {
        LinearGradient(colors: [.brandA, .brandB], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(destructive ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(.brand), in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Loads an app/file icon off the render path and caches it.
struct FileIcon: View {
    let url: URL
    var size: CGFloat = 36
    @State private var image: NSImage?
    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable() } else { Color.clear }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            Self.cache.setObject(icon, forKey: url as NSURL)
            image = icon
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var detail: String?
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            if let detail { Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RingGauge: View {
    let fraction: Double
    var tint: Color = .brandA
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(max(fraction, 0.001), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}
