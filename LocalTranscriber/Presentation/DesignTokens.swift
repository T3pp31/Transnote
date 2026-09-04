import SwiftUI

enum DesignTokens {
    enum Spacing {
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 20
        static let bottomPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let footerVerticalPadding: CGFloat = 10
    }

    enum Corner {
        static let card: CGFloat = 12
        static let banner: CGFloat = 12
        static let inner: CGFloat = 8
        static let segment: CGFloat = 6
    }

    enum Card {
        static let padding: CGFloat = 22
    }

    enum Layout {
        static let windowMinHeight: CGFloat = 600
        static let dropZoneMinHeight: CGFloat = 120
        static let dropZoneMaxHeight: CGFloat = 220
    }

    enum Colors {
        static func border(_ colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.12)
        }

        static func hoverFill(_ colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
        }

        static func dropShadow(_ colorScheme: ColorScheme, isHovered: Bool) -> Color {
            if colorScheme == .dark {
                return Color.black.opacity(isHovered ? 0.55 : 0.4)
            }
            return Color.black.opacity(isHovered ? 0.12 : 0.08)
        }

        static func toastShadow(_ colorScheme: ColorScheme) -> Color {
            colorScheme == .dark
                ? Color.black.opacity(0.55)
                : Color.black.opacity(0.14)
        }
    }
}
