import AppKit
import QuickLookUI

/// Space over a thumbnail → the macOS Finder Quick Look panel.
///
/// `QLPreviewPanel` is app-global, so all we do is hand it the whole folder
/// listing plus the index of the hovered photo; arrow keys then walk the list.
final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()

    private var urls: [URL] = []

    var isOpen: Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }

    /// Shows `urls[index]`. Returns false when the index is out of range.
    @discardableResult
    func show(_ urls: [URL], index: Int) -> Bool {
        guard urls.indices.contains(index) else { return false }
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else {
            // Should not happen in a normal app — fall back to Preview.
            NSWorkspace.shared.open(urls[index])
            return true
        }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = index
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}
