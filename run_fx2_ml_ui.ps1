param(
    [string]$Python = 'D:\Programs\cyclone2-handwriting-ml-venv\Scripts\python.exe'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
& $Python (Join-Path $repo 'python\fx2_ml_ui.py')
if ($LASTEXITCODE -ne 0) {
    throw "FX2 ML UI exited with code $LASTEXITCODE"
}
