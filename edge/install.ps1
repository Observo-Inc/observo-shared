# Observo Edge Installation Script for Windows
# This script installs and configures the Observo Edge agent

# ASCII Art Banner
$ObservoHeading = @"
       #######    ######      #####     #######    ######     #     #    #######              #       ###
       #     #    #     #    #     #    #          #     #    #     #    #     #             # #       #
       #     #    #     #    #          #          #     #    #     #    #     #            #   #      #
       #     #    ######      #####     #####      ######     #     #    #     #           #     #     #
       #     #    #     #          #    #          #   #       #   #     #     #    ###    #######     #
       #     #    #     #    #     #    #          #    #       # #      #     #    ###    #     #     #
       #######    ######      #####     #######    #     #       #       #######    ###    #     #    ###




 ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### ##### #####




 ####### ######   #####  #######    ### #     #  #####  #######    #    #       #          #    ####### ### ####### #     #
 #       #     # #     # #           #  ##    # #     #    #      # #   #       #         # #      #     #  #     # ##    #
 #       #     # #       #           #  # #   # #          #     #   #  #       #        #   #     #     #  #     # # #   #
 #####   #     # #  #### #####       #  #  #  #  #####     #    #     # #       #       #     #    #     #  #     # #  #  #
 #       #     # #     # #           #  #   # #       #    #    ####### #       #       #######    #     #  #     # #   # #
 #       #     # #     # #           #  #    ## #     #    #    #     # #       #       #     #    #     #  #     # #    ##
 ####### ######   #####  #######    ### #     #  #####     #    #     # ####### ####### #     #    #    ### ####### #     #

"@

# Configuration Variables
$InstallDir = "C:\Program Files\Observo"
$TmpDir = "$env:TEMP\observo"
$ConfigDir = "C:\Program Files\Observo"
$ZipFile = "$TmpDir\edge.zip"
$ExtractDir = "$ConfigDir\binaries_edge"
$ConfigFile = "$ConfigDir\edge-config.json"
$BaseUrl = "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download"
$PackageName = "otelcol-contrib"
$DefaultDownloadUrl = "https://example.com"
$ServiceName = "ObservoEdge"
$LogDir = "$InstallDir\logs"
$StdoutLogFile = "$LogDir\observoedge_stdout.log"
$StderrLogFile = "$LogDir\observoedge_stderr.log"
$EdgeCollectorLogFile = "$LogDir\edge-collector.log"
$OtelExecutablePath = "$InstallDir\otelcontribcol.exe"
# Function to check for and install prerequisites
function Check-Prerequisites {
    Write-Host "Checking for required PowerShell modules..."

    # Only check for NuGet if PowerShell version is older than 5.1
    if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        # Check if the NuGet package provider is installed
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-Host "Installing NuGet package provider..."
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser
        }
    } else {
        Write-Host "PowerShell 5.1 or later detected, skipping NuGet package provider check."
    }

    # Check for required modules
    $requiredModules = @("Microsoft.PowerShell.Archive")
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "Installing module: $module..."
            Install-Module -Name $module -Force -Scope CurrentUser
        } else {
            Write-Host "$module is already installed."
        }
    }
}

# Function to parse command line arguments
function Parse-EnvironmentVariable {
    param (
        [Parameter(Mandatory=$false)]
        [string]$EnvVar
    )

    if (-not $EnvVar) {
        Write-Host "Error: Missing -EnvVar argument"
        Write-Host "Usage: .\install-observo.ps1 -EnvVar 'install_id=<JWT Token> download_url=<Custom URL>'"
        return $false
    }

    Write-Host "Received environment variable: $EnvVar"

    # Parse install_id
    if ($EnvVar -match "install_id=([A-Za-z0-9+/=]+)") {
        $script:Token = $matches[1]
        Write-Host "Extracted install_id (base64): $Token"

        try {
            # Decode the base64 string
            $bytes = [Convert]::FromBase64String($Token)
            $script:Decoded = [System.Text.Encoding]::UTF8.GetString($bytes)
            Write-Host "Decoded install_id (JSON): $Decoded"
        } catch {
            Write-Host "Error decoding base64 string: $_"
            return $false
        }
    } else {
        Write-Host "Error: install_id not found in argument"
        return $false
    }

    # Parse download_url (optional) and update DefaultDownloadUrl directly
    if ($EnvVar -match "download_url=([^\s]+)") {
        $script:DefaultDownloadUrl = $matches[1]
        Write-Host "Updated DefaultDownloadUrl to: $DefaultDownloadUrl"
    } else {
        Write-Host "No DownloadUrl provided: $DefaultDownloadUrl"
        return $false
    }

    # Parse caCertificate parameter
    if ($EnvVar -match "caCertificate=([A-Za-z0-9+/=]+)") {
        $script:CaCert = $matches[1]
        Write-Host "Extracted caCertificate (base64): $CaCert"
    } else {
        Write-Host "Warning: caCertificate not found in argument"
        $script:CaCert = ""
    }

    return $true
}

