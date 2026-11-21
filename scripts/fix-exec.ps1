# =============================================================================
#  fix-exec.ps1 - mark the scripts as executable and refresh the workflows
# =============================================================================
#  The Windows version of scripts/fix-exec.sh.
#
#  Why this is needed:
#    Files that are uploaded through the GitHub API are created without the
#    executable bit (mode 100644). The workflows then die with
#    "Permission denied" (exit 126).
#    On Windows there is no chmod - Git for Windows normally has
#    core.fileMode=false, so the bit has to be set in the index directly:
#        git update-index --chmod=+x
#
#  What it does:
#    1. sets the executable bit in the git index (100755)
#    2. copies the workflows from automation\ into .github\workflows\
#    3. prints the commit command - the commit and the push are left to you
#
#  Usage (PowerShell, in the repository root):
#      powershell -ExecutionPolicy Bypass -File scripts\fix-exec.ps1
#      # or simply:
#      .\scripts\fix-exec.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "=== 1. the executable bit in the index ==="
$files = @(Get-ChildItem -Path scripts -Include *.sh,*.py -File | ForEach-Object { $_.FullName })
if ($files.Count -eq 0) { throw "no scripts found in scripts\" }
git update-index --add --chmod=+x -- $files
if ($LASTEXITCODE -ne 0) { throw "git update-index failed" }
git ls-files -s scripts/ | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== 2. the workflows ==="
if ((Test-Path automation) -and (Test-Path .github\workflows)) {
    Copy-Item -Path automation\*.yml -Destination .github\workflows\ -Force
    Write-Host "  automation\*.yml -> .github\workflows\"
} else {
    Write-Host "  skipped: automation\ or .github\workflows\ is missing"
}

Write-Host ""
Write-Host "=== 3. commit ==="
Write-Host '  git commit -m "chore: exec bit for the scripts, hardened workflows"'
Write-Host "  git push"

Write-Host ""
Write-Host "Running the scripts themselves (they are bash):"
Write-Host "  Git Bash:   bash scripts/build-ruleset.sh"
Write-Host "  WSL:        wsl bash scripts/build-ruleset.sh"
Write-Host "  PowerShell cannot run them directly - use Git Bash or WSL."
