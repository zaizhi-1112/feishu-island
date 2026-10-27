import SwiftUI

/// Fit short island pages to their content; only long pages need a scroll viewport.
struct IslandContentScroll<Content: View>: View {
    var maximumHeight: CGFloat = IslandHost.panelHeight
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = IslandHost.panelHeight
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { ceil($0.size.height) }) { contentHeight = $0 }
        }
        .frame(height: min(maximumHeight, max(1, contentHeight)))
        .scrollBounceBehavior(.basedOnSize)
    }
}