function Detect-System {
    $OS = "windows"

    # Determine architecture
    if ([Environment]::Is64BitOperatingSystem) {
        $script:Arch = "amd64"
        Write-Host "Detected 64-bit Windows architecture (amd64)"
    } else {
        Write-Host "Error: Your system architecture is not supported. 64-bit Windows is required." -ForegroundColor Red
        exit 1
    }

    Write-Host "Detected OS: $OS"
    Write-Host "Detected Architecture: $Arch"

    $script:OS = $OS
}

# Function to decode and extract configuration
function Decode-AndExtractConfig {
    Write-Host "Processing token: $Token"

    # Create config directory if it doesn't exist
    if (-not (Test-Path -Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }

    # Create a history subdirectory for timestamped configs
    $HistoryDir = Join-Path -Path $ConfigDir -ChildPath "history"
    if (-not (Test-Path -Path $HistoryDir)) {
        New-Item -ItemType Directory -Path $HistoryDir -Force | Out-Null
    }

    # Create timestamp for historical file
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $HistoricalConfigFile = Join-Path -Path $HistoryDir -ChildPath "edge-config-$Timestamp.json"

    # Write decoded JSON to both current and historical config files
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($ConfigFile, $Decoded, $utf8NoBom)
    [System.IO.File]::WriteAllText($HistoricalConfigFile, $Decoded, $utf8NoBom)

    Write-Host "Configuration saved to $ConfigFile"
    Write-Host "Historical copy saved to $HistoricalConfigFile"

    # Parse JSON configuration
    try {
        $config = $Decoded | ConvertFrom-Json

        $script:SiteId = $config.site_id
        $script:AuthToken = $config.auth_token
        $script:AgentVersion = $config.agent_version
        $script:ConfigVersionId = $config.config_version_id
        $script:FleetId = $config.fleet_id
        $script:Platform = $config.platform
        $script:EdgeManagerUrl = $config.edge_manager_url

        Write-Host "SITE_ID: $SiteId"
        Write-Host "AUTH_TOKEN: $AuthToken"
        Write-Host "AGENT_VERSION: $AgentVersion"
        Write-Host "CONFIG_VERSION_ID: $ConfigVersionId"
        Write-Host "FLEET_ID: $FleetId"
        Write-Host "PLATFORM: $Platform"
        Write-Host "EDGE_MANAGER_URL: $EdgeManagerUrl"
    } catch {
        Write-Host "Error parsing JSON configuration: $_" -ForegroundColor Red
        exit 1
    }
}

# Function to setup CA certificate
function Setup-CaCertificate {
    if ([string]::IsNullOrEmpty($CaCert)) {
        Write-Host "No CA certificate provided, skipping certificate setup"
        return
    }

    Write-Host "Setting up CA certificate..."

    # Create certificate directory if it doesn't exist
    $CertDir = "C:\Program Files\Observo\certs"
    if (-not (Test-Path -Path $CertDir)) {
        Write-Host "Creating certificate directory: $CertDir"
        New-Item -ItemType Directory -Path $CertDir -Force | Out-Null
    }

    try {
        # Decode the base64 certificate and save it
        Write-Host "Decoding and saving CA certificate to $CertDir\ca.crt"
        $bytes = [Convert]::FromBase64String($CaCert)
        $certContent = [System.Text.Encoding]::UTF8.GetString($bytes)
        
        $CertFile = Join-Path -Path $CertDir -ChildPath "ca.crt"
        [System.IO.File]::WriteAllText($CertFile, $certContent, [System.Text.Encoding]::UTF8)
        
        Write-Host "CA certificate successfully saved to $CertFile"
    } catch {
        Write-Host "Error: Failed to decode and save CA certificate: $_" -ForegroundColor Red
        return
    }
}

# Function to download and extract the agent
function Download-AndExtractAgent {
    param (
        [string]$DownloadUrl = $DefaultDownloadUrl
    )

    # Create temp directory if it doesn't exist
    if (-not (Test-Path -Path $TmpDir)) {
        New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
    }

    Write-Host "Downloading from $DownloadUrl"

    try {
        # Download the zip file
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($DownloadUrl, $ZipFile)
        Write-Host "Download completed and saved to $ZipFile"

        # Create extract directory if it doesn't exist
        if (-not (Test-Path -Path $ExtractDir)) {
            New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
        }

        # Extract the zip file
        Write-Host "Extracting $ZipFile to $ExtractDir"
        Expand-Archive -Path $ZipFile -DestinationPath $ExtractDir -Force
        Write-Host "Extraction complete. Files are in $ExtractDir"
    } catch {
        Write-Host "Error during download or extraction: $_"
        exit 1
    }
}

function Move-BinariesToInstallDir {
    # Create install directory if it doesn't exist
    if (-not (Test-Path -Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Find the otelcontrib executable
    $OtelBinaryFile = Get-ChildItem -Path $ExtractDir -Recurse -Filter "otelcontrib*.exe" | Select-Object -First 1 -ExpandProperty FullName

    if (-not $OtelBinaryFile) {
        Write-Host "Error: No otelcontrib executable file found in $ExtractDir!"
        exit 1
    }

    # Check if the target file exists and terminate any processes using it
    $OtelBinaryName = Split-Path $OtelBinaryFile -Leaf
    $TargetPath = "$InstallDir\$OtelBinaryName"

    if (Test-Path -Path $TargetPath) {
        Write-Host "Target file exists, checking for processes using it..."
        try {
            $processes = Get-Process | Where-Object { $_.Modules.FileName -eq $TargetPath }
            foreach ($process in $processes) {
                Write-Host "Stopping process $($process.Id) that is using $TargetPath"
                Stop-Process -Id $process.Id -Force
                Start-Sleep -Seconds 1
            }
        } catch {
            Write-Host "Error checking for processes: $_"
        }
    }

    # Move the file with retry
    Write-Host "Moving $OtelBinaryFile to $InstallDir..."
    $retryCount = 0
    $maxRetries = 3
    $success = $false

    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            Copy-Item -Path $OtelBinaryFile -Destination $TargetPath -Force
            $script:OtelExecutablePath = $TargetPath
            Write-Host "OtelExecutablePath updated to: $OtelExecutablePath"
            $success = $true
        } catch {
            $retryCount++
            Write-Host "Retry ${retryCount}: Failed to copy file: $_"
            Start-Sleep -Seconds 2
        }
    }

    if (-not $success) {
        Write-Host "Failed to copy $OtelBinaryFile after $maxRetries attempts. Installation will continue, but service may not function properly."
    }

    # Find the edge executable
    $EdgeBinaryFile = Get-ChildItem -Path $ExtractDir -Recurse -Filter "edge*.exe" | Select-Object -First 1 -ExpandProperty FullName

    if (-not $EdgeBinaryFile) {
        Write-Host "Error: No edge executable file found in $ExtractDir!"
        exit 1
    }

    # Move the file
    Write-Host "Moving $EdgeBinaryFile to $InstallDir..."
    $EdgeBinaryName = Split-Path $EdgeBinaryFile -Leaf
    Copy-Item -Path $EdgeBinaryFile -Destination "$InstallDir\$EdgeBinaryName" -Force

    # Clean up
    Write-Host "Cleaning up temporary files..."
    Remove-Item -Path $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue

    # Save the edge binary name for service creation
    $script:EdgeExe = "$InstallDir\$EdgeBinaryName"
}

function Install-AsScheduledTask {
    Write-Host "Installing Observo Edge as a scheduled task..."

    # Check if service already exists and remove it
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Host "Service exists. Stopping and removing..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        sc.exe delete $ServiceName
        Start-Sleep -Seconds 2
    }

    # Check if task already exists and remove it
    $taskExists = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
    if ($taskExists) {
        Write-Host "Scheduled task exists. Removing..."
        Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false
    }

    # Verify the binary and config file exist
    Write-Host "Verifying binary and config file exist:"
    $binaryExists = Test-Path -Path $EdgeExe
    $configExists = Test-Path -Path $ConfigFile
    Write-Host "Binary: $binaryExists"
    Write-Host "Config: $configExists"

    if (-not $binaryExists -or -not $configExists) {
        Write-Host "Error: Binary or config file missing!" -ForegroundColor Red
        exit 1
    }

    # Create log directory if it doesn't exist
    if (-not (Test-Path -Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Write-Host "Created log directory: $LogDir"
    }

    $MachineGuid = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
    Write-Host "MachineGuid: $MachineGuid"

    # Create a wrapper script that will run the edge binary and redirect output to log files
    $WrapperScript = @"
@echo off
set AGENT_ID=$MachineGuid
echo Starting Observo Edge Agent at %DATE% %TIME% > "$StdoutLogFile"
echo Starting Observo Edge Agent at %DATE% %TIME% > "$StderrLogFile"
    "$EdgeExe" -config "$ConfigFile" >> "$StdoutLogFile" 2>> "$StderrLogFile"
"@

    $WrapperPath = "$InstallDir\run_observo.cmd"
    Set-Content -Path $WrapperPath -Value $WrapperScript
    Write-Host "Created wrapper script: $WrapperPath"

    # Create the action to run the wrapper script
    $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$WrapperPath`""

    # Create the trigger (at system startup)
    $trigger = New-ScheduledTaskTrigger -AtStartup

    # Configure the settings
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    # Create the principal (run as SYSTEM with highest privileges)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    # Register the task
    Register-ScheduledTask -TaskName $ServiceName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Observo Edge telemetry collection agent"

    # Start the task immediately
    Write-Host "Starting scheduled task: $ServiceName"
    Start-ScheduledTask -TaskName $ServiceName

    # Check if the task started and the process is running
    Start-Sleep -Seconds 5
    $processes = Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($EdgeExe)) -ErrorAction SilentlyContinue

    if ($processes.Count -gt 0) {
        Write-Host "Observo Edge started successfully as a scheduled task." -ForegroundColor Green
        Write-Host "Process ID(s): $($processes.Id -join ', ')"
        Write-Host "You can view logs using View-ObservoLogs command."
    } else {
        Write-Host "Warning: The scheduled task was created but the process may not have started." -ForegroundColor Yellow

        # Try to start manually for debugging
        Write-Host "Attempting to start the binary directly for debugging..."
        $processInfo = Start-Process -FilePath $EdgeExe -ArgumentList "-config `"$ConfigFile`"" -PassThru -NoNewWindow -RedirectStandardOutput $StdoutLogFile -RedirectStandardError $StderrLogFile
        Write-Host "Manual process started with PID: $($processInfo.Id)"

        # Give it a few seconds to initialize
        Start-Sleep -Seconds 10

        if ($processInfo.HasExited) {
            Write-Host "Process exited with code: $($processInfo.ExitCode)" -ForegroundColor Red
            Write-Host "Check logs for details using View-ObservoLogs command."
        } else {
            Write-Host "Process is running. Check logs using View-ObservoLogs command."
        }
    }

    # Show the scheduled task status
    Get-ScheduledTask -TaskName $ServiceName | Format-List State, LastRunTime, LastTaskResult
}

