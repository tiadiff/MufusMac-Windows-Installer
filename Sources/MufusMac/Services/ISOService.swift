import Foundation

class ISOService {
    
    static let shared = ISOService()
    
    private let diskService = DiskService.shared
    private var isCancelled = false
    
    private init() {}
    
    /// Validates that the file at the given URL is a valid ISO image
    func validateISO(at url: URL) throws -> ISOInfo {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: url.path) else {
            throw FlashError.isoInvalid("File does not exist")
        }
        
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? UInt64 else {
            throw FlashError.isoInvalid("Cannot read file attributes")
        }
        
        // Check for ISO 9660 magic bytes at sector 16 (offset 0x8000)
        guard let fileHandle = FileHandle(forReadingAtPath: url.path) else {
            throw FlashError.isoInvalid("Cannot open file for reading")
        }
        defer { fileHandle.closeFile() }
        
        // ISO 9660 primary volume descriptor starts at byte 32768 (0x8000)
        // The identifier "CD001" should be at offset 32769
        if fileSize > 32773 {
            fileHandle.seek(toFileOffset: 32769)
            let magic = fileHandle.readData(ofLength: 5)
            let magicString = String(data: magic, encoding: .ascii) ?? ""
            
            if magicString != "CD001" {
                throw FlashError.isoInvalid("Not a valid ISO 9660 image (missing CD001 signature)")
            }
        }
        
