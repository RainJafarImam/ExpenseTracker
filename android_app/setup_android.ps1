# One-click setup for the Expense Tracker Android app.
#
#   Double-click setup_android.bat   (or run: powershell -ExecutionPolicy Bypass -File .\setup_android.ps1)
#
# What it does:
#   1. checks that Flutter is installed
#   2. generates the Android project files (keeps your lib/, pubspec.yaml, assets/)
#   3. removes Flutter's demo test and sets the app name + Auto Backup in the manifest
#   4. installs packages, analyzes the code, runs the tests
#   5. builds a release APK you can install or share
#
# Options:
#   -Org com.yourname   app id prefix (CHANGE this before sharing the APK; default com.example)
#   -SkipTests          skip "flutter test"
#   -Run                run the app on a connected phone/emulator instead of building the APK

param(
    [string]$Org = "com.example",
    [switch]$SkipTests,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Step([string]$Text) { Write-Host ""; Write-Host "== $Text ==" -ForegroundColor Cyan }
function Fail([string]$Text) { Write-Host ""; Write-Host "ERROR: $Text" -ForegroundColor Red; exit 1 }
function Run([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        Fail "'$Exe $($Arguments -join ' ')' failed (exit code $LASTEXITCODE). Copy the output above and send it to Claude."
    }
}
function ReadText([string]$Path) { [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot $Path)) }
function WriteText([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot $Path), $Text)  # UTF-8 without BOM
}

# ---------------------------------------------------------------- 1. Flutter
Step "Checking Flutter"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Fail ("Flutter is not installed or not on PATH.`n" +
          "Install it from https://docs.flutter.dev/get-started/install/windows (with Android Studio),`n" +
          "open a NEW PowerShell window, and run this script again.")
}
Run "flutter" @("--version")

if ($Org -eq "com.example") {
    Write-Host "Note: using the placeholder app id prefix 'com.example'. Re-run with -Org com.yourname before sharing the APK." -ForegroundColor Yellow
}

# ------------------------------------------------- 2. Generate Android files
Step "Generating Android project files"
# Keep our own files safe in case flutter create touches them.
$mainDart = ReadText "lib\main.dart"
$pubspec  = ReadText "pubspec.yaml"

Run "flutter" @("create", "--project-name", "expense_tracker", "--org", $Org, "--platforms", "android", ".")

WriteText "lib\main.dart" $mainDart
WriteText "pubspec.yaml" $pubspec

# ------------------------------------------------------------ 3. Fix-ups
Step "Applying settings"
$demoTest = Join-Path $PSScriptRoot "test\widget_test.dart"
if (Test-Path $demoTest) { Remove-Item $demoTest -Force; Write-Host "Removed Flutter's demo test." }

$manifestPath = "android\app\src\main\AndroidManifest.xml"
if (Test-Path (Join-Path $PSScriptRoot $manifestPath)) {
    $manifest = ReadText $manifestPath
    $manifest = [regex]::Replace($manifest, '(<application[^>]*?)android:label="[^"]*"', '${1}android:label="Expense Tracker"')
    if ($manifest -notmatch 'android:allowBackup') {
        $manifest = $manifest -replace '<application', "<application`n        android:allowBackup=`"true`""
    }
    WriteText $manifestPath $manifest
    Write-Host "App name set to 'Expense Tracker'; Android Auto Backup enabled."
} else {
    Write-Host "Could not find AndroidManifest.xml; check android:label and android:allowBackup by hand." -ForegroundColor Yellow
}

# --------------------------------------------------- 4. Packages and checks
Step "Installing packages"
Run "flutter" @("pub", "get")

Step "Accepting Android licenses (if needed)"
try {
    $ErrorActionPreference = "Continue"
    (1..40 | ForEach-Object { "y" }) | flutter doctor --android-licenses 2>&1 | Out-Null
} catch { }
$ErrorActionPreference = "Stop"

Step "Analyzing the code"
Run "flutter" @("analyze", "--no-fatal-infos", "--no-fatal-warnings")

if (-not $SkipTests) {
    Step "Running tests"
    & flutter test
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Some tests failed. If the message mentions sqlite3.dll, the tests need desktop SQLite; the app itself does not." -ForegroundColor Yellow
        Write-Host "Continuing with the build. Send the test output to Claude if it is not the sqlite3.dll problem." -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------- 5. Build / run
if ($Run) {
    Step "Running on a connected device (turn on USB debugging, or start an emulator)"
    Run "flutter" @("run")
    exit 0
}

Step "Building the release APK"
Run "flutter" @("build", "apk", "--release")

$apk = Join-Path $PSScriptRoot "build\app\outputs\flutter-apk\app-release.apk"
Write-Host ""
Write-Host "Done. APK:" -ForegroundColor Green
Write-Host "  $apk"
Write-Host "Copy it to a phone and open it (allow 'install unknown apps' when asked)."
if (Test-Path $apk) { explorer.exe "/select,$apk" }
