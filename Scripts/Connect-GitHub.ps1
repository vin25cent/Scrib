[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$gh = "C:\Program Files\GitHub CLI\gh.exe"

if (-not (Test-Path -LiteralPath $gh)) {
    throw "GitHub CLI est introuvable : $gh"
}

& $gh auth login `
    --hostname github.com `
    --git-protocol https `
    --web `
    --clipboard

if ($LASTEXITCODE -eq 0) {
    Write-Host "Connexion GitHub terminée. Tu peux fermer cette fenêtre." -ForegroundColor Green
} else {
    Write-Host "La connexion GitHub n'a pas abouti." -ForegroundColor Red
}

Read-Host "Appuie sur Entrée pour fermer"
