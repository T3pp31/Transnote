import AppKit
import SwiftUI
import XCTest
@testable import LocalTranscriber

@MainActor
final class ToastViewAccessibilityTests: XCTestCase {
    func testActionToastPreservesButtonLabelAndCanPerformAction() async throws {
        let actionPerformed = expectation(description: "トーストのアクションが実行される")
        let message = ToastMessage(
            text: "保存しました: result.txt",
            icon: "checkmark.circle.fill",
            action: (label: "Finder で表示", handler: { actionPerformed.fulfill() })
        )
        let window = host(message)
        defer { window.close() }

        let contentView = try XCTUnwrap(window.contentView)
        let elements = accessibilityElements(in: contentView)
        let buttons = elements.filter { $0.accessibilityRole() == .button }
        XCTAssertEqual(buttons.count, 1)
        let button = try XCTUnwrap(buttons.first)
        XCTAssertEqual(spokenText(of: button), message.action?.label)
        XCTAssertNotEqual(spokenText(of: button), message.text)
        let messageTexts = elements.filter {
            $0.accessibilityRole() == .staticText && spokenText(of: $0) == message.text
        }
        XCTAssertEqual(messageTexts.count, 1, "本文は独立したテキストとして1回だけ公開する")
        XCTAssertFalse(elements.contains { $0.accessibilityRole() == .image }, "装飾アイコンは読み上げない")

        XCTAssertTrue(button.accessibilityPerformPress())
        await fulfillment(of: [actionPerformed], timeout: 2)
    }

    func testToastWithoutActionExposesMessageButNoImageOrButton() throws {
        let message = ToastMessage(
            text: "文字起こし結果をコピーしました",
            icon: "checkmark.circle.fill"
        )
        let window = host(message)
        defer { window.close() }

        let contentView = try XCTUnwrap(window.contentView)
        let elements = accessibilityElements(in: contentView)
        let texts = elements.filter { $0.accessibilityRole() == .staticText }
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(spokenText(of: try XCTUnwrap(texts.first)), message.text)
        XCTAssertFalse(elements.contains { $0.accessibilityRole() == .button })
        XCTAssertFalse(elements.contains { $0.accessibilityRole() == .image }, "装飾アイコンは読み上げない")
    }

    private func host(_ message: ToastMessage) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ToastView(message: message))
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    private func accessibilityElements(in element: any NSAccessibility) -> [any NSAccessibility] {
        let children = (element.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibility }
        let current: [any NSAccessibility] = element.isAccessibilityElement() ? [element] : []
        return current + children.flatMap { accessibilityElements(in: $0) }
    }

    private func spokenText(of element: any NSAccessibility) -> String? {
        // AppKit はコントロールの種類に応じて label/title/value に読み上げ文言を格納する。
        [element.accessibilityLabel(), element.accessibilityTitle(), element.accessibilityValue() as? String]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }
}
