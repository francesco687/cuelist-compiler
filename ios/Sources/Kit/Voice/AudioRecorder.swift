import Foundation

/// Records mic audio to a file. Concrete AVFoundation impl lives in the app;
/// tests inject a mock.
@MainActor public protocol AudioRecorder: AnyObject {
    func requestPermission() async -> Bool
    func start() throws
    func stop() async -> URL?
}
