# Yime Rime data in PIME

This branch prepares PIME to consume Yime through the upstream Go Rime backend.

## Data flow

1. Yime exports one Rime schema and dictionary from `C:\dev\Yime-variable-length`.
2. PIME keeps shared Rime data under `go-backend\input_methods\yime\data`.
3. PIME keeps user Rime data under `%AppData%\PIME\Rime`.
4. The Go Rime backend loads `go-backend\input_methods\yime\rime.dll`, initializes librime with those two directories, and uses the selected Yime schema.

## Prepare local data

From `C:\dev\Yime`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-yime-rime-data.ps1
```

The default mode is `variable`, which exports and deploys `yime_variable`.

Other modes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-yime-rime-data.ps1 -Mode full
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-yime-rime-data.ps1 -Mode shorthand
```

The script copies shared Rime data from `C:\dev\weasel\output\data` by default.
Use `-WeaselDataDir` if the shared data lives elsewhere.

## Build notes

The current upstream PIME build needs Rust for `PIMELauncher`.
On this machine, Win32 builds require:

```powershell
$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
$env:RUSTUP_TOOLCHAIN = "stable-i686-pc-windows-msvc"
cmd /c build.bat
```

The Go backend additionally requires Go on `PATH`:

```powershell
cd go-backend
cmd /c build.bat
```

## Generated files

Do not commit generated Rime data:

- `go-backend\input_methods\yime\data\`
- `%AppData%\PIME\Rime\`
- `%AppData%\PIME\Rime\build\`
