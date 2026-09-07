import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ExpandedImagePayload {
    let image: NSImage
    let data: Data
    let contentType: UTType
    let filename: String

    init?(data: Data, url: URL) {
        guard let image = NSImage(data: data),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String) else { return nil }
        self.image = image
        self.data = data
        contentType = type
        let stem = url.deletingPathExtension().lastPathComponent
        filename = (stem.isEmpty ? "Image" : stem) + "." + (type.preferredFilenameExtension ?? "img")
    }
}

struct ExpandedImageView: NSViewRepresentable {
    let payload: ExpandedImagePayload

    func makeNSView(context: Context) -> ImageActionView {
        let view = ImageActionView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.animates = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setAccessibilityLabel("Expanded image")
        return view
    }

    func updateNSView(_ view: ImageActionView, context: Context) {
        view.payload = payload
        view.image = payload.image
    }
}

final class ImageActionView: NSImageView {
    var payload: ExpandedImagePayload?
    private var sharingPicker: NSSharingServicePicker?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard payload != nil else { return nil }
        let menu = NSMenu()
        for (title, action) in [("Copy Image", #selector(copyImage)),
                                ("Save Image…", #selector(saveImage)),
                                ("Share Image…", #selector(shareImage))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func copyImage() {
        guard let payload else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([payload.image])
    }

    @objc private func saveImage() {
        guard let payload, let window else { return }
        let panel = NSSavePanel()
        panel.title = "Save Image"
        panel.nameFieldStringValue = payload.filename
        panel.allowedContentTypes = [payload.contentType]
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let destination = panel.url else { return }
            do {
                // Preserve the downloaded format and full resolution.
                try payload.data.write(to: destination, options: .atomic)
            } catch {
                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: window)
            }
        }
    }

    @objc private func shareImage() {
        guard let payload else { return }
        let picker = NSSharingServicePicker(items: [payload.image])
        sharingPicker = picker
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            let anchor = NSRect(x: self.bounds.midX, y: self.bounds.midY, width: 1, height: 1)
            picker.show(relativeTo: anchor, of: self, preferredEdge: .minY)
        }
    }
}
