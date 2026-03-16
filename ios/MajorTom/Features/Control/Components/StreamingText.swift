import SwiftUI

struct StreamingText: View {
    let text: String
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(text)
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .textSelection(.enabled)

            if isStreaming {
                BlinkingCursor()
            }
        }
    }
}

struct BlinkingCursor: View {
    @State private var isVisible = true

    var body: some View {
        Text("▋")
            .font(MajorTomTheme.Typography.body)
            .foregroundStyle(MajorTomTheme.Colors.accent)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(), value: isVisible)
            .task {
                isVisible = false
            }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        StreamingText(text: "I'm analyzing the code...", isStreaming: true)
        StreamingText(text: "Done analyzing.", isStreaming: false)
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
