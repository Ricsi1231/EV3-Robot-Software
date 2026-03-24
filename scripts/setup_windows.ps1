# =============================================================================
# EV3 Pybricks Development Environment Setup - Windows
# =============================================================================
#
# Usage:
#   .\scripts\setup_windows.ps1
#
# If blocked by execution policy, run this first (as admin):
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# =============================================================================

# -- Output helpers ------------------------------------------------------------
function Write-Info    { param($Msg) Write-Host "[INFO] " -ForegroundColor Blue -NoNewline; Write-Host $Msg }
function Write-Success { param($Msg) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Warn    { param($Msg) Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Write-Err     { param($Msg) Write-Host "[ERROR] " -ForegroundColor Red -NoNewline; Write-Host $Msg }
function Write-Header  { param($Msg) Write-Host "`n=== $Msg ===`n" -ForegroundColor Cyan }

# -- Resolve project root ------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# -- Check execution policy ----------------------------------------------------
$currentPolicy = Get-ExecutionPolicy
if ($currentPolicy -eq "Restricted") {
    Write-Err "PowerShell execution policy is 'Restricted'."
    Write-Err "Run this command in an admin PowerShell first:"
    Write-Host "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Cyan
    exit 1
}

# -- Find Python ---------------------------------------------------------------
function Find-Python {
    Write-Header "Checking Python Installation"

    $pythonCmd = $null
    $version = $null

    # Try 'py' launcher first (standard on Windows)
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $pythonCmd = "py"
        $version = & py -3 --version 2>&1
        if ($LASTEXITCODE -ne 0) { $pythonCmd = $null }
    }

    # Try 'python'
    if (-not $pythonCmd) {
        if (Get-Command python -ErrorAction SilentlyContinue) {
            $pythonCmd = "python"
            $version = & python --version 2>&1
        }
    }

    # Try 'python3'
    if (-not $pythonCmd) {
        if (Get-Command python3 -ErrorAction SilentlyContinue) {
            $pythonCmd = "python3"
            $version = & python3 --version 2>&1
        }
    }

    if (-not $pythonCmd) {
        Write-Err "Python not found."
        Write-Err "Please install Python 3.10+ from https://www.python.org/downloads/"
        Write-Err "Make sure to check 'Add Python to PATH' during installation."
        exit 1
    }

    # Parse and validate version
    $versionStr = "$version"
    $match = [regex]::Match($versionStr, '(\d+)\.(\d+)\.(\d+)')
    if (-not $match.Success) {
        Write-Err "Could not parse Python version from: $versionStr"
        exit 1
    }

    $major = [int]$match.Groups[1].Value
    $minor = [int]$match.Groups[2].Value

    if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 10)) {
        Write-Err "Python 3.10+ required. Found: $versionStr"
        exit 1
    }

    Write-Success "Found: $versionStr (using '$pythonCmd')"
    return $pythonCmd
}

# -- Create virtual environment ------------------------------------------------
function New-VirtualEnvironment {
    param([string]$PythonCmd)

    Write-Header "Setting Up Virtual Environment"

    $venvDir = Join-Path $ProjectRoot ".venv"

    if (Test-Path $venvDir) {
        Write-Info "Virtual environment already exists at $venvDir"
        Write-Info "To recreate, delete it first: Remove-Item -Recurse -Force $venvDir"
    }
    else {
        Write-Info "Creating virtual environment at $venvDir..."
        if ($PythonCmd -eq "py") {
            & py -3 -m venv $venvDir
        }
        else {
            & $PythonCmd -m venv $venvDir
        }

        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvDir)) {
            Write-Err "Failed to create virtual environment."
            exit 1
        }
        Write-Success "Virtual environment created."
    }

    # Activate
    $activateScript = Join-Path $venvDir "Scripts\Activate.ps1"
    if (Test-Path $activateScript) {
        & $activateScript
        Write-Info "Virtual environment activated."
    }
    else {
        Write-Err "Activation script not found at $activateScript"
        exit 1
    }

    # Upgrade pip
    Write-Info "Upgrading pip..."
    & pip install --upgrade pip --quiet 2>$null
    Write-Success "pip upgraded."
}

