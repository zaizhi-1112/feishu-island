import SwiftUI

/// Preserve reading/display order while letting short options share a row.
/// Measure the complete control, including the switch and any reorder buttons.
struct HubCardOptionsLayout: Layout {
    static let columnGap: CGFloat = 24
    static let rowGap: CGFloat = 8

    struct Slot: Equatable {
        let x: CGFloat
        let width: CGFloat
        let row: Int
    }

    static func slots(idealWidths: [CGFloat], width: CGFloat) -> [Slot] {
        let width = max(0, width)
        let half = max(0, (width - columnGap) / 2)
        var row = 0
        var hasLeading = false
        return idealWidths.map { ideal in
            if ideal > half {
                if hasLeading { row += 1; hasLeading = false }
                let slot = Slot(x: 0, width: width, row: row)
                row += 1
                return slot
            }
            let slot = Slot(x: hasLeading ? half + columnGap : 0, width: half, row: row)
            if hasLeading { row += 1 }
            hasLeading.toggle()
            return slot
        }
    }

    private func frames(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        let slots = Self.slots(idealWidths: subviews.map { $0.sizeThatFits(.unspecified).width }, width: width)
        var heights = [Int: CGFloat]()
        for (view, slot) in zip(subviews, slots) {
            heights[slot.row] = max(heights[slot.row, default: 0], view.sizeThatFits(.init(width: slot.width, height: nil)).height)
        }
        var origins = [Int: CGFloat]()
        var y: CGFloat = 0
        for row in heights.keys.sorted() { origins[row] = y; y += heights[row, default: 0] + Self.rowGap }
        return slots.map { CGRect(x: $0.x, y: origins[$0.row, default: 0], width: $0.width, height: heights[$0.row, default: 0]) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return CGSize(width: width, height: frames(subviews, width: width).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, rect) in zip(subviews, frames(subviews, width: bounds.width)) {
            view.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.midY), anchor: .leading, proposal: .init(rect.size))
        }
    }
}
