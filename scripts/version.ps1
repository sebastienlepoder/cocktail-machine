# Version Management Script for Cocktail Machine Project (PowerShell)
# Manages versions across all project components

param(
    [Parameter(Position=0)]
    [string]$Command = "help",
    
    [Parameter(Position=1)]
    [string]$Value = ""
)

$PROJECT_ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$VERSION_FILE = Join-Path $PROJECT_ROOT "VERSION"

# Helper functions
function Write-Info { Write-Host "ℹ $args" -ForegroundColor Blue }
function Write-Success { Write-Host "✓ $args" -ForegroundColor Green }
function Write-Warning { Write-Host "⚠ $args" -ForegroundColor Yellow }
function Write-Error { Write-Host "✗ $args" -ForegroundColor Red }

# Get current version
function Get-Version {
    if (Test-Path $VERSION_FILE) {
        Get-Content $VERSION_FILE -Raw | ForEach-Object { $_.Trim() }
    } else {
        "1.0.0"
    }
}

# Set version
function Set-Version {
    param([string]$NewVersion)
    
    if ($NewVersion -notmatch '^\d+\.\d+\.\d+$') {
        Write-Error "Version must be in format X.Y.Z (e.g., 1.0.0)"
        exit 1
    }
    
    Set-Content -Path $VERSION_FILE -Value $NewVersion
    Write-Success "Version set to $NewVersion"
    Update-AllComponents $NewVersion
}

# Bump version
function Update-Version {
    param([string]$BumpType)
    
    $CurrentVersion = Get-Version
    $VersionParts = $CurrentVersion.Split('.')
    $Major = [int]$VersionParts[0]
    $Minor = [int]$VersionParts[1]
    $Patch = [int]$VersionParts[2]
    
    switch ($BumpType.ToLower()) {
        "major" {
            $Major++
            $Minor = 0
            $Patch = 0
        }
        "minor" {
            $Minor++
            $Patch = 0
        }
        "patch" {
            $Patch++
        }
        default {
            Write-Error "Bump type must be: major, minor, or patch"
            exit 1
        }
    }
    
    $NewVersion = "$Major.$Minor.$Patch"
    Set-Content -Path $VERSION_FILE -Value $NewVersion
    Write-Success "Version bumped from $CurrentVersion to $NewVersion"
    Update-AllComponents $NewVersion
}

# Update all components with new version
function Update-AllComponents {
    param([string]$Version)
    
    $DateVersion = "$(Get-Date -Format 'yyyy.MM.dd')-v$Version"
    $BuildNumber = "Build-$((Get-Date).Ticks % 1000 | ForEach-Object { $_.ToString('000') })"
    
    Write-Info "Updating component versions..."
    
    # Update setup scripts
    $SetupScript1 = Join-Path $PROJECT_ROOT "deployment\setup-ultimate.sh"
    if (Test-Path $SetupScript1) {
        (Get-Content $SetupScript1) -replace 'SCRIPT_VERSION="[^"]*"', "SCRIPT_VERSION=`"$DateVersion`"" -replace 'SCRIPT_BUILD="[^"]*"', "SCRIPT_BUILD=`"$BuildNumber`"" | Set-Content $SetupScript1
        Write-Success "Updated deployment/setup-ultimate.sh"
    }
    
    $SetupScript2 = Join-Path $PROJECT_ROOT "scripts\setup-ultimate.sh"
    if (Test-Path $SetupScript2) {
        (Get-Content $SetupScript2) -replace 'SCRIPT_VERSION="[^"]*"', "SCRIPT_VERSION=`"$DateVersion`"" -replace 'SCRIPT_BUILD="[^"]*"', "SCRIPT_BUILD=`"$BuildNumber`"" | Set-Content $SetupScript2
        Write-Success "Updated scripts/setup-ultimate.sh"
    }
    
    # Update web package.json
    $WebPackage = Join-Path $PROJECT_ROOT "web\package.json"
    if (Test-Path $WebPackage) {
        $PackageContent = Get-Content $WebPackage | ConvertFrom-Json
        $PackageContent.version = $Version
        $PackageContent | ConvertTo-Json -Depth 10 | Set-Content $WebPackage
        Write-Success "Updated web/package.json"
    }
    
    # Update Node-RED package.json
    $NodeRedPackage = Join-Path $PROJECT_ROOT "node-red\settings\package.json"
    if (Test-Path $NodeRedPackage) {
        $PackageContent = Get-Content $NodeRedPackage | ConvertFrom-Json
        $PackageContent.version = $Version
        $PackageContent | ConvertTo-Json -Depth 10 | Set-Content $NodeRedPackage
        Write-Success "Updated node-red/settings/package.json"
    }
    
    # Update web VERSION file with git commit hash if available
    $WebVersion = Join-Path $PROJECT_ROOT "web\VERSION"
    if (Test-Path $WebVersion) {
        $CommitHash = ""
        try {
            if (Get-Command git -ErrorAction SilentlyContinue) {
                $CommitHash = git rev-parse --short HEAD 2>$null
                if ($CommitHash) {
                    Set-Content -Path $WebVersion -Value "v$DateVersion-$CommitHash"
                } else {
                    Set-Content -Path $WebVersion -Value "v$DateVersion"
                }
            } else {
                Set-Content -Path $WebVersion -Value "v$DateVersion"
            }
        } catch {
            Set-Content -Path $WebVersion -Value "v$DateVersion"
        }
        Write-Success "Updated web/VERSION"
    }
    
    Write-Success "All components updated to version $Version"
}

