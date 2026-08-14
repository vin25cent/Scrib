param(
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repositoryRoot 'Benchmarks\DemoAudio\sources.json'
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path $repositoryRoot 'Benchmarks\DemoAudio\Local'
}

$destinationRoot = [System.IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
$headers = @{ 'User-Agent' = 'Scrib-DemoAudio-Downloader/1.0 (https://github.com/vin25cent/Scrib)' }

foreach ($source in $manifest.sources) {
    $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $destinationRoot $source.fileName))
    if (-not $destinationPath.StartsWith($destinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Chemin de destination invalide pour $($source.fileName)."
    }

    if (Test-Path -LiteralPath $destinationPath) {
        $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destinationPath).Hash
        if ($currentHash -ne $source.sha256) {
            throw "Empreinte invalide pour $($source.fileName). Supprimez manuellement le fichier local avant de réessayer."
        }
        Write-Host "Déjà vérifié : $($source.fileName)"
        continue
    }

    $temporaryPath = "$destinationPath.download"
    $downloaded = $false
    for ($attempt = 1; $attempt -le 3 -and -not $downloaded; $attempt++) {
        try {
            Invoke-WebRequest -Uri $source.downloadURL -Headers $headers -OutFile $temporaryPath
            $downloaded = $true
        } catch {
            if ($attempt -eq 3) { throw }
            Start-Sleep -Seconds (5 * $attempt)
        }
    }

    $downloadHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporaryPath).Hash
    if ($downloadHash -ne $source.sha256) {
        throw "Le téléchargement de $($source.fileName) ne correspond pas à l'empreinte publiée dans le manifeste."
    }
    Move-Item -LiteralPath $temporaryPath -Destination $destinationPath
    Write-Host "Téléchargé et vérifié : $($source.fileName)"
    Start-Sleep -Seconds 2
}

Write-Host "Audios prêts dans $destinationRoot"
