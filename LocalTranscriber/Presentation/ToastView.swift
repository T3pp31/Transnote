import SwiftUI

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    var icon: String
    var action: (label: String, handler: @Sendable () -> Void)?
}

extension ToastMessage: Equatable {
    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        // `handler` はクロージャのため比較できないので無視する
        lhs.id == rhs.id
            && lhs.text == rhs.text
            && lhs.icon == rhs.icon
    }
}
struct ToastView: View {
    let message: ToastMessage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.icon)
                .foregroundStyle(.green)
            Text(message.text)
                .font(.subheadline)
            if let action = message.action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(action.label)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border(colorScheme), lineWidth: 1)
        }
        .shadow(color: DesignTokens.Colors.toastShadow(colorScheme), radius: 8, y: 2)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityLabel(message.text)
    }
}
