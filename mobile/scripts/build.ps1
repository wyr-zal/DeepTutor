param(
    [ValidateSet("debug", "release", "both")]
    [string]$Mode = "both"
)

$batch = Join-Path $PSScriptRoot "build.bat"
& "$env:SystemRoot\System32\cmd.exe" /d /c call $batch $Mode
exit $LASTEXITCODE
