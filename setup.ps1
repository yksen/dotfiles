param (
    [switch]$r
)

$run = $r
$sourceDir = Resolve-Path .
$targetDir = $HOME
$files = Get-ChildItem -Path $sourceDir -File -Recurse | Where-Object { $_.Name -ne "README.md" -and $_.Name -notmatch "setup" -and $_.FullName -notmatch "\\.git\\" -and $_.FullName -notmatch "\\bash\\"}

foreach ($file in $files) {
    $targetPath = $file.FullName
    $sourcePath = $file.FullName.Replace($sourceDir, '')
    $sourcePath = $sourcePath.Substring($sourcePath.IndexOf('\', 1))
    $sourcePath = Join-Path $targetDir $sourcePath

    if ($run) {
        New-Item -ItemType Directory -Path (Split-Path -Path $sourcePath -Parent) -Force
        New-Item -ItemType SymbolicLink -Target $targetPath -Path $sourcePath -Force
    }
    else {
        Write-Output "New-Item -ItemType SymbolicLink -Target $targetPath -Path $sourcePath -Force"
    }
}

if (-not $run) {
    Write-Output "This was a dry run, use with -r to execute"
}