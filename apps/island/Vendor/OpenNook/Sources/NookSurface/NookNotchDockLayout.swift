// SPDX-License-Identifier: MIT
// Local OpenNook extension for YuIsland.

import Foundation

/// A physical notch is already the resting silhouette. Only the invisible pointer
/// target gets a fixed size; exposed chrome must retain its natural content height.
public struct NookNotchDockLayout: Equatable, Sendable {
    public let isRetracted: Bool
    public let frameWidth: CGFloat?
    public let frameHeight: CGFloat?

    public init(state: NookState, hovering: Bool, peeking: Bool = false, notchSize: CGSize) {
        isRetracted = state == .compact && !hovering && !peeking
        frameWidth = isRetracted ? max(0, notchSize.width) : nil
        frameHeight = isRetracted ? max(0, notchSize.height) : nil
    }
}
