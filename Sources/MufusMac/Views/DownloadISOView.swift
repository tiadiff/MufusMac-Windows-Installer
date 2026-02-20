import SwiftUI

struct DownloadISOView: View {
    @ObservedObject var downloadService = DownloadService.shared
    @State private var selectedCategory: DownloadableISO.ISOCategory = .windows
    @State private var showDownloadProgress = false
    @State private var currentDownload: DownloadableISO? = nil
    
    var onISODownloaded: (URL) -> Void
    
    private var filteredISOs: [DownloadableISO] {
        DownloadService.availableISOs.filter { $0.category == selectedCategory }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Category picker
            Picker("Category", selection: $selectedCategory) {
                ForEach(DownloadableISO.ISOCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .tag(category)
                }
            }
            .pickerStyle(.segmented)
            .disabled(downloadService.isDownloading)
            
            // ISO list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(filteredISOs) { iso in
                        isoCard(iso)
                    }
                }
            }
            .frame(maxHeight: 300)
            
            // Download progress
            if showDownloadProgress {
                downloadProgressView
            }
        }
    }
    
    // MARK: - ISO Card
    
    private func isoCard(_ iso: DownloadableISO) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: categoryColors(iso.category),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                
                Image(systemName: iso.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(iso.name)
                    .font(.body.bold())
                
                Text(iso.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Text(iso.estimatedSize)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // Download button
            if downloadService.isDownloading && currentDownload?.id == iso.id {
                Button {
                    downloadService.cancelDownload()
                    showDownloadProgress = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            } else if iso.id == "win10" || iso.id == "win11" {
                // Windows official ISOs need browser download
                Button {
                    NSWorkspace.shared.open(iso.url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                        Text("Open")
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .help("Opens Microsoft download page in browser")
            } else if downloadService.isDownloaded(iso: iso) {
                // Already downloaded
                Button {
                    let localURL = downloadService.localPath(for: iso)
                    onISODownloaded(localURL)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Use Local")
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(downloadService.isDownloading)
            } else {
                Button {
                    startDownload(iso)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download")
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(downloadService.isDownloading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }
    
    // MARK: - Download Progress
    
    private var downloadProgressView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let dl = currentDownload {
                        Label(dl.name, systemImage: "arrow.down.doc.fill")
                            .font(.callout.bold())
                    }
                    Spacer()
                    
                    if downloadService.isDownloading {
                        Button("Cancel") {
                            downloadService.cancelDownload()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .font(.caption)
                    }
                }
                
                ProgressView(value: downloadService.downloadProgress, total: 1.0)
                    .tint(.blue)
                
                Text(downloadService.downloadStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let error = downloadService.downloadError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(4)
        }
    }
    
    // MARK: - Helpers
    
    private func startDownload(_ iso: DownloadableISO) {
        currentDownload = iso
        showDownloadProgress = true
        
        downloadService.download(
            iso: iso,
            progress: { _, _ in },
            completion: { result in
                switch result {
                case .success(let url):
                    onISODownloaded(url)
                case .failure(let error):
                    print("Download failed: \(error)")
                }
            }
        )
    }
    
    private func categoryColors(_ category: DownloadableISO.ISOCategory) -> [Color] {
        switch category {
        case .windows:
            return [Color(red: 0.0, green: 0.47, blue: 0.84), Color(red: 0.0, green: 0.35, blue: 0.72)]
        case .windowsLite:
            return [Color(red: 0.55, green: 0.24, blue: 0.78), Color(red: 0.42, green: 0.15, blue: 0.65)]
        case .linux:
            return [Color(red: 0.85, green: 0.35, blue: 0.13), Color(red: 0.72, green: 0.22, blue: 0.08)]
        }
    }
}
