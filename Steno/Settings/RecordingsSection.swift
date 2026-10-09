import AppKit
import SwiftUI

/// The audio kept on this Mac: how long, how much, where, and deleting it ahead of time.
struct RecordingsSection: View {
    @State private var days = AppSettings.retentionDays
    @State private var size: Int64 = 0
    @State private var isConfirmingDeletion = false

    var body: some View {
        Section {
            Stepper(value: $days, in: 1...90) {
                Text("Keep audio for \(days) days")
            }
            // Applied by the cleanup at launch and once a day: a click too many on the Stepper
            // must not delete audio on the spot.
            .onChange(of: days) { AppSettings.retentionDays = days }
            LabeledContent("Audio on this Mac") {
                HStack {
                    Text(size.formatted(.byteCount(style: .file)))
                    Button("Show in Finder", action: showInFinder)
                    Button("Delete audio", role: .destructive) { isConfirmingDeletion = true }
                        .disabled(size == 0)
                }
            }
        } header: {
            Text("Recordings")
        } footer: {
            Text("About 20 MB per hour of Meeting. Notes and Transcripts stay in the Vault: without the audio, Retry makes only the Summary again.")
                .foregroundStyle(.secondary)
        }
        .onAppear { size = RecordingStorage.audioSize() }
        .confirmationDialog(
            String(localized: "Delete the audio of all concluded Meetings?"),
            isPresented: $isConfirmingDeletion
        ) {
            Button("Delete audio", role: .destructive) {
                RecordingStorage.deleteAudio(olderThanDays: 0)
                size = RecordingStorage.audioSize()
            }
        } message: {
            Text("It cannot be undone. Meetings being recorded or processed are not touched.")
        }
    }

    private func showInFinder() {
        let folder = MeetingRecorder.recordingsDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
