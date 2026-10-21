import SwiftUI

/// Aurora Pastel: an accessible, low-chroma interface shared with Android.
/// Semantic colors preserve meaning without turning the app into a dark terminal.
enum GP {
    static let background = Color(red: 0.973, green: 0.961, blue: 0.985) // #F8F5FB
    static let card = Color.white
    static let raised = Color(red: 0.944, green: 0.920, blue: 0.973)
    static let border = Color(red: 0.889, green: 0.858, blue: 0.932)
    static let ink = Color(red: 0.200, green: 0.173, blue: 0.290)
    static let secondary = Color(red: 0.389, green: 0.365, blue: 0.478)
    static let subtle = Color(red: 0.463, green: 0.437, blue: 0.548)
    static let accent = Color(red: 0.414, green: 0.304, blue: 0.690)
    static let red = Color(red: 0.655, green: 0.282, blue: 0.392)
    static let green = Color(red: 0.176, green: 0.455, blue: 0.341)
    static let amber = Color(red: 0.565, green: 0.340, blue: 0.153)
    static let blue = Color(red: 0.247, green: 0.420, blue: 0.639)
    static let lavender = Color(red: 0.911, green: 0.865, blue: 0.978)
    static let mint = Color(red: 0.835, green: 0.947, blue: 0.879)
    static let peach = Color(red: 1.000, green: 0.892, blue: 0.844)
    static let blush = Color(red: 0.979, green: 0.864, blue: 0.914)
    static let radius: CGFloat = 22
    static let spacing: CGFloat = 16
    static let hero = LinearGradient(
        colors: [Color(red: 0.901, green: 0.862, blue: 0.980),
                 Color(red: 0.984, green: 0.919, blue: 0.924),
                 Color(red: 0.932, green: 0.971, blue: 0.922)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// A visible edge and extremely subtle shadow keep white cards separated
/// from the tinted canvas, including for users with reduced transparency.
struct Surface<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GP.card, in: RoundedRectangle(cornerRadius: GP.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GP.radius, style: .continuous)
                    .strokeBorder(GP.border.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: GP.ink.opacity(0.045), radius: 12, y: 5)
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
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(GP.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
            .accessibilityLabel(text)
    }
}

struct GPHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Eyebrow(text: eyebrow)
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-1.1)
                .foregroundStyle(GP.ink)
                .minimumScaleFactor(0.80)
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
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Spacer(minLength: 4)
            Text(detail)
                .font(.caption)
                .foregroundStyle(GP.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(GP.ink)
    }
}

struct GPIndicator: View {
    let icon: String
    let tint: Color
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct GPEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                GPIndicator(icon: icon, tint: GP.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GP.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(GP.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Deliberately pastel, never a credential form. OAuth uses Apple's system
/// browser instead of an embedded WebView.
struct GPWelcomeCard: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: eyebrow)
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(GP.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(GP.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(GP.accent)
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.60), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GP.hero, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(GP.border.opacity(0.65)))
    }
}

extension View {
    func gpScreen() -> some View {
        background(GP.background.ignoresSafeArea())
            .tint(GP.accent)
    }
}
