import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Application;
import Toybox.SensorHistory;
import Toybox.Weather;
import Toybox.Math;

//
// Sanctuary - a Diablo-inspired watch face.
//
//   - Center:  large time + small date line
//   - Left:    Body Battery, a crimson "health" globe filling from the bottom
//   - Right:   device battery, a sapphire "mana" globe filling from the bottom
//   - Bottom:  steps "XP" bar (today's steps vs. step goal)
//
// Everything is laid out relative to dc.getWidth()/getHeight() and the screen
// center, so it scales cleanly between the 454x454 (51mm) and 416x416 (47mm)
// tactix 8 panels with no hardcoded pixel coordinates.
//
// Two render paths share one onUpdate():
//   - Full / active mode: gradients, glows, filled globes (mIsSleep == false)
//   - Always-on / low-power: dim thin rings + outlines only, burn-in shifted
//
class SanctuaryView extends WatchUi.WatchFace {

    // --- Screen geometry (resolved in onLayout) ---
    private var mWidth as Number = 0;
    private var mHeight as Number = 0;
    private var mCenterX as Number = 0;
    private var mCenterY as Number = 0;

    // --- State ---
    private var mIsSleep as Boolean = false;
    private var mLowPower as Boolean = false;  // true only on AMOLED in Always-On (burn-in) mode
    private var mFlatGlobes as Boolean = false; // true on MIP: flat 2-tone fills (no banded gradient)
    private var mLastMin as Number = -1;       // throttles low-power partial updates

    // --- Settings (see resources/settings) ---
    private var mShowDate as Boolean = true;
    private var mStepGoalOverride as Number = 0;  // 0 => use device step goal
    private var mShowHeartRate as Boolean = true;
    private var mShowStatusIcons as Boolean = true;
    private var mLeftMetric as Number = 0;   // METRIC_BODY
    private var mRightMetric as Number = 1;  // METRIC_BATTERY
    private var mShowSunTimes as Boolean = true;

    // --- Localized on-face labels (loaded in onLayout; safe fallbacks here) ---
    private var mLifeLabel as String = "LIFE";
    private var mManaLabel as String = "MANA";
    private var mHrLabel as String = "HR";
    private var mStepsLabel as String = "STEPS";
    private var mStressLabel as String = "STRESS";

    // --- Fonts (vector fonts with safe fallbacks) ---
    private var mFontTime as Graphics.FontType or Null = null;
    private var mFontDate as Graphics.FontType or Null = null;
    private var mFontValue as Graphics.FontType or Null = null;
    private var mFontLabel as Graphics.FontType or Null = null;
    private var mBackground as WatchUi.BitmapResource or Null = null;

    // --- Palettes: { fluidBright, fluidDark, rim, glow } -----------------------
    // Body Battery globe = crimson "health"
    private const C_BODY_BRIGHT = 0xFF4030;
    private const C_BODY_DARK   = 0x5A0808;
    private const C_BODY_RIM    = 0xFF6048;
    private const C_BODY_GLOW   = 0x902418;
    // Device battery globe = sapphire "mana"
    private const C_BATT_BRIGHT = 0x40A8FF;
    private const C_BATT_DARK   = 0x081C4A;
    private const C_BATT_RIM    = 0x60B0FF;
    private const C_BATT_GLOW   = 0x1C4C90;
    // Steps globe = molten gold (matches the XP bar family)
    private const C_STEP_BRIGHT = 0xFFD060;
    private const C_STEP_DARK   = 0x3A2A08;
    private const C_STEP_RIM    = 0xFFE090;
    private const C_STEP_GLOW   = 0x6A4810;
    // Stress globe = arcane violet
    private const C_STRS_BRIGHT = 0xB060FF;
    private const C_STRS_DARK   = 0x1C0A3A;
    private const C_STRS_RIM    = 0xC080FF;
    private const C_STRS_GLOW   = 0x4A1C90;

    // Globe metric ids (must match the listEntry values in settings.xml).
    private const METRIC_BODY    = 0;
    private const METRIC_BATTERY = 1;
    private const METRIC_STEPS   = 2;
    private const METRIC_STRESS  = 3;
    // Heart-rate readout = crimson (shares the "health" hue family)
    private const C_HR_BRIGHT   = 0xFF5040;
    private const C_HR_DIM       = 0x8A3028;
    // Status icons
    private const C_ICON_ON      = 0xB89860;   // active / connected (bronze-gold)
    private const C_ICON_OFF     = 0x4A3A22;   // inactive / disconnected (dim bronze)
    private const C_ICON_ALERT   = 0xFF6048;   // notification accent (crimson)
    // Sun-times indicator
    private const C_SUN          = 0xFFC040;   // amber sun
    private const C_MOON         = 0xC0C0D0;   // pale silver moon
    private const C_SUN_TEXT     = 0x9A8A6A;   // muted gold time text
    // XP bar = molten amber/gold
    private const C_XP_TRACK    = 0x1C1408;
    private const C_XP_FILL     = 0xE0A028;
    private const C_XP_BRIGHT   = 0xFFD060;
    private const C_XP_GLOW     = 0x6A4810;
    private const C_XP_BORDER   = 0x4A3A14;