# Show current versions across all components
function Show-Versions {
    Write-Info "Current project versions:"
    Write-Host ""
    
    # Main version
    $MainVersion = Get-Version
    Write-Host "📦 Project Version: $MainVersion"
    Write-Host ""
    
    # Component versions
    Write-Host "🔧 Component Versions:"
    
    $SetupScript1 = Join-Path $PROJECT_ROOT "deployment\setup-ultimate.sh"
    if (Test-Path $SetupScript1) {
        $ScriptVersion = (Get-Content $SetupScript1 | Select-String 'SCRIPT_VERSION=' | Select-Object -First 1) -replace '.*SCRIPT_VERSION="([^"]*)".*', '$1'
        Write-Host "  • Setup Script (deployment): $ScriptVersion"
    }
    
    $SetupScript2 = Join-Path $PROJECT_ROOT "scripts\setup-ultimate.sh"
    if (Test-Path $SetupScript2) {
        $ScriptVersion = (Get-Content $SetupScript2 | Select-String 'SCRIPT_VERSION=' | Select-Object -First 1) -replace '.*SCRIPT_VERSION="([^"]*)".*', '$1'
        Write-Host "  • Setup Script (scripts): $ScriptVersion"
    }
    
    $WebPackage = Join-Path $PROJECT_ROOT "web\package.json"
    if (Test-Path $WebPackage) {
        $PackageContent = Get-Content $WebPackage | ConvertFrom-Json
        Write-Host "  • Web Dashboard: $($PackageContent.version)"
    }
    
    $WebVersion = Join-Path $PROJECT_ROOT "web\VERSION"
    if (Test-Path $WebVersion) {
        $WebDetailedVersion = Get-Content $WebVersion -Raw | ForEach-Object { $_.Trim() }
        Write-Host "  • Web Deployment: $WebDetailedVersion"
    }
    
    $NodeRedPackage = Join-Path $PROJECT_ROOT "node-red\settings\package.json"
    if (Test-Path $NodeRedPackage) {
        $PackageContent = Get-Content $NodeRedPackage | ConvertFrom-Json
        Write-Host "  • Node-RED: $($PackageContent.version)"
    }
    
    Write-Host ""
}

# Main script logic
switch ($Command.ToLower()) {
    "get" {
        Get-Version
    }
    "set" {
        if ([string]::IsNullOrEmpty($Value)) {
            Write-Error "Please specify version (e.g., .\version.ps1 set 1.2.3)"
            exit 1
        }
        Set-Version $Value
    }
    "bump" {
        if ([string]::IsNullOrEmpty($Value)) {
            Write-Error "Please specify bump type: major, minor, or patch"
            exit 1
        }
        Update-Version $Value
    }
    { $_ -eq "show" -or $_ -eq "status" } {
        Show-Versions
    }
    "sync" {
        $CurrentVersion = Get-Version
        Update-AllComponents $CurrentVersion
    }
    default {
        Write-Host "Cocktail Machine Version Manager (PowerShell)"
        Write-Host ""
        Write-Host "Usage: .\version.ps1 <command> [arguments]"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  get                    Get current project version"
        Write-Host "  set <version>         Set project version (e.g., 1.2.3)"
        Write-Host "  bump <type>           Bump version (major|minor|patch)"
        Write-Host "  show                  Show all component versions"
        Write-Host "  sync                  Sync all components to main version"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  .\version.ps1 get                # Shows: 1.0.5"
        Write-Host "  .\version.ps1 set 1.1.0         # Sets version to 1.1.0"
        Write-Host "  .\version.ps1 bump patch        # 1.0.5 -> 1.0.6"
        Write-Host "  .\version.ps1 bump minor        # 1.0.5 -> 1.1.0"
        Write-Host "  .\version.ps1 bump major        # 1.0.5 -> 2.0.0"
        Write-Host "  .\version.ps1 show              # Lists all versions"
        Write-Host "  .\version.ps1 sync              # Updates all components"
        Write-Host ""
    }
}
