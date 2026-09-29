# Claude Intune Apps

Intune Win32 app packages. Each app is a folder of scripts plus a manifest that pins its installers
by URL and SHA-256. A shared build script downloads the installers, checks their hashes and builds
the `.intunewin`. Installers and packages are never committed.

## Apps

| Folder | Installs |
|---|---|
| [PyCharm-Python](apps/PyCharm-Python/) | PyCharm 2026.2.3 + Python 3.14.7, with Python 3.14.7 as PyCharm's default interpreter |

## Layout

```
apps/
  <App>/
    app.json          name, version, setup file, installer URLs + SHA-256
    README.md         Intune app settings and what the install does
    Detect.ps1        custom detection script (uploaded to Intune separately, not packaged)
    source/           everything packaged into the .intunewin
      Install.ps1
      Uninstall.ps1
      ...             config files, helper scripts
  _template/          starting point for a new app (never built)
tools/
  build.py            builds one or all apps
  intunewin.py        creates and verifies .intunewin files on any OS
.github/workflows/
  build.yml           checks every app and builds the ones a push changed
```

Build output and the download cache are git-ignored:
- `out/<App>/Install.intunewin`
- `.cache/downloads/`

## Adding an app

1. Copy `apps/_template` to `apps/<App>`. Use a product name without the version, such as
   `Zoom` or `VSCode`, so version bumps don't rename the folder.
2. Fill in `app.json`:
   - **`downloads`:** each installer's URL and SHA-256. Take the hash from the vendor's
     published checksum where there is one. Downloaded files land next to the scripts in the
     package, under the URL's file name, or under `file` if you set it.
   - **`version`:** used in the CI artifact name.
   - **`setupFile`:** the script in `source/` that Intune runs, normally `Install.ps1`.
3. Write `source/Install.ps1` and `source/Uninstall.ps1`. The template already handles the
   64-bit relaunch, logging to the Intune logs folder, and exit codes.
4. Write `Detect.ps1` so it checks for the exact version this package installs.
5. Fill in `README.md` with the Intune settings.
6. Build it locally (below), or push and let CI build it.

To update an app, change the version and hashes in `app.json` and the version strings in its
scripts, then push.

## Building

### Locally

Needs Python 3.9+ and `pip install cryptography`.

```sh
python3 tools/build.py --list              # apps and versions
python3 tools/build.py PyCharm-Python      # -> out/PyCharm-Python/Install.intunewin
python3 tools/build.py --all
python3 tools/build.py --check             # validate every app.json, no downloads
```

Downloads are cached in `.cache/downloads/`, so rebuilding doesn't fetch them again. A hash
mismatch stops the build.

`tools/intunewin.py` writes the same format as Microsoft's Win32 Content Prep Tool. To use
Microsoft's tool on Windows instead, put the downloaded installers in the app's `source\` folder
and run `IntuneWinAppUtil.exe -c source -s Install.ps1 -o out`.

### With GitHub Actions

On every push that touches `apps/`, `tools/` or the workflow, `build.yml`:
1. checks every `app.json` and every `.ps1` for syntax errors
2. builds the apps whose folders changed, or all of them when `tools/` or the workflow changed

To build on demand, open **Actions → Build Intune packages → Run workflow** and enter an app
folder name or `all`. The button only appears once the workflow is on the default branch.

Each package becomes an artifact named `<App>-<version>`:
- download it from the run page
- GitHub wraps it in a .zip, so extract it before uploading to Intune
- the run summary lists each package's SHA-256
- artifacts are kept for 14 days
