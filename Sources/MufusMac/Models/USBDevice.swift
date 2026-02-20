import Foundation

struct USBDevice: Identifiable, Hashable {
    let id: String          // e.g. "disk2"
    let name: String        // e.g. "SanDisk Ultra"
    let size: UInt64        // size in bytes
    let mountPoint: String? // e.g. "/Volumes/USBDRIVE"
    let bsdName: String     // e.g. "/dev/disk2"
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    var displayName: String {
        let label = name.isEmpty ? "USB Drive" : name
        return "\(label) (\(formattedSize)) [\(id)]"
    }
}
