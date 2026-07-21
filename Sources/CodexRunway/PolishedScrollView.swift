import AppKit
import SwiftUI

struct PolishedScrollView<Content: View>: View {
    private let content: Content
    private let verticalPadding: CGFloat
    /// Soft edge fade. Disable when a fixed toolbar sits above the scroll view so the first row is not washed out.
    private let fadesEdges: Bool

    init(verticalPadding: CGFloat = 8, fadesEdges: Bool = true, @ViewBuilder content: () -> Content) {
        self.verticalPadding = verticalPadding
        self.fadesEdges = fadesEdges
        self.content = content()
    }

    var body: some View {
        let scroll = HiddenScrollerScrollView {
            content
                .padding(.vertical, verticalPadding)
                .padding(.trailing, 4)
        }
        if fadesEdges {
            scroll.mask(verticalFade)
        } else {
            scroll
        }
    }

    private var verticalFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 10)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 10)
        }
    }
}

private struct HiddenScrollerScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = SizingScrollView()
        let hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.isFlipped = true

        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .automatic
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = hostingView
        scrollView.onLayout = { [weak scrollView, weak hostingView] in
            guard let scrollView, let hostingView else { return }
            resize(hostingView, in: scrollView)
        }
        resize(hostingView, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let hostingView = scrollView.documentView as? NSHostingView<AnyView> else { return }
        hostingView.rootView = AnyView(content)
        resize(hostingView, in: scrollView)
    }

    private func resize(_ hostingView: NSView, in scrollView: NSScrollView) {
        let width = max(1, scrollView.contentSize.width)
        // Size document to content only — do not stretch to the viewport height,
        // otherwise short SwiftUI stacks appear vertically centered in the scroll area.
        hostingView.setFrameSize(NSSize(width: width, height: 1_000_000))
        hostingView.layoutSubtreeIfNeeded()
        let height = max(1, hostingView.fittingSize.height)
        hostingView.setFrameSize(NSSize(width: width, height: height))
    }
}

private final class SizingScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}
