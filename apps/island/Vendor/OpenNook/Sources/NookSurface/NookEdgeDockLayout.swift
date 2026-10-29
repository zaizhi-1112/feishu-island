// SPDX-License-Identifier: MIT
// Local OpenNook extension for YuIsland.

import Foundation

/// Geometry for a retracted edge, a revealed compact pill, and an expanded panel.
/// Coordinates start at the screen's top edge and increase downwards.
public struct NookEdgeDockLayout: Equatable, Sendable {
    public static let edgeHeight: CGFloat = 4
    public static let revealGap: CGFloat = 4
    public let isRetracted: Bool
    public let contentOffset: CGFloat
    public let containerHeight: CGFloat
    public let visibleTop: CGFloat
    public let visibleHeight: CGFloat

    public init(
        state: NookState,
        hovering: Bool,
        peeking: Bool = false,
        contentHeight: CGFloat,
        shownTopInset: CGFloat,
        physicalNotchHeight: CGFloat
    ) {
        let height = max(contentHeight, Self.edgeHeight)
        let notch = max(physicalNotchHeight, 0)
        isRetracted = state == .compact && !hovering && !peeking
        if isRetracted {
            // A hardware notch cannot be hidden. Leave the lip immediately below it.
            visibleTop = notch
            visibleHeight = Self.edgeHeight
            containerHeight = notch + Self.edgeHeight
            contentOffset = containerHeight - height
        } else {
            contentOffset = max(shownTopInset, 0)
            containerHeight = max(contentOffset + height, notch + Self.edgeHeight)
            visibleTop = 0
            visibleHeight = containerHeight
        }
    }

    /// The revealed hit region bridges the edge and pill, so the pointer can travel
    /// down to click without losing hover as the pill slides away from the edge.
    public func hitRect(width: CGFloat) -> CGRect {
        CGRect(x: 0, y: visibleTop, width: max(width, 0), height: visibleHeight)
    }
    /// Keep the entry bridge narrow and below the camera/menu bar.
    public func hitRects(width: CGFloat, bridgeWidth: CGFloat, physicalNotchHeight: CGFloat) -> [CGRect] {
        if isRetracted { return [hitRect(width: width)] }
        let bridge = max(0, min(width, bridgeWidth))
        let bridgeTop = max(0, physicalNotchHeight)
        return [CGRect(x: 0, y: contentOffset, width: max(0, width), height: max(0, containerHeight - contentOffset)),
                CGRect(x: (width - bridge) / 2, y: bridgeTop, width: bridge, height: max(0, contentOffset - bridgeTop))]
    }

    /// A cursor that entered the island may continue upward over the hardware
    /// camera. Retain that hover without adding a click target over the menu bar.
    public func hoverRects(width: CGFloat, bridgeWidth: CGFloat, physicalNotchHeight: CGFloat) -> [CGRect] {
        let regions = hitRects(width: width, bridgeWidth: bridgeWidth, physicalNotchHeight: physicalNotchHeight)
        guard !isRetracted, physicalNotchHeight > 0 else { return regions }
        let bridge = max(0, min(width, bridgeWidth))
        return regions + [CGRect(x: (width - bridge) / 2, y: 0, width: bridge, height: physicalNotchHeight)]
    }

}
