import Toybox.Lang;
import Toybox.Math;

// Pure sunrise / sunset solar calculation, with no device state, so it can be
// unit-tested directly (see source/Tests.mc). Implements the standard "sunrise
// equation" (https://en.wikipedia.org/wiki/Sunrise_equation): given a UTC instant
// and an observer's latitude/longitude it returns that day's sunrise and sunset as
// UTC unix seconds. SanctuaryView applies the local timezone offset for display.
module SolarUtil {

    const J1970 = 2440587.5d;          // Julian date of the unix epoch
    const J2000 = 2451545.0d;          // Julian date of 2000-01-01 12:00 TT
    const DEG = 0.01745329251994d;     // pi / 180

    // floor() for Doubles (Toybox.Math.floor is not guaranteed). toNumber()
    // truncates toward zero, so nudge down for negatives.
    function floorD(x as Double) as Double {
        var f = x.toNumber().toDouble();
        if (f > x) { f -= 1.0d; }
        return f;
    }

    // a mod m for Doubles, result in [0, m).
    function fmod(a as Double, m as Double) as Double {
        return a - m * floorD(a / m);
    }

    // Sunrise / sunset for the UTC day containing `unixSec`, at the given location.
    //   unixSec : seconds since the unix epoch (UTC)
    //   lat,lng : degrees, north / east positive
    // Returns { :sunrise => Number, :sunset => Number } as UTC unix seconds, or
    // null when the sun never crosses the horizon that day (polar day / night).
    function sunEvents(unixSec as Number, lat as Double, lng as Double) as Dictionary or Null {
        var jdate = unixSec.toDouble() / 86400.0d + J1970;

        // Mean solar time (lw = west longitude = -lng).
        var n = floorD(jdate - J2000 + 0.0008d);
        var jStar = n + (lng / 360.0d);

        // Solar mean anomaly (degrees).
        var m = fmod(357.5291d + 0.98560028d * jStar, 360.0d);
        var mr = m * DEG;

        // Equation of the center (degrees).
        var c = 1.9148d * Math.sin(mr)
              + 0.0200d * Math.sin(2.0d * mr)
              + 0.0003d * Math.sin(3.0d * mr);

        // Ecliptic longitude (degrees).
        var lambda = fmod(m + c + 282.9372d, 360.0d);   // 180 + 102.9372
        var lr = lambda * DEG;

        // Solar transit (Julian date).
        var jTransit = J2000 + jStar + 0.0053d * Math.sin(mr) - 0.0069d * Math.sin(2.0d * lr);

        // Declination of the sun.
        var sinDelta = Math.sin(lr) * Math.sin(23.4397d * DEG);
        var cosDelta = Math.cos(Math.asin(sinDelta));

        // Hour angle for the sun's center at -0.833 deg (refraction + radius).
        var latR = lat * DEG;
        var cosOmega = (Math.sin(-0.833d * DEG) - Math.sin(latR) * sinDelta)
                     / (Math.cos(latR) * cosDelta);
        if (cosOmega > 1.0d || cosOmega < -1.0d) {
            return null;   // polar day or night
        }
        var omega = Math.acos(cosOmega) / DEG;          // degrees

        var jRise = jTransit - omega / 360.0d;
        var jSet  = jTransit + omega / 360.0d;

        return {
            :sunrise => julianToUnix(jRise),
            :sunset  => julianToUnix(jSet)
        };
    }

    function julianToUnix(j as Double) as Number {
        return ((j - J1970) * 86400.0d).toNumber();
    }
}
