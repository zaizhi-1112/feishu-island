import SwiftUI

/// Keep the third-stage island viewport stable; overflow stays inside the scroll view.
struct IslandContentScroll<Content: View>: View {
    var height: CGFloat = IslandHost.panelHeight
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(height: height, alignment: .top)
        .scrollIndicators(.visible)
        .scrollBounceBehavior(.basedOnSize)
    }
}
