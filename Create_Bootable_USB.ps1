<#
.SYNOPSIS
    Creates a bootable USB drive from an ISO file to install Windows
.DESCRIPTION
    This script creates a bootable USB drive from a specified ISO file.
.NOTES
    Created: 2024-11-06
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
Write-Host "Enter 'YES' to confirm that you want to erase all data on this disk: " -ForegroundColor Yellow -NoNewline
$confirm = Read-Host
if ($confirm -ne 'YES') {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit
}

# Erase and format the selected disk
Clear-Disk -Number $diskNumber -RemoveData
New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter
$usbDriveLetter = (Get-Partition -DiskNumber $diskNumber).DriveLetter
Format-Volume -DriveLetter $usbDriveLetter -FileSystem NTFS -NewFileSystemLabel "WindowsServer2025" -Confirm:$false



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

# Copy files from ISO to USB drive
Write-Host "Copying files from ISO to USB drive..." -ForegroundColor Green
Robocopy "$($isoDriveLetter):\" "$($usbDriveLetter):\" /E /V /MT:16
Write-Host "Files copied successfully!" -ForegroundColor Green

# Dismount the ISO file
Dismount-DiskImage -ImagePath $isoPath
Write-Host "Bootable USB drive created successfully!" -ForegroundColor Green
Write-Host "You can now use the USB drive to install Windows Server 2025." -ForegroundColor Green

# End of script