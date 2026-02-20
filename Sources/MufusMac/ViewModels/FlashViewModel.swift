import Foundation
import SwiftUI

@Observable
class FlashViewModel {
    // State
    var devices: [USBDevice] = []
    var selectedDevice: USBDevice? = nil
    var selectedISO: URL? = nil
    var isoInfo: ISOInfo? = nil
    var options = FlashOptions()
    var detectedOS: DetectedOS = .unknown
    var autoPresetApplied: Bool = false
    var driveSizeWarning: String? = nil
    var installBootCampDrivers: Bool = false
    
    // Progress
    var progress: Double = 0.0
    var statusText: String = "Ready"
    var logMessages: [String] = []
    var isFlashing: Bool = false
    var isComplete: Bool = false
    var errorMessage: String? = nil
    
    // Services
    private let diskService = DiskService.shared
    private let isoService = ISOService.shared
    private let bootCampService = BootCampService.shared
    
    init() {
        refreshDevices()
    }
    
    // MARK: - Actions
    
    func refreshDevices() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let foundDevices = DiskService.shared.listUSBDrives()
            DispatchQueue.main.async {
                self?.devices = foundDevices
                if let current = self?.selectedDevice,
                   !foundDevices.contains(where: { $0.id == current.id }) {
                    self?.selectedDevice = foundDevices.first
                }
                if self?.selectedDevice == nil {
                    self?.selectedDevice = foundDevices.first
                }
                self?.appendLog("🔍 Found \(foundDevices.count) USB device(s)")
            }
        }
    }
    
    func selectISO() {
        let panel = NSOpenPanel()
        panel.title = "Select ISO Image"
        panel.message = "Choose an ISO file to write to the USB drive"
        panel.allowedContentTypes = [.init(filenameExtension: "iso")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            applyISO(url: url)
        }
    }
    
    /// Apply an ISO file — validates it, detects OS, and auto-applies the preset
    func applyISO(url: URL) {
        do {
            let info = try isoService.validateISO(at: url)
            selectedISO = url
            isoInfo = info
            appendLog("📀 Selected: \(info.fileName) (\(info.formattedSize))")
            
            // Auto-detect OS and apply preset
            let detected = DetectedOS.detect(from: url.lastPathComponent)
            applyOSPreset(detected)
        } catch {
            selectedISO = nil
            isoInfo = nil
            detectedOS = .unknown
            autoPresetApplied = false
            installBootCampDrivers = false
            errorMessage = error.localizedDescription
            appendLog("❌ \(error.localizedDescription)")
        }
    }
    
    /// Apply an ISO from the download catalog
    func applyDownloadedISO(url: URL, downloadId: String) {
        do {
            let info = try isoService.validateISO(at: url)
            selectedISO = url
            isoInfo = info
            appendLog("📀 Downloaded: \(info.fileName) (\(info.formattedSize))")
            
            // Detect from download ID (more accurate than filename)
            let detected = DetectedOS.detect(fromDownloadId: downloadId)
            applyOSPreset(detected)
        } catch {
            // If validation fails (e.g. zip file for tiny11), still set it
            selectedISO = url
            isoInfo = nil
            let detected = DetectedOS.detect(fromDownloadId: downloadId)
            applyOSPreset(detected)
            appendLog("⚠️ File selected but ISO validation skipped: \(error.localizedDescription)")
        }
    }
    
    /// Apply OS preset to formatting options
    private func applyOSPreset(_ os: DetectedOS) {
        detectedOS = os
        let preset = os.preset
        preset.apply(to: &options)
        autoPresetApplied = true
        
        // Auto-enable Boot Camp drivers for Windows if on Mac (can be disabled by user)
        if os == .windows10 || os == .windows11 || os == .tiny10 || os == .tiny11 {
            installBootCampDrivers = true
        } else {
            installBootCampDrivers = false
        }
        
        appendLog("🔍 Detected OS: \(os.rawValue)")
        appendLog("⚙️  Auto-configured: \(preset.description)")
        appendLog("   Partition: \(preset.partitionScheme.displayName)")
        appendLog("   Target: \(preset.targetSystem.displayName)")
        appendLog("   File System: \(preset.fileSystem.displayName)")
        appendLog("   Min drive: \(preset.minDriveSizeFormatted)")
        if installBootCampDrivers {
            appendLog("   Boot Camp: Driver injection enabled")
        }
        
        // Check drive size
        checkDriveSize()
    }
    
    /// Check if selected drive is large enough
    func checkDriveSize() {
        guard let device = selectedDevice else {
            driveSizeWarning = nil
            return
        }
        let minSize = detectedOS.preset.minDriveSize
        if device.size > 0 && device.size < minSize {
            let needed = ByteCountFormatter.string(fromByteCount: Int64(minSize), countStyle: .file)
            let have = device.formattedSize
            driveSizeWarning = "Drive too small! Need at least \(needed), but \(device.displayName) is only \(have)"
            appendLog("⚠️ \(driveSizeWarning!)")
        } else {
            driveSizeWarning = nil
        }
    }
    
    func startFlash() {
        guard let device = selectedDevice else {
            errorMessage = "No USB device selected"
            return
        }
        guard let isoURL = selectedISO else {
            errorMessage = "No ISO file selected"
            return
        }
        
        // Check drive size before starting
        let minSize = detectedOS.preset.minDriveSize
        if device.size > 0 && device.size < minSize {
            let needed = ByteCountFormatter.string(fromByteCount: Int64(minSize), countStyle: .file)
            errorMessage = "USB drive is too small. You need at least \(needed) for \(detectedOS.rawValue)."
            return
        }
        
        isFlashing = true
        isComplete = false
        progress = 0.0
        errorMessage = nil
        statusText = "Starting..."
        
        appendLog("═══════════════════════════════════════")
        appendLog("🚀 Starting flash operation")
        appendLog("   OS: \(detectedOS.rawValue)")
        appendLog("   Device: \(device.displayName)")
        appendLog("   ISO: \(isoURL.lastPathComponent)")
        appendLog("   File System: \(options.fileSystem.displayName)")
        appendLog("   Partition: \(options.partitionScheme.displayName)")
        appendLog("   Target: \(options.targetSystem.displayName)")
        appendLog("   Boot Camp Drivers: \(installBootCampDrivers ? "Yes" : "No")")
        appendLog("═══════════════════════════════════════")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Determine destination path first (we'll need it for BootCamp)
                var destPath = ""
                
                try self.isoService.writeISO(
                    at: isoURL,
                    to: device,
                    options: self.options,
                    progress: { value, status in
                        DispatchQueue.main.async {
                            // Scale ISO writing to 0.0 - 0.8
                            self.progress = value * 0.8
                            self.statusText = status
                        }
                    },
                    log: { message in
                        DispatchQueue.main.async {
                            self.appendLog(message)
                            // Sniff the mount point from logs to pass to BootCamp process
                            if message.starts(with: "✅ USB drive mounted at: ") {
                                destPath = message.replacingOccurrences(of: "✅ USB drive mounted at: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                )
                
                // If Boot Camp drivers are requested, inject them now
                if self.installBootCampDrivers {
                    if destPath.isEmpty {
                        // Backup check if sniffing failed
                        destPath = DiskService.shared.getMountPoint(for: device) ?? ""
                    }
                    
                    if !destPath.isEmpty {
                        try self.bootCampService.downloadBootCampDrivers(
                            to: destPath,
                            log: { message in
                                DispatchQueue.main.async {
                                    self.appendLog(message)
                                }
                            },
                            progressCallback: { bootCampProgress, status in
                                DispatchQueue.main.async {
                                    // Scale Boot Camp progress to 0.8 - 0.95
                                    self.progress = 0.8 + (bootCampProgress * 0.15)
                                    self.statusText = status
                                }
                            }
                        )
                    } else {
                        DispatchQueue.main.async {
                            self.appendLog("⚠️ Impossibile trovare il punto di mount per installare i driver Boot Camp.")
                        }
                    }
                }
                
                // Final Sync
                DispatchQueue.main.async {
                    self.progress = 0.98
                    self.statusText = "Syncing data to drive..."
                }
                let _ = DiskService.shared.runCommand("/bin/sync", arguments: [])
                
                DispatchQueue.main.async {
                    self.progress = 1.0
                    self.isFlashing = false
                    self.isComplete = true
                    self.statusText = "Complete! ✅"
                    self.appendLog("🎉 Operazione completata con successo!")
                }
            } catch {
                DispatchQueue.main.async {
                    self.isFlashing = false
                    self.progress = 0.0
                    self.statusText = "Error"
                    self.errorMessage = error.localizedDescription
                    self.appendLog("❌ Errore: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func cancelFlash() {
        isoService.cancel()
        appendLog("⛔ Cancellation requested...")
    }
    
    // MARK: - Helpers
    
    var canStart: Bool {
        selectedDevice != nil && selectedISO != nil && !isFlashing
    }
    
    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logMessages.append("[\(timestamp)] \(message)")
    }
}
