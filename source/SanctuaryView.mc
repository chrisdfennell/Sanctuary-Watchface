import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.SensorHistory;
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
    private var mLastMin as Number = -1;       // throttles low-power partial updates

    // --- Settings (see resources/settings) ---
    private var mShowDate as Boolean = true;
    private var mStepGoalOverride as Number = 0;  // 0 => use device step goal

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
                if (showDate != null) { mShowDate = showDate; }
                if (stepGoal != null) { mStepGoalOverride = stepGoal; }
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

        try {
            mBackground = WatchUi.loadResource(Rez.Drawables.diablo_background) as WatchUi.BitmapResource;
        } catch (e) {
            mBackground = null;
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

        // AMOLED burn-in protection: in always-on mode shift all lit pixels a few
        // px each minute and never paint large bright fills (handled per-element).
        var burnIn = false;
        var dx = 0;
        var dy = 0;
        var settings = System.getDeviceSettings();
        if ((settings has :requiresBurnInProtection) && settings.requiresBurnInProtection && mIsSleep) {
            burnIn = true;
            var phase = System.getClockTime().min % 4;
            if (phase == 1)      { dx = 4;  dy = 2; }
            else if (phase == 2) { dx = -3; dy = 4; }
            else if (phase == 3) { dx = 3;  dy = -4; }
        }

        var cx = mCenterX + dx;
        var cy = mCenterY + dy;

        // Always clear to pitch black first to ensure a clean slate.
        dc.setColor(BG_COLOR, BG_COLOR);
        dc.clear();

        // Draw Diablo-inspired background in active mode.
        if (!mIsSleep && !burnIn && mBackground != null) {
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

        // --- Time ---
        drawTime(dc, cx, timeY);

        // --- Ornamental divider + date (active mode only) ---
        if (!burnIn) {
            drawDivider(dc, cx, dividerY, (w * 0.20).toNumber());
            if (mShowDate) {
                drawDate(dc, cx, dateY);
            }
        }

        // --- Globes ---
        var bodyBattery = getBodyBattery();              // Number 0-100 or null
        var bodyAvail = (bodyBattery != null);
        var bodyVal = bodyAvail ? bodyBattery : 0;
        drawGlobe(dc, leftX, globeY, globeR, bodyVal, bodyAvail,
                  C_BODY_BRIGHT, C_BODY_DARK, C_BODY_RIM, C_BODY_GLOW);

        var stats = System.getSystemStats();
        var battery = (stats.battery != null) ? stats.battery.toNumber() : 0;
        drawGlobe(dc, rightX, globeY, globeR, battery, true,
                  C_BATT_BRIGHT, C_BATT_DARK, C_BATT_RIM, C_BATT_GLOW);

        // --- Globe value + label (active mode only). LIFE / MANA = the Diablo orbs. ---
        if (!burnIn) {
            drawGlobeText(dc, leftX, globeY, labelY, bodyAvail ? bodyVal.format("%d") : "--", "LIFE", C_BODY_RIM);
            drawGlobeText(dc, rightX, globeY, labelY, battery.format("%d") + "%", "MANA", C_BATT_RIM);
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
        onUpdate(dc);   // mIsSleep is true here -> low-power render path
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
        dc.setColor(mIsSleep ? 0x6E6E6E : 0xF2F2F2, Graphics.COLOR_TRANSPARENT);
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
        if (mIsSleep) {
            drawGlobeLowPower(dc, gx, gy, r, value, available, rim);
            return;
        }

        // 1. Soft outer glow (only when there is fluid to glow).
        if (available && value > 0) {
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
            var step = 2;
            for (var y = surfaceY; y <= bottomY; y += step) {
                var half = chordHalf(r - 1, y - gy);
                if (half < 1) { continue; }
                var t = 1.0 - ((y - surfaceY).toFloat() / fillH);  // 1 surface .. 0 bottom
                if (t < 0.0) { t = 0.0; }
                if (t > 1.0) { t = 1.0; }
                dc.setColor(lerpColor(dark, bright, t), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(gx - half, y, 2 * half, step);
            }

            // Molten core: a soft brighter glow at the fluid's center of mass for
            // volume (skipped on a near-empty orb so it doesn't float in the void).
            if (fillH > r * 0.5) {
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

        if (mIsSleep) {
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

    // ------------------------------------------------------------ Color helpers

    // Half-length of the horizontal chord of a circle (radius r) at vertical
    // offset dy from its center. Used to size fluid-surface lines.
    function chordHalf(r as Number, dy as Number) as Number {
        var d = r * r - dy * dy;
        if (d <= 0) { return 0; }
        return Math.sqrt(d).toNumber();
    }

    // Linear interpolate between two 0xRRGGBB colors. t in [0,1].
    function lerpColor(c1 as Number, c2 as Number, t as Float) as Number {
        if (t < 0.0) { t = 0.0; }
        if (t > 1.0) { t = 1.0; }
        var r1 = (c1 >> 16) & 0xFF;
        var g1 = (c1 >> 8) & 0xFF;
        var b1 = c1 & 0xFF;
        var r2 = (c2 >> 16) & 0xFF;
        var g2 = (c2 >> 8) & 0xFF;
        var b2 = c2 & 0xFF;
        var r = (r1 + ((r2 - r1) * t)).toNumber();
        var g = (g1 + ((g2 - g1) * t)).toNumber();
        var b = (b1 + ((b2 - b1) * t)).toNumber();
        return (r << 16) | (g << 8) | b;
    }

    // Scale a color's brightness toward black. f in [0,1].
    function scaleColor(c as Number, f as Float) as Number {
        return lerpColor(0x000000, c, f);
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
