import SwiftUI

struct VoiceInputButton: View {
    @Bindable var speechService: SpeechService
    var onTranscription: (String) -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var showTranscriptionPopover = false

    var body: some View {
        Button {
            HapticService.buttonTap()
            handleTap()
        } label: {
            ZStack {
                // Pulsing background when recording
                if speechService.isRecording {
                    Circle()
                        .fill(MajorTomTheme.Colors.deny.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .scaleEffect(pulseScale)
                }

                Image(systemName: speechService.isRecording ? "mic.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(
                        speechService.isRecording
                            ? MajorTomTheme.Colors.deny
                            : MajorTomTheme.Colors.textSecondary
                    )
            }
        }
        .onChange(of: speechService.isRecording) { _, isRecording in
            if isRecording {
                startPulse()
            } else {
                pulseScale = 1.0
                showTranscriptionPopover = false
                // Send transcription when recording stops
                let text = speechService.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    onTranscription(text)
                }
            }
        }
        .onChange(of: speechService.transcribedText) {
            showTranscriptionPopover = speechService.isRecording && !speechService.transcribedText.isEmpty
        }
        .popover(isPresented: $showTranscriptionPopover) {
            transcriptionPreview
                .presentationCompactAdaptation(.popover)
        }
    }

    private var transcriptionPreview: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                Circle()
                    .fill(MajorTomTheme.Colors.deny)
                    .frame(width: 8, height: 8)
                Text("Listening...")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }

            Text(speechService.transcribedText)
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .lineLimit(3)
        }
        .padding(MajorTomTheme.Spacing.md)
        .frame(maxWidth: 280)
        .background(MajorTomTheme.Colors.surfaceElevated)
    }

    private func handleTap() {
        if !speechService.isAuthorized {
            Task {
                await speechService.requestAuthorization()
                if speechService.isAuthorized {
                    speechService.toggleRecording()
                }
            }
        } else {
            speechService.toggleRecording()
        }
    }

    private func startPulse() {
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.4
        }
    }
}

#Preview {
    VoiceInputButton(
        speechService: SpeechService(),
        onTranscription: { text in
            print("Transcribed: \(text)")
        }
    )
    .padding()
    .background(MajorTomTheme.Colors.background)
    .preferredColorScheme(.dark)
}
