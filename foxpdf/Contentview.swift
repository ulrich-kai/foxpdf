import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - ContentView (platform adaptive)

struct ContentView: View {
    @StateObject private var compressor = PDFCompressor()
    @State private var droppedURLs: [URL] = []
    @State private var selectedPreset: CompressionPreset = .ebook
    @State private var customQuality: Double = 0.6
    @State private var customDPI: Double = 150
    @State private var stripMetadata: Bool = true
    @State private var downscaleImages: Bool = true
    @State private var useCustomOutput: Bool = false
    @State private var outputDirectory: URL? = nil
    @State private var isDragOver: Bool = false
    @State private var showSettings: Bool = false
    @State private var showFilePicker: Bool = false

    var body: some View {
        ZStack {
            FoxGradientBackground()

            #if os(macOS)
            macLayout
            #else
            iOSLayout
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                selectedPreset: $selectedPreset,
                customQuality: $customQuality,
                customDPI: $customDPI,
                stripMetadata: $stripMetadata,
                downscaleImages: $downscaleImages
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                // Security-Scoped URLs als Bookmarks sichern,
                // damit der Zugriff beim späteren Komprimieren erhalten bleibt.
                let resolved: [URL] = urls.compactMap { url in
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? url.bookmarkData(
                            options: .minimalBookmark,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil) {
                        var stale = false
                        if let bookmarked = try? URL(
                                resolvingBookmarkData: data,
                                options: [],
                                relativeTo: nil,
                                bookmarkDataIsStale: &stale) {
                            return bookmarked
                        }
                    }
                    return url
                }
                droppedURLs.append(contentsOf: resolved.filter { !droppedURLs.contains($0) })
            case .failure(let error):
                compressor.errors.append("Datei-Auswahl: \(error.localizedDescription)")
            }
        }
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    var macLayout: some View {
        HSplitView {
            VStack(spacing: 0) {
                foxHeader
                macDropZone
                Color.foxDivider.frame(height: 1)
                fileList
            }
            .frame(minWidth: 320, maxWidth: .infinity)

            VStack(spacing: 0) {
                macSettingsPanel
                Color.foxDivider.frame(height: 1)
                resultsPanel
            }
            .frame(minWidth: 280, maxWidth: 340)
            .background(Color.white.opacity(0.04))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: startCompression) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("Komprimieren")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(droppedURLs.isEmpty || compressor.isProcessing
                                ? Color.foxBlue.opacity(0.35) : Color.foxBlue)
                    .foregroundColor(.white).cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(droppedURLs.isEmpty || compressor.isProcessing)
            }
            ToolbarItem {
                Button {
                    droppedURLs = []; compressor.results = []; compressor.errors = []
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(droppedURLs.isEmpty ? .foxSecondary : .foxWarning)
                }
                .disabled(droppedURLs.isEmpty || compressor.isProcessing)
            }
            if compressor.isProcessing {
                ToolbarItem {
                    Button { compressor.cancel() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.foxDeadline)
                    }
                }
            }
        }
    }
    #endif

    // MARK: - iOS/iPadOS Layout

    #if os(iOS)
    var iOSLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    foxHeader
                        .padding(.horizontal)

                    iOSDropZone
                        .padding(.horizontal)

                    if !droppedURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            FoxSectionLabel(icon: "doc.on.doc", title: "Dateien (\(droppedURLs.count))")
                                .padding(.horizontal)

                            VStack(spacing: 6) {
                                ForEach(droppedURLs, id: \.self) { url in
                                    FoxFileRow(
                                        url: url,
                                        result: compressor.results.first { $0.inputURL == url }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }

                    // Quick preset picker (iOS inline)
                    VStack(alignment: .leading, spacing: 8) {
                        FoxSectionLabel(icon: "slider.horizontal.3", title: "Qualitätsprofil")
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(CompressionPreset.allCases) { preset in
                                    iOSPresetChip(preset)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if !compressor.results.isEmpty || !compressor.errors.isEmpty {
                        resultsPanel
                            .padding(.horizontal)
                    }

                    if compressor.isProcessing {
                        VStack(spacing: 8) {
                            HStack {
                                Text(compressor.statusMessage)
                                    .font(.caption).foregroundColor(.foxSecondary)
                                Spacer()
                                Text("\(Int(compressor.progress * 100)) %")
                                    .font(.caption.monospacedDigit()).foregroundColor(.white)
                            }
                            ProgressView(value: compressor.progress)
                                .progressViewStyle(.linear).tint(.foxBlue)
                        }
                        .foxCard()
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.foxBlue)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if compressor.isProcessing {
                        Button { compressor.cancel() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.foxDeadline)
                        }
                    } else {
                        Button {
                            droppedURLs = []; compressor.results = []; compressor.errors = []
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(droppedURLs.isEmpty ? .foxSecondary : .foxWarning)
                        }
                        .disabled(droppedURLs.isEmpty)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                iOSCompressButton
            }
        }
        .preferredColorScheme(.dark)
    }

    var iOSCompressButton: some View {
        Button(action: startCompression) {
            HStack(spacing: 8) {
                if compressor.isProcessing {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                }
                Text(compressor.isProcessing ? "Läuft…" : "Komprimieren")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(droppedURLs.isEmpty ? Color.foxBlue.opacity(0.35) : Color.foxBlue)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(droppedURLs.isEmpty || compressor.isProcessing)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(
            Color.foxBgTop.opacity(0.92)
                .ignoresSafeArea()
        )
    }

    func iOSPresetChip(_ preset: CompressionPreset) -> some View {
        let selected = preset == selectedPreset
        return Button { selectedPreset = preset } label: {
            VStack(spacing: 4) {
                Text(preset.rawValue.components(separatedBy: " (").first ?? preset.rawValue)
                    .font(.callout.weight(selected ? .bold : .regular))
                Text(preset.description)
                    .font(.caption2)
                    .foregroundColor(selected ? .white.opacity(0.8) : .foxSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(selected ? Color.foxBlue : Color.foxCard)
            .foregroundColor(selected ? .white : .foxSecondary)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Color.clear : Color.foxDivider, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Shared: Header

    var foxHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Color.foxBlue)
                    .frame(width: 34, height: 34)
                Image(systemName: "doc.zipper")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("FoxPDF").font(.headline).foregroundColor(.white)
                Text("PDF-Kompressor").font(.caption).foregroundColor(.foxSecondary)
            }
            Spacer()
            Text("FoxSuite")
                .font(.caption2).foregroundColor(.foxBlue)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.foxBlue.opacity(0.15))
                .cornerRadius(4)
        }
    }

    // MARK: - macOS Drop Zone

    #if os(macOS)
    var macDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isDragOver ? Color.foxBlue : Color.foxDivider,
                              style: StrokeStyle(lineWidth: 1.5, dash: isDragOver ? [] : [7,5]))
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(isDragOver ? Color.foxBlue.opacity(0.10) : Color.white.opacity(0.04)))
                .animation(.easeInOut(duration: 0.15), value: isDragOver)

            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.foxBlue.opacity(0.18)).frame(width: 54, height: 54)
                    Image(systemName: isDragOver ? "arrow.down.doc.fill" : "doc.badge.plus")
                        .font(.system(size: 22))
                        .foregroundColor(isDragOver ? .foxBlue : .foxSecondary)
                }
                Text(droppedURLs.isEmpty ? "PDF-Dateien hier ablegen" : "\(droppedURLs.count) Datei(en) geladen")
                    .font(.callout.weight(.medium)).foregroundColor(.white)
                Button("Dateien auswählen…") { pickFilesMac() }
                    .buttonStyle(FoxPrimaryButton())
            }
        }
        .padding(12).frame(height: 170)
        .onDrop(of: [UTType.pdf], isTargeted: $isDragOver) { handleDrop(providers: $0) }
    }
    #endif

    // MARK: - iOS Drop Zone

    #if os(iOS)
    var iOSDropZone: some View {
        Button { showFilePicker = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.foxDivider,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.04)))

                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.foxBlue.opacity(0.18)).frame(width: 60, height: 60)
                        Image(systemName: droppedURLs.isEmpty ? "doc.badge.plus" : "doc.on.doc.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.foxBlue)
                    }
                    Text(droppedURLs.isEmpty ? "PDFs auswählen" : "\(droppedURLs.count) Datei(en) geladen")
                        .font(.callout.weight(.medium)).foregroundColor(.white)
                    Text(droppedURLs.isEmpty ? "Tippen zum Hinzufügen" : "Tippen zum Hinzufügen weiterer Dateien")
                        .font(.caption).foregroundColor(.foxSecondary)
                }
                .padding(.vertical, 28)
            }
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Shared: File List

    var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if droppedURLs.isEmpty {
                    Text("Keine Dateien ausgewählt")
                        .font(.caption).foregroundColor(.foxSecondary).padding(.top, 24)
                } else {
                    ForEach(droppedURLs, id: \.self) { url in
                        FoxFileRow(url: url, result: compressor.results.first { $0.inputURL == url })
                            .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.top, 10).padding(.bottom, 16)
        }
    }

    // MARK: - macOS Settings Panel

    #if os(macOS)
    var macSettingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FoxSectionLabel(icon: "slider.horizontal.3", title: "Einstellungen")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Qualitätsprofil").font(.subheadline).foregroundColor(.white)
                    Picker("Profil", selection: $selectedPreset) {
                        ForEach(CompressionPreset.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden().accentColor(.foxBlue)
                }
                .foxCard()

                if selectedPreset == .custom {
                    VStack(spacing: 12) {
                        foxSlider("Bildqualität", value: $customQuality, range: 0.05...1.0, step: 0.05)
                        { "\(Int($0 * 100)) %" }
                        Color.foxDivider.frame(height: 1)
                        foxSlider("Max. Auflösung", value: $customDPI, range: 72...600, step: 1)
                        { "\(Int($0)) dpi" }
                    }
                    .foxCard()
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut, value: selectedPreset)
                }

                VStack(spacing: 12) {
                    foxToggle("Bilder neu skalieren", sub: "Stärkstes Mittel zur Verkleinerung", isOn: $downscaleImages)
                    Color.foxDivider.frame(height: 1)
                    foxToggle("Metadaten entfernen", sub: "Autor, Datum, Keywords…", isOn: $stripMetadata)
                }
                .foxCard()

                VStack(alignment: .leading, spacing: 8) {
                    foxToggle("Eigener Ausgabeordner",
                              sub: useCustomOutput ? (outputDirectory?.lastPathComponent ?? "Nicht gewählt") : "Standard: neben Original",
                              isOn: $useCustomOutput)
                    if useCustomOutput {
                        Button("Ordner wählen…") { pickOutputDirectoryMac() }
                            .buttonStyle(FoxPrimaryButton(compact: true))
                    }
                }
                .foxCard()

                if compressor.isProcessing {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(compressor.statusMessage).font(.caption).foregroundColor(.foxSecondary)
                            Spacer()
                            Text("\(Int(compressor.progress * 100)) %")
                                .font(.caption.monospacedDigit()).foregroundColor(.white)
                        }
                        ProgressView(value: compressor.progress)
                            .progressViewStyle(.linear).tint(.foxBlue)
                    }
                    .foxCard()
                }
            }
            .padding(12)
        }
    }
    #endif

    // MARK: - Shared: Results Panel

    var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            FoxSectionLabel(icon: "chart.bar.fill", title: "Ergebnisse")

            ForEach(compressor.results) { result in
                FoxResultCard(result: result)
            }

            ForEach(compressor.errors, id: \.self) { error in
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.foxDeadline)
                    Text(error).font(.caption).foregroundColor(.foxSecondary)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.foxDeadline.opacity(0.08)).cornerRadius(10)
            }

            if !compressor.results.isEmpty {
                totalBadge
            }
        }
    }

    var totalBadge: some View {
        let orig = compressor.results.reduce(0) { $0 + $1.originalSize }
        let comp = compressor.results.reduce(0) { $0 + $1.compressedSize }
        let pct  = orig > 0 ? Double(orig - comp) / Double(orig) * 100 : 0.0

        return HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundColor(.foxSuccess)
            Text("Gesamt gespart: \(String(format: "%.1f", pct)) %")
                .font(.subheadline.bold()).foregroundColor(.white)
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(Color.foxSuccess.opacity(0.12)).cornerRadius(12)
    }

    // MARK: - Sub-view helpers

    func foxToggle(_ title: String, sub: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundColor(.white)
                Text(sub).font(.caption).foregroundColor(.foxSecondary)
            }
        }
        .toggleStyle(FoxToggleStyle())
    }

    func foxSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, _ fmt: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline).foregroundColor(.white)
                Spacer()
                Text(fmt(value.wrappedValue)).font(.caption.monospacedDigit()).foregroundColor(.foxBlue)
            }
            Slider(value: value, in: range, step: step).tint(.foxBlue)
        }
    }

    // MARK: - Actions

    #if os(macOS)
    func pickFilesMac() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            droppedURLs.append(contentsOf: panel.urls.filter { !droppedURLs.contains($0) })
        }
    }

    func pickOutputDirectoryMac() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK { outputDirectory = panel.url }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        for p in providers {
            p.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, _ in
                let url: URL? = (item as? URL) ?? {
                    (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                }()
                if let url { DispatchQueue.main.async { if !droppedURLs.contains(url) { droppedURLs.append(url) } } }
            }
        }
        return true
    }
    #endif

    func startCompression() {
        Task {
            await compressor.compress(
                urls: droppedURLs,
                preset: selectedPreset,
                customQuality: customQuality,
                customDPI: customDPI,
                outputDirectory: (useCustomOutput ? outputDirectory : nil),
                stripMetadata: stripMetadata,
                downscaleImages: downscaleImages
            )
        }
    }
}
