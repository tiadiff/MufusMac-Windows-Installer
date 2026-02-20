import Foundation

/// Detected operating system type from ISO filename or download selection
enum DetectedOS: String, CaseIterable, Identifiable {
    case windows10 = "Windows 10"
    case windows11 = "Windows 11"
    case tiny10 = "Tiny10"
    case tiny11 = "Tiny11"
    case ubuntu = "Ubuntu"
    case ubuntuServer = "Ubuntu Server"
    case linuxGeneric = "Linux"
    case unknown = "Unknown"
    
    var id: String { rawValue }
    
    /// Recommended formatting preset for this OS
    var preset: FlashPreset {
        switch self {
        case .windows10:
            return FlashPreset(
                partitionScheme: .mbr,
                targetSystem: .bios,
                fileSystem: .ntfs,
                volumeLabel: "WIN10",
                description: "Windows 10 — MBR/BIOS with NTFS (max compatibility)",
                minDriveSize: 8 * 1024 * 1024 * 1024 // 8 GB
            )
        case .windows11:
            return FlashPreset(
                partitionScheme: .gpt,
                targetSystem: .uefi,
                fileSystem: .ntfs,
                volumeLabel: "WIN11",
                description: "Windows 11 — GPT/UEFI with NTFS (required for W11)",
                minDriveSize: 8 * 1024 * 1024 * 1024
            )
        case .tiny10:
            return FlashPreset(
                partitionScheme: .mbr,
                targetSystem: .bios,
                fileSystem: .ntfs,
                volumeLabel: "TINY10",
                description: "Tiny10 — MBR/BIOS with NTFS (lightweight W10)",
                minDriveSize: 4 * 1024 * 1024 * 1024 // 4 GB
            )
        case .tiny11:
            return FlashPreset(
                partitionScheme: .gpt,
                targetSystem: .uefi,
                fileSystem: .ntfs,
                volumeLabel: "TINY11",
                description: "Tiny11 — GPT/UEFI with NTFS (lightweight W11)",
                minDriveSize: 4 * 1024 * 1024 * 1024
            )
        case .ubuntu, .linuxGeneric:
            return FlashPreset(
                partitionScheme: .gpt,
                targetSystem: .uefi,
                fileSystem: .fat32,
                volumeLabel: "UBUNTU",
                description: "Ubuntu/Linux — GPT/UEFI with FAT32 (standard boot)",
                minDriveSize: 4 * 1024 * 1024 * 1024
            )
        case .ubuntuServer:
            return FlashPreset(
                partitionScheme: .gpt,
                targetSystem: .uefi,
                fileSystem: .fat32,
                volumeLabel: "UBUNTUSRV",
                description: "Ubuntu Server — GPT/UEFI with FAT32",
                minDriveSize: 2 * 1024 * 1024 * 1024
            )
        case .unknown:
            return FlashPreset(
                partitionScheme: .gpt,
                targetSystem: .uefi,
                fileSystem: .fat32,
                volumeLabel: "MUFUSMAC",
                description: "Generic — GPT/UEFI with FAT32 (safe default)",
                minDriveSize: 1 * 1024 * 1024 * 1024
            )
        }
    }
    
    /// Icon for UI display
    var icon: String {
        switch self {
        case .windows10, .windows11: return "desktopcomputer"
        case .tiny10, .tiny11: return "gauge.with.dots.needle.33percent"
        case .ubuntu, .ubuntuServer, .linuxGeneric: return "terminal.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    /// Detect OS from ISO filename
    static func detect(from filename: String) -> DetectedOS {
        let lower = filename.lowercased()
        
        // Tiny variants (check first — they also contain "win" patterns)
        if lower.contains("tiny10") || lower.contains("tiny 10") {
            return .tiny10
        }
        if lower.contains("tiny11") || lower.contains("tiny 11") {
            return .tiny11
        }
        
        // Windows
        if lower.contains("win10") || lower.contains("windows10") || lower.contains("windows_10") || lower.contains("win_10") || (lower.contains("windows") && lower.contains("10")) {
            return .windows10
        }
        if lower.contains("win11") || lower.contains("windows11") || lower.contains("windows_11") || lower.contains("win_11") || (lower.contains("windows") && lower.contains("11")) {
            return .windows11
        }
        
        // Ubuntu
        if lower.contains("ubuntu") {
            if lower.contains("server") || lower.contains("live-server") {
                return .ubuntuServer
            }
            return .ubuntu
        }
        
        // Generic Linux
        if lower.contains("linux") || lower.contains("fedora") || lower.contains("debian") || lower.contains("mint") || lower.contains("arch") || lower.contains("manjaro") || lower.contains("opensuse") || lower.contains("centos") || lower.contains("kali") {
            return .linuxGeneric
        }
        
        return .unknown
    }
    
    /// Detect OS from download catalog selection
    static func detect(fromDownloadId id: String) -> DetectedOS {
        switch id {
        case "win10": return .windows10
        case "win11": return .windows11
        case "tiny10": return .tiny10
        case "tiny11": return .tiny11
        case "ubuntu-2404": return .ubuntu
        case "ubuntu-2404-server": return .ubuntuServer
        default: return .unknown
        }
    }
}

/// Recommended formatting settings for a detected OS
struct FlashPreset {
    let partitionScheme: PartitionScheme
    let targetSystem: TargetSystem
    let fileSystem: FileSystemType
    let volumeLabel: String
    let description: String
    let minDriveSize: UInt64 // minimum USB size in bytes
    
    /// Apply this preset to FlashOptions
    func apply(to options: inout FlashOptions) {
        options.partitionScheme = partitionScheme
        options.targetSystem = targetSystem
        options.fileSystem = fileSystem
        options.volumeLabel = volumeLabel
    }
    
    var minDriveSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(minDriveSize), countStyle: .file)
    }
}
