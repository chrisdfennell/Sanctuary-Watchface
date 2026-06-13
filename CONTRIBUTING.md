# Contributing to Sanctuary

Thanks for your interest in improving Sanctuary! This is a Diablo-inspired Garmin
Connect IQ watch face for the tactix 8, written in
[Monkey C](https://developer.garmin.com/connect-iq/monkey-c/). Contributions of all
kinds are welcome — bug reports, layout/styling improvements, new indicators,
device support, art/font assets, and documentation.

By participating in this project you agree to abide by our
[Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug** — open a [bug report](../../issues/new?template=bug_report.yml).
  Please include your device, firmware version, and the SDK version you used.
- **Request a feature** — open a [feature request](../../issues/new?template=feature_request.yml).
- **Submit a change** — fork, branch, and open a pull request (see below).

## Development setup

### Prerequisites

- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) **9.1.0+**
  (install the Fenix 8 device profiles via the **SDK / Device Manager**).
- **Java 17+** (Java 21 is what `build.ps1` defaults to).
- **PowerShell** (the build script is PowerShell-based).
- **Python 3 + Pillow** — only needed if you regenerate the Exocet fonts
  (`pip install pillow`, then `python tools/gen_fonts.py`).
- A Connect IQ **developer key** (`developer_key.der`) in the repo root.
  Generate one with:
  ```powershell
  openssl genrsa -out developer_key.pem 4096
  openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
  ```
  This file is git-ignored and must **never** be committed.

### Build

```powershell
# Compile for a specific device (defaults to fenix847mm / 454x454)
.\build.ps1 -Device fenix847mm

# Compile and launch in the simulator
.\build.ps1 -Device fenix843mm -Run

# Package a store-ready .iq bundle (all products in the manifest)
.\build.ps1 -Export
```

On first run, `build.ps1` writes a `build_config.json` (git-ignored) with your
local `JavaHome` and `SdkDir` paths — edit it to match your machine.

## Project layout

- `source/SanctuaryApp.mc` / `SanctuaryView.mc` — the app + watch face (all
  rendering is procedural in `onUpdate`).
- `resources/` — strings, settings, fonts (`fonts/`), the launcher icon, and a
  placeholder background.
- `resources-round-454x454/` and `resources-round-416x416/` — per-resolution art,
  wired up via device `resourcePath` entries in `monkey.jungle`.
- `fonts-src/` — source Exocet TTFs; `tools/gen_fonts.py` bakes them into the
  bitmap fonts under `resources/fonts/`.

## Testing your changes

Sanctuary targets the **tactix 8 (Fenix 8 AMOLED)** in both case sizes. Please
verify your change on both before submitting:

- `fenix847mm` (454×454, 51mm)
- `fenix843mm` (416×416, 47mm)

Things to check in the simulator:

- Layout holds on **both** panels — no text or bezel clipping at the round edge.
- The **LIFE** and **MANA** globes fill correctly from live data (Settings →
  Battery, Simulation → Body Battery) and degrade gracefully to a dimmed `--` when
  a value is unavailable.
- **Always-On / low-power mode** (Settings → toggle sleep) — the burn-in shift and
  the reduced, dim AOD layout (no large bright fills) still render correctly.
- `savescreenshot.ps1` captures a clean, correctly-framed shot on both sizes.

## Coding guidelines

- Match the existing style in `source/SanctuaryView.mc`: 4-space indentation,
  explicit type annotations on method signatures, and `private var` for fields.
- Keep drawing **procedural** — size everything relative to `mWidth` / `mHeight`
  and the screen center, never hard-coded pixel coordinates, so layouts hold
  across the supported device range.
- Guard optional APIs with `has` checks (e.g. `SensorHistory has
  :getBodyBatteryHistory`) and wrap risky calls in `try/catch` so missing data
  never crashes the face.
- Globe / XP palettes are the `C_*` constants at the top of the view; layout
  anchors are the percentage values in `onUpdate()`.
- New user settings go in `resources/settings/` (properties + settings) with a
  matching label in `resources/strings/strings.xml`.
- If you change a font size or glyph set, re-run `python tools/gen_fonts.py` and
  commit the regenerated `.fnt` / `.png`.

## Pull request process

1. Fork the repo and create a topic branch off `main`
   (e.g. `feature/arcane-sigil` or `fix/mana-label-clip`).
2. Make your change and confirm it **builds clean** (`.\build.ps1` with no
   warnings) and runs in the simulator.
3. Fill out the pull request template, including the devices you tested and
   before/after screenshots for any visual change.
4. Keep PRs focused — one logical change per PR is easier to review.

### Commit messages

Short, imperative summaries are preferred, optionally using
[Conventional Commits](https://www.conventionalcommits.org/) prefixes:

```
feat: add an arcane sigil behind the time
fix: keep the MANA label from clipping on the 416 panel
docs: document the Exocet font pipeline
```

## Questions

Open a [discussion](../../discussions) or file an issue. Thanks for contributing!
