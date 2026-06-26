import Toybox.Lang;
import Toybox.Math;

// Pure color / geometry helpers used by the globe rendering. Extracted into a
// module (no WatchFace state) so they can be unit-tested directly — see
// source/Tests.mc. SanctuaryView delegates to these.
module ColorUtil {

    // Linear interpolate between two 0xRRGGBB colors. t in [0,1] (clamped).
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

    // Half-length of the horizontal chord of a circle (radius r) at vertical
    // offset dy from its center. Used to size fluid-surface lines. Returns 0 when
    // the offset is outside the circle.
    function chordHalf(r as Number, dy as Number) as Number {
        var d = r * r - dy * dy;
        if (d <= 0) { return 0; }
        return Math.sqrt(d).toNumber();
    }
}
