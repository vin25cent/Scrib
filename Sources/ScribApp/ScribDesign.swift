import AppKit
import SwiftUI

enum ScribDesign {
    static let accent = Color(red: 0.20, green: 0.34, blue: 0.92)
    static let accentDark = Color(red: 0.15, green: 0.27, blue: 0.72)
    static let success = Color(red: 0.14, green: 0.63, blue: 0.40)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor).opacity(0.72)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.42)
    static let mutedSurface = accent.opacity(0.055)

    static let cardRadius: CGFloat = 16
}

struct ScribCardModifier: ViewModifier {
    var padding: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(ScribDesign.surface, in: RoundedRectangle(cornerRadius: ScribDesign.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ScribDesign.cardRadius)
                    .stroke(ScribDesign.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.025), radius: 10, y: 3)
    }
}

extension View {
    func scribCard(padding: CGFloat = 22) -> some View {
        modifier(ScribCardModifier(padding: padding))
    }
}

struct ScribSectionHeading: View {
    let title: String
    let subtitle: String?
    let icon: String

    init(_ title: String, subtitle: String? = nil, icon: String) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ScribDesign.accent)
                .frame(width: 32, height: 32)
                .background(ScribDesign.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ScribPageHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ScribDesign.accent)
                .frame(width: 46, height: 46)
                .background(ScribDesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 22)
    }
}
