import SwiftUI

// MARK: - FoxFileRow (shared)

struct FoxFileRow: View {
    let url: URL
    let result: CompressionResult?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.foxBlue.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: result != nil ? "checkmark.doc.fill" : "doc.richtext")
                    .font(.system(size: 16))
                    .foregroundColor(result != nil ? .foxSuccess : .foxBlue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent).font(.callout).foregroundColor(.white)
                    .lineLimit(1).truncationMode(.middle)
                if let r = result {
                    Text("\(r.originalSizeFormatted) → \(r.compressedSizeFormatted)  (−\(String(format: "%.0f", r.savings)) %)")
                        .font(.caption).foregroundColor(r.savings > 0 ? .foxSuccess : .foxWarning)
                } else {
                    Text(fileSizeString).font(.caption).foregroundColor(.foxSecondary)
                }
            }
            Spacer()

            #if os(macOS)
            if result != nil {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.foxSuccess).font(.caption)
            }
            #endif
        }
        .padding(10)
        .background(Color.foxCard)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.foxDivider, lineWidth: 0.5))
    }

    var fileSizeString: String {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else { return "" }
        let f = ByteCountFormatter(); f.allowedUnits = [.useKB, .useMB]; f.countStyle = .file
        return f.string(fromByteCount: size)
    }
}

// MARK: - FoxResultCard (shared)

struct FoxResultCard: View {
    let result: CompressionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.inputURL.lastPathComponent)
                    .font(.caption.bold()).foregroundColor(.white)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("−\(String(format: "%.1f", result.savings)) %")
                    .font(.caption.bold()).foregroundColor(result.savings.foxSavingsColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(result.savings.foxSavingsColor.opacity(0.15)).cornerRadius(6)
            }
            HStack(spacing: 12) {
                stat("Vorher", result.originalSizeFormatted, .foxSecondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundColor(.foxSecondary)
                stat("Nachher", result.compressedSizeFormatted, .foxSuccess)
                Spacer()
                #if os(macOS)
                Button {
                    NSWorkspace.shared.selectFile(result.outputURL.path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder.fill").font(.caption).foregroundColor(.foxBlue)
                }
                .buttonStyle(.plain).help("Im Finder zeigen")
                #else
                ShareLink(item: result.outputURL) {
                    Image(systemName: "square.and.arrow.up").font(.caption).foregroundColor(.foxBlue)
                }
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(10)
        .background(Color.foxCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.foxDivider, lineWidth: 0.5))
    }

    func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundColor(.foxSecondary)
            Text(value).font(.caption.monospacedDigit()).foregroundColor(color)
        }
    }
}

// MARK: - iOS Settings Sheet

#if os(iOS)
struct SettingsSheet: View {
    @Binding var selectedPreset: CompressionPreset
    @Binding var customQuality: Double
    @Binding var customDPI: Double
    @Binding var stripMetadata: Bool
    @Binding var downscaleImages: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FoxGradientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    HStack {
                        Text("Einstellungen").font(.title3.bold()).foregroundColor(.white)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3).foregroundColor(.foxSecondary)
                        }
                    }
                    .padding(.bottom, 4)

                    FoxSectionLabel(icon: "waveform", title: "Qualitätsprofil")

                    ForEach(CompressionPreset.allCases) { preset in
                        Button { selectedPreset = preset } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.rawValue)
                                        .font(.callout.weight(selectedPreset == preset ? .bold : .regular))
                                        .foregroundColor(.white)
                                    Text(preset.description)
                                        .font(.caption).foregroundColor(.foxSecondary)
                                }
                                Spacer()
                                if selectedPreset == preset {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.foxBlue)
                                }
                            }
                            .padding(12)
                            .background(selectedPreset == preset ? Color.foxBlue.opacity(0.18) : Color.foxCard)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(selectedPreset == preset ? Color.foxBlue : Color.foxDivider, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }

                    if selectedPreset == .custom {
                        VStack(spacing: 12) {
                            settingsSlider("Bildqualität", value: $customQuality, range: 0.05...1.0, step: 0.05)
                            { "\(Int($0 * 100)) %" }
                            Color.foxDivider.frame(height: 1)
                            settingsSlider("Max. Auflösung", value: $customDPI, range: 72...600, step: 1)
                            { "\(Int($0)) dpi" }
                        }
                        .foxCard()
                    }

                    FoxSectionLabel(icon: "gearshape", title: "Optionen")

                    VStack(spacing: 12) {
                        settingsToggle("Bilder neu skalieren", sub: "Stärkstes Mittel zur Verkleinerung", isOn: $downscaleImages)
                        Color.foxDivider.frame(height: 1)
                        settingsToggle("Metadaten entfernen", sub: "Autor, Datum, Keywords…", isOn: $stripMetadata)
                    }
                    .foxCard()

                    Spacer(minLength: 30)
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
    }

    func settingsToggle(_ title: String, sub: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundColor(.white)
                Text(sub).font(.caption).foregroundColor(.foxSecondary)
            }
        }
        .toggleStyle(FoxToggleStyle())
    }

    func settingsSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, _ fmt: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline).foregroundColor(.white)
                Spacer()
                Text(fmt(value.wrappedValue)).font(.caption.monospacedDigit()).foregroundColor(.foxBlue)
            }
            Slider(value: value, in: range, step: step).tint(.foxBlue)
        }
    }
}
#endif
