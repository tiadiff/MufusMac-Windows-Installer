import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
                
                Image(systemName: "externaldrive.fill.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            
            // App Name
            VStack(spacing: 4) {
                Text("MufusMac")
                    .font(.title.bold())
                
                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Description
            Text("A macOS utility for creating bootable USB drives from ISO images. Inspired by Rufus for Windows.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Features
            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "externaldrive.fill", text: "USB drive detection & formatting")
                featureRow(icon: "opticaldisc.fill", text: "ISO image validation & writing")
                featureRow(icon: "shield.checkered", text: "UEFI & BIOS boot support")
                featureRow(icon: "gearshape.fill", text: "GPT/MBR partition schemes")
                featureRow(icon: "internaldrive.fill", text: "FAT32, ExFAT, APFS file systems")
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Close
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(30)
        .frame(width: 400, height: 480)
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AboutView()
}
