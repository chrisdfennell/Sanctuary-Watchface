import Toybox.Test;
import Toybox.Lang;

// Unit tests for the pure helpers in ColorUtil. Run with:
//   ./build.ps1 -Test     (or `monkeyc --unit-test` / the simulator's Test runner)
// These exercise the math that drives the globe fluid rendering without needing a
// live WatchFace / device context.

(:test)
function testLerpEndpoints(logger as Test.Logger) as Boolean {
    Test.assertEqual(ColorUtil.lerpColor(0x000000, 0xFFFFFF, 0.0), 0x000000);
    Test.assertEqual(ColorUtil.lerpColor(0x000000, 0xFFFFFF, 1.0), 0xFFFFFF);
    return true;
}

(:test)
function testLerpMidpoint(logger as Test.Logger) as Boolean {
    // 0x00 -> 0xFF at 0.5 truncates per channel to 127 (0x7F).
    Test.assertEqual(ColorUtil.lerpColor(0x000000, 0xFFFFFF, 0.5), 0x7F7F7F);
    return true;
}

(:test)
function testLerpPerChannel(logger as Test.Logger) as Boolean {
    // Channels interpolate independently.
    Test.assertEqual(ColorUtil.lerpColor(0xFF0000, 0x0000FF, 1.0), 0x0000FF);
    Test.assertEqual(ColorUtil.lerpColor(0xFF0000, 0x00FF00, 0.0), 0xFF0000);
    return true;
}

(:test)
function testLerpClamps(logger as Test.Logger) as Boolean {
    // t outside [0,1] is clamped to the endpoints.
    Test.assertEqual(ColorUtil.lerpColor(0x102030, 0x405060, -1.0), 0x102030);
    Test.assertEqual(ColorUtil.lerpColor(0x102030, 0x405060, 2.0), 0x405060);
    return true;
}

(:test)
function testScaleColor(logger as Test.Logger) as Boolean {
    Test.assertEqual(ColorUtil.scaleColor(0xFFFFFF, 0.0), 0x000000);
    Test.assertEqual(ColorUtil.scaleColor(0xFFFFFF, 1.0), 0xFFFFFF);
    Test.assertEqual(ColorUtil.scaleColor(0xFFFFFF, 0.5), 0x7F7F7F);
    return true;
}

// 2023-06-21 12:00 UTC (summer solstice).
const SOLSTICE_NOON_UTC = 1687348800;

(:test)
function testSunEventsLondon(logger as Test.Logger) as Boolean {
    // London (~51.48 N, ~0 E) on the summer solstice: sunrise ~03:43 UTC,
    // sunset ~20:21 UTC. Assert generous ranges so the test isn't brittle.
    var ev = SolarUtil.sunEvents(SOLSTICE_NOON_UTC, 51.4769d, -0.0005d);
    Test.assert(ev != null);
    var sunrise = ev[:sunrise];
    var sunset = ev[:sunset];
    Test.assert(sunrise < sunset);

    var riseHourUtc = (sunrise % 86400) / 3600;
    var setHourUtc = (sunset % 86400) / 3600;
    logger.debug("London solstice rise=" + riseHourUtc + "h set=" + setHourUtc + "h UTC");
    Test.assert(riseHourUtc >= 3 && riseHourUtc <= 5);
    Test.assert(setHourUtc >= 19 && setHourUtc <= 21);

    // Daylight on the longest day should be ~16.5 h.
    var daylight = sunset - sunrise;
    Test.assert(daylight > 16 * 3600 && daylight < 17 * 3600);
    return true;
}

(:test)
function testSunEventsPolarDay(logger as Test.Logger) as Boolean {
    // Above the Arctic Circle at the summer solstice the sun never sets.
    var ev = SolarUtil.sunEvents(SOLSTICE_NOON_UTC, 80.0d, 0.0d);
    Test.assert(ev == null);
    return true;
}

(:test)
function testChordHalf(logger as Test.Logger) as Boolean {
    // At the center the chord half-length is the radius; at the edge it is 0.
    Test.assertEqual(ColorUtil.chordHalf(10, 0), 10);
    Test.assertEqual(ColorUtil.chordHalf(10, 10), 0);
    // Outside the circle returns 0, never a negative / NaN.
    Test.assertEqual(ColorUtil.chordHalf(10, 20), 0);
    // 3-4-5 triangle: chord half at dy=4 of an r=5 circle is 3.
    Test.assertEqual(ColorUtil.chordHalf(5, 4), 3);
    return true;
}
