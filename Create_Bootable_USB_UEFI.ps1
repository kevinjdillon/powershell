<#
.SYNOPSIS
    Creates a bootable UEFI USB drive from an ISO file to install Windows
.DESCRIPTION
    This script creates a bootable USB drive from a specified ISO file.
.NOTES
    Created: 2026-03-31
#>

# Get available disks and display them
$disks = Get-Disk | Where-Object { -not $_.IsSystem } | Select-Object -Property Number, @{Name="Size(GB)";Expression={[math]::Round($_.Size/1GB,2)}}, Manufacturer, Model, IsSystem

if ($disks.Count -eq 0) {
    Write-Host "No non-system disks found!" -ForegroundColor Red
    exit
}

Write-Host "Select the disk that you would like to use for the bootable USB:" -ForegroundColor Green
Write-Host "Warning! All data will be erased on this disk!" -ForegroundColor Red
Write-Host "Available disks:" -ForegroundColor Green
$disks | Format-Table -AutoSize

# Retrieve user selection
do {
    $diskNumber = Read-Host "Enter the disk number"
    $selectedDisk = $disks | Where-Object { $_.Number -eq $diskNumber }

    if ($selectedDisk) {
        Write-Host "Selected disk: Disk $($selectedDisk.Number) - $($selectedDisk.'Size(GB)') GB - $($selectedDisk.Manufacturer) $($selectedDisk.Model)" -ForegroundColor Green
        break
    } else {
        Write-Host "Invalid disk number! Please select from the available disk numbers shown above." -ForegroundColor Red
    }
} while ($true)

# Confirm the selection
Write-Host "Enter 'Y' to confirm that you want to erase all data on this disk: " -ForegroundColor Yellow -NoNewline
$confirm = Read-Host
if ($confirm -ne 'Y') {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit
}

# Erase and format the selected disk
Clear-Disk -Number $diskNumber -RemoveData -RemoveOEM -Confirm:$false

# Create System Partition
$usbPartition = New-Partition `
    -DiskNumber $diskNumber `
    -UseMaximumSize `
    -AssignDriveLetter

Format-Volume `
    -Partition $usbPartition `
    -FileSystem FAT32 `
    -NewFileSystemLabel "WindowsUEFI" `
    -Confirm:$false

# Capture USB drive letter
$usbDriveLetter = ($usbPartition | Get-Volume).DriveLetter

# Get ISO file path from user
$isoPath = Read-Host "Enter the full path to the Windows Server 2025 ISO file (e.g., C:\ISOs\WindowsServer2025.iso)"
if (-not (Test-Path $isoPath)) {
    Write-Host "ISO file not found at the specified path!" -ForegroundColor Red
    exit
}   

# Mount the ISO file
$iso = Mount-DiskImage -ImagePath $isoPath -PassThru
$isoDriveLetter = ($iso | Get-Volume).DriveLetter
Write-Host "Mounted ISO at drive letter: $isoDriveLetter" -ForegroundColor Green


# Copy everything EXCEPT install.wim
Write-Host "Copying ISO contents (excluding install.wim) to USB drive..." -ForegroundColor Green
Robocopy `
    "$($isoDriveLetter):\" `
    "$($usbDriveLetter):\" `
    /E /XJ /R:0 /W:0 `
    /XF install.wim

Write-Host "Initial files copied successfully!" -ForegroundColor Green

# Split install.wim for FAT32
$wimSource = "$($isoDriveLetter):\sources\install.wim"
$wimDest   = "$($usbDriveLetter):\sources\install.swm"

Write-Host "Splitting install.wim for FAT32 compatibility..." -ForegroundColor Green
dism `
  /Split-Image `
  /ImageFile:$wimSource `
  /SWMFile:$wimDest `
  /FileSize:3800

Write-Host "install.wim split successfully." -ForegroundColor Green

# Dismount the ISO file
Dismount-DiskImage -ImagePath $isoPath
Write-Host "Bootable USB drive created successfully!" -ForegroundColor Green
Write-Host "You can now use the USB drive to install Windows." -ForegroundColor Green

# End of script