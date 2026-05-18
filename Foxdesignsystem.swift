import SwiftUI

// MARK: - FoxSuite Design System

extension Color {
    static let foxBlue      = Color(foxHex: "#1976D2")
    static let foxBlueDark  = Color(foxHex: "#1565C0")
    static let foxBlueLight = Color(foxHex: "#1E76D2")
    static let foxBgTop     = Color(foxHex: "#1C1C1E")
    static let foxBgBottom  = Color(foxHex: "#1976D2")
    static let foxCard      = Color.white.opacity(0.08)
    static let foxDivider   = Color.white.opacity(0.20)
    static let foxSecondary = Color(foxHex: "#8E8E93")
    static let foxSuccess   = Color(foxHex: "#34C759")
    static let foxWarning   = Color(foxHex: "#FF9500")
    static let foxDeadline  = Color(foxHex: "#FF3B30")
    static let foxP3Blue    = Color(foxHex: "#007AFF")

    init(foxHex hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3: (a,r,g,b) = (255,(int>>8)*17,(int>>4 & 0xF)*17,(int & 0xF)*17)
        case 6: (a,r,g,b) = (255,int>>16,int>>8 & 0xFF,int & 0xFF)
        case 8: (a,r,g,b) = (int>>24,int>>16 & 0xFF,int>>8 & 0xFF,int & 0xFF)
        default:(a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB,
                  red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - FoxGradientBackground

struct FoxGradientBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .foxBgTop,    location: 0.0),
                .init(color: .foxBgTop,    location: 0.55),
                .init(color: .foxBgBottom, location: 1.0)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - FoxCard

struct FoxCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.foxCard)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.foxDivider, lineWidth: 0.5))
    }
}

extension View {
    func foxCard() -> some View { modifier(FoxCardStyle()) }
}

// MARK: - FoxToggleStyle

struct FoxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? Color.foxBlue : Color.white.opacity(0.2))
                    .frame(width: 40, height: 24)
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .offset(x: configuration.isOn ? 9 : -9)
                    .shadow(radius: 1)
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

// MARK: - FoxButtonStyle

struct FoxPrimaryButton: ButtonStyle {
    var compact: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .caption : .callout.weight(.medium))
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.vertical, compact ? 5 : 8)
            .background(
                isEnabled
                ? (configuration.isPressed ? Color.foxBlueDark : Color.foxBlue)
                : Color.foxBlue.opacity(0.35)
            )
            .foregroundColor(.white)
            .cornerRadius(9)
    }
}

// MARK: - Section Label

struct FoxSectionLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.foxBlue)
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.foxSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }
}

// MARK: - Fox Savings Badge Color

extension Double {
    /// Returns the FoxSuite status color for a savings percentage
    var foxSavingsColor: Color {
        if self > 50 { return .foxSuccess }
        if self > 20 { return .foxP3Blue }
        return .foxWarning
    }
}