    private const BG_COLOR = 0x000000;        // pitch black for AMOLED contrast/battery

    function initialize() {
        WatchFace.initialize();
        loadSettings();
    }

    // Read user settings; safe to call any time (e.g. from App.onSettingsChanged).
    function loadSettings() as Void {
        try {
            if (Application has :Properties) {
                var showDate = Application.Properties.getValue("ShowDate");
                var stepGoal = Application.Properties.getValue("StepGoalOverride");
                var showHr = Application.Properties.getValue("ShowHeartRate");
                var showIcons = Application.Properties.getValue("ShowStatusIcons");
                var leftMetric = Application.Properties.getValue("LeftGlobeMetric");
                var rightMetric = Application.Properties.getValue("RightGlobeMetric");
                var showSun = Application.Properties.getValue("ShowSunTimes");
                if (showDate != null) { mShowDate = showDate; }
                if (stepGoal != null) { mStepGoalOverride = stepGoal; }
                if (showHr != null) { mShowHeartRate = showHr; }
                if (showIcons != null) { mShowStatusIcons = showIcons; }
                if (leftMetric != null) { mLeftMetric = leftMetric; }
                if (rightMetric != null) { mRightMetric = rightMetric; }
                if (showSun != null) { mShowSunTimes = showSun; }
            }
        } catch (e) {
            // keep defaults
        }
        if (mStepGoalOverride < 0) { mStepGoalOverride = 0; }
    }

    function onLayout(dc as Dc) as Void {
        mWidth = dc.getWidth();
        mHeight = dc.getHeight();
        mCenterX = mWidth / 2;
        mCenterY = mHeight / 2;
        initFonts();
        initLabels();

        try {
            mBackground = WatchUi.loadResource(Rez.Drawables.diablo_background) as WatchUi.BitmapResource;
        } catch (e) {
            mBackground = null;
        }
    }

    // Load the localizable on-face labels; keep the English fallbacks on failure.
    function initLabels() as Void {
        try {
            mLifeLabel   = WatchUi.loadResource(Rez.Strings.LabelLife) as String;
            mManaLabel   = WatchUi.loadResource(Rez.Strings.LabelMana) as String;
            mHrLabel     = WatchUi.loadResource(Rez.Strings.LabelHeart) as String;
            mStepsLabel  = WatchUi.loadResource(Rez.Strings.LabelSteps) as String;
            mStressLabel = WatchUi.loadResource(Rez.Strings.LabelStress) as String;
        } catch (e) {
            // keep defaults
        }
    }

