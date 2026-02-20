import Foundation

/// Represents a downloadable ISO image with metadata
struct DownloadableISO: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let url: URL
    let category: ISOCategory
    let icon: String
    let estimatedSize: String
    
    enum ISOCategory: String, CaseIterable, Identifiable {
        case windows = "Windows"
        case windowsLite = "Windows Lite"
        case linux = "Linux"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .windows: return "pc"
            case .windowsLite: return "memorychip"
            case .linux: return "terminal"
            }
        }
    }
}

/// Service for downloading ISO images from the internet
class DownloadService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadService()
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""
    @Published var downloadedFileURL: URL? = nil
    @Published var downloadError: String? = nil
    
    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession!
    private var destinationURL: URL?
    private var progressHandler: ((Double, String) -> Void)?
    private var completionHandler: ((Result<URL, Error>) -> Void)?
    
    // MARK: - Available ISOs
    
    static let availableISOs: [DownloadableISO] = [
        // Windows
        DownloadableISO(
            id: "win10",
            name: "Windows 10",
            description: "Official Windows 10 ISO (download from Microsoft)",
            url: URL(string: "https://www.microsoft.com/en-us/software-download/windows10ISO")!,
            category: .windows,
            icon: "desktopcomputer",
            estimatedSize: "~5.8 GB"
        ),
        DownloadableISO(
            id: "win11",
            name: "Windows 11",
            description: "Official Windows 11 ISO (download from Microsoft)",
            url: URL(string: "https://www.microsoft.com/en-us/software-download/windows11")!,
            category: .windows,
            icon: "desktopcomputer",
            estimatedSize: "~6.2 GB"
        ),
        
        // Windows Lite
        DownloadableISO(
            id: "tiny10",
            name: "Tiny10 (x64 23H2)",
            description: "Windows 10 Lightweight — Version 23H2 x64",
            url: URL(string: "https://archive.org/download/tiny-10-23-h2/tiny10%20x64%2023h2.iso")!,
            category: .windowsLite,
            icon: "gauge.with.dots.needle.33percent",
            estimatedSize: "~4 GB"
        ),
        DownloadableISO(
            id: "tiny11",
            name: "Tiny11 (x64 2311)",
            description: "Windows 11 Lightweight — Version 2311 x64",
            url: URL(string: "https://archive.org/download/tiny11-2311/tiny11%202311%20x64.iso")!,
            category: .windowsLite,
            icon: "gauge.with.dots.needle.33percent",
            estimatedSize: "~4 GB"
        ),
        
        // Linux
        DownloadableISO(
            id: "ubuntu-2404",
            name: "Ubuntu 24.04 LTS",
            description: "Ubuntu Desktop — Long Term Support",
            url: URL(string: "https://releases.ubuntu.com/24.04/ubuntu-24.04.1-desktop-amd64.iso")!,
            category: .linux,
            icon: "terminal.fill",
            estimatedSize: "~5.7 GB"
        ),
        DownloadableISO(
            id: "ubuntu-2404-server",
            name: "Ubuntu 24.04 Server",
            description: "Ubuntu Server — Long Term Support",
            url: URL(string: "https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso")!,
            category: .linux,
            icon: "server.rack",
            estimatedSize: "~2.6 GB"
        ),
    ]
    
    // MARK: - Init
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 86400 // 24 hours for large downloads
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    // MARK: - Download
    
    func download(
        iso: DownloadableISO,
        to directory: URL? = nil,
        progress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        // Download destination
        destinationURL = localPath(for: iso, in: directory)
        
        progressHandler = progress
        completionHandler = completion
        
        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "Connecting to server..."
        downloadError = nil
        
        downloadTask = session.downloadTask(with: iso.url)
        downloadTask?.resume()
    }
    
    /// Helper to find the real user's Download directory even when the app is running as root
    private func getRealUserDownloadsDirectory() -> URL {
        if getuid() == 0 {
            // Se l'app gira come root, .downloadsDirectory punterebbe a /var/root/Downloads.
            // Troviamo l'utente loggato reale controllando il proprietario di /dev/console
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/stat")
            process.arguments = ["-f", "%Su", "/dev/console"]
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let username = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty, username != "root" {
                    return URL(fileURLWithPath: "/Users/\(username)/Downloads")
                }
            } catch {
                print("Impossibile determinare l'utente reale: \(error)")
            }
        }
        
        // Fallback al comportamento standard
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }
    
    /// Returns the local path where an ISO would be stored
    func localPath(for iso: DownloadableISO, in directory: URL? = nil) -> URL {
        let downloadsDir = directory ?? getRealUserDownloadsDirectory()
        let fileName = iso.url.lastPathComponent.removingPercentEncoding ?? iso.url.lastPathComponent
        return downloadsDir.appendingPathComponent(fileName)
    }
    
    /// Checks if an ISO file is already present in the Downloads folder
    func isDownloaded(iso: DownloadableISO) -> Bool {
        let path = localPath(for: iso)
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        isDownloading = false
        downloadProgress = 0.0
        downloadStatus = "Cancelled"
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destinationURL = destinationURL else { return }
        
        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            isDownloading = false
            downloadProgress = 1.0
            downloadStatus = "Download complete!"
            downloadedFileURL = destinationURL
            completionHandler?(.success(destinationURL))
        } catch {
            isDownloading = false
            downloadError = error.localizedDescription
            completionHandler?(.failure(error))
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            downloadProgress = progress
            let downloaded = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)
            let status = "Downloading: \(downloaded) / \(total) (\(Int(progress * 100))%)"
            downloadStatus = status
            progressHandler?(progress, status)
        } else {
            let downloaded = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
            downloadStatus = "Downloading: \(downloaded)..."
            progressHandler?(0.0, downloadStatus)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error = error {
            DispatchQueue.main.async { [weak self] in
                self?.isDownloading = false
                self?.downloadError = error.localizedDescription
                self?.downloadStatus = "Download failed"
                self?.completionHandler?(.failure(error))
            }
        }
    }
}