function Install-AsScheduledTask {
    Write-Host "Installing Observo Edge as a scheduled task..."

    # Check if service already exists and remove it
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Host "Service exists. Stopping and removing..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        sc.exe delete $ServiceName
        Start-Sleep -Seconds 2
    }

    # Check if task already exists and remove it
    $taskExists = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
    if ($taskExists) {
        Write-Host "Scheduled task exists. Removing..."
        Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false
    }

    # Verify the binary and config file exist
    Write-Host "Verifying binary and config file exist:"
    $binaryExists = Test-Path -Path $EdgeExe
    $configExists = Test-Path -Path $ConfigFile
    Write-Host "Binary: $binaryExists"
    Write-Host "Config: $configExists"

    if (-not $binaryExists -or -not $configExists) {
        Write-Host "Error: Binary or config file missing!" -ForegroundColor Red
        exit 1
    }

    # Create log directory if it doesn't exist
    if (-not (Test-Path -Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Write-Host "Created log directory: $LogDir"
    }

    # Create a wrapper script that will run the edge binary and redirect output to log files
    $WrapperScript = @"
@echo off
echo Starting Observo Edge Agent at %DATE% %TIME% > "$StdoutLogFile"
echo Starting Observo Edge Agent at %DATE% %TIME% > "$StderrLogFile"
    "$EdgeExe" -config "$ConfigFile" >> "$StdoutLogFile" 2>> "$StderrLogFile"
"@

    $WrapperPath = "$InstallDir\run_observo.cmd"
    Set-Content -Path $WrapperPath -Value $WrapperScript
    Write-Host "Created wrapper script: $WrapperPath"

    # Create the action to run the wrapper script
    $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$WrapperPath`""

    # Create the trigger (at system startup)
    $trigger = New-ScheduledTaskTrigger -AtStartup

    # Configure the settings
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    # Create the principal (run as SYSTEM with highest privileges)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    # Register the task
    Register-ScheduledTask -TaskName $ServiceName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Observo Edge telemetry collection agent"

    # Start the task immediately
    Write-Host "Starting scheduled task: $ServiceName"
    Start-ScheduledTask -TaskName $ServiceName

    # Check if the task started and the process is running
    Start-Sleep -Seconds 5
    $processes = Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($EdgeExe)) -ErrorAction SilentlyContinue

    if ($processes.Count -gt 0) {
        Write-Host "Observo Edge started successfully as a scheduled task." -ForegroundColor Green
        Write-Host "Process ID(s): $($processes.Id -join ', ')"
        Write-Host "You can view logs using View-ObservoLogs command."
    } else {
        Write-Host "Warning: The scheduled task was created but the process may not have started." -ForegroundColor Yellow

        # Try to start manually for debugging
        Write-Host "Attempting to start the binary directly for debugging..."
        $processInfo = Start-Process -FilePath $EdgeExe -ArgumentList "-config `"$ConfigFile`"" -PassThru -NoNewWindow -RedirectStandardOutput $StdoutLogFile -RedirectStandardError $StderrLogFile
        Write-Host "Manual process started with PID: $($processInfo.Id)"

        # Give it a few seconds to initialize
        Start-Sleep -Seconds 10

        if ($processInfo.HasExited) {
            Write-Host "Process exited with code: $($processInfo.ExitCode)" -ForegroundColor Red
            Write-Host "Check logs for details using View-ObservoLogs command."
        } else {
            Write-Host "Process is running. Check logs using View-ObservoLogs command."
        }
    }

    # Show the scheduled task status
    Get-ScheduledTask -TaskName $ServiceName | Format-List State, LastRunTime, LastTaskResult
}

