import Foundation
import AVFoundation
import CuelistCompilerKit

enum RecorderError: Error { case couldNotStart }

/// Concrete AudioRecorder backed by AVAudioRecorder. Records ~AAC m4a to a temp file.
@MainActor
final class AVAudioFileRecorder: AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        guard rec.record() else { throw RecorderError.couldNotStart }
        recorder = rec; fileURL = url
    }

    func stop() async -> URL? {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        let url = fileURL
        fileURL = nil
        return url
    }
}
