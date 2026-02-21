import Foundation

class BootCampService: ObservableObject {
    
    static let shared = BootCampService()
    
    @Published var isDownloading = false
    @Published var progress: Double = 0.0
    @Published var statusText: String = ""
    
    private let session = URLSession(configuration: .default)
    private var downloadTask: URLSessionDownloadTask?
    
    // Brigadier is an open-source Python script that fetches Boot Camp drivers directly from Apple
    // Using the python3 branch since macOS 12.3+ no longer includes Python 2
    private let brigadierURL = URL(string: "https://raw.githubusercontent.com/timsutton/brigadier/python3/brigadier")!
    
    private init() {}
    
    /// Detects the current Mac model identifier (e.g. MacBookPro16,1)
    func getMacModel() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        process.arguments = ["-n", "hw.model"]
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let model = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return model
            }
        } catch {
            print("Failed to get Mac model: \(error)")
        }
        return "Unknown"
    }
    
    /// Downloads and executes Brigadier to fetch the Boot Camp drivers for the current Mac model
    func downloadBootCampDrivers(to destinationPath: String, log: @escaping (String) -> Void, progressCallback: @escaping (Double, String) -> Void) throws {
        let fileManager = FileManager.default
        let model = getMacModel()
        
        log("🔍 Rilevamento Mac in corso... Modello: \(model)")
        progressCallback(0.0, "Preparazione download Boot Camp...")
        
        // 1. Download Brigadier script
        log("⏳ Download strumento 'brigadier' da GitHub...")
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("MufusMacBootCamp")
        if fileManager.fileExists(atPath: tempDir.path) {
            try? fileManager.removeItem(at: tempDir)
        }
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let brigadierScriptPath = tempDir.appendingPathComponent("brigadier").path
        
        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error?
        
        let task = session.downloadTask(with: brigadierURL) { url, response, error in
            if let error = error {
                downloadError = error
            } else if let tempURL = url {
                do {
                    try fileManager.copyItem(at: tempURL, to: URL(fileURLWithPath: brigadierScriptPath))
                    // Make executable
                    let _ = DiskService.shared.runCommand("/bin/chmod", arguments: ["+x", brigadierScriptPath])
                } catch {
                    downloadError = error
                }
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        
        if let error = downloadError {
            throw FlashError.copyFailed("Impossibile scaricare brigadier: \(error.localizedDescription)")
        }
        
        // 1.5 Inject socket timeout into Brigadier to prevent infinite hangs with urllib
        do {
            var scriptStr = try String(contentsOfFile: brigadierScriptPath, encoding: .utf8)
            if !scriptStr.contains("socket.setdefaulttimeout") {
                scriptStr = scriptStr.replacingOccurrences(
                    of: "import os\n",
                    with: "import os\nimport socket\nsocket.setdefaulttimeout(30)\n"
                )
                try scriptStr.write(toFile: brigadierScriptPath, atomically: true, encoding: .utf8)
            }
        } catch {
            log("⚠️ Impossibile applicare patch di timeout a Brigadier, il download potrebbe bloccarsi.")
        }
        
        log("✅ Brigadier scaricato e configurato")
        progressCallback(0.1, "Ricerca driver macOS nei server Apple...")
        
        // 2. Run Brigadier using system Python3
        log("⏳ Ricerca e download dei driver Boot Camp (può richiedere molto tempo, in base al disco utilizzato, al tuo Mac ed alla velocità della tua connessione internet)...")
        
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        
        // Check for python3
        let pythonPath = DiskService.shared.runCommand("/usr/bin/which", arguments: ["python3"]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        if pythonPath.isEmpty {
            throw FlashError.copyFailed("Python3 non trovato nel sistema. È richiesto per scaricare i driver Boot Camp.")
        }
        
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [brigadierScriptPath, "--model", model, "--output-dir", tempDir.path]
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        var capturedErrorOutput = ""
        
        // Asynchronously read stdout (Normal logs)
        let outHandle = pipe.fileHandleForReading
        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.count > 0, let str = String(data: data, encoding: .utf8) {
                let lines = str.components(separatedBy: .newlines).filter { !$0.isEmpty }
                for line in lines {
                    let cleanLine = line.trimmingCharacters(in: .whitespaces)
                    
                    // Solo se NON è una riga di progresso (%), la logghiamo nel log persistente
                    if !cleanLine.contains("%") || !cleanLine.contains("bytes") {
                        DispatchQueue.main.async { log(cleanLine) }
                    }
                    
                    if cleanLine.contains("Extracting") {
                        DispatchQueue.main.async { progressCallback(0.6, "Estrazione del pacchetto driver...") }
                    } else if cleanLine.contains("Done") {
                        DispatchQueue.main.async { progressCallback(1.0, "Driver scaricati") }
                    }
                }
            }
        }
        
        // Asynchronously read stderr (Where Brigadier prints its download progress bar)
        let errHandle = errorPipe.fileHandleForReading
        errHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.count > 0, let str = String(data: data, encoding: .utf8) {
                capturedErrorOutput += str
                let lines = str.components(separatedBy: CharacterSet(charactersIn: "\r\n")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                
                for line in lines {
                    let cleanLine = line.trimmingCharacters(in: .whitespaces)
                    if cleanLine.contains("%") && cleanLine.contains("bytes") {
                        // Extract percentage to move the progress bar
                        DispatchQueue.main.async {
                            if let percentStr = cleanLine.components(separatedBy: "%").first,
                               let percentVal = Double(percentStr.trimmingCharacters(in: .whitespaces)) {
                                // Scale download phase between 10% and 60% of Boot Camp phase
                                progressCallback(0.1 + (percentVal / 100.0) * 0.5, "Download: \(cleanLine)")
                            } else {
                                progressCallback(0.3, "Download in corso...")
                            }
                        }
                    } else if !cleanLine.isEmpty {
                        // Print other stderr messages to log (e.g. errors, warnings)
                        DispatchQueue.main.async { log("⚠️ " + cleanLine) }
                    }
                }
            }
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            
            if process.terminationStatus != 0 {
                let errorStr = capturedErrorOutput.isEmpty ? "Errore sconosciuto" : capturedErrorOutput
                throw FlashError.copyFailed("Brigadier fallito: \(errorStr)")
            }
        } catch {
            throw FlashError.copyFailed("Errore esecuzione brigadier: \(error.localizedDescription)")
        }
        
        progressCallback(0.8, "Copia dei driver sulla chiavetta...")
        log("⏳ Copia dei driver Boot Camp sulla chiavetta USB...")
        
        // 3. Find the downloaded BootCamp folder or DMG inside tempDir
        // Structure is usually: tempDir/BootCamp-Something/WindowsSupport/ OR tempDir/BootCamp-Something/WindowsSupport.dmg
        let enumerator = fileManager.enumerator(atPath: tempDir.path)
        var sourcePath: String?
        var isDmgMounted = false
        var dmgMountPoint: String?
        
        while let file = enumerator?.nextObject() as? String {
            let fullPath = tempDir.appendingPathComponent(file).path
            
            if file.hasSuffix(".dmg") {
                log("⏳ Trovato archivio DMG: \(file). Montaggio in corso...")
                let mountOutput = DiskService.shared.runCommand("/usr/bin/hdiutil", arguments: ["attach", fullPath, "-readonly", "-noverify", "-noautofsck"])
                
                // Parse mount point
                let lines = mountOutput.components(separatedBy: "\n")
                for line in lines.reversed() {
                    if line.contains("/Volumes/") {
                        let parts = line.components(separatedBy: "\t")
                        if let mountPath = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines), !mountPath.isEmpty {
                            sourcePath = mountPath
                            isDmgMounted = true
                            dmgMountPoint = mountPath
                            log("✅ DMG montato in: \(mountPath)")
                            break
                        }
                    }
                }
                if isDmgMounted { break }
            } else if file.hasSuffix("WindowsSupport") || file.hasSuffix("BootCamp") {
                let isDir = (try? fileManager.attributesOfItem(atPath: fullPath))?[.type] as? FileAttributeType == .typeDirectory
                if isDir {
                    sourcePath = fullPath
                    break
                }
            }
        }
        
        guard let finalSourcePath = sourcePath else {
            throw FlashError.copyFailed("Cartella driver o file DMG non trovati dopo il download.")
        }
        
        // 4. Copy to USB root named "WindowsSupport"
        let destPath = (destinationPath as NSString).appendingPathComponent("WindowsSupport")
        
        if fileManager.fileExists(atPath: destPath) {
            try fileManager.removeItem(atPath: destPath)
        }
        
        do {
            try fileManager.copyItem(atPath: finalSourcePath, toPath: destPath)
            log("✅ Driver Boot Camp copiati in: /WindowsSupport")
            
            // 5. Build $WinPEDriver$ for Windows Setup (fixes keyboard/mouse not working during installation)
            log("⏳ Configurazione iniezione driver per Windows Setup (WinPE)...")
            try setupWinPEDrivers(from: finalSourcePath, to: destinationPath, log: log)
            
            progressCallback(1.0, "Driver installati")
        } catch {
            log("❌ Errore durante la copia dei driver: \(error.localizedDescription)")
            throw FlashError.copyFailed("Impossibile copiare i driver nella chiavetta.")
        }
        
        // Cleanup DMG mount
        if isDmgMounted, let mountPt = dmgMountPoint {
            log("⏳ Smontaggio DMG driver...")
            let _ = DiskService.shared.runCommand("/usr/bin/hdiutil", arguments: ["detach", mountPt, "-force"])
        }
        
        // Cleanup temp
        try? fileManager.removeItem(at: tempDir)
    }
    
    // MARK: - WinPE Driver Injection
    
    private func setupWinPEDrivers(from sourcePath: String, to usbRootPath: String, log: @escaping (String) -> Void) throws {
        let fileManager = FileManager.default
        let winpeDestPath = (usbRootPath as NSString).appendingPathComponent("$WinPEDriver$")
        
        // Ensure destination is clean
        if fileManager.fileExists(atPath: winpeDestPath) { try? fileManager.removeItem(atPath: winpeDestPath) }
        try fileManager.createDirectory(atPath: winpeDestPath, withIntermediateDirectories: true)
        
        // CRITICAL: "Windows could not configure hardware" is often caused by injecting 
        // full Boot Camp drivers (especially Mass Storage/SSD) into the offline image.
        // We MUST cherry-pick only the drivers needed to finish the initial setup (Input).
        let driverFoldersToFind = [
            "AppleKeyboard", "AppleMultiTouchTrackPad", "AppleMightyMouse",
            "AppleWirelessMouse", "AppleWirelessTrackpad", "AppleSPIKeyboard",
            "AppleSPITrackpad", "AppleBluetoothBroadcom", "AppleUSBVHCI",
            "AppleUserHID"
        ]
        
        var foundCount = 0
        
        // We look both in the root and in the native $WinPEDriver$ if it exists
        let searchFolders = ["", "$WinPEDriver$"]
        
        for subFolder in searchFolders {
            let currentSearchPath = (sourcePath as NSString).appendingPathComponent(subFolder)
            if let enumerator = fileManager.enumerator(atPath: currentSearchPath) {
                while let file = enumerator.nextObject() as? String {
                    let folderName = (file as NSString).lastPathComponent
                    if driverFoldersToFind.contains(where: { folderName.contains($0) }) {
                        let fullSourceDriver = (currentSearchPath as NSString).appendingPathComponent(file)
                        let fullDestDriver = (winpeDestPath as NSString).appendingPathComponent(folderName)
                        
                        // Copy folder/file if it doesn't already exist in destination
                        if !fileManager.fileExists(atPath: fullDestDriver) {
                            try? fileManager.copyItem(atPath: fullSourceDriver, toPath: fullDestDriver)
                            foundCount += 1
                        }
                    }
                }
            }
        }
        
        log("✅ Estratti \(foundCount) driver di input critici in $WinPEDriver$ (per evitare errori OOBE)")
    }
}
