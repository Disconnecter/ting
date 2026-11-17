import Foundation

/// The macOS system sounds that Ting can play when it opens something.
public enum SystemSounds {
    /// The folder of the built-in macOS alert sounds.
    public static let defaultFolder = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
    /// The sound Ting plays by default, and when the configured one cannot be loaded.
    public static let defaultName = "Tink"
    /// File extensions treated as sound files (lowercased).
    public static let soundExtensions: Set<String> = ["aiff", "aif", "aifc", "caf", "wav", "mp3", "m4a"]

    /// Sorted, unique names without extension of the regular sound files directly in `folder`.
    /// A missing or unreadable folder gives an empty list.
    public static func names(in folder: URL = defaultFolder) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        let names = files
            .filter { soundExtensions.contains($0.pathExtension.lowercased()) }
            // A folder named like a sound ("Folder.aiff") is not a sound file.
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.deletingPathExtension().lastPathComponent }
        return Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
