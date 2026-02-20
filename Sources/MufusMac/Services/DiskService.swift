import Foundation
import DiskArbitration
import IOKit
import IOKit.storage

class DiskService {
    
    static let shared = DiskService()
    
    private var session: DASession?
    private var callbackQueue: DispatchQueue
    
    private init() {
        callbackQueue = DispatchQueue(label: "com.mufusmac.disk", qos: .userInitiated)
        session = DASessionCreate(kCFAllocatorDefault)
        if let session = session {
            DASessionSetDispatchQueue(session, callbackQueue)
        }
    }
    
    /// Lists all removable USB drives using diskutil
    func listUSBDrives() -> [USBDevice] {
        let output = runCommand("/usr/sbin/diskutil", arguments: ["list", "-plist", "external", "physical"])
        guard let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let allDisks = plist["AllDisksAndPartitions"] as? [[String: Any]] else {
            return []
        }
        
        var devices: [USBDevice] = []
        
        for disk in allDisks {
            guard let deviceId = disk["DeviceIdentifier"] as? String else { continue }
            let size = disk["Size"] as? UInt64 ?? 0
            
            // Get more info via diskutil info
            let infoOutput = runCommand("/usr/sbin/diskutil", arguments: ["info", "-plist", deviceId])
            var name = ""
            var mountPoint: String? = nil
            
            if let infoData = infoOutput.data(using: .utf8),
               let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any] {
                name = info["MediaName"] as? String ?? info["VolumeName"] as? String ?? ""
                mountPoint = info["MountPoint"] as? String
                
                // Skip non-removable disks
                let removable = info["RemovableMediaOrExternalDevice"] as? Bool ?? false
                let isInternal = info["Internal"] as? Bool ?? true
                if !removable && isInternal { continue }
            }
            
            let device = USBDevice(
                id: deviceId,
                name: name,
                size: size,
                mountPoint: mountPoint,
                bsdName: "/dev/\(deviceId)"
            )
            devices.append(device)
        }
        
