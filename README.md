# Sanctuary

A Diablo-inspired **watch face** for the **Garmin tactix 8**, written in Monkey C
for Connect IQ.

Two glowing resource globes flank a large central clock:

- **Left globe — Body Battery** (crimson "health" orb), fills from the bottom 0–100.
- **Right globe — device battery** (sapphire "mana" orb), fills from the bottom 0–100%.
- Each orb is **configurable** (Body Battery, Device Battery, Steps or Stress); its
  color and label follow the chosen metric. The crimson/sapphire pairing above is the
  default.
- **Center** — the time (12/24h follows the device setting) with an optional date line,
  and the current **heart rate** (crimson heart + BPM) in the column between the orbs.
- **Top** — a **status-icon row**: phone connection, notifications, alarms and Do Not
  Disturb, each shown only when active.
- **Below the date** — the next **sunrise/sunset** (sun + sunset by day, moon + sunrise
  by night), when a GPS location is known.
- **Bottom** — a steps **"XP" bar** showing today's steps vs. your step goal.

The globes use a liquid-fill look (dark glass sphere, brighter fluid level inside, a
specular highlight, a soft outer glow), all drawn procedurally since Monkey C has no
native gradient fill.

## Hardware / scaling

The tactix 8 runs on the **Fenix 8 (AMOLED)** platform. Connect IQ has no dedicated
`tactix8` product id, so the project targets the Fenix 8 AMOLED products that share the
identical hardware and resolution:

| Product id      | Resolution | Case            |
|-----------------|------------|-----------------|
| `fenix847mm`    | 454×454    | tactix 8 51mm   |
| `fenix843mm`    | 416×416    | tactix 8 47mm   |
| `fenix8pro47mm` | 454×454    | Fenix 8 Pro     |
| `fenix8solar51mm` / `fenix8solar47mm` | 280/260 (MIP) | broader Fenix 8 coverage |

Everything is laid out in percentages of `dc.getWidth()/getHeight()` and the screen
center, so it scales cleanly across all of these — no hardcoded pixel coordinates.

## Always-on display

The face has two render paths sharing one `onUpdate()`:

- **Active mode** — full brightness, gradients, glows, filled globes.
- **Always-on / low-power** (`mIsSleep`) — burn-in-safe: dim time, thin globe rings +
  fluid-level lines, a thin XP outline, **no large bright fills**. All lit pixels are
  shifted a few px each minute (`requiresBurnInProtection`). `onPartialUpdate()` only
  repaints when the minute changes, staying well inside the always-on power budget.

## Data sources

- **Steps + goal:** `ActivityMonitor.getInfo()` (`steps`, `stepGoal`).
- **Device battery:** `System.getSystemStats().battery`.
- **Body Battery:** `SensorHistory.getBodyBatteryHistory()` (requires the `SensorHistory`
  permission, already declared). Fails gracefully to a dimmed globe (`--`) if the value
  is unavailable. A Complications-based alternative is noted in `getBodyBattery()`.
- **Heart rate:** `Activity.getActivityInfo().currentHeartRate`, falling back to the
  latest `ActivityMonitor.getHeartRateHistory()` sample, then `--`.
- **Status icons:** `System.getDeviceSettings()` — `phoneConnected`, `notificationCount`,
  `alarmCount`, `doNotDisturb` (each guarded with a `has` check).
- **Sunrise/sunset:** computed in `SolarUtil` (the standard sunrise equation) from the
  last known location — `Activity.currentLocation`, falling back to the `Weather`
  observation location. No extra permission; hidden when no fix is available.

## Settings

Editable in Garmin Connect / the simulator's App Settings:

- **Show Date** — toggle the date line.
- **Step Goal Override** — steps for a full XP bar; `0` uses the watch's own step goal.
- **Show Heart Rate** — toggle the central heart-rate readout.
- **Show Status Icons** — toggle the notification / alarm / phone / DND row.
- **Left Orb / Right Orb** — choose what each orb shows: Body Battery (Life),
  Device Battery (Mana), Steps, or Stress. The orb's color and label follow the
  metric, so this doubles as the face's theming.
