$ErrorActionPreference = "Stop"
$ndkBin = "D:\Android\ndk-sdk\ndk\29.0.14206865\toolchains\llvm\prebuilt\windows-x86_64\bin"
if (-not (Test-Path "$ndkBin\aarch64-linux-android26-clang.cmd")) {
    throw "Missing NDK clang at $ndkBin"
}

$env:CC_aarch64_linux_android = "$ndkBin\aarch64-linux-android26-clang.cmd"
$env:AR_aarch64_linux_android = "$ndkBin\llvm-ar.exe"
$env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "$ndkBin\aarch64-linux-android26-clang.cmd"

Push-Location "d:\16. Code\45. Tut tricks\tkmg-rust-core"
try {
    cargo test
    if ($LASTEXITCODE -ne 0) { throw "Rust tests failed" }

    cargo build --release --target aarch64-linux-android
    if ($LASTEXITCODE -ne 0) { throw "Rust arm64 release build failed" }
} finally {
    Pop-Location
}

$soSrc = "d:\16. Code\45. Tut tricks\tkmg-rust-core\target\aarch64-linux-android\release\libtkmg_core.so"
$soSizeKb = [Math]::Round((Get-Item $soSrc).Length / 1KB, 1)
Write-Output "Built libtkmg_core.so ($soSizeKb KB)"

foreach ($proj in @("TKMGPlayer", "TKMGScanner")) {
    $jniDir = "d:\16. Code\45. Tut tricks\$proj\app\src\main\jniLibs\arm64-v8a"
    New-Item -ItemType Directory -Force -Path $jniDir | Out-Null
    Copy-Item $soSrc -Destination "$jniDir\libtkmg_core.so" -Force
}
