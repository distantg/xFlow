import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsTransferControls: View {
    @EnvironmentObject private var store: DeckStore
    @EnvironmentObject private var updateManager: UpdateManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument = SettingsDocument(data: Data())
    @State private var pendingImport: MosaicSettingsArchive?
    @State private var confirmsImport = false
    @State private var resultMessage: String?
    @State private var showsResult = false
    @State private var backupURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Move your setup between Macs, including every account’s columns, filters, appearance, and update preferences.")
                .font(.caption)
                .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
            HStack(spacing: 12) {
                Button("Export Settings…", action: exportSettings)
                Button("Import Settings…") {
                    backupURL = nil
                    isImporting = true
                }
            }
            Text("New accounts need a one-time sign-in on this Mac. Login credentials are not included.")
                .font(.caption)
                .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Mosaic Settings"
        ) { result in
            if case .failure(let error) = result { showResult(error.localizedDescription) }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let data = try file.read(upToCount: MosaicSettingsArchive.maximumFileSize + 1) ?? Data()
                pendingImport = try MosaicSettingsArchive.decode(data)
                confirmsImport = true
            } catch {
                showResult(error.localizedDescription)
            }
        }
        .alert("Import Mosaic settings?", isPresented: $confirmsImport) {
            Button("Cancel", role: .cancel) { pendingImport = nil }
            Button("Import Settings", action: importSettings)
        } message: {
            Text(importSummary)
        }
        .alert("Mosaic Settings", isPresented: $showsResult) {
            if let backupURL {
                Button("Show Backup") {
                    NSWorkspace.shared.activateFileViewerSelecting([backupURL])
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var importSummary: String {
        guard let archive = pendingImport else { return "" }
        let matching = store.matchingSettingsAccountCount(in: archive)
        return "Import \(archive.accounts.count) account(s): update \(matching) existing layout(s) and add \(archive.accounts.count - matching) account(s). Other accounts on this Mac are kept. App preferences will also be restored.\n\nA backup of your current settings will be saved before importing. New accounts will need to sign in."
    }

    private func currentArchive() -> MosaicSettingsArchive {
        store.settingsArchive(
            automaticallyChecksForUpdates: updateManager.automaticallyChecksForUpdates,
            automaticallyDownloadsUpdates: updateManager.automaticallyDownloadsUpdates
        )
    }

    private func exportSettings() {
        backupURL = nil
        do {
            exportDocument = SettingsDocument(data: try currentArchive().encoded())
            isExporting = true
        } catch {
            showResult(error.localizedDescription)
        }
    }

    private func importSettings() {
        guard let archive = pendingImport else { return }
        pendingImport = nil
        backupURL = nil
        do {
            try archive.validate()
            let backup = try SettingsBackup.save(currentArchive())
            try store.importSettings(archive)
            updateManager.setAutomaticChecks(archive.preferences.automaticallyChecksForUpdates)
            updateManager.setAutomaticDownloads(archive.preferences.automaticallyDownloadsUpdates)
            backupURL = backup
            showResult("Settings imported for \(archive.accounts.count) account(s). Select any account that needs to sign in to finish setup. Your previous settings were saved in \(backup.lastPathComponent).")
        } catch {
            showResult("Settings could not be imported. \(error.localizedDescription)")
        }
    }

    private func showResult(_ message: String) {
        resultMessage = message
        showsResult = true
    }
}

private struct SettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum SettingsBackup {
    static func save(_ archive: MosaicSettingsArchive) throws -> URL {
        let data = try archive.encoded()
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let directory = support.appendingPathComponent("Mosaic/Settings Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("Before Import \(timestamp) \(UUID().uuidString.prefix(8)).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