- **Show Sun Times** — toggle the sunrise/sunset indicator.

## Build & run

Prerequisites: the **Connect IQ SDK** and a JDK. Paths live in `build_config.json`
(auto-created on first run) — edit them to match your machine:

```json
{
  "JavaHome": "C:\\Program Files\\Android\\openjdk\\jdk-21.0.8",
  "SdkDir":   "C:\\Users\\<you>\\AppData\\Roaming\\Garmin\\ConnectIQ\\Sdks\\<sdk-version>"
}
```

### Build (default device = `fenix847mm`, 454×454)

```powershell
./build.ps1                     # build .prg
./build.ps1 -Device fenix843mm  # build the 416×416 variant
./build.ps1 -Export             # package a store-ready .iq
```

### Build + launch in the simulator

```powershell
./build.ps1 -Run                # or double-click run_simulator.bat
```

In the simulator you can exercise the design via the menus:
- **Settings → Battery** to move the device-battery globe.
- **Simulation → Body Battery** for the crimson globe.
- **Simulation → Time / Sleep** (Always On) to preview the low-power render path.

### Run the unit tests

The pure color/geometry helpers (`source/ColorUtil.mc`) have `(:test)` coverage in
`source/Tests.mc`:

```powershell
./build.ps1 -Test               # builds a unit-test image and runs it in the simulator
```

### Sideload to the watch

1. Build the `.prg` (or `.iq`).
2. Connect the tactix 8 by USB; it mounts as a drive.
3. Copy `bin/Sanctuary.prg` to `GARMIN/APPS/` on the device.
4. Eject and select **Sanctuary** from the watch face list.

For store distribution, upload the `.iq` from `./build.ps1 -Export`.

## Fonts (Exocet / Diablo typeface)

The face renders in **Exocet**, the Diablo typeface. Connect IQ's `<font>` resource
cannot consume a `.ttf` directly — it needs an AngelCode **bitmap font** (`.fnt` + a
`.png` glyph atlas). So the pipeline is:

```
fonts-src/ExocetHeavy.ttf  ──┐
fonts-src/ExocetLight.ttf  ──┤  python tools/gen_fonts.py
                             └─▶  resources/fonts/exocet_*.fnt + .png
```

- `tools/gen_fonts.py` rasterizes the glyphs we use (digits + `:` for the time, digits
  + `% -` for the globe values, `A–Z 0–9` for labels/date) into white + alpha atlases
  so `dc.setColor()` tints them. Re-run it after changing sizes or glyph sets.
- `resources/fonts/fonts.xml` declares `ExocetTime` / `ExocetValue` / `ExocetLabel`.
- `initFonts()` loads them, falling back to vector fonts then built-ins if missing.
- The atlases are baked at sizes tuned for **454×454**; they render a touch larger on
  the 416 panel (still fits). For pixel-perfect 416, generate a second set and add a
  device-specific `resourcePath` for `fenix843mm` in `monkey.jungle`.

## Customizing

- **Colors / thresholds:** globe and XP palettes are the `C_*` constants at the top of
  `SanctuaryView.mc`. Layout anchors are the percentage values in `onUpdate()`.
- **Orb metrics:** `drawMetricGlobe()` maps each metric id (Body Battery / Battery /
  Steps / Stress) to its value, palette and label. Add a metric by extending that
  switch, the `METRIC_*` constants, and the `listEntry` values in `settings.xml`.
- **Ornamentation:** `drawOrnateBezel()` (globe frames + rivets), `drawDivider()` (the
  flourish under the time), and `drawXpBar()` (bronze frame + diamond end-caps) are the
  Diablo styling helpers — tweak metal colors / rivet counts there.
- **Labels:** the `LIFE` / `MANA` / `HR` / `STEPS` / `STRESS` labels live in
  `resources/strings/strings.xml` (loaded in `initLabels()`).
