import Foundation
import Observation
@preconcurrency import WhisperKit
import os

private let logger = Logger(subsystem: "dev.mameli.steno", category: "transcription")

/// A Whisper model Steno offers. All are multilingual (Italian and English).
struct TranscriptionModel: Identifiable, Hashable, Sendable {
    /// The WhisperKit variant, i.e. the folder name in argmaxinc/whisperkit-coreml.
    let id: String
    let name: String
    let downloadMB: Int
    let note: LocalizedStringResource

    static let all = [
        TranscriptionModel(
            id: "openai_whisper-large-v3-v20240930_turbo_632MB", name: "Large v3 Turbo", downloadMB: 646,
            note: "Recommended: fast and accurate."
        ),
        TranscriptionModel(
            id: "openai_whisper-large-v3-v20240930_turbo", name: "Large v3 Turbo (full)", downloadMB: 1_638,
            note: "Slightly more accurate; more memory, slower to prepare."
        ),
        TranscriptionModel(
            id: "openai_whisper-small_216MB", name: "Small", downloadMB: 217,
            note: "Light and fast; more mistakes, especially in Italian."
        ),
    ]

    static let `default` = all[0]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The model chosen in Settings or in the menu; the default if the saved one is no longer offered.
    static var selected: TranscriptionModel {
        all.first { $0.id == AppSettings.transcriptionModelID } ?? .default
    }
}

/// The models on this Mac: which ones are downloaded, downloads in progress, deletion. A model
/// is downloaded once, from Settings or at the first Meeting that needs it; only one download
/// per model runs at a time.
@MainActor
@Observable
final class TranscriptionModels {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Steno/Models", directoryHint: .isDirectory)
    }

    /// Written next to a model once it is fully downloaded: a download interrupted halfway is
    /// resumed instead of being loaded.
    private static let downloadedMarker = ".steno-downloaded"

    /// Whole percent of the downloads in progress, by model.
    private(set) var progress: [String: Int] = [:]
    /// Changes whenever a model is downloaded or deleted, so views read the disk again.
    private(set) var revision = 0
    /// Called with every whole-percent step of a download (the menu updates its item in place).
    @ObservationIgnored var onProgress: (TranscriptionModel, Int) -> Void = { _, _ in }
    @ObservationIgnored private var downloads: [String: Task<URL, Error>] = [:]

    static func folder(of model: TranscriptionModel) -> URL {
        directory.appending(path: "models/argmaxinc/whisperkit-coreml/\(model.id)", directoryHint: .isDirectory)
    }

    func isDownloaded(_ model: TranscriptionModel) -> Bool {
        _ = revision
        return FileManager.default.fileExists(
            atPath: Self.folder(of: model).appending(path: Self.downloadedMarker).path(percentEncoded: false)
        )
    }

    var downloaded: [TranscriptionModel] {
        TranscriptionModel.all.filter(isDownloaded)
    }

    /// The model's folder, downloading it first if needed. `downloadedNow` is true when it was
    /// downloaded by this call (or by one already running): macOS then still has to prepare it.
    func ensureDownloaded(_ model: TranscriptionModel) async throws -> (folder: URL, downloadedNow: Bool) {
        if isDownloaded(model) { return (Self.folder(of: model), false) }
        let task = downloads[model.id] ?? startDownload(model)
        return (try await task.value, true)
    }

    /// Starts the download from Settings; errors are shown there.
    func download(_ model: TranscriptionModel) async throws {
        _ = try await ensureDownloaded(model)
    }

    func delete(_ model: TranscriptionModel) throws {
        try FileManager.default.removeItem(at: Self.folder(of: model))
        // WhisperKit's download metadata for that model: without it a new download starts clean.
        let metadata = Self.directory.appending(path: "models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/\(model.id)")
        try? FileManager.default.removeItem(at: metadata)
        revision += 1
    }

    private func startDownload(_ model: TranscriptionModel) -> Task<URL, Error> {
        progress[model.id] = 0
        onProgress(model, 0)
        // Strong references: the list lives as long as the app.
        let task = Task { () throws -> URL in
            defer {
                progress[model.id] = nil
                downloads[model.id] = nil
                revision += 1
            }
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            let folder = try await WhisperKit.download(variant: model.id, downloadBase: Self.directory) { progress in
                let percent = Int(progress.fractionCompleted * 100)
                Task { @MainActor in self.report(model, percent) }
            }
            try Data().write(to: folder.appending(path: Self.downloadedMarker))
            logger.info("Downloaded \(model.id, privacy: .public)")
            return folder
        }
        downloads[model.id] = task
        return task
    }

    /// Whole percents only, and never backwards: progress reports arrive many times a second
    /// and not always in order.
    private func report(_ model: TranscriptionModel, _ percent: Int) {
        guard let current = progress[model.id], percent > current else { return }
        progress[model.id] = percent
        onProgress(model, percent)
    }
}
