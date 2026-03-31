# Observo Edge Uninstall Script for Windows
param (
    [switch]$KeepConfig,
    [switch]$KeepLogs
)

$InstallDir  = "C:\Program Files\Observo"
$ConfigFile  = "$InstallDir\edge-config.json"
$HistoryDir  = "$InstallDir\history"
$LogDir      = "$InstallDir\logs"
$WrapperPath = "$InstallDir\run_observo.cmd"
$ServiceName = "ObservoEdge"

function Stop-ObservoTask {
    Write-Host "Stopping scheduled task: $ServiceName..."
    $task = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "Error: Scheduled task '$ServiceName' not found." -ForegroundColor Red
        exit 1
    }

    Stop-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Write-Host "Unregistering scheduled task: $ServiceName..."
    try {
        Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Host "Error: Failed to unregister scheduled task '$ServiceName': $_" -ForegroundColor Red
        exit 1
    }
}

function Stop-ObservoProcesses {
    Write-Host "Checking for running Observo processes..."
    foreach ($name in @("edge", "otelcontribcol")) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            Write-Host "Stopping process $name (PID $($proc.Id))..."
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            } catch {
                Write-Host "Error: Failed to stop process $name (PID $($proc.Id)): $_" -ForegroundColor Red
                exit 1
            }
        }
    }
    Start-Sleep -Seconds 1
}

function Remove-WrapperScript {
    Write-Host "Removing wrapper script: $WrapperPath..."
    if (-not (Test-Path -Path $WrapperPath)) {
        Write-Host "Error: Wrapper script $WrapperPath not found." -ForegroundColor Red
        exit 1
    }
    try {
        Remove-Item -Path $WrapperPath -Force -ErrorAction Stop
    } catch {
        Write-Host "Error: Failed to remove wrapper script: $_" -ForegroundColor Red
        exit 1
    }
}

function Remove-Binaries {
    Write-Host "Removing binaries from $InstallDir..."
    if (-not (Test-Path -Path $InstallDir)) {
        Write-Host "Error: Install directory $InstallDir not found." -ForegroundColor Red
        exit 1
    }

    $binaries  = @(Get-ChildItem -Path $InstallDir -Filter "edge*.exe"        -ErrorAction SilentlyContinue)
    $binaries += @(Get-ChildItem -Path $InstallDir -Filter "otelcontrib*.exe" -ErrorAction SilentlyContinue)

    if ($binaries.Count -eq 0) {
        Write-Host "Error: No binaries found in $InstallDir." -ForegroundColor Red
        exit 1
    }

    foreach ($bin in $binaries) {
        Write-Host "Removing $($bin.FullName)..."
        try {
            Remove-Item -Path $bin.FullName -Force -ErrorAction Stop
        } catch {
            Write-Host "Error: Failed to remove $($bin.FullName): $_" -ForegroundColor Red
            exit 1
        }
    }
}

function Remove-Config {
    if ($KeepConfig) {
        Write-Host "Skipping config removal (-KeepConfig set)."
        return
    }

    Write-Host "Removing config file: $ConfigFile..."
    if (-not (Test-Path -Path $ConfigFile)) {
        Write-Host "Error: Config file $ConfigFile not found." -ForegroundColor Red
        exit 1
    }
    try {
        Remove-Item -Path $ConfigFile -Force -ErrorAction Stop
    } catch {
        Write-Host "Error: Failed to remove config file: $_" -ForegroundColor Red
        exit 1
    }

    if (Test-Path -Path $HistoryDir) {
        Write-Host "Removing config history directory: $HistoryDir..."
        try {
            Remove-Item -Path $HistoryDir -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host "Error: Failed to remove history directory: $_" -ForegroundColor Red
            exit 1
        }
    }
}

function Remove-LogDir {
    if ($KeepLogs) {
        Write-Host "Skipping log directory removal (-KeepLogs set)."
        return
    }

    Write-Host "Removing log directory: $LogDir..."
    if (-not (Test-Path -Path $LogDir)) {
        Write-Host "Error: Log directory $LogDir not found." -ForegroundColor Red
        exit 1
    }
    try {
        Remove-Item -Path $LogDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Host "Error: Failed to remove log directory: $_" -ForegroundColor Red
        exit 1
    }
}

function Remove-InstallDir {
    # Keep the directory if config or logs are being preserved (they live inside it).
    if ($KeepConfig -or $KeepLogs) {
        Write-Host "Preserving install directory (config or logs retained): $InstallDir"
        return
    }

    Write-Host "Removing install directory: $InstallDir..."
    if (-not (Test-Path -Path $InstallDir)) {
        Write-Host "Error: Install directory $InstallDir not found." -ForegroundColor Red
        exit 1
    }
    try {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Host "Error: Failed to remove install directory: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Uninstalling Observo Edge..."

# Step 1: Stop and unregister scheduled task
Stop-ObservoTask

# Step 2: Kill any remaining processes
Stop-ObservoProcesses

# Step 3: Remove wrapper script
Remove-WrapperScript

# Step 4: Remove binaries
Remove-Binaries

# Step 5: Remove config
Remove-Config

# Step 6: Remove log directory
Remove-LogDir

# Step 7: Remove install directory
Remove-InstallDir

Write-Host "Observo Edge uninstalled successfully."
