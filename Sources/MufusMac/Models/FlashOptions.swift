import Foundation

enum PartitionScheme: String, CaseIterable, Identifiable {
    case gpt = "GPT"
    case mbr = "MBR"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .gpt: return "GPT (GUID Partition Table)"
        case .mbr: return "MBR (Master Boot Record)"
        }
    }
    
    var diskutilScheme: String {
        switch self {
        case .gpt: return "GPTFormat"
        case .mbr: return "MBRFormat"
        }
    }
}

enum TargetSystem: String, CaseIterable, Identifiable {
    case uefi = "UEFI"
    case bios = "BIOS"
    case uefiBios = "UEFI+BIOS"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .uefi: return "UEFI (non CSM)"
        case .bios: return "BIOS (o UEFI-CSM)"
        case .uefiBios: return "UEFI + BIOS"
        }
    }
}

enum FileSystemType: String, CaseIterable, Identifiable {
    case fat32 = "FAT32"
    case ntfs = "NTFS"
    case exfat = "ExFAT"
    case apfs = "APFS"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .fat32: return "FAT32 (Sconsigliato)"
        case .exfat: return "ExFAT"
        case .ntfs: return "NTFS"
        case .apfs: return "APFS"
        }
    }
    
    var diskutilFormat: String {
        switch self {
        case .fat32: return "MS-DOS"
        case .ntfs: return "ExFAT" // Format as ExFAT first, then reformat with ntfs-3g
        case .exfat: return "ExFAT"
        case .apfs: return "APFS"
        }
    }
    
    var requiresNTFS3G: Bool {
        self == .ntfs
    }
}

struct FlashOptions {
    var partitionScheme: PartitionScheme = .gpt
    var targetSystem: TargetSystem = .uefi
    var fileSystem: FileSystemType = .fat32
    var volumeLabel: String = "MUFUSMAC"
    var createWindowsDataPartition: Bool = false
    var createWindowsToGoScript: Bool = false
}
