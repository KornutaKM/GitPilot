import SwiftUI

// GitPilot Aurora: a quiet, high-contrast visual language shared conceptually
// with the Android Material 3 theme. Status colors indicate meaning, not branding.
enum GP {
    static let background = Color(red: 0.044, green: 0.056, blue: 0.087)
    static let card = Color(red: 0.083, green: 0.104, blue: 0.155)
    static let raised = Color(red: 0.117, green: 0.146, blue: 0.207)
    static let border = Color.white.opacity(0.075)
    static let secondary = Color(red: 0.61, green: 0.66, blue: 0.74)
    static let subtle = Color(red: 0.42, green: 0.49, blue: 0.60)
    static let accent = Color(red: 0.69, green: 0.63, blue: 1.0)
    static let red = Color(red: 1.0, green: 0.46, blue: 0.51)
    static let green = Color(red: 0.40, green: 0.88, blue: 0.69)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.43)
    static let blue = Color(red: 0.45, green: 0.72, blue: 1.0)
    static let radius: CGFloat = 20
    static let spacing: CGFloat = 16
}

struct Surface<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GP.card, in: RoundedRectangle(cornerRadius: GP.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: GP.radius, style: .continuous).stroke(GP.border, lineWidth: 1))
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.7)
            .foregroundStyle(GP.secondary)
    }
}

struct MetaText: View {
    let text: String
    var body: some View { Text(text).font(.caption).foregroundStyle(GP.secondary) }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.14), lineWidth: 1))
    }
}

struct GPHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: eyebrow)
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-1.1)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.82)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(GP.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct GPSectionTitle: View {
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 19, weight: .bold, design: .rounded))
            Spacer(minLength: 4)
            Text(detail).font(.caption).foregroundStyle(GP.secondary).lineLimit(1)
        }
        .foregroundStyle(.white)
    }
}

struct GPIndicator: View {
    let icon: String
    let tint: Color
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 37, height: 37)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct GPEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                GPIndicator(icon: icon, tint: GP.green)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(GP.secondary)
            }
        }
    }
}

extension View {
    func gpScreen() -> some View { background(GP.background.ignoresSafeArea()).tint(GP.accent) }
}
