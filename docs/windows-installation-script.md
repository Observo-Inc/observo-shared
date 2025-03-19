# Observo Edge Installation in Windows System

## Overview

This PowerShell script automates the installation and configuration of the Observo Edge agent on Windows systems. It sets up the agent to run as a scheduled task with system privileges and provides comprehensive logging capabilities.

## System Requirements

- **Operating System**: Windows (64-bit only)
- **Architecture**: AMD64/x86_64 architecture
- **PowerShell**: Version 5.1 or higher recommended
- **Permissions**: Administrative privileges required for installation
## Dependencies & Tools

- **PowerShell Modules**:
    - Microsoft.PowerShell.Archive (for extracting the agent binaries)
    - NuGet package provider (Automatically installed if Powershell version less than 5.1)

## Installation Process

1. Validates prerequisites and PowerShell modules
2. Detects system architecture to confirm compatibility
3. Decodes the provided token to extract agent configuration
4. Downloads and extracts the agent binaries from a secure URL
5. Moves binaries to the installation directory (`C:\Program Files\Observo`)
6. Creates a scheduled task to run the agent at system startup as SYSTEM user
7. Configures log redirection to capture all agent output

## Installation Command

Run the script with the installation token:
```powershell
.\install-observo.ps1 -e 'install_id=<Token>'
```

## Monitoring & Management

### Log Location
All agent output is consolidated in a single log file:
```
C:\Program Files\Observo\logs\observoedge_stdout.log
```

### Checking Process Status
To verify the agent is running:
```powershell
Get-Process -Name "edge" -ErrorAction SilentlyContinue
```

### Managing the Scheduled Task
```powershell
# View task status
Get-ScheduledTask -TaskName "ObservoEdge"

# Stop the agent
Stop-ScheduledTask -TaskName "ObservoEdge"

# Start the agent
Start-ScheduledTask -TaskName "ObservoEdge"
```

### Process Management
```powershell
# Stop the agent process
Stop-Process -Name "edge" -Force

# Find process ID
Get-Process -Name "edge" | Select-Object Id
```

## Installation Artifacts

- **Installation Directory**: `C:\Program Files\Observo`
- **Configuration File**: `C:\Program Files\Observo\edge-config.json`
- **Historical Configs**: `C:\Program Files\Observo\history\`
- **Scheduled Task**: "ObservoEdge" (visible in Task Scheduler)

## Troubleshooting

- Check the log file for detailed error messages
- Verify the scheduled task is running with "Ready" status
- Confirm the system has network connectivity to the Observo backend
- Verify the agent has appropriate permissions to access required resources

## Security Considerations

- The agent runs with SYSTEM privileges to ensure proper functionality
- All configuration data is stored securely in the Program Files directory
- The agent communicates with the Observo backend using secure authentication tokens