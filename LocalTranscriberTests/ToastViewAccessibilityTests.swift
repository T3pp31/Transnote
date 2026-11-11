import AppKit
import ApplicationServices
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
        let elements = try await renderedAccessibilityElements(in: contentView)
        let buttons = elements.filter { $0.accessibilityRole?() == .button }
        XCTAssertEqual(buttons.count, 1)
        let button = try XCTUnwrap(buttons.first)
        XCTAssertEqual(spokenText(of: button), message.action?.label)
        XCTAssertNotEqual(spokenText(of: button), message.text)
        let messageTexts = elements.filter {
            $0.accessibilityRole?() == .staticText && spokenText(of: $0) == message.text
        }
        XCTAssertEqual(messageTexts.count, 1, "本文は独立したテキストとして1回だけ公開する")
        XCTAssertFalse(elements.contains { $0.accessibilityRole?() == .image }, "装飾アイコンは読み上げない")

        XCTAssertTrue(button.accessibilityPerformPress?() ?? false)
        await fulfillment(of: [actionPerformed], timeout: 2)
    }

    func testToastWithoutActionExposesMessageButNoImageOrButton() async throws {
        let message = ToastMessage(
            text: "文字起こし結果をコピーしました",
            icon: "checkmark.circle.fill"
        )
        let window = host(message)
        defer { window.close() }

        let contentView = try XCTUnwrap(window.contentView)
        let elements = try await renderedAccessibilityElements(in: contentView)
        let texts = elements.filter { $0.accessibilityRole?() == .staticText }
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(spokenText(of: try XCTUnwrap(texts.first)), message.text)
        XCTAssertFalse(elements.contains { $0.accessibilityRole?() == .button })
        XCTAssertFalse(elements.contains { $0.accessibilityRole?() == .image }, "装飾アイコンは読み上げない")
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

    private func accessibilityElements(in element: AnyObject) -> [AnyObject] {
        let children = (element.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        let current: [AnyObject] = (element.isAccessibilityElement?() ?? false) ? [element] : []
        return current + children.flatMap { accessibilityElements(in: $0) }
    }

    private func renderedAccessibilityElements(in view: NSView) async throws -> [AnyObject] {
        let result = await Task.detached {
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            var role: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &role)
            return error
        }.value
        XCTAssertEqual(result, .success)
        view.layoutSubtreeIfNeeded()
        view.window?.displayIfNeeded()
        return accessibilityElements(in: view)
    }

    private func spokenText(of element: AnyObject) -> String? {
        // SwiftUI の仮想ノードは NSAccessibilityProtocol に準拠しないため Objective-C で値を読む。
        let value: Any? = element.accessibilityValue?()
        return [element.accessibilityLabel?(), element.accessibilityTitle?(), value as? String]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }
}
