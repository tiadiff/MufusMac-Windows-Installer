import SwiftUI

@main
struct MufusMacApp: App {
    @State private var showAbout = false
    @State private var hasCheckedDependencies = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 430, height: 920)
                .sheet(isPresented: $showAbout) {
                    AboutView()
                }
                .onAppear {
                    if !hasCheckedDependencies {
                        hasCheckedDependencies = true
                        // Small delay so the window renders first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            DependencyChecker.checkAndInstallDependencies()
                        }
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MufusMac") {
                    showAbout = true
                }
            }
        }
    }
}

/// Checks and installs required dependencies before the GUI loads
struct DependencyChecker {
    
    /// Runs all dependency checks — called before the main window appears
    static func checkAndInstallDependencies() {
        if !DiskService.shared.isNTFS3GInstalled() {
            promptInstallNTFS3G()
        }
    }
    
    /// Checks if Homebrew is installed
    private static func isHomebrewInstalled() -> Bool {
        let paths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }
    
    /// Returns the path to the brew binary
    private static func brewPath() -> String? {
        let paths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    /// Prompts the user to install ntfs-3g via Homebrew
    private static func promptInstallNTFS3G() {
        let alert = NSAlert()
        alert.messageText = "Supporto NTFS"
        alert.informativeText = """
        MufusMac necessita di ntfs-3g per formattare le chiavette USB in NTFS (necessario per le ISO di Windows).
        
        Vuoi installarlo ora tramite Homebrew?
        
        Si aprirà il Terminale dove potrai seguire l'installazione.
        
        Se salti, potrai comunque usare FAT32, ExFAT e APFS.
        """
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "externaldrive.fill.badge.plus", accessibilityDescription: nil)
        alert.addButton(withTitle: "Installa ntfs-3g")
        alert.addButton(withTitle: "Salta")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            installNTFS3GInTerminal()
        }
    }
    
    /// Installs ntfs-3g by opening Terminal with the correct commands
    private static func installNTFS3GInTerminal() {
        // First check for Homebrew
        guard let brew = brewPath() else {
            promptInstallHomebrew()
            return
        }
        
        // Write install script to a temp file to avoid quoting issues
        let scriptContent = """
        #!/bin/bash
        echo ""
        echo "╔══════════════════════════════════════════════╗"
        echo "║   MufusMac — Installazione supporto NTFS     ║"
        echo "╚══════════════════════════════════════════════╝"
        echo ""
        echo "⏳ Step 1/3: Installazione macFUSE (dipendenza)..."
        echo "   (potrebbe richiedere la password di amministratore)"
        echo ""
        \(brew) install --cask macfuse 2>&1
        echo ""
        echo "⏳ Step 2/3: Aggiunta repository gromgit/fuse..."
        \(brew) tap gromgit/fuse 2>&1
        echo ""
        echo "⏳ Step 3/3: Installazione ntfs-3g-mac..."
        echo "   (potrebbe richiedere qualche minuto)"
        echo ""
        \(brew) install gromgit/fuse/ntfs-3g-mac 2>&1
        echo ""
        if which mkntfs > /dev/null 2>&1; then
            echo "✅ ntfs-3g installato con successo!"
            echo "   Puoi chiudere questa finestra e tornare a MufusMac."
        else
            echo "❌ Installazione fallita."
            echo "   Prova manualmente con:"
            echo "   brew install --cask macfuse"
            echo "   brew tap gromgit/fuse"
            echo "   brew install gromgit/fuse/ntfs-3g-mac"
        fi
        echo ""
        """
        
        let scriptPath = "/tmp/mufusmac_install_ntfs3g.sh"
        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            // Make executable
            let _ = DiskService.shared.runCommand("/bin/chmod", arguments: ["+x", scriptPath])
        } catch {
            // Fallback: show manual instructions
            let alert = NSAlert()
            alert.messageText = "Errore"
            alert.informativeText = "Impossibile creare lo script di installazione.\n\nInstalla manualmente:\nbrew tap gromgit/fuse\nbrew install gromgit/fuse/ntfs-3g-mac"
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        // Open Terminal with a simple command — no escaping issues
        let appleScript = "tell application \"Terminal\"\nactivate\ndo script \"bash \(scriptPath)\"\nend tell"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        try? process.run()
        process.waitUntilExit()
        
        // Show a dialog to wait for the user
        let waitAlert = NSAlert()
        waitAlert.messageText = "⏳ Installazione in corso..."
        waitAlert.informativeText = """
        L'installazione di ntfs-3g è in corso nel Terminale.
        
        Attendi che il terminale mostri il messaggio di completamento, poi clicca "Verifica installazione".
        
        Se l'installazione non va a buon fine, potrai comunque usare MufusMac con FAT32, ExFAT e APFS.
        """
        waitAlert.alertStyle = .informational
        waitAlert.addButton(withTitle: "Verifica installazione")
        waitAlert.addButton(withTitle: "Salta")
        
        let waitResponse = waitAlert.runModal()
        
        if waitResponse == .alertFirstButtonReturn {
            // Check if installation succeeded
            if DiskService.shared.isNTFS3GInstalled() {
                let successAlert = NSAlert()
                successAlert.messageText = "✅ ntfs-3g installato!"
                successAlert.informativeText = "Il supporto NTFS è ora disponibile. Puoi creare chiavette USB bootable per Windows."
                successAlert.alertStyle = .informational
                successAlert.addButton(withTitle: "OK")
                successAlert.runModal()
            } else {
                let retryAlert = NSAlert()
                retryAlert.messageText = "⚠️ ntfs-3g non trovato"
                retryAlert.informativeText = """
                L'installazione potrebbe essere ancora in corso nel Terminale.
                
                Attendi il completamento, poi riavvia MufusMac.
                
                Se necessario, installa manualmente:
                  brew tap gromgit/fuse
                  brew install gromgit/fuse/ntfs-3g-mac
                """
                retryAlert.alertStyle = .warning
                retryAlert.addButton(withTitle: "OK")
                retryAlert.runModal()
            }
        }
    }
    
    /// Prompts to install Homebrew first
    private static func promptInstallHomebrew() {
        let alert = NSAlert()
        alert.messageText = "Homebrew non trovato"
        alert.informativeText = """
        Homebrew è necessario per installare ntfs-3g ma non è presente sul tuo sistema.
        
        Vuoi installare Homebrew?
        Si aprirà il Terminale con l'installer ufficiale.
        
        Dopo l'installazione di Homebrew, riavvia MufusMac per installare ntfs-3g.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Installa Homebrew")
        alert.addButton(withTitle: "Annulla")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let script = """
            tell application "Terminal"
                activate
                do script "/bin/bash -c \\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\""
            end tell
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            process.waitUntilExit()
            
            let infoAlert = NSAlert()
            infoAlert.messageText = "Installazione Homebrew avviata"
            infoAlert.informativeText = """
            L'installer di Homebrew è stato avviato nel Terminale.
            
            Al termine dell'installazione:
            1. Chiudi e riapri MufusMac
            2. Ti verrà chiesto di installare ntfs-3g
            """
            infoAlert.alertStyle = .informational
            infoAlert.addButton(withTitle: "OK")
            infoAlert.runModal()
        }
    }
}