function Install-AsScheduledTask {
    Write-Host "Installing Observo Edge as a scheduled task..."

    # Check if service already exists and remove it
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Host "Service exists. Stopping and removing..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        sc.exe delete $ServiceName
        Start-Sleep -Seconds 2
    }

    # Check if task already exists and remove it
    $taskExists = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
    if ($taskExists) {
        Write-Host "Scheduled task exists. Removing..."
        Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false
    }

    # Verify the binary and config file exist
    Write-Host "Verifying binary and config file exist:"
    $binaryExists = Test-Path -Path $EdgeExe
    $configExists = Test-Path -Path $ConfigFile
    Write-Host "Binary: $binaryExists"
    Write-Host "Config: $configExists"

    if (-not $binaryExists -or -not $configExists) {
        Write-Host "Error: Binary or config file missing!" -ForegroundColor Red
        exit 1
    }

    # Create log directory if it doesn't exist
    if (-not (Test-Path -Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Write-Host "Created log directory: $LogDir"
    }
    $MachineGuid = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
    Write-Host "MachineGuid: $MachineGuid"

    # Create a wrapper script that will run the edge binary and redirect all output to stdout log file
    $WrapperScript = @"
@echo off
set OTEL_LOG_FILE_PATH=$EdgeCollectorLogFile
set OTEL_EXECUTABLE_PATH=$OtelExecutablePath
set AGENT_ID=$MachineGuid
echo Starting Observo Edge Agent at %DATE% %TIME% > "$StdoutLogFile"
    "$EdgeExe" -config "$ConfigFile" >> "$StdoutLogFile" 2>&1
"@

    $WrapperPath = "$InstallDir\run_observo.cmd"
    Set-Content -Path $WrapperPath -Value $WrapperScript
    Write-Host "Created wrapper script: $WrapperPath"

    # Create the action to run the wrapper script
    $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$WrapperPath`""

    # Create the trigger (at system startup)
    $trigger = New-ScheduledTaskTrigger -AtStartup

    # Configure the settings
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    # Create the principal (run as SYSTEM with highest privileges)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    # Register the task
    Register-ScheduledTask -TaskName $ServiceName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Observo Edge telemetry collection agent"

    # Start the task immediately
    Write-Host "Starting scheduled task: $ServiceName"
    Start-ScheduledTask -TaskName $ServiceName

    # Check if the task started and the process is running
    Start-Sleep -Seconds 5
    $processes = Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($EdgeExe)) -ErrorAction SilentlyContinue

    if ($processes.Count -gt 0) {
        Write-Host "Observo Edge started successfully as a scheduled task." -ForegroundColor Green
        Write-Host "Process ID(s): $($processes.Id -join ', ')"
    } else {
        Write-Host "Warning: The scheduled task was created but the process may not have started." -ForegroundColor Yellow
    }

    # Show the scheduled task status
    Get-ScheduledTask -TaskName $ServiceName | Format-List State, LastRunTime, LastTaskResult
}

# Main execution flow
Write-Host $ObservoHeading

# Parse command line arguments
$installId = $args[1]
if (-not (Parse-EnvironmentVariable -EnvVar $installId)) {
    Write-Host "Usage: .\install-observo.ps1 -EnvVar 'install_id=<JWT Token> download_url=<Custom URL>'"
    Write-Host "Note: download_url is optional. If not provided, the default URL will be used."
    exit 1
}

# Add a function to view the logs
function View-ObservoLogs {
    param (
        [Parameter(Mandatory=$false)]
        [int]$Lines = 50,

        [Parameter(Mandatory=$false)]
        [switch]$Errors,

        [Parameter(Mandatory=$false)]
        [switch]$Follow
    )

    $LogFile = if ($Errors) { $StderrLogFile } else { $StdoutLogFile }

    if (-not (Test-Path -Path $LogFile)) {
        Write-Host "Log file not found: $LogFile" -ForegroundColor Yellow
        return
    }

    if ($Follow) {
        Write-Host "Showing logs from $LogFile (Press Ctrl+C to exit)" -ForegroundColor Cyan
        Get-Content -Path $LogFile -Tail $Lines -Wait
    } else {
        Write-Host "Last $Lines lines from ${LogFile}:" -ForegroundColor Cyan
        Get-Content -Path $LogFile -Tail $Lines
    }
}

function Show-InstallationCompleteMessage {
    Write-Host "Installation completed!"
    Write-Host ""
    Write-Host "Log file is stored at: $StdoutLogFile"
}

# Check prerequisites
Check-Prerequisites

# Detect system architecture
Detect-System

# Decode and extract configuration
Decode-AndExtractConfig

# Setup CA certificate if provided
Setup-CaCertificate

# Download and extract the agent
Download-AndExtractAgent

# Move binaries to installation directory
Move-BinariesToInstallDir

# Install and start service
Install-AsScheduledTask

Show-InstallationCompleteMessage