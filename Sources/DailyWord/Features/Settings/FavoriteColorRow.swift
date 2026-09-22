import SwiftUI
import AppKit

/// 带「常用颜色」收藏的颜色选择行：
/// 把当前选中的颜色加入该设置项的常用列表，下次点击圆点即可复用。
struct FavoriteColorRow: View {
    let label: String
    /// 当前设置值（nil = 使用默认色）
    @Binding var color: Color?
    let defaultColor: Color
    /// 收藏存储 key（每个颜色设置项独立）
    let favoriteKey: String
    var onReset: () -> Void

    @State private var favorites: [Color] = []

    private var userDefaultsKey: String { "favoriteColors.\(favoriteKey)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                ColorPicker(label, selection: Binding(
                    get: { color ?? defaultColor },
                    set: { color = $0 }
                ))
                .font(.caption)
                Spacer()
                Button {
                    addFavorite(color ?? defaultColor)
                } label: {
                    Image(systemName: "star")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .help("把当前颜色加入常用")
                Button("默认") { onReset() }
                    .controlSize(.small)
            }
            if !favorites.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(favorites.enumerated()), id: \.offset) { _, c in
                        Circle()
                            .fill(c)
                            .frame(width: 15, height: 15)
                            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                            .onTapGesture { color = c }
                            .contextMenu {
                                Button("移除常用", role: .destructive) { removeFavorite(c) }
                            }
                            .help("点击使用此颜色 · 右键移除")
                    }
                    Spacer()
                }
            }
        }
        .onAppear { loadFavorites() }
        // 导入数据/外部修改 UserDefaults 时自动刷新收藏（导入后立即显示）
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            loadFavorites()
        }
    }

    private func loadFavorites() {
        guard let raw = UserDefaults.standard.array(forKey: userDefaultsKey) as? [[Double]] else { return }
        favorites = raw.compactMap { rgba in
            guard rgba.count == 4 else { return nil }
            return Color(nsColor: NSColor(
                srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3]))
        }
    }

    private func persistFavorites() {
        let raw = favorites.map { c -> [Double] in
            let ns = NSColor(c).usingColorSpace(.sRGB) ?? .black
            return [ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent]
        }
        UserDefaults.standard.set(raw, forKey: userDefaultsKey)
    }

    private func addFavorite(_ c: Color) {
        guard !favorites.contains(where: { colorDistance($0, c) < 0.02 }) else { return }
        favorites.insert(c, at: 0)
        if favorites.count > 10 { favorites.removeLast() }
        persistFavorites()
    }

    private func removeFavorite(_ c: Color) {
        favorites.removeAll { colorDistance($0, c) < 0.02 }
        persistFavorites()
    }

    private func colorDistance(_ a: Color, _ b: Color) -> Double {
        let na = NSColor(a).usingColorSpace(.sRGB) ?? .black
        let nb = NSColor(b).usingColorSpace(.sRGB) ?? .black
        return abs(na.redComponent - nb.redComponent)
            + abs(na.greenComponent - nb.greenComponent)
            + abs(na.blueComponent - nb.blueComponent)
    }
}
