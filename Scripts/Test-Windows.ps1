[CmdletBinding()]
param(
    [switch] $CleanEnvironment
)

$ErrorActionPreference = "Stop"

# Certains hotes injectent a la fois Path et PATH. On relance le script une fois
# avec l'environnement Windows standard, qui ne contient qu'une seule cle PATH.
if (-not $CleanEnvironment) {
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershell
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -CleanEnvironment"
    $startInfo.UseShellExecute = $false

    $cleanVariables = New-Object System.Collections.Specialized.StringDictionary
    foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
        if ($entry.Key -ine "Path") {
            $cleanVariables[$entry.Key] = $entry.Value
        }
    }
    $cleanVariables["Path"] = $env:Path

    # Le getter .NET échoue avant de rendre la collection lorsque le processus
    # parent contient Path et PATH. On fournit directement la collection saine.
    $flags = [Reflection.BindingFlags] "NonPublic,Instance"
    $field = $startInfo.GetType().GetField("environmentVariables", $flags)
    $field.SetValue($startInfo, $cleanVariables)

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $process.WaitForExit()
    exit $process.ExitCode
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw "Visual Studio Build Tools est introuvable."
}

$vsInstallPath = & $vswhere `
    -latest `
    -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath

if (-not $vsInstallPath) {
    throw "Les outils C++ x64 de Visual Studio sont introuvables."
}

$devShellModule = Join-Path $vsInstallPath "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
Import-Module $devShellModule
Enter-VsDevShell `
    -VsInstallPath $vsInstallPath `
    -SkipAutomaticLocation `
    -DevCmdArguments "-arch=x64 -host_arch=x64"

$localAppData = [Environment]::GetFolderPath("LocalApplicationData")
$swiftRoot = Join-Path $localAppData "Programs\Swift"
$toolchain = Get-ChildItem -LiteralPath (Join-Path $swiftRoot "Toolchains") -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $toolchain) {
    throw "Aucun toolchain Swift n'est installé."
}

$swiftVersion = $toolchain.Name -replace "\+.*$", ""
$toolchainBin = Join-Path $toolchain.FullName "usr\bin"
$runtimeBin = Join-Path $swiftRoot "Runtimes\$swiftVersion\usr\bin"
$env:SDKROOT = Join-Path $swiftRoot "Platforms\$swiftVersion\Windows.platform\Developer\SDKs\Windows.sdk"

if (-not (Test-Path -LiteralPath $env:SDKROOT)) {
    throw "Le SDK Windows de Swift est introuvable : $env:SDKROOT"
}

# Certains hôtes injectent à la fois Path et PATH. Swift les considère comme des
# clés en double ; on reconstruit donc une seule variable pour ce processus.
$developerPath = $env:Path
Remove-Item Env:PATH -ErrorAction SilentlyContinue
$env:Path = "$toolchainBin;$runtimeBin;$developerPath"

& (Join-Path $toolchainBin "swift.exe") --version
& (Join-Path $toolchainBin "swift.exe") test
exit $LASTEXITCODE
