import Foundation
import CoreGraphics

public enum OverlayLayout {
    /// Accessibility uses a global top-left origin, AppKit a global bottom-left origin.
    public static func appKitFrame(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }

    public static func badgeFrame(in preview: CGRect, screen: CGRect) -> CGRect? {
        guard preview.width.isFinite, preview.height.isFinite,
              preview.minX.isFinite, preview.minY.isFinite,
              preview.width >= 32, preview.height >= 12,
              screen.intersects(preview) else { return nil }
        let width = min(max(preview.width - 6, 32), 360, screen.width - 16)
        let height: CGFloat = 24
        let x = min(max(preview.midX - width / 2, screen.minX + 8), screen.maxX - width - 8)
        let y = min(max(preview.minY + 3, screen.minY + 8), screen.maxY - height - 4)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