        return ISOInfo(url: url, size: fileSize)
    }
    
    /// Mounts an ISO, copies its contents to the USB drive, then unmounts
    func writeISO(
        at isoURL: URL,
        to device: USBDevice,
        options: FlashOptions,
        progress: @escaping (Double, String) -> Void,
        log: @escaping (String) -> Void
    ) throws {
        isCancelled = false
        
        // Step 1: Mount the ISO
        progress(0.05, "Mounting ISO image...")
        log("⏳ Mounting ISO: \(isoURL.lastPathComponent)")
        
        let isoMountPoint = try mountISO(at: isoURL, log: log)
        defer {
            unmountISO(at: isoMountPoint, log: log)
        }
        
        guard !isCancelled else { throw FlashError.cancelled }
        
        log("✅ ISO mounted at: \(isoMountPoint)")
        progress(0.10, "ISO mounted successfully")
        
        // Step 2: Check for large files on FAT32 (>4GB limit)
        if options.fileSystem == .fat32 {
            let largeFiles = findLargeFiles(in: isoMountPoint, largerThan: 4 * 1024 * 1024 * 1024 - 1)
            if !largeFiles.isEmpty {
                let fileNames = largeFiles.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                log("⚠️  WARNING: Found files larger than 4GB: \(fileNames)")
                log("⚠️  FAT32 does not support files larger than 4GB!")
                log("⚠️  Switching to ExFAT format to avoid errors...")
                
                // Auto-switch to ExFAT to avoid failure
                var adjustedOptions = options
                adjustedOptions.fileSystem = .exfat
                
                log("✅ Format changed to ExFAT (supports large files)")
                
                // Continue with adjusted options
                try performFormat(device: device, options: adjustedOptions, log: log)
                progress(0.25, "Waiting for formatted drive to mount...")
                let destinationPath = try waitForMount(device: device, options: adjustedOptions, log: log)
                try copyFiles(from: isoMountPoint, to: destinationPath, options: adjustedOptions, progress: progress, log: log)
                try finalize(device: device, destinationPath: destinationPath, options: adjustedOptions, log: log, progress: progress)
                return
            }
        }
        
        // Step 3: Format the drive
        progress(0.15, "Formatting USB drive...")
        try performFormat(device: device, options: options, log: log)
        
        guard !isCancelled else { throw FlashError.cancelled }
        
        // Step 4: Wait for mount and copy
        progress(0.25, "Waiting for formatted drive to mount...")
        let destinationPath = try waitForMount(device: device, options: options, log: log)
        try copyFiles(from: isoMountPoint, to: destinationPath, options: options, progress: progress, log: log)
        try finalize(device: device, destinationPath: destinationPath, options: options, log: log, progress: progress)
    }
    
    func cancel() {
        isCancelled = true
    }
    
    // MARK: - Format & Mount
    
    private func performFormat(device: USBDevice, options: FlashOptions, log: @escaping (String) -> Void) throws {
        // For NTFS: format as ExFAT first, then format with ntfs-3g
        // But then we need to MOUNT the NTFS partition for writing
        // macOS cannot write to NTFS natively — we need ntfs-3g mount or fallback to ExFAT
        
        if options.fileSystem == .ntfs {
            // Check if ntfs-3g mount tools are available (not just mkntfs)
            let ntfs3gMountAvailable = findNTFS3GMount() != nil
            
            if !ntfs3gMountAvailable {
                log("⚠️  ntfs-3g mount not available — macOS cannot write to NTFS natively!")
                log("⚠️  Falling back to ExFAT (compatible with Windows & macOS)")
                
                var fallbackOptions = options
                fallbackOptions.fileSystem = .exfat
                try diskService.formatDrive(device: device, options: fallbackOptions, log: log)
                return
            }
        }
        
        try diskService.formatDrive(device: device, options: options, log: log)
    }
    
    /// Waits for the formatted drive to mount and returns the mount point
    private func waitForMount(device: USBDevice, options: FlashOptions, log: @escaping (String) -> Void) throws -> String {
        log("⏳ Waiting for formatted drive to appear...")
        Thread.sleep(forTimeInterval: 3.0)
        
        // For NTFS: need to mount with ntfs-3g instead of native macOS mount
        // BUT only in Single-Partition mode! In Dual-Partition mode, the installer partition is ALWAYS ExFAT, so we use native mount.
        if options.fileSystem == .ntfs && !options.createWindowsDataPartition, let ntfs3gMount = findNTFS3GMount() {
            return try mountNTFSForWriting(device: device, ntfs3gMount: ntfs3gMount, log: log)
        }
        
        // Standard mount for FAT32/ExFAT/APFS
        if let mountPt = diskService.getMountPoint(for: device, options: options) {
            log("✅ USB drive mounted at: \(mountPt)")
            return mountPt
        }
        
        // Try to mount manually — use mountDisk to mount all mountable partitions (fixes GUID s2 issue)
        let mountResult = diskService.runCommand("/usr/sbin/diskutil", arguments: ["mountDisk", device.id])
        log(mountResult)
        Thread.sleep(forTimeInterval: 2.0)
        
        guard let retryMount = diskService.getMountPoint(for: device, options: options) else {
            throw FlashError.mountFailed("Could not find mount point for formatted drive. Try formatting manually with Disk Utility.")
        }
        log("✅ USB drive mounted at: \(retryMount)")
        return retryMount
    }
    
    /// Mounts an NTFS partition for read-write using ntfs-3g
    private func mountNTFSForWriting(device: USBDevice, ntfs3gMount: String, log: @escaping (String) -> Void) throws -> String {
        var partition = "\(device.bsdName)s1"
        
        // Dynamically find the partition (s1 for MBR, s2 for GPT)
        let listOutput = diskService.runCommand("/usr/sbin/diskutil", arguments: ["list", "-plist", device.id])
        if let listData = listOutput.data(using: .utf8),
           let listPlist = try? PropertyListSerialization.propertyList(from: listData, format: nil) as? [String: Any],
           let allDisks = listPlist["AllDisks"] as? [String] {
            if let lastPart = allDisks.filter({ $0 != device.id }).last {
                partition = "/dev/\(lastPart)"
            }
        }
        
        let mountPath = "/Volumes/MUFUSMAC_NTFS"
        
        log("⏳ Preparing NTFS mount...")
        
        // 1. Force unmount any existing native mount (macOS usually auto-mounts as read-only)
        let unmountResult = diskService.runCommand("/usr/sbin/diskutil", arguments: ["unmount", partition])
        if !unmountResult.contains("Unmount failed") {
            log("✅ System auto-mount removed")
        }
        
        log("⏳ Mounting NTFS partition with ntfs-3g for writing...")
        
        let script = """
        #!/bin/bash
        mkdir -p "\(mountPath)"
        "\(ntfs3gMount)" "\(partition)" "\(mountPath)" -olocal -oallow_other -oauto_xattr
        """
        
        let tempScriptPath = FileManager.default.temporaryDirectory.appendingPathComponent("mufusmac_ntfs_mount.sh").path
        do {
            try script.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)
            let _ = diskService.runCommand("/bin/chmod", arguments: ["+x", tempScriptPath])
        } catch {
            throw FlashError.mountFailed("Failed to create temporary mount script.")
        }
        
        // Run the script file instead of passing it as a string argument to avoid quote escaping hell in osascript
        let result = diskService.runCommandPrivileged(tempScriptPath, arguments: [])
        
        // Check if mount succeeded
        let fm = FileManager.default
        Thread.sleep(forTimeInterval: 1.0)
        
        if fm.fileExists(atPath: mountPath) && fm.isWritableFile(atPath: mountPath) {
            log("✅ NTFS partition mounted for writing at: \(mountPath)")
            try? fm.removeItem(atPath: tempScriptPath)
            return mountPath
        }
        
        log("❌ Failed to mount NTFS for writing: \(result)")
        try? fm.removeItem(atPath: tempScriptPath)
        log("💡 Ensure macFUSE is installed and permitted in System Settings > Privacy & Security")
        throw FlashError.mountFailed("Cannot mount NTFS partition for writing. Permission denied or ntfs-3g failed.")
    }
    
    // MARK: - File Copy
    
    private func copyFiles(
        from isoMountPoint: String,
        to destinationPath: String,
        options: FlashOptions,
        progress: @escaping (Double, String) -> Void,
        log: @escaping (String) -> Void
    ) throws {
        let fileManager = FileManager.default
        
        guard !isCancelled else { throw FlashError.cancelled }
        
        progress(0.30, "Calculating files to copy...")
        log("⏳ Enumerating files in ISO...")
        
        let isoContents = try getAllFiles(in: isoMountPoint)
        let totalFiles = isoContents.count
        let totalSize: UInt64 = isoContents.reduce(0) { sum, file in
            let fileSize = (try? fileManager.attributesOfItem(atPath: file))?[.size] as? UInt64 ?? 0
            return sum + fileSize
        }
        
        log("📁 Found \(totalFiles) files/folders (\(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)))")
        
        var copiedFiles = 0
        var copiedBytes: UInt64 = 0
        var skippedFiles: [String] = []
        
        for filePath in isoContents {
            guard !isCancelled else { throw FlashError.cancelled }
            
            let relativePath = String(filePath.dropFirst(isoMountPoint.count))
            let destPath = destinationPath + relativePath
            let destDir = (destPath as NSString).deletingLastPathComponent
            
            // Create directory structure
            if !fileManager.fileExists(atPath: destDir) {
                try fileManager.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            }
            
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: filePath, isDirectory: &isDir)
            
            if isDir.boolValue {
                if !fileManager.fileExists(atPath: destPath) {
                    try fileManager.createDirectory(atPath: destPath, withIntermediateDirectories: true)
                }
            } else {
                // Check file size for FAT32 limit
                let fileSize = (try? fileManager.attributesOfItem(atPath: filePath))?[.size] as? UInt64 ?? 0
                
                if options.fileSystem == .fat32 && fileSize >= (4 * 1024 * 1024 * 1024 - 1) {
                    let fileName = (relativePath as NSString).lastPathComponent
                    log("⚠️  SKIPPING \(fileName) — too large for FAT32 (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))")
                    skippedFiles.append(fileName)
                    continue
                }
                
                // Copy file
                if fileManager.fileExists(atPath: destPath) {
                    try fileManager.removeItem(atPath: destPath)
                }
                
                do {
                    try fileManager.copyItem(atPath: filePath, toPath: destPath)
                    copiedBytes += fileSize
                } catch {
                    log("⚠️  Error copying \((relativePath as NSString).lastPathComponent): \(error.localizedDescription)")
                    skippedFiles.append((relativePath as NSString).lastPathComponent)
                }
            }
            
            copiedFiles += 1
            let fileProgress = 0.30 + (Double(copiedFiles) / Double(totalFiles)) * 0.65
            let shortName = (relativePath as NSString).lastPathComponent
            progress(fileProgress, "Copying: \(shortName)")
            
            if copiedFiles % 50 == 0 || copiedFiles == totalFiles {
                log("📋 Copied \(copiedFiles)/\(totalFiles) items (\(ByteCountFormatter.string(fromByteCount: Int64(copiedBytes), countStyle: .file)))")
            }
        }
        
        if !skippedFiles.isEmpty {
            log("⚠️  \(skippedFiles.count) file(s) were skipped: \(skippedFiles.joined(separator: ", "))")
            log("⚠️  The bootable USB may not work correctly with missing files!")
        }
    }
    
    // MARK: - Finalize
    
    func finalize(device: USBDevice, destinationPath: String, options: FlashOptions, log: @escaping (String) -> Void, progress: @escaping (Double, String) -> Void) throws {
        guard !isCancelled else { throw FlashError.cancelled }
        
        // 1. GESTIONE WINDOWS TO GO (Se richiesto)
        if options.createWindowsToGoScript && !destinationPath.isEmpty {
            log("⏳ Generating Windows To Go Bypass Script (install_wtg.bat)...")
            let scriptContent = """
            @echo off
            color 1f
            echo ==========================================
            echo      MufusMac - Windows To Go Installer
            echo ==========================================
            echo.
            echo Ricerca della chiavetta USB in corso...
            
            set "installerDrive="
            for %%I in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
                if exist "%%I:\\install_wtg.bat" set "installerDrive=%%I:"
            )
            
            if "%installerDrive%"=="" (
                echo ERRORE: Chiavetta MufusMac non trovata!
                pause
                exit /b
            )
            
            echo Installer rilevato su disco: %installerDrive%
            echo.
            echo Verrà installato Windows bypassando le restrizioni Setup.
            echo ATTENZIONE: Questa operazione formatterà una partizione!
            echo.
            echo Dischi e Volumi disponibili:
            echo list volume > %temp%\\list.txt
            diskpart /s %temp%\\list.txt
            
            echo.
            set /p wtgVol="Inserisci il NUMERO del Volume 'DATI' (es. 2): "
            
            echo.
            echo Formattazione Volume %wtgVol% in NTFS in corso...
            echo select volume %wtgVol% > %temp%\\wtg.txt
            echo format fs=ntfs quick label="WindowsToGo" >> %temp%\\wtg.txt
            echo assign letter=W >> %temp%\\wtg.txt
            diskpart /s %temp%\\wtg.txt
            
            set "wimPath=%installerDrive%\\sources\\install.wim"
            if not exist "%wimPath%" set "wimPath=%installerDrive%\\sources\\install.esd"
            if not exist "%wimPath%" set "wimPath=%installerDrive%\\sources\\install.swm"
            
            if not exist "%wimPath%" goto :missingWim
            goto :applyWim

            :missingWim
            echo ERRORE: Immagine Windows non trovata!
            pause
            exit /b
            
            :applyWim
            echo.
            echo Estrazione Windows (%wimPath%) su W:\\... (Richiede tempo!)
            dism /Apply-Image /ImageFile:"%wimPath%" /Index:1 /ApplyDir:W:\\
            
            echo.
            echo Patching Registro di Sistema (Bypass Hardware in fase di Boot)...
            :: Carica l'alveare SYSTEM del nuovo Windows per modificarlo offline
            reg load HKLM\\OFFLINE_SYSTEM W:\\Windows\\System32\\config\\SYSTEM
            
            :: Crea la chiave LabConfig se non esiste e aggiunge i bypass
            reg add HKLM\\OFFLINE_SYSTEM\\Setup\\LabConfig /f
            reg add HKLM\\OFFLINE_SYSTEM\\Setup\\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f
            reg add HKLM\\OFFLINE_SYSTEM\\Setup\\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
            reg add HKLM\\OFFLINE_SYSTEM\\Setup\\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f
            reg add HKLM\\OFFLINE_SYSTEM\\Setup\\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f
            reg add HKLM\\OFFLINE_SYSTEM\\Setup\\LabConfig /v BypassStorageCheck /t REG_DWORD /d 1 /f
            
            :: Aggiunge bypass per MoSetup
            reg add HKLM\\OFFLINE_SYSTEM\\Setup\\MoSetup /f
            reg add HKLM\\OFFLINE_SYSTEM\\Setup\\MoSetup /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f
            
            :: Aggiunge bypass per Windows To Go (Evita blocco hardware USB)
            reg add HKLM\\OFFLINE_SYSTEM\\ControlSet001\\Control /v PortableOperatingSystem /t REG_DWORD /d 1 /f
            
            :: Smonta l'alveare
            reg unload HKLM\\OFFLINE_SYSTEM
            
            if not exist "%installerDrive%\\$WinPEDriver$" goto :skipDrivers
            echo.
            echo Iniezione driver Boot Camp (Tastiera/Mouse/ecc) in W:\\...
            dism /Image:W:\\ /Add-Driver /Driver:"%installerDrive%\\$WinPEDriver$" /Recurse
            
            :skipDrivers
            
            echo.
            echo Copia file di configurazione automatica...
            if not exist "W:\\Windows\\Panther" mkdir "W:\\Windows\\Panther"
            copy /y "%installerDrive%\\AutoUnattend.xml" "W:\\Windows\\Panther\\unattend.xml"
            
            echo.
            echo Creazione Bootloader su EFI...
            W:\\Windows\\System32\\bcdboot W:\\Windows /s %installerDrive% /f UEFI
            
            echo.
            echo Impostazione Windows To Go come avvio predefinito...
            :: Forza il menu di avvio a non mostrare scelte e avviare subito il nuovo OS
            W:\\Windows\\System32\\bcdedit /store %installerDrive%\\efi\\microsoft\\boot\\bcd /set {default} device partition=W:
            W:\\Windows\\System32\\bcdedit /store %installerDrive%\\efi\\microsoft\\boot\\bcd /set {default} osdevice partition=W:
            W:\\Windows\\System32\\bcdedit /store %installerDrive%\\efi\\microsoft\\boot\\bcd /set {bootmgr} default {default}
            W:\\Windows\\System32\\bcdedit /store %installerDrive%\\efi\\microsoft\\boot\\bcd /timeout 0
            
            echo.
            echo ==========================================
            echo FATTO! Puoi chiudere questa finestra.
            echo Al riavvio del Mac spegni e riaccendi
            echo per avviare il tuo nuovo Windows To Go!
            echo ==========================================
            pause
            """
            
            // CRITICAL: Windows batch files, especially those with FOR loops and labels, 
            // will fail to execute properly in WinPE if they only have macOS/Unix (\n) line endings.
            // We MUST force CRLF (\r\n) before writing.
            let crlfScriptContent = scriptContent.replacingOccurrences(of: "\n", with: "\r\n")
            
            let scriptPath = (destinationPath as NSString).appendingPathComponent("install_wtg.bat")
            do {
                try crlfScriptContent.write(toFile: scriptPath, atomically: true, encoding: .windowsCP1252)
                log("✅ install_wtg.bat creato con successo nella root della chiavetta.")
            } catch {
                log("⚠️  Impossibile scrivere install_wtg.bat: \(error.localizedDescription)")
            }
        }
        
        // 2. GESTIONE BYPASS HARDWARE (Fuori dall'if WTG, così si applica alle chiavette standard!)
        if !destinationPath.isEmpty {
            log("⏳ Generazione AutoUnattend.xml per bypass controlli hardware...")
            let unattendContent = """
            <?xml version="1.0" encoding="utf-8"?>
            <unattend xmlns="urn:schemas-microsoft-com:unattend">
                <settings pass="windowsPE">
                    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WCM/2002/Xml" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                        <UserData>
                            <AcceptEula>true</AcceptEula>
                        </UserData>
                        <RunSynchronous>
                            <RunSynchronousCommand wcm:action="add">
                                <Order>1</Order>
                                <Path>cmd /c reg add "HKLM\\SYSTEM\\Setup\\LabConfig" /v "BypassTPMCheck" /t REG_DWORD /d 1 /f</Path>
                            </RunSynchronousCommand>
                            <RunSynchronousCommand wcm:action="add">
                                <Order>2</Order>
                                <Path>cmd /c reg add "HKLM\\SYSTEM\\Setup\\LabConfig" /v "BypassSecureBootCheck" /t REG_DWORD /d 1 /f</Path>
                            </RunSynchronousCommand>
                            <RunSynchronousCommand wcm:action="add">
                                <Order>3</Order>
                                <Path>cmd /c reg add "HKLM\\SYSTEM\\Setup\\LabConfig" /v "BypassRAMCheck" /t REG_DWORD /d 1 /f</Path>
                            </RunSynchronousCommand>
                            <RunSynchronousCommand wcm:action="add">
                                <Order>4</Order>
                                <Path>cmd /c reg add "HKLM\\SYSTEM\\Setup\\LabConfig" /v "BypassCPUCheck" /t REG_DWORD /d 1 /f</Path>
                            </RunSynchronousCommand>
                            <RunSynchronousCommand wcm:action="add">
                                <Order>5</Order>
                                <Path>cmd /c reg add "HKLM\\SYSTEM\\Setup\\LabConfig" /v "BypassStorageCheck" /t REG_DWORD /d 1 /f</Path>
                            </RunSynchronousCommand>
                        </RunSynchronous>
                    </component>
                </settings>
                <settings pass="specialize">
                    <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WCM/2002/Xml" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                        <RunSynchronous>
                            <RunSynchronousCommand wcm:action="add">
                                <Order>1</Order>
                                <Path>cmd /c reg add "HKLM\\SYSTEM\\Setup\\LabConfig" /v "BypassTPMCheck" /t REG_DWORD /d 1 /f</Path>
                            </RunSynchronousCommand>
                            <RunSynchronousCommand wcm:action="add">
                                <Order>2</Order>
                                <Path>cmd /c reg add "HKLM\\SYSTEM\\Setup\\LabConfig" /v "BypassSecureBootCheck" /t REG_DWORD /d 1 /f</Path>
                            </RunSynchronousCommand>
                        </RunSynchronous>
                    </component>
                </settings>
            </unattend>
            """
            
            let unattendPath = (destinationPath as NSString).appendingPathComponent("AutoUnattend.xml")
            let crlfUnattendContent = unattendContent.replacingOccurrences(of: "\n", with: "\r\n")
            do {
                try crlfUnattendContent.write(toFile: unattendPath, atomically: true, encoding: .utf8)
                log("✅ AutoUnattend.xml creato (Bypass Hardware attivato).")
            } catch {
                log("⚠️  Impossibile scrivere AutoUnattend.xml: \(error.localizedDescription)")
            }
        }
        
        // 3. PULIZIA E SMONTAGGIO
        progress(0.96, "Syncing data to drive...")
        log("⏳ Syncing data to USB drive...")
        let _ = diskService.runCommand("/bin/sync", arguments: [])
        
        // Clean up the mount points to avoid user confusion (unmount the whole disk, then mount only the installer)
        log("⏳ Cleaning up volumes...")
        let _ = diskService.runCommand("/usr/sbin/diskutil", arguments: ["unmountDisk", device.id])
        
        // Remount just the installer partition so the user can see it
        let listOutput = diskService.runCommand("/usr/sbin/diskutil", arguments: ["list", "-plist", device.id])
        if let listData = listOutput.data(using: .utf8),
           let listPlist = try? PropertyListSerialization.propertyList(from: listData, format: nil) as? [String: Any],
           let allDisks = listPlist["AllDisks"] as? [String] {
            if let lastPart = allDisks.filter({ $0 != device.id }).last {
                let _ = diskService.runCommand("/usr/sbin/diskutil", arguments: ["mount", "/dev/\(lastPart)"])
            }
        }
        
        progress(1.0, "Done!")
        log("🎉 Successfully created bootable USB drive!")
    }
    
    // MARK: - ISO Mount Helpers
    
    private func mountISO(at url: URL, log: @escaping (String) -> Void) throws -> String {
        // Direct mount — single hdiutil call
        let mountOutput = diskService.runCommand("/usr/bin/hdiutil", arguments: ["attach", url.path, "-readonly", "-noverify", "-noautofsck"])
        log(mountOutput)
        
        // Parse mount point from output
        let lines = mountOutput.components(separatedBy: "\n")
        for line in lines.reversed() {
            if line.contains("/Volumes/") {
                // hdiutil output is tab-separated: device \t type \t mount_point
                let parts = line.components(separatedBy: "\t")
                if let mountPath = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines), !mountPath.isEmpty {
                    return mountPath
                }
                // Try space-separated fallback
                if let range = line.range(of: "/Volumes/") {
                    let mountPath = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !mountPath.isEmpty {
                        return mountPath
                    }
                }
            }
        }
        
        throw FlashError.mountFailed("Could not mount ISO image. hdiutil output:\n\(mountOutput)")
    }
    
    private func unmountISO(at mountPoint: String, log: @escaping (String) -> Void) {
        log("⏳ Unmounting ISO...")
        let _ = diskService.runCommand("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-force"])
        log("✅ ISO unmounted")
    }
    
    private func getAllFiles(in directory: String) throws -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            throw FlashError.copyFailed("Cannot enumerate directory: \(directory)")
        }
        
        var files: [String] = []
        while let element = enumerator.nextObject() as? String {
            files.append(directory + "/" + element)
        }
        return files
    }
    
    /// Finds files larger than the given size in bytes
    private func findLargeFiles(in directory: String, largerThan maxSize: UInt64) -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: directory) else { return [] }
        
        var largeFiles: [String] = []
        while let element = enumerator.nextObject() as? String {
            let fullPath = directory + "/" + element
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? UInt64,
               size > maxSize {
                largeFiles.append(fullPath)
            }
        }
        return largeFiles
    }
    
    /// Finds ntfs-3g mount binary
    private func findNTFS3GMount() -> String? {
        let paths = [
            "/usr/local/bin/ntfs-3g",
            "/opt/homebrew/bin/ntfs-3g",
            "/usr/local/sbin/ntfs-3g",
            "/opt/homebrew/sbin/ntfs-3g"
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }
}

struct ISOInfo {
    let url: URL
    let size: UInt64
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    var fileName: String {
        url.lastPathComponent
    }
}