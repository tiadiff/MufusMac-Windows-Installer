# MufusMac

A native macOS utility for creating bootable USB flash drives from ISO image files.<br>Inspired by [Rufus](https://rufus.ie/) for Windows, but designed natively for the Mac ecosystem.<br>

<img width="430" height="372" alt="Screenshot 2026-02-20 alle 23 28 43" src="https://github.com/user-attachments/assets/6bf9a5cd-abe3-4274-967c-9068cf36510a" /><br>

## ✨ Advanced New Features

- 🍏 **Full Boot Camp Support (WinPE Injection)** — Not only does it download the Boot Camp drivers for your specific Mac model, but it also **injects Keyboard, Mouse, and Trackpad drivers (SPI/VHCI)** directly into the pre-installation environment (Windows Setup / WinPE). No more frozen keyboards during the very first Windows 11 installation screen!
- 🪓 **Dual-Partition Mode** — Want to use a large USB drive as both an installer and a data drive for Windows? MufusMac can split the drive: it creates a fixed 16GB partition for the Windows installation and expands the remaining space into a "Data" partition formattable in NTFS (e.g., for carrying large games, software, or files).
- 📋 **Real-Time Detailed Logs** — Direct extraction of the Apple driver download stream. See exact percentages, downloaded bytes, and extracted files (even from hidden DMG packages). Includes a **"Copy"** button to paste the log anywhere.
- ⬇️ **Integrated ISO Download** — Download Windows 10, Windows 11, the lightweight Tiny10/Tiny11 versions, and Ubuntu directly from the app.
- 🤖 **Auto-Configuration** — Automatically detects the operating system from the ISO filename (Windows 10/11, Tiny10/11, Ubuntu) and sets the ideal partitioning parameters (MBR/GPT) and target system (BIOS/UEFI).

## 📋 Requirements

- macOS 14.0 (Sonoma) or later
- Swift 5.9+
- Administrator privileges (system password is required for disk operations)
- **For NTFS data partitions**: `ntfs-3g` installed via Homebrew.

## 🔧 NTFS Installation (Step-by-Step Guide)

MufusMac can format in NTFS using `ntfs-3g`. If your Mac doesn't have these tools, follow these 3 simple steps:

### 1. Install Homebrew
Open the **Terminal** and paste this command to download the official package manager:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
*(During installation, you will be asked for your Mac password and you will need to press ENTER when prompted. At the end, if the terminal suggests running "Next steps" commands to add brew to your PATH, copy and run them).*

### 2. Install ntfs-3g-mac
Once Homebrew is installed, run these two commands:
```bash
# Add the specific repository for FUSE support
brew tap gromgit/fuse

# Install the ntfs-3g package
brew install gromgit/fuse/ntfs-3g-mac
```

### 3. System Permissions (macFUSE)
On the first launch, macOS might block the macFUSE system extension.
1. Go to **System Settings > Privacy & Security**.
2. Scroll down and click **"Allow"** or **"Details"** near the message regarding macFUSE (Benjamin Fleischer).
3. A Mac restart may be required to enable the drivers.

## 🚀 Build and Run

```bash
cd MufusMac
swift build
swift run
```

---

## 📖 Guide: Installing Windows on Mac (Boot Camp Alternative)

If you want to install Windows on your Mac using a USB drive (for example, because the official Boot Camp Assistant fails or you want to use Tiny11), use this guaranteed procedure:

1. Insert a USB drive (at least 16 GB, 32 GB+ recommended).
2. Open MufusMac and choose the drive from the dropdown menu.
3. Select the Windows ISO (e.g., the official Microsoft ISO or Tiny11, which you can download from the `Download ISO` menu).
4. ✅ Check **"Download Mac Boot Camp Drivers"**.
   - *This will cause the app to download the perfect drivers for your Mac model from Apple, extracting them and configuring `AutoUnattend.xml` so that the mouse and keyboard work during Windows Setup.*
5. **(Optional but Recommended)** ✅ Check **"Create Windows Storage Partition"** (Dual-Partition Mode).
   - *If your drive is large (e.g., 128GB), MufusMac will use 16GB for the Windows installer (formatted in ExFAT, readable by Mac for booting) and will use the remaining 112GB creating a Data partition (in NTFS, visible in Windows) where you can store extra drivers, games, or backups.*
6. Click **START**. The app will do everything for you: unmount, format, file extraction, driver download, WinPE driver generation, repacking, and clean unmount.
7. When finished, restart your Mac while holding the **Option (⌥)** key and choose "EFI Boot".

After the Windows installation is complete, go into the USB drive (in the `WindowsSupport`/`BootCamp` folder) and run `setup.exe` to install the final graphics, audio, Wi-Fi drivers, etc.

---

## 🛠️ Windows To Go (WTG) - Native Installation on USB

MufusMac includes an advanced feature to turn your external drive into a **portable Windows operating system**. Normally, the Windows installer blocks installation on USB peripherals with the error *"Windows cannot be installed to this disk"*.

By enabling the **"Enable Windows To Go (WTG)"** option, MufusMac generates a file called `install_wtg.bat` in the root of the drive. This script is a "magic wand" that:
- 🚀 **Bypasses setup.exe**: Completely ignores the low-level checks and limits that prevent installation on USB.
- ⚡ **Direct Installation**: Uses the `DISM` engine to unpack Windows directly onto the external disk partition.
- 🍏 **Drivers Ready**: If you downloaded Boot Camp drivers, the script injects them into the newly cloned system, ensuring that the keyboard and mouse work on the first boot.

### Usage Procedure:
1. In MufusMac, enable **"Dual-Partition Mode"** and check **"Enable Windows To Go (WTG)"**.
2. Click **START** to create the disk.
3. Restart your Mac while holding **Option (⌥)** and choose the drive (EFI Boot).
4. At the first blue installation screen, **DO NOT** proceed. Press **Shift + F10** to open the command prompt.
5. Identify your drive letter: type `notepad`, press Enter, go to *File > Open > This PC* and check the letter of your USB drive (e.g., `D:`).
6. In the terminal, launch the script: type `D:\install_wtg.bat` (change D to your letter) and press Enter.
7. Follow the instructions: type the number of the "DATA" volume when prompted and wait for 100%.
8. When finished, restart your Mac. Windows To Go will start automatically from the external disk!

---

## 📖 Guide: Creating an Installer for Standard PCs

### 🪟 Windows 10 / Tiny10 (Old PCs / BIOS)

| Setting | Value |
|---|---|
| **Partition scheme** | MBR (Master Boot Record) |
| **Target system** | BIOS (or UEFI-CSM) |
| **File system** | NTFS |
| **Extra Options** | ❌ Disable "Mac Boot Camp Drivers" |

### 🪟 Windows 11 / Tiny11 (Modern PCs / UEFI)

Reminder: Windows 11 (including Tiny11) is only compatible with Intel processors newer than 8th generation.

| Setting | Value |
|---|---|
| **Partition scheme** | GPT (GUID Partition Table) |
| **Target system** | UEFI (non-CSM) |
| **File system** | NTFS |
| **Extra Options** | ❌ Disable "Mac Boot Camp Drivers" |
> ⚠️ Remember: Official Windows 11 requires TPM 2.0 and Secure Boot. Tiny11 **does not** have these requirements.

### 🐧 Ubuntu Desktop / Server

| Setting | Value |
|---|---|
| **Partition scheme** | GPT |
| **Target system** | UEFI |
| **File system** | FAT32 |
> 💡 IMPORTANT: Linux ISOs **always** use the FAT32 file system, not NTFS.

---

## ⚠️ Technical Details & Troubleshooting

- **Ghost Partitions ("Three Disks"):** To prevent the macOS desktop from being cluttered with useless icons, at the end of a "Dual-Partition" flash, MufusMac will force the unmounting of the entire drive and remount only the 16GB partition. If you see other mounted disks (e.g., `tiny11 2311`), they are just the ISO image that macOS occasionally struggles to unmount in the background; eject them manually.
- **mkntfs Failure:** If the file system is not correctly formatted as NTFS, check the log output. This is often due to macFUSE permissions in System Settings under 'Privacy & Security'.
- **DMG Support:** If the Apple server responds with drivers wrapped inside a `.dmg` file instead of a raw folder format, MufusMac is now able to recognize it, mount it hiddenly, extract its contents (WindowsSupport), and unmount it without requiring user intervention.

---
