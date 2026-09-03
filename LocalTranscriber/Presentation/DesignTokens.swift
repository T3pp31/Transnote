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
}