# -- Install Python packages ---------------------------------------------------
function Install-PythonPackages {
    Write-Header "Installing Python Packages"

    $requirements = Join-Path $ProjectRoot "requirements.txt"
    if (-not (Test-Path $requirements)) {
        Write-Err "requirements.txt not found at $requirements"
        exit 1
    }

    Write-Info "Installing packages from requirements.txt..."
    & pip install -r $requirements

    if ($LASTEXITCODE -ne 0) {
        Write-Err "Package installation failed."
        Write-Warn "If hidapi or other packages fail to build, you may need Visual C++ Build Tools."
        Write-Warn "Download from: https://visualstudio.microsoft.com/visual-cpp-build-tools/"
        exit 1
    }

    Write-Success "Python packages installed."

    # Verify
    Write-Info "Verifying installations..."
    & python -c "import pybricksdev; print('  pybricksdev: ' + pybricksdev.__version__)" 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Warn "Could not verify pybricksdev import" }
}

# -- VS Code extensions --------------------------------------------------------
function Install-VSCodeExtensions {
    Write-Header "VS Code Extensions"

    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-Info "VS Code CLI not found. If you use VS Code, install these extensions:"
        Write-Info "  - lego-education.ev3-micropython"
        Write-Info "  - ms-python.python"
        Write-Info "  - ms-python.vscode-pylance"
        return
    }

    Write-Info "Installing recommended VS Code extensions..."

    $extensions = @("lego-education.ev3-micropython", "ms-python.python", "ms-python.vscode-pylance")
    $installed = & code --list-extensions 2>$null

    foreach ($ext in $extensions) {
        if ($installed -match $ext) {
            Write-Info "  $ext (already installed)"
        }
        else {
            & code --install-extension $ext --force 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "  Installed $ext"
            }
            else {
                Write-Warn "  Failed to install $ext"
            }
        }
    }
}

# -- Summary -------------------------------------------------------------------
function Write-Summary {
    Write-Header "Setup Complete!"

    Write-Host "What was configured:" -ForegroundColor Green
    Write-Host "  * Python virtual environment: $ProjectRoot\.venv"
    Write-Host "  * Python packages from requirements.txt"
    Write-Host "  * VS Code extensions (if VS Code was found)"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Activate the virtual environment:" -ForegroundColor White
    Write-Host "     .venv\Scripts\Activate.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2. Prepare a microSD card with the EV3 MicroPython image:" -ForegroundColor White
    Write-Host "     https://pybricks.com/install/mindstorms-ev3/installation/" -ForegroundColor Cyan
    Write-Host "     Download the ~360MB image and flash it with Etcher." -ForegroundColor White
    Write-Host ""
    Write-Host "  3. Insert the microSD card into your EV3 and boot it up." -ForegroundColor White
    Write-Host "     (Status light turns green when ready)" -ForegroundColor White
    Write-Host ""
    Write-Host "  4. Connect the EV3 via mini-USB cable." -ForegroundColor White
    Write-Host "     The EV3 should appear as a USB network device." -ForegroundColor White
    Write-Host "     If Windows does not recognize it:" -ForegroundColor White
    Write-Host "       - Open Device Manager" -ForegroundColor White
    Write-Host "       - Look for EV3 under 'Other devices' or 'Network adapters'" -ForegroundColor White
    Write-Host "       - The EV3 MicroPython VS Code extension handles" -ForegroundColor White
    Write-Host "         communication automatically when connected via USB" -ForegroundColor White
    Write-Host ""
    Write-Host "  5. Open VS Code in this project directory:" -ForegroundColor White
    Write-Host "     code $ProjectRoot" -ForegroundColor Cyan
    Write-Host ""
}

# -- Main ----------------------------------------------------------------------
Write-Header "EV3 Pybricks Development Environment Setup"
Write-Info "Project: $ProjectRoot"

$pythonCmd = Find-Python
New-VirtualEnvironment -PythonCmd $pythonCmd
Install-PythonPackages
Install-VSCodeExtensions
Write-Summary
