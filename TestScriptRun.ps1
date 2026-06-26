$Script:Name = 'TestScriptRun'
Function New-Log {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0)]
        [string] $path = (Join-Path -Path C:\Temp -ChildPath 'Logs')
    )

    # if ($env:SUPPRESS_FILELOG -eq '1') { return }
    $date = Get-Date -UFormat "%Y-%m-%d %H-%M-%S"
    Set-Variable logFile -Scope Script
    $script:logFile = "$Script:Name-$date.log"

    if ((Test-Path $path ) -eq $false) {
        $null = New-Item -Path $path -type directory
    }

    $Script:Log = Join-Path $path $logfile

    Add-Content $Script:Log "Date`t`t`tCategory`t`tDetails"
}

Function Write-Log {
    Param (
        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateSet("Info", "Warning", "Error")]
        $Category = 'Info',
        [Parameter(Mandatory = $true, Position = 1)]
        $Message
    )

    $Content = "[$(Get-Date -Format 'MM/dd/yyyy HH:mm:ss')]`t$Category`t`t$Message"
    if (-not $env:SUPPRESS_FILELOG) {
        Add-Content $Script:Log $Content -ErrorAction SilentlyContinue
    }
    Switch ($Category) {
        'Info'    { Write-Host $Content }
        'Error'   { Write-Error $Content -ErrorAction Continue }
        'Warning' { Write-Warning $Content }
    }
}

# main
New-Log
Write-Log -Message "Starting '$PSCommandPath'."

Write-Log -Category Info -Message "Test Script Completed Successfully."