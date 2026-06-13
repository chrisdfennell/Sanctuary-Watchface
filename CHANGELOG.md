# Changelog

All notable changes to Sanctuary are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial Diablo-inspired watch face for the Garmin tactix 8 (Fenix 8 AMOLED),
  supporting both case sizes: 454×454 (51mm) and 416×416 (47mm).
- Twin liquid-fill resource globes: **LIFE** (Body Battery, crimson) and **MANA**
  (device battery, sapphire), each with gradient fill, molten core, specular
  highlight, soft glow, and an ornate riveted metal bezel.
- Centered time in the **Exocet** typeface with an ornamental divider and date
  line; steps **XP bar** with a bronze frame and diamond end-caps.
- Diablo-inspired full-screen background art, per-resolution (454 / 416), shown in
  active mode only.
- Always-On / low-power render path: dimmed time, thin globe rings + fluid-level
  lines, no large bright fills, with per-minute burn-in pixel shift.
- User settings: **Show Date** and **Step Goal Override**.
- Tooling: `tools/gen_fonts.py` (TTF → Connect IQ bitmap fonts) and
  `savescreenshot.ps1` (auto-framed simulator capture for both panel sizes).
