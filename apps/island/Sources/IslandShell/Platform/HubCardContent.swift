import SwiftUI

struct HubCardContent: View {
    let card: HubCard
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let sections = card.sections, !sections.isEmpty, card.kind != "report" {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    HubSectionView(section: section, depth: 0)
                }
            } else {
                Text(HubCardPresentation.text(card)).font(.system(size: 14)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
}
private struct HubSectionView: View {
    let section: HubContentSection
    let depth: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !section.title.isEmpty {
                if section.children.isEmpty && !section.text.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(section.title).foregroundStyle(.secondary).fixedSize()
                            Text(section.text).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title).foregroundStyle(.secondary)
                            Text(section.text)
                        }
                    }.font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                } else { Text(section.title).font(.system(size: depth == 0 ? 15 : 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true) }
            } else if !section.text.isEmpty { Text(section.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(section.children.enumerated()), id: \.offset) { index, child in
                AnyView(HubSectionView(section: child, depth: depth + 1))
                if depth == 0 && index < section.children.count - 1 && !child.children.isEmpty { Divider() }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
