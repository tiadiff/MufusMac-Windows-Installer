import SwiftUI

struct ContentView: View {
    @State private var viewModel = FlashViewModel()
    @State private var showConfirmation = false
    @State private var showAbout = false
    @State private var showDownloadSection = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.5)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    headerSection
                    
                    VStack(spacing: 16) {
                        // Device Selection
                        deviceSection
                        
                        // ISO Selection
                        isoSection
                        
                        // Download ISO Section (collapsible)
                        downloadSection
                        
                        Divider()
                            .padding(.horizontal)
                        
                        // Options
                        optionsSection
                        
                        // NTFS warning
                        if viewModel.options.fileSystem == .ntfs {
                            ntfsWarning
                        }
                        
                        Divider()
                            .padding(.horizontal)
                        
                        // Action
                        actionSection
                        
                        // Progress
                        if viewModel.isFlashing || viewModel.isComplete {
                            progressSection
                        }
                        
                        // Log
                        logSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .alert("Confirm Operation", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Format & Write", role: .destructive) {
                viewModel.startFlash()
            }
        } message: {
            Text("⚠️ WARNING: All data on \(viewModel.selectedDevice?.displayName ?? "the selected drive") will be PERMANENTLY ERASED.\n\nThis action cannot be undone.\n\nAre you sure you want to continue?")
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("MufusMac")
                    .font(.title.bold())
                
                Text("Bootable USB Creator")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("v1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Device Section
    
    private var deviceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("USB Device", systemImage: "externaldrive.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    if viewModel.devices.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("No USB drives detected")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Picker("", selection: $viewModel.selectedDevice) {
                            ForEach(viewModel.devices) { device in
                                HStack {
                                    Image(systemName: "externaldrive.fill")
                                    Text(device.displayName)
                                }
                                .tag(device as USBDevice?)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 100)
                    }
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.refreshDevices()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.bold())
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh USB device list")
                    .disabled(viewModel.isFlashing)
                }
            }
            .padding(4)
        }
    }
    
    // MARK: - ISO Section
    
    private var isoSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Boot Selection", systemImage: "opticaldisc.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let info = viewModel.isoInfo {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(info.fileName)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Text(info.formattedSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.badge.plus")
                                    .foregroundStyle(.secondary)
                                Text("No ISO image selected")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button("SELECT") {
                        viewModel.selectISO()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(viewModel.isFlashing)
                }
                
                // Detected OS badge
                if viewModel.autoPresetApplied && viewModel.detectedOS != .unknown {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.detectedOS.icon)
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Detected: \(viewModel.detectedOS.rawValue)")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                            Text(viewModel.detectedOS.preset.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .help("Settings auto-configured for \(viewModel.detectedOS.rawValue)")
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.08))
                            .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // Drive size warning
                if let warning = viewModel.driveSizeWarning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.08))
                            .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(4)
        }
    }
    
    // MARK: - Options Section
    
    private var optionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Format Options", systemImage: "gearshape.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                // Partition scheme
                HStack {
                    Text("Partition scheme")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $viewModel.options.partitionScheme) {
                        ForEach(PartitionScheme.allCases) { scheme in
                            Text(scheme.displayName).tag(scheme)
                        }
                    }
                    .labelsHidden()
                    .disabled(viewModel.isFlashing)
                }
                
                // Target system
                HStack {
                    Text("Target system")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $viewModel.options.targetSystem) {
                        ForEach(TargetSystem.allCases) { system in
                            Text(system.displayName).tag(system)
                        }
                    }
                    .labelsHidden()
                    .disabled(viewModel.isFlashing)
                }
                
                Divider()
                
                // File system
                HStack {
                    Text("File system")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $viewModel.options.fileSystem) {
                        ForEach(FileSystemType.allCases) { fs in
                            Text(fs.displayName).tag(fs)
                        }
                    }
                    .labelsHidden()
                    .disabled(viewModel.isFlashing)
                }
                
                // Volume label
                HStack {
                    Text("Volume label")
                        .frame(width: 120, alignment: .leading)
                    TextField("MUFUSMAC", text: $viewModel.options.volumeLabel)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isFlashing)
                }
                
                // Dual Partition
                Divider()
                    .padding(.vertical, 4)
                    
                Toggle(isOn: $viewModel.options.createWindowsDataPartition) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create Windows Storage Partition")
                            .font(.body)
                        Text("Splits the drive: 16GB for the USB installer, and the rest as a data partition for installing Windows later.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(3)
                    }
                }
                .toggleStyle(.switch)
                .disabled(viewModel.isFlashing)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(viewModel.options.createWindowsDataPartition ? Color.blue.opacity(0.1) : Color.clear)
                )

                // Windows To Go Script (Only visible if Dual Partition is enabled and OS is Windows)
                if viewModel.options.createWindowsDataPartition && 
                   (viewModel.detectedOS == .windows10 || viewModel.detectedOS == .windows11 || viewModel.detectedOS == .tiny10 || viewModel.detectedOS == .tiny11) {
                    Toggle(isOn: $viewModel.options.createWindowsToGoScript) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Windows To Go (WTG)")
                                .font(.body)
                            Text("Generates 'install_wtg.bat' to bypass Windows Setup restrictions and install directly to the Data partition.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(3)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(viewModel.isFlashing)
                    .padding(.vertical, 4)
                    .padding(.leading, 16) // Indent to show it's a sub-option
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(viewModel.options.createWindowsToGoScript ? Color.purple.opacity(0.1) : Color.clear)
                    )
                }

                // Boot Camp Drivers (Windows only)
                if viewModel.detectedOS == .windows10 || viewModel.detectedOS == .windows11 || viewModel.detectedOS == .tiny10 || viewModel.detectedOS == .tiny11 {
                    Divider()
                        .padding(.vertical, 4)
                        
                    Toggle(isOn: $viewModel.installBootCampDrivers) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Download Mac Boot Camp Drivers")
                                .font(.body)
                            Text("Automatically downloads Apple's Windows Support Software (Wi-Fi, trackpad, keyboard) and injects it into the USB drive.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(3)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(viewModel.isFlashing)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(viewModel.installBootCampDrivers ? Color.blue.opacity(0.1) : Color.clear)
                    )
                }
            }
            .padding(4)
        }
    }
    
    // MARK: - Action Section
    
    private var actionSection: some View {
        HStack(spacing: 12) {
            if viewModel.isFlashing {
                Button {
                    viewModel.cancelFlash()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("CANCEL")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button {
                    showConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isComplete ? "checkmark.circle.fill" : "bolt.fill")
                        Text(viewModel.isComplete ? "DONE — START AGAIN" : "START")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isComplete ? .green : .blue)
                .controlSize(.large)
                .disabled(!viewModel.canStart)
            }
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Progress", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                ProgressView(value: viewModel.progress, total: 1.0) {
                    EmptyView()
                } currentValueLabel: {
                    HStack {
                        Text(viewModel.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(viewModel.progress * 100))%")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(viewModel.isComplete ? .green : .blue)
                    }
                }
                .tint(viewModel.isComplete ? .green : .blue)
            }
            .padding(4)
        }
    }
    
    // MARK: - Log Section
    
    private var logSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Log", systemImage: "doc.text.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Button {
                        let fullLog = viewModel.logMessages.joined(separator: "\n")
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(fullLog, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy full log to clipboard")
                    
                    Button {
                        viewModel.logMessages.removeAll()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear log")
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(viewModel.logMessages.enumerated()), id: \.offset) { index, message in
                                Text(message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .frame(height: 150)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onChange(of: viewModel.logMessages.count) { _, _ in
                        if let last = viewModel.logMessages.indices.last {
                            withAnimation {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }
    
    // MARK: - Download Section
    
    private var downloadSection: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $showDownloadSection) {
                DownloadISOView { downloadedURL in
                    // Auto-select and detect the downloaded ISO
                    viewModel.applyISO(url: downloadedURL)
                    showDownloadSection = false
                }
                .padding(.top, 8)
            } label: {
                Label("Download ISO Image", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(4)
        }
    }
    
    // MARK: - NTFS Warning
    
    private var ntfsWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("NTFS requires ntfs-3g")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text("Install with: brew install ntfs-3g-mac")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            if DiskService.shared.isNTFS3GInstalled() {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
        .frame(width: 520, height: 780)
}
