import AppKit
import SwiftUI

struct PolishedScrollView<Content: View>: View {
    private let content: Content
    private let verticalPadding: CGFloat

    init(verticalPadding: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        HiddenScrollerScrollView {
            content
                .padding(.vertical, verticalPadding)
                .padding(.trailing, 4)
        }
        .mask(verticalFade)
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
        hostingView.setFrameSize(NSSize(width: width, height: 1_000_000))
        hostingView.layoutSubtreeIfNeeded()
        let height = max(scrollView.contentSize.height, hostingView.fittingSize.height)
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
