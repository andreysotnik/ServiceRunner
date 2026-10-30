import AppKit
import SwiftUI

/// Read-only log viewer backed by NSTextView. Appends incrementally and keeps
/// the view pinned to the bottom while the user hasn't scrolled up.
struct LogView: NSViewRepresentable {
    let lines: [LogLine]
    let revision: Int
    let filter: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.layoutManager?.allowsNonContiguousLayout = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        let coordinator = context.coordinator
        let visible = filter.isEmpty ? lines : lines.filter { $0.text.localizedCaseInsensitiveContains(filter) }
        let wasAtBottom = isAtBottom(scrollView)

        storage.beginEditing()
        if filter != coordinator.filter || !coordinator.canAppend(visible) {
            storage.setAttributedString(NSAttributedString())
            coordinator.reset(filter: filter)
        }
        // Drop lines that were trimmed from the buffer.
        if let firstID = visible.first?.id {
            var dropLength = 0
            var dropCount = 0
            for entry in coordinator.rendered where entry.id < firstID {
                dropLength += entry.length
                dropCount += 1
            }
            if dropCount > 0 {
                storage.deleteCharacters(in: NSRange(location: 0, length: dropLength))
                coordinator.rendered.removeFirst(dropCount)
            }
        }
        let newLines = visible.filter { $0.id > coordinator.lastID }
        if !newLines.isEmpty {
            let chunk = NSMutableAttributedString()
            for line in newLines {
                let rendered = Self.render(line)
                chunk.append(rendered)
                coordinator.rendered.append((line.id, rendered.length))
            }
            storage.append(chunk)
            coordinator.lastID = newLines.last!.id
        }
        storage.endEditing()

        if wasAtBottom || coordinator.needsInitialScroll {
            coordinator.needsInitialScroll = false
            textView.scrollToEndOfDocument(nil)
        }
    }

    private func isAtBottom(_ scrollView: NSScrollView) -> Bool {
        guard let doc = scrollView.documentView else { return true }
        let visible = scrollView.contentView.documentVisibleRect
        return visible.maxY >= doc.bounds.maxY - 20
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    static func render(_ line: LogLine) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: timeFormatter.string(from: line.date) + "  ",
            attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        )
        let color: NSColor = line.kind == .system ? .systemBlue : .labelColor
        result.append(NSAttributedString(
            string: line.text + "\n",
            attributes: [.font: font, .foregroundColor: color]
        ))
        return result
    }

    final class Coordinator {
        var filter = ""
        var lastID = -1
        var rendered: [(id: Int, length: Int)] = []
        var needsInitialScroll = true

        func reset(filter: String) {
            self.filter = filter
            lastID = -1
            rendered = []
            needsInitialScroll = true
        }

        /// False when the buffer was cleared or otherwise no longer extends what's on screen.
        func canAppend(_ visible: [LogLine]) -> Bool {
            guard let lastRendered = rendered.last else { return true }
            guard let lastVisible = visible.last else { return false }
            return lastVisible.id >= lastRendered.id
        }
    }
}