        return devices
    }
    
    /// Formats a USB drive with the given options
    func formatDrive(device: USBDevice, options: FlashOptions, log: @escaping (String) -> Void) throws {
        log("⏳ Unmounting disk \(device.id)...")
        let unmountResult = runCommand("/usr/sbin/diskutil", arguments: ["unmountDisk", "force", device.bsdName])
        log(unmountResult)
        
        let scheme = options.partitionScheme.diskutilScheme
        let format = options.fileSystem.diskutilFormat
        let label = options.volumeLabel.isEmpty ? "UNTITLED" : options.volumeLabel
        
        if options.createWindowsDataPartition {
            log("⏳ Partitioning \(device.id) in Dual Mode: Data (R) + Installer (\(label), 16G)...")
            
            // Format 1 is the Data partition (user's chosen FS)
            // Format 2 is the Installer partition (always ExFAT so Mac can boot it natively to install Windows)
            let partResult = runCommandPrivileged(
                "/usr/sbin/diskutil",
                arguments: ["partitionDisk", device.bsdName, "2", scheme, format, "WindowsData", "R", "ExFAT", label, "16G"]
            )
            
            if partResult.contains("Error") || partResult.contains("error") {
                throw FlashError.formatFailed(partResult)
            }
            log("✅ Dual Partition Format complete")
            log(partResult)
            
            if options.fileSystem.requiresNTFS3G {
                try formatDualDataPartitionAsNTFS(device: device, label: "WindowsData", log: log)
            }
            return
        }
        
        // Check if NTFS is requested (Single partition mode)
        if options.fileSystem.requiresNTFS3G {
            try formatAsNTFS(device: device, options: options, log: log)
            return
        }
        
        // Standard single partition format
        log("⏳ Formatting \(device.id) as \(format) with scheme \(scheme)...")
        log("   Volume label: \(label)")
        
        let formatResult = runCommandPrivileged(
            "/usr/sbin/diskutil",
            arguments: ["eraseDisk", format, label, scheme, device.bsdName]
        )
        
        if formatResult.contains("Error") || formatResult.contains("error") {
            throw FlashError.formatFailed(formatResult)
        }
        
        log("✅ Format complete")
        log(formatResult)
    }
    
    /// Checks if ntfs-3g is available on the system
    func isNTFS3GInstalled() -> Bool {
        let result = runCommand("/usr/bin/which", arguments: ["mkntfs"])
        if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !result.contains("not found") {
            return true
        }
        // Check common Homebrew paths
        let brewPaths = [
            "/usr/local/bin/mkntfs",
            "/opt/homebrew/bin/mkntfs",
            "/usr/local/sbin/mkntfs",
            "/opt/homebrew/sbin/mkntfs"
        ]
        return brewPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }
    
    /// Returns the path to mkntfs binary
    func mkntfsPath() -> String? {
        let paths = [
            "/usr/local/bin/mkntfs",
            "/opt/homebrew/bin/mkntfs",
            "/usr/local/sbin/mkntfs",
            "/opt/homebrew/sbin/mkntfs"
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    /// Formats the drive as NTFS using ntfs-3g's mkntfs
    private func formatAsNTFS(device: USBDevice, options: FlashOptions, log: @escaping (String) -> Void) throws {
        guard let mkntfs = mkntfsPath() else {
            log("❌ ntfs-3g is not installed!")
            log("💡 Install it with: brew install ntfs-3g-mac")
            throw FlashError.formatFailed("ntfs-3g is not installed. Install with: brew install ntfs-3g-mac")
        }
        
        let scheme = options.partitionScheme.diskutilScheme
        let label = options.volumeLabel.isEmpty ? "UNTITLED" : options.volumeLabel
        
        // Step 1: Partition the disk with diskutil (as FAT32 placeholder)
        log("⏳ Partitioning \(device.id) with \(scheme)...")
        let partResult = runCommandPrivileged(
            "/usr/sbin/diskutil",
            arguments: ["eraseDisk", "MS-DOS", label, scheme, device.bsdName]
        )
        
        if partResult.contains("Error") || partResult.contains("error") {
            throw FlashError.formatFailed(partResult)
        }
        log("✅ Partition created")
        
        // Step 2: Unmount the partition
        let unmountResult = runCommand("/usr/sbin/diskutil", arguments: ["unmountDisk", "force", device.bsdName])
        log(unmountResult)
        
        // Step 3: Identify the true data partition (s1 for MBR, s2 for GPT)
        var partition = "\(device.bsdName)s1"
        let listOutput = runCommand("/usr/sbin/diskutil", arguments: ["list", "-plist", device.id])
        if let listData = listOutput.data(using: .utf8),
           let listPlist = try? PropertyListSerialization.propertyList(from: listData, format: nil) as? [String: Any],
           let allDisks = listPlist["AllDisks"] as? [String] {
            if let lastPart = allDisks.filter({ $0 != device.id }).last {
                partition = "/dev/\(lastPart)"
            }
        }
        
        log("⏳ Formatting \(partition) as NTFS...")
        
        let ntfsResult = runCommandPrivileged(
            mkntfs,
            arguments: ["-f", "-L", label, partition]
        )
        
        if ntfsResult.contains("Error") || ntfsResult.contains("error") {
            // Some mkntfs versions output to stderr but succeed
            log("⚠️  mkntfs output: \(ntfsResult)")
        }
        
        log("✅ NTFS format complete")
        log(ntfsResult)
    }
    
    /// Formats only the Data partition as NTFS in Dual-Partition mode
    private func formatDualDataPartitionAsNTFS(device: USBDevice, label: String, log: @escaping (String) -> Void) throws {
        guard let mkntfs = mkntfsPath() else {
            throw FlashError.formatFailed("ntfs-3g is not installed. Install with: brew install ntfs-3g-mac")
        }
        
        log("⏳ Unmounting partitions for NTFS format...")
        let _ = runCommand("/usr/sbin/diskutil", arguments: ["unmountDisk", "force", device.bsdName])
        
        var targetPart = ""
        let listOutput = runCommand("/usr/sbin/diskutil", arguments: ["list", "-plist", device.id])
        if let listData = listOutput.data(using: .utf8),
           let listPlist = try? PropertyListSerialization.propertyList(from: listData, format: nil) as? [String: Any],
           let allDisks = listPlist["AllDisks"] as? [String] {
            
            for part in allDisks.filter({ $0 != device.id }) {
                let infoOutput = runCommand("/usr/sbin/diskutil", arguments: ["info", "-plist", part])
                if let infoData = infoOutput.data(using: .utf8),
                   let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
                   let volName = info["VolumeName"] as? String, volName.lowercased() == label.lowercased() {
                    targetPart = "/dev/\(part)"
                    break
                }
            }
        }
        
        if targetPart.isEmpty { throw FlashError.formatFailed("Could not find Data partition for NTFS formatting.") }
        
        log("⏳ Formatting \(targetPart) as NTFS...")
        let ntfsResult = runCommandPrivileged(mkntfs, arguments: ["-f", "-L", label, targetPart])
        if ntfsResult.contains("Error") || ntfsResult.contains("error") {
            log("⚠️  mkntfs output: \(ntfsResult)")
        }
        log("✅ NTFS format complete on Data partition")
    }
    
    /// Gets the mount point for a device after formatting
    func getMountPoint(for device: USBDevice, options: FlashOptions? = nil) -> String? {
        // 1. Get all partitions for this device
        let output = runCommand("/usr/sbin/diskutil", arguments: ["list", "-plist", device.id])
        guard let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let allDisks = plist["AllDisks"] as? [String] else {
            return fallbackGetMountPoint(for: device)
        }
        
        // Exclude the whole disk ID and reverse to prefer s2/s3 over s1 (EFI)
        let partitions = allDisks.filter { $0 != device.id }.reversed()
        
        for partition in partitions {
            let infoOutput = runCommand("/usr/sbin/diskutil", arguments: ["info", "-plist", partition])
            if let infoData = infoOutput.data(using: .utf8),
               let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
               let mount = info["MountPoint"] as? String, !mount.isEmpty {
                
                // Ignore EFI System Partitions which might be silently mounted
                let volumeName = (info["VolumeName"] as? String ?? "").lowercased()
                if volumeName != "efi" && !mount.lowercased().contains("/efi") {
                    
                    // In Dual-Partition mode, ensure we are targeting the Installer partition, not the WindowsData one
                    if let opts = options, opts.createWindowsDataPartition {
                        if volumeName == "windowsdata" {
                            continue // Skip the data partition, we want the installer one
                        }
                    }
                    return mount
                }
            }
        }
        
        return fallbackGetMountPoint(for: device)
    }
    
    private func fallbackGetMountPoint(for device: USBDevice) -> String? {
        let output = runCommand("/usr/sbin/diskutil", arguments: ["info", "-plist", device.id])
        if let data = output.data(using: .utf8),
           let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let mount = info["MountPoint"] as? String, !mount.isEmpty {
            return mount
        }
        return nil
    }
    
    // MARK: - Private Helpers
    
    func runCommand(_ command: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    func runCommandPrivileged(_ command: String, arguments: [String]) -> String {
        // Se siamo già root (es. app riavviata con privilegi), esegui normalmente ereditando i permessi
        if getuid() == 0 {
            return runCommand(command, arguments: arguments)
        }
        
        // Use osascript for admin privileges
        let script = "do shell script \"\(command) \(arguments.joined(separator: " "))\" with administrator privileges"
        
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

enum FlashError: LocalizedError {
    case formatFailed(String)
    case isoInvalid(String)
    case mountFailed(String)
    case copyFailed(String)
    case deviceNotFound
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .formatFailed(let msg): return "Format failed: \(msg)"
        case .isoInvalid(let msg): return "Invalid ISO: \(msg)"
        case .mountFailed(let msg): return "Mount failed: \(msg)"
        case .copyFailed(let msg): return "Copy failed: \(msg)"
        case .deviceNotFound: return "Device not found"
        case .cancelled: return "Operation cancelled"
        }
    }
}
