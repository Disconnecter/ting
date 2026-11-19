import AppKit
import AVFoundation
import ImageIO
import TingCore
import UniformTypeIdentifiers

/// Inspect bounded local movie data off the UI thread, after the privacy check.
enum ClipVideoCapture {
    static func isMovie(_ path: String) -> Bool {
        UTType(filenameExtension: (path as NSString).pathExtension)?.conforms(to: .movie) == true
    }

    static func needsInspection(_ capture: ClipCapture) -> Bool {
        capture.files.contains { isMovie($0.path) }
            || capture.representations.contains { ClipboardTypes.videoTypes.contains($0.type) }
    }

    static func prepare(_ original: ClipCapture) async -> ClipCapture {
        var capture = original
        capture.rejectedVideo = true
        let data: Data
        let type: String
        let name: String
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("io.bobuk.ting.video-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            if let file = capture.files.first, capture.files.count == 1, isMovie(file.path) {
                let source = URL(fileURLWithPath: file.path)
                guard ["mp4", "mov", "m4v"].contains(source.pathExtension.lowercased()) else { return capture }
                let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize,
                      size <= ClipHistory.maxItemBytes else { return capture }
                let handle = try FileHandle(forReadingFrom: source)
                defer { try? handle.close() }
                data = try handle.read(upToCount: ClipHistory.maxItemBytes + 1) ?? Data()
                type = source.pathExtension.lowercased() == "mov" ? ClipboardTypes.quickTime : ClipboardTypes.mpeg4
                name = file.name
            } else if capture.files.isEmpty,
                      let movie = capture.representations.first(where: { ClipboardTypes.videoTypes.contains($0.type) }) {
                data = movie.data
                type = movie.type
                name = "Video"
            } else { return capture }
            guard data.count <= ClipHistory.maxItemBytes, !data.isEmpty else { return capture }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent(type == ClipboardTypes.quickTime ? "clip.mov" : "clip.mp4")
            try data.write(to: url)
            // Inspect the exact owned bytes, not a source file that may change mid-capture.
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0, duration <= 30 else { return capture }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            let (image, _) = try await generator.image(at: .zero)
            let thumbnail = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(thumbnail, UTType.jpeg.identifier as CFString, 1, nil) else { return capture }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return capture }
            capture.files = []
            // Replace ephemeral source URLs with owned bytes; restart does not depend on the source file.
            capture.representations.removeAll { $0.type == ClipboardTypes.fileURL || ClipboardTypes.videoTypes.contains($0.type) }
            capture.representations.append(.init(type: type, data: data))
            capture.video = ClipVideoInfo(duration: duration, thumbnail: thumbnail as Data, name: name)
            capture.rejectedVideo = false
        } catch { /* Unreadable or unsupported movies are never retained as bare file references. */ }
        return capture
    }
}