    // Vector fonts scale to the panel; fall back to built-ins if unavailable.
    // Fonts, in priority order:
    //   1. Exocet bitmap fonts (the Diablo typeface) from resources/fonts/
    //   2. Connect IQ vector fonts (RobotoCondensedBold), scaled to the panel
    //   3. Built-in fonts (last-resort fallback)
    // The Exocet fonts are bitmap fonts baked at fixed pixel sizes tuned for the
    // 454x454 panel (see tools/gen_fonts.py); they look a touch larger on the
    // smaller 416 panel, which still fits.
    function initFonts() as Void {
        // 1. Try the custom Exocet bitmap fonts.
        try {
            mFontTime  = WatchUi.loadResource(Rez.Fonts.ExocetTime) as Graphics.FontType;
            mFontValue = WatchUi.loadResource(Rez.Fonts.ExocetValue) as Graphics.FontType;
            mFontLabel = WatchUi.loadResource(Rez.Fonts.ExocetLabel) as Graphics.FontType;
            mFontDate  = mFontLabel;
        } catch (e) {
            mFontTime = null;
            mFontValue = null;
            mFontLabel = null;
            mFontDate = null;
        }

        // 2. Vector-font fallback for anything that didn't load.
        if (Graphics has :getVectorFont) {
            var bold = ["RobotoCondensedBold", "RobotoRegular", "sans-serif"] as Array<String>;
            if (mFontTime == null)  { mFontTime  = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.21).toNumber() }); }
            if (mFontDate == null)  { mFontDate  = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.058).toNumber() }); }
            if (mFontValue == null) { mFontValue = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.085).toNumber() }); }
            if (mFontLabel == null) { mFontLabel = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.044).toNumber() }); }
        }

        // 3. Built-in last resort.
        if (mFontTime == null)  { mFontTime  = Graphics.FONT_NUMBER_THAI_HOT; }
        if (mFontDate == null)  { mFontDate  = Graphics.FONT_TINY; }
        if (mFontValue == null) { mFontValue = Graphics.FONT_MEDIUM; }
        if (mFontLabel == null) { mFontLabel = Graphics.FONT_XTINY; }
    }

    function onShow() as Void {
        loadSettings();
    }

    // Single render entry point for both active and low-power frames.
    function onUpdate(dc as Dc) as Void {
        var w = mWidth;
        var h = mHeight;

        // Reduced / burn-in-safe rendering applies ONLY to AMOLED panels in Always-On
        // mode. MIP / transflective panels (e.g. tactix 8 Solar) have no burn-in and
        // sit in low-power most of the time while STILL showing the full face, so they
        // must always render the full layout - never the dimmed variant.
        var burnIn = false;
        var dx = 0;
        var dy = 0;
        var settings = System.getDeviceSettings();
        var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        if (hasBurnIn && mIsSleep) {
            burnIn = true;
            var phase = System.getClockTime().min % 4;
            if (phase == 1)      { dx = 4;  dy = 2; }
            else if (phase == 2) { dx = -3; dy = 4; }
            else if (phase == 3) { dx = 3;  dy = -4; }
        }
        mLowPower = burnIn;   // drives the dim/thin render path used below
        // AMOLED panels need burn-in protection; the panels that DON'T are MIP /
        // transflective, whose limited palette bands smooth gradients - so use clean
        // flat fills there instead.
        mFlatGlobes = !hasBurnIn;

        var cx = mCenterX + dx;
        var cy = mCenterY + dy;

        // Always clear to pitch black first to ensure a clean slate.
        dc.setColor(BG_COLOR, BG_COLOR);
        dc.clear();

        // Draw the Diablo background art in full-power mode. (MIP devices have no
        // background asset - only the 1x1 base placeholder - so they stay solid black.)
        if (!mLowPower && mBackground != null) {
            dc.drawBitmap(0, 0, mBackground);
        }

        // --- Layout anchors (relative to screen) ---
        var timeY   = (h * 0.30).toNumber() + dy;
        var dividerY = (h * 0.41).toNumber() + dy;
        var dateY   = (h * 0.47).toNumber() + dy;
        var globeY  = (h * 0.66).toNumber() + dy;
        var globeR  = (w * 0.140).toNumber();
        var leftX   = (w * 0.240).toNumber() + dx;
        var rightX  = (w * 0.760).toNumber() + dx;
        var labelY  = globeY + globeR + (h * 0.038).toNumber();
        var xpY     = (h * 0.92).toNumber() + dy;
        var xpW     = (w * 0.40).toNumber();
        var xpH     = (h * 0.024).toNumber();
        if (xpH < 5) { xpH = 5; }
        var iconY   = (h * 0.135).toNumber() + dy;

        // --- Status icons (active mode only; lit pixels burn in) ---
        if (!burnIn && mShowStatusIcons) {
            drawStatusIcons(dc, cx, iconY, (w * 0.034).toNumber());
        }

        // --- Time ---
        drawTime(dc, cx, timeY);

        // --- Ornamental divider + date + sun times (active mode only) ---
        if (!burnIn) {
            drawDivider(dc, cx, dividerY, (w * 0.20).toNumber());
            if (mShowDate) {
                drawDate(dc, cx, dateY);
            }
            if (mShowSunTimes) {
                drawSunTimes(dc, cx, (h * 0.525).toNumber() + dy);
            }
        }

        // --- Globes (each fills with its user-selected metric). The value + label
        //     are drawn in active mode only; the fluid renders in both paths. ---
        drawMetricGlobe(dc, leftX, globeY, globeR, labelY, mLeftMetric, !burnIn);
        drawMetricGlobe(dc, rightX, globeY, globeR, labelY, mRightMetric, !burnIn);

        // --- Heart rate, centered in the open column between the orbs (active only) ---
        if (!burnIn && mShowHeartRate) {
            drawHeartRate(dc, cx, globeY, labelY, getHeartRate());
        }

        // --- Steps XP bar ---
        drawXpBar(dc, cx, xpY, xpW, xpH, getStepFraction());
    }

    // Called ~once per second in always-on mode. We only show minute-resolution
    // time, so redraw the low-power frame only when the minute actually changes.
    // This keeps us well inside the always-on pixel/power budget.
    function onPartialUpdate(dc as Dc) as Void {
        var min = System.getClockTime().min;
        if (min == mLastMin) { return; }
        mLastMin = min;

        // Constrain the partial frame to the face bounds and re-assert it after.
        // The low-power path only lights thin rings/lines so we stay well inside the
        // always-on power budget; bounding the clip keeps the watchdog's per-frame
        // lit-pixel accounting tied to what we actually touch.
        if (dc has :setClip) {
            dc.setClip(0, 0, mWidth, mHeight);
        }
        onUpdate(dc);   // mIsSleep is true here -> low-power render path
        if (dc has :clearClip) {
            dc.clearClip();
        }
    }

    // ------------------------------------------------------------------ Elements

    function drawTime(dc as Dc, cx as Number, cy as Number) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        var min = clock.min;
        var is24 = System.getDeviceSettings().is24Hour;
        if (!is24) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var hourStr = is24 ? hour.format("%02d") : hour.format("%d");
        var timeStr = hourStr + ":" + min.format("%02d");

        // Dim in AOD (fewer lit pixels), bright otherwise.
        dc.setColor(mLowPower ? 0x6E6E6E : 0xF2F2F2, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, mFontTime, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawDate(dc as Dc, cx as Number, y as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = info.day_of_week.toUpper() + "   " + info.month.toUpper() + " " + info.day;
        dc.setColor(0x9A6A6A, Graphics.COLOR_TRANSPARENT);   // muted gothic crimson-gray
        dc.drawText(cx, y, mFontDate, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Numeric value centered inside the globe + a themed label beneath it.
    function drawGlobeText(dc as Dc, gx as Number, gy as Number, labelY as Number,
                           valueStr as String, label as String, labelColor as Number) as Void {
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(gx, gy, mFontValue, valueStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(gx, labelY, mFontLabel, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Resolve a metric id to its value / availability / palette / label, then draw
    // the globe (and, when showText, the centered value + themed label). This is how
    // each orb honors the user's Left/Right Orb setting. Unknown ids fall back to
    // Body Battery so a bad stored value still renders something sane.
    function drawMetricGlobe(dc as Dc, gx as Number, gy as Number, r as Number,
                             labelY as Number, metricId as Number, showText as Boolean) as Void {
        var value = 0;
        var avail = false;
        var valueStr = "--";
        var bright; var dark; var rim; var glow; var label;

        if (metricId == METRIC_BATTERY) {
            var stats = System.getSystemStats();
            value = (stats.battery != null) ? stats.battery.toNumber() : 0;
            avail = true;
            valueStr = value.format("%d") + "%";
            bright = C_BATT_BRIGHT; dark = C_BATT_DARK; rim = C_BATT_RIM; glow = C_BATT_GLOW;
            label = mManaLabel;
        } else if (metricId == METRIC_STEPS) {
            value = (getStepFraction() * 100.0).toNumber();
            avail = true;
            valueStr = value.format("%d") + "%";
            bright = C_STEP_BRIGHT; dark = C_STEP_DARK; rim = C_STEP_RIM; glow = C_STEP_GLOW;
            label = mStepsLabel;
        } else if (metricId == METRIC_STRESS) {
            var stress = getStress();
            avail = (stress != null);
            value = avail ? stress : 0;
            valueStr = avail ? value.format("%d") : "--";
            bright = C_STRS_BRIGHT; dark = C_STRS_DARK; rim = C_STRS_RIM; glow = C_STRS_GLOW;
            label = mStressLabel;
        } else {  // METRIC_BODY (and any unknown id)
            var body = getBodyBattery();
            avail = (body != null);
            value = avail ? body : 0;
            valueStr = avail ? value.format("%d") : "--";
            bright = C_BODY_BRIGHT; dark = C_BODY_DARK; rim = C_BODY_RIM; glow = C_BODY_GLOW;
            label = mLifeLabel;
        }

        drawGlobe(dc, gx, gy, r, value, avail, bright, dark, rim, glow);
        if (showText) {
            drawGlobeText(dc, gx, gy, labelY, valueStr, label, rim);
        }
    }

    // Ornamental gothic divider: a tapering line broken by a center diamond, with
    // small end pips. Ties the layout together with a Diablo-menu feel.
    function drawDivider(dc as Dc, cx as Number, y as Number, halfW as Number) as Void {
        var gold = 0x9A7A3A;
        var goldDim = 0x4A3A1C;
        dc.setPenWidth(1);
        // Tapered double line with a gap for the diamond
        dc.setColor(gold, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - halfW, y, cx - 9, y);
        dc.drawLine(cx + 9, y, cx + halfW, y);
        dc.setColor(goldDim, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - halfW, y + 1, cx - 9, y + 1);
        dc.drawLine(cx + 9, y + 1, cx + halfW, y + 1);
        // Center diamond
        dc.setColor(gold, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, y - 5], [cx + 5, y], [cx, y + 5], [cx - 5, y]]);
        dc.setColor(0x1A1206, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, y - 2], [cx + 2, y], [cx, y + 2], [cx - 2, y]]);
        // End pips
        dc.setColor(gold, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - halfW, y, 2);
        dc.fillCircle(cx + halfW, y, 2);
    }

    // Ornate metal bezel framing a globe: beveled bronze/iron rings + rivets, the
    // Diablo health/mana orb frame. Active mode only (the AOD path draws a thin ring).
    function drawOrnateBezel(dc as Dc, gx as Number, gy as Number, r as Number, lit as Boolean) as Void {
        var iron     = lit ? 0x4A4036 : 0x2A2620;   // main frame band
        var ironDark = 0x140F0A;                    // outer/inner shadow
        var bronze   = lit ? 0x8A6A3A : 0x4A3A22;   // bronze sheen
        var highlight = lit ? 0xCBA86A : 0x6A5836;  // top-left catch-light
        var rivet    = lit ? 0xB89860 : 0x6A5836;

        // Outer shadow ring (depth)
        dc.setPenWidth(7);
        dc.setColor(ironDark, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r + 4);
        // Main iron band
        dc.setPenWidth(6);
        dc.setColor(iron, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r + 2);
        // Bronze sheen inside the band
        dc.setPenWidth(2);
        dc.setColor(bronze, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r + 3);
        // Top-left catch-light arc (where the "metal" reflects)
        dc.setPenWidth(3);
        dc.setColor(highlight, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(gx, gy, r + 3, Graphics.ARC_COUNTER_CLOCKWISE, 110, 175);
        // Inner shadow lip against the glass
        dc.setPenWidth(1);
        dc.setColor(ironDark, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r - 1);
        // Rivets every 45 degrees around the frame
        var rr = r + 2;
        for (var a = 0; a < 360; a += 45) {
            var rad = a * Math.PI / 180.0;
            var rx = gx + (rr * Math.cos(rad)).toNumber();
            var ry = gy + (rr * Math.sin(rad)).toNumber();
            dc.setColor(rivet, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(rx, ry, 2);
            dc.setColor(ironDark, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(rx, ry, 1);
        }
    }

    // Liquid-fill globe. value is 0-100; `available` false => dim empty orb.
    function drawGlobe(dc as Dc, gx as Number, gy as Number, r as Number,
                       value as Number, available as Boolean,
                       bright as Number, dark as Number, rim as Number, glow as Number) as Void {
        if (mLowPower) {
            drawGlobeLowPower(dc, gx, gy, r, value, available, rim);
            return;
        }

        // 1. Soft outer glow (only when there is fluid to glow). Skipped on MIP,
        //    where dim halo rings just read as muddy banding.
        if (available && value > 0 && !mFlatGlobes) {
            dc.setPenWidth(3);
            dc.setColor(scaleColor(glow, 0.60), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 2);
            dc.setPenWidth(2);
            dc.setColor(scaleColor(glow, 0.30), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 5);
        }

        // 2. Dark glass sphere base.
        dc.setColor(scaleColor(dark, 0.55), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gx, gy, r);

        // 3. Liquid fill from the bottom: a vertical gradient faked with stacked
        //    horizontal bands (Monkey C has no native gradient fill). Each band is
        //    a rectangle sized to the circle's chord width at that row, so the
        //    fluid keeps clean round edges without needing clip regions. Brightest
        //    at the fluid surface, darkening with depth.
        if (available && value > 0) {
            var v = value;
            if (v > 100) { v = 100; }
            var fillH = (2.0 * r) * v / 100.0;
            var surfaceY = ((gy + r) - fillH).toNumber();
            var bottomY = gy + r - 1;
            // Precompute the two flat MIP tones so we don't lerp per row.
            var flatTop = bright;
            var flatBottom = lerpColor(bright, dark, 0.5);
            var step = 2;
            for (var y = surfaceY; y <= bottomY; y += step) {
                var half = chordHalf(r - 1, y - gy);
                if (half < 1) { continue; }
                var depth = (y - surfaceY).toFloat() / fillH;       // 0 surface .. 1 bottom
                var c;
                if (mFlatGlobes) {
                    // Clean 2-tone fill - no smooth gradient for MIP to band.
                    c = (depth < 0.55) ? flatTop : flatBottom;
                } else {
                    var t = 1.0 - depth;                            // 1 surface .. 0 bottom
                    if (t < 0.0) { t = 0.0; }
                    if (t > 1.0) { t = 1.0; }
                    c = lerpColor(dark, bright, t);
                }
                dc.setColor(c, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(gx - half, y, 2 * half, step);
            }

            // Molten core: a soft brighter glow at the fluid's center of mass for
            // volume (skipped on MIP and on a near-empty orb).
            if (fillH > r * 0.5 && !mFlatGlobes) {
                var coreY = (gy + r - fillH * 0.45).toNumber();
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.10), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(gx, coreY, (r * 0.22).toNumber());
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.22), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(gx, coreY, (r * 0.10).toNumber());
            }

            // Bright meniscus line at the fluid surface.
            var mHalf = chordHalf(r, surfaceY - gy);
            if (mHalf > 1) {
                dc.setPenWidth(2);
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.35), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx - mHalf, surfaceY, gx + mHalf, surfaceY);
            }
        }

        // 4. Specular glass highlight (top-left).
        if (available) {
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(gx - (r * 0.34).toNumber(), gy - (r * 0.42).toNumber(), (r * 0.12).toNumber());
        }

        // 5. Ornate metal bezel (replaces a plain rim).
        drawOrnateBezel(dc, gx, gy, r, (available && value > 0));
    }

    // Burn-in-safe globe: just a thin dim ring + a thin fluid-level line.
    function drawGlobeLowPower(dc as Dc, gx as Number, gy as Number, r as Number,
                               value as Number, available as Boolean, rim as Number) as Void {
        dc.setPenWidth(1);
        dc.setColor(scaleColor(rim, 0.45), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r);
        if (available && value > 0) {
            var v = value;
            if (v > 100) { v = 100; }
            var surfaceY = ((gy + r) - (2.0 * r) * v / 100.0).toNumber();
            var half = chordHalf(r, surfaceY - gy);
            if (half > 1) {
                dc.setColor(scaleColor(rim, 0.65), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx - half, surfaceY, gx + half, surfaceY);
            }
        }
    }

    // Steps "XP" bar: a rounded capsule that fills with today's progress.
    function drawXpBar(dc as Dc, cx as Number, y as Number, barW as Number, barH as Number, frac as Float) as Void {
        var x = cx - barW / 2;
        var top = y - barH / 2;
        var rad = barH / 2;

        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var fw = (barW * frac).toNumber();

        if (mLowPower) {
            // Thin dim outline + thin progress line (no bright fills).
            dc.setPenWidth(1);
            dc.setColor(C_XP_BORDER, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, top, barW, barH, rad);
            if (fw > 2) {
                dc.setColor(scaleColor(C_XP_FILL, 0.55), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x + 2, y, x + fw - 2, y);
            }
            return;
        }

        // Track.
        dc.setColor(C_XP_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, top, barW, barH, rad);

        // Fill (+ glow underlay + bright top sliver).
        if (frac > 0.0) {
            if (fw < barH) { fw = barH; }          // keep the rounded cap visible
            if (fw > barW) { fw = barW; }
            dc.setColor(C_XP_GLOW, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x - 1, top - 1, fw + 2, barH + 2, rad + 1);
            dc.setColor(C_XP_FILL, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, top, fw, barH, rad);
            dc.setColor(C_XP_BRIGHT, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, top, fw, barH / 3, rad);
        }

        // Bronze frame + gothic diamond end caps (the "ornate plate" feel).
        dc.setPenWidth(2);
        dc.setColor(0x6A5028, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, top, barW, barH, rad);
        dc.setPenWidth(1);
        dc.setColor(0xB89860, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x + rad, top, x + barW - rad, top);   // top catch-light
        var dymid = barH / 2 + 3;
        dc.setColor(0x9A7A3A, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x - 4, y], [x - 1, y - dymid + 1], [x + 2, y], [x - 1, y + dymid - 1]]);
        dc.fillPolygon([[x + barW + 4, y], [x + barW + 1, y - dymid + 1], [x + barW - 2, y], [x + barW + 1, y + dymid - 1]]);
    }

    // Central heart-rate readout: a small crimson heart above the BPM number, with
    // a themed label beneath it (aligned with the LIFE / MANA orb labels). Sits in
    // the open column between the two globes. Active mode only.
    function drawHeartRate(dc as Dc, cx as Number, gy as Number, labelY as Number,
                           bpm as Number or Null) as Void {
        var avail = (bpm != null);
        var heartY = gy - (mHeight * 0.045).toNumber();
        drawHeart(dc, cx, heartY, (mHeight * 0.022).toNumber(), avail ? C_HR_BRIGHT : C_HR_DIM);

        dc.setColor(avail ? 0xFFFFFF : 0x707070, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, gy + (mHeight * 0.005).toNumber(), mFontValue, avail ? bpm.format("%d") : "--",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(C_HR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, labelY, mFontLabel, mHrLabel,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // A small filled heart: two top lobes + a downward point. `s` is the lobe radius.
    function drawHeart(dc as Dc, cx as Number, cy as Number, s as Number, color as Number) as Void {
        if (s < 2) { s = 2; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var lobe = (s * 0.55).toNumber();
        if (lobe < 1) { lobe = 1; }
        dc.fillCircle(cx - lobe, cy - (s * 0.25).toNumber(), lobe);
        dc.fillCircle(cx + lobe, cy - (s * 0.25).toNumber(), lobe);
        dc.fillPolygon([
            [cx - s, cy - (s * 0.05).toNumber()],
            [cx + s, cy - (s * 0.05).toNumber()],
            [cx, cy + s]
        ]);
    }

    // Status-icon row above the time: phone connection (always), then notification,
    // alarm and Do Not Disturb indicators when active. Centered as a group so the
    // row stays balanced regardless of how many icons are showing. `s` is the icon
    // half-size. Each guarded against missing DeviceSettings fields.
    function drawStatusIcons(dc as Dc, cx as Number, cy as Number, s as Number) as Void {
        var settings = System.getDeviceSettings();

        // Decide which icons to show, in fixed left-to-right order.
        var connected = (settings has :phoneConnected) && settings.phoneConnected;
        var notes = (settings has :notificationCount) ? settings.notificationCount : 0;
        var alarms = (settings has :alarmCount) ? settings.alarmCount : 0;
        var dnd = (settings has :doNotDisturb) && settings.doNotDisturb;
        if (notes == null) { notes = 0; }
        if (alarms == null) { alarms = 0; }

        // :phone is always drawn; the rest only when active.
        var icons = [:phone] as Array<Symbol>;
        if (notes > 0)  { icons.add(:bell); }
        if (alarms > 0) { icons.add(:alarm); }
        if (dnd)        { icons.add(:moon); }

        var n = icons.size();
        var gap = (s * 3.0).toNumber();              // center-to-center spacing
        var startX = cx - ((n - 1) * gap) / 2;
        for (var i = 0; i < n; i++) {
            var ix = startX + i * gap;
            var sym = icons[i];
            if (sym == :phone) {
                drawIconBluetooth(dc, ix, cy, s, connected ? C_ICON_ON : C_ICON_OFF, !connected);
            } else if (sym == :bell) {
                drawIconBell(dc, ix, cy, s, C_ICON_ALERT);
            } else if (sym == :alarm) {
                drawIconAlarm(dc, ix, cy, s, C_ICON_ON);
            } else if (sym == :moon) {
                drawIconMoon(dc, ix, cy, s, C_ICON_ON);
            }
        }
    }

    // Bluetooth rune: vertical staff with the two crossing triangles. `slash` draws
    // a diagonal strike when the phone is disconnected.
    function drawIconBluetooth(dc as Dc, cx as Number, cy as Number, s as Number, color as Number, slash as Boolean) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var rx = (s * 0.55).toNumber();
        var ry = (s * 0.45).toNumber();
        dc.drawLine(cx, cy - s, cx, cy + s);              // staff
        dc.drawLine(cx, cy - s, cx + rx, cy - ry);        // upper-right arm
        dc.drawLine(cx + rx, cy - ry, cx - rx, cy + ry);  // diagonal down-left
        dc.drawLine(cx - rx, cy - ry, cx + rx, cy + ry);  // diagonal up-right
        dc.drawLine(cx + rx, cy + ry, cx, cy + s);        // lower-right arm
        if (slash) {
            dc.setColor(C_ICON_OFF, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - s, cy + s, cx + s, cy - s);
        }
    }

    // Small notification bell.
    function drawIconBell(dc as Dc, cx as Number, cy as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var top = cy - s;
        var bot = cy + (s * 0.5).toNumber();
        // Body: tapered dome.
        dc.fillPolygon([
            [cx - (s * 0.7).toNumber(), bot],
            [cx - (s * 0.45).toNumber(), cy - (s * 0.3).toNumber()],
            [cx, top],
            [cx + (s * 0.45).toNumber(), cy - (s * 0.3).toNumber()],
            [cx + (s * 0.7).toNumber(), bot]
        ]);
        // Clapper.
        dc.fillCircle(cx, bot + (s * 0.25).toNumber(), (s * 0.22).toNumber());
    }

    // Small alarm clock: ringed face with two top bells and a pair of hands.
    function drawIconAlarm(dc as Dc, cx as Number, cy as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var r = (s * 0.7).toNumber();
        dc.drawCircle(cx, cy, r);
        // Top bell legs.
        dc.drawLine(cx - (s * 0.45).toNumber(), cy - (s * 0.55).toNumber(), cx - (s * 0.8).toNumber(), cy - (s * 0.9).toNumber());
        dc.drawLine(cx + (s * 0.45).toNumber(), cy - (s * 0.55).toNumber(), cx + (s * 0.8).toNumber(), cy - (s * 0.9).toNumber());
        // Hands.
        dc.setPenWidth(1);
        dc.drawLine(cx, cy, cx, cy - (s * 0.4).toNumber());
        dc.drawLine(cx, cy, cx + (s * 0.3).toNumber(), cy);
    }

    // Crescent moon (Do Not Disturb): a disc with a bite carved by the background.
    function drawIconMoon(dc as Dc, cx as Number, cy as Number, s as Number, color as Number) as Void {
        var r = (s * 0.7).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
        dc.setColor(BG_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx + (s * 0.35).toNumber(), cy - (s * 0.2).toNumber(), r);
    }

    // Sun glyph: a filled core with eight short rays.
    function drawSun(dc as Dc, cx as Number, cy as Number, r as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var core = (r * 0.55).toNumber();
        if (core < 2) { core = 2; }
        dc.fillCircle(cx, cy, core);
        dc.setPenWidth(2);
        for (var a = 0; a < 360; a += 45) {
            var rad = a * Math.PI / 180.0;
            var co = Math.cos(rad);
            var si = Math.sin(rad);
            dc.drawLine(cx + ((core + 1) * co).toNumber(), cy + ((core + 1) * si).toNumber(),
                        cx + (r * co).toNumber(),          cy + (r * si).toNumber());
        }
    }

    // Next sun event in the open column below the date: a sun + sunset time during
    // the day, a moon + sunrise time at night. Silently draws nothing when no GPS
    // location is known or during polar day/night. Active mode only.
    function drawSunTimes(dc as Dc, cx as Number, y as Number) as Void {
        var loc = getLocationDeg();
        if (loc == null) { return; }
        var nowUnix = Time.now().value();
        var ev = SolarUtil.sunEvents(nowUnix, loc[0], loc[1]);
        if (ev == null) { return; }

        var sunrise = ev[:sunrise];
        var sunset = ev[:sunset];
        var isDay = (nowUnix >= sunrise && nowUnix < sunset);
        var nextUnix = isDay ? sunset : sunrise;

        var tz = System.getClockTime().timeZoneOffset;   // local offset, seconds
        var timeStr = formatLocalHM(nextUnix + tz);

        var iconR = (mWidth * 0.020).toNumber();
        if (iconR < 5) { iconR = 5; }
        var gap = (mWidth * 0.014).toNumber();
        var tw = dc.getTextWidthInPixels(timeStr, mFontLabel);
        var startX = cx - (iconR * 2 + gap + tw) / 2;
        var iconCx = startX + iconR;

        if (isDay) {
            drawSun(dc, iconCx, y, iconR, C_SUN);
        } else {
            drawIconMoon(dc, iconCx, y, iconR, C_MOON);
        }
        dc.setColor(C_SUN_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + iconR * 2 + gap, y, mFontLabel, timeStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Format a UTC-plus-offset second count as H:MM / HH:MM per the device's clock.
    function formatLocalHM(localSec as Number) as String {
        var totalMin = localSec / 60;
        var hh = (totalMin / 60) % 24;
        var mm = totalMin % 60;
        if (hh < 0) { hh += 24; }
        if (mm < 0) { mm += 60; }
        if (System.getDeviceSettings().is24Hour) {
            return hh.format("%02d") + ":" + mm.format("%02d");
        }
        var h12 = hh % 12;
        if (h12 == 0) { h12 = 12; }
        return h12.format("%d") + ":" + mm.format("%02d");
    }

    // ------------------------------------------------------------------- Data

    // Today's steps as a fraction of the step goal (0.0 .. 1.0).
    function getStepFraction() as Float {
        var info = ActivityMonitor.getInfo();
        if (info == null || info.steps == null) { return 0.0; }
        var steps = info.steps;
        var goal = mStepGoalOverride;                       // user override
        if (goal <= 0) {                                    // else device goal
            if (info.stepGoal != null && info.stepGoal > 0) {
                goal = info.stepGoal;
            } else {
                goal = 10000;                               // sane fallback
            }
        }
        if (goal <= 0) { return 0.0; }
        var f = steps.toFloat() / goal.toFloat();
        if (f > 1.0) { f = 1.0; }
        return f;
    }

    // Body Battery via SensorHistory. Returns 0-100 or null if unavailable, so the
    // caller can dim the globe instead of crashing.
    //
    // ALTERNATIVE: the Complications framework also exposes Body Battery
    // (Complications.COMPLICATION_TYPE_BODY_BATTERY). It is push-based (subscribe in
    // onShow, cache the value in onComplicationUpdated). SensorHistory is used here
    // because it is synchronous and simpler; swap if you prefer Complications.
    function getBodyBattery() as Number or Null {
        try {
            if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
                var iter = SensorHistory.getBodyBatteryHistory({
                    :period => 1,
                    :order => SensorHistory.ORDER_NEWEST_FIRST
                });
                if (iter != null) {
                    var sample = iter.next();
                    if (sample != null && sample.data != null) {
                        var v = sample.data.toNumber();
                        if (v < 0) { v = 0; }
                        if (v > 100) { v = 100; }
                        return v;
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    // Current heart rate in BPM, or null if unavailable (no recent reading / no
    // sensor). Prefers the live Activity value, falling back to the most recent
    // ActivityMonitor heart-rate history sample. Null => the readout shows "--".
    function getHeartRate() as Number or Null {
        try {
            var info = Activity.getActivityInfo();
            if (info != null && info.currentHeartRate != null) {
                return info.currentHeartRate.toNumber();
            }
        } catch (e) {
            // fall through to history
        }
        try {
            if (ActivityMonitor has :getHeartRateHistory) {
                var iter = ActivityMonitor.getHeartRateHistory(1, true);
                if (iter != null) {
                    var sample = iter.next();
                    if (sample != null && sample.heartRate != null
                            && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                        return sample.heartRate.toNumber();
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    // Last known location as [latDeg, lngDeg], or null if none is available. Uses
    // the activity's current location (no extra permission), falling back to the
    // weather observation location. Watch faces can't drive GPS, so this is whatever
    // the system last fixed.
    function getLocationDeg() as Array or Null {
        try {
            var info = Activity.getActivityInfo();
            if (info != null && (info has :currentLocation) && info.currentLocation != null) {
                return info.currentLocation.toDegrees();
            }
        } catch (e) {
            // fall through
        }
        try {
            if (Toybox has :Weather) {
                var cc = Weather.getCurrentConditions();
                if (cc != null && (cc has :observationLocationPosition)
                        && cc.observationLocationPosition != null) {
                    return cc.observationLocationPosition.toDegrees();
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    // Current stress level (0-100) via SensorHistory, or null if unavailable.
    // Same shape as getBodyBattery: synchronous newest sample, fully guarded.
    function getStress() as Number or Null {
        try {
            if ((Toybox has :SensorHistory) && (SensorHistory has :getStressHistory)) {
                var iter = SensorHistory.getStressHistory({
                    :period => 1,
                    :order => SensorHistory.ORDER_NEWEST_FIRST
                });
                if (iter != null) {
                    var sample = iter.next();
                    if (sample != null && sample.data != null) {
                        var v = sample.data.toNumber();
                        if (v < 0) { v = 0; }
                        if (v > 100) { v = 100; }
                        return v;
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    // ------------------------------------------------------------ Color helpers

    // Thin delegators to ColorUtil (kept so the many call sites above read locally).
    // The implementations live in source/ColorUtil.mc so they can be unit-tested.
    function chordHalf(r as Number, dy as Number) as Number {
        return ColorUtil.chordHalf(r, dy);
    }

    function lerpColor(c1 as Number, c2 as Number, t as Float) as Number {
        return ColorUtil.lerpColor(c1, c2, t);
    }

    function scaleColor(c as Number, f as Float) as Number {
        return ColorUtil.scaleColor(c, f);
    }

    // ----------------------------------------------------------- Lifecycle

    function onHide() as Void {}

    function onExitSleep() as Void {
        mIsSleep = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        mIsSleep = true;
        mLastMin = -1;
        WatchUi.requestUpdate();
    }
}
