//! Oslo local time, for the local days of the best-window-per-day (#263).
//!
//! Norway follows the EU rule: UTC+2 from the last Sunday of March 01:00 UTC to the last
//! Sunday of October 01:00 UTC, UTC+1 otherwise.

/// Days since 1970-01-01 of a civil date (Howard Hinnant's algorithm).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The year of a day count since 1970-01-01.
fn year_of(days: i64) -> i64 {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    yoe + era * 400 + i64::from(m <= 2)
}

/// Unix seconds of 01:00 UTC on the last Sunday of a month (31 days long).
fn last_sunday_0100(y: i64, m: i64) -> i64 {
    let day31 = days_from_civil(y, m, 31);
    // 1970-01-01 was a Thursday; (days + 4) % 7 is 0 on Sundays.
    let sunday = day31 - (day31 + 4).rem_euclid(7);
    sunday * 86_400 + 3600
}

/// Oslo local time minus UTC, in hours, at Unix time `t`.
pub fn oslo_offset(t: i64) -> i32 {
    let y = year_of(t.div_euclid(86_400));
    if t >= last_sunday_0100(y, 3) && t < last_sunday_0100(y, 10) {
        2
    } else {
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn civil_round_trip() {
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        assert_eq!(days_from_civil(2026, 11, 28), 20_785);
        assert_eq!(year_of(20_785), 2026);
        assert_eq!(year_of(days_from_civil(2024, 12, 31)), 2024);
        assert_eq!(year_of(days_from_civil(2025, 1, 1)), 2025);
    }

    #[test]
    fn oslo_switches_on_the_last_sundays_of_march_and_october() {
        // 2026: summer time 29 March 01:00 UTC to 25 October 01:00 UTC.
        let start = days_from_civil(2026, 3, 29) * 86_400 + 3600;
        let end = days_from_civil(2026, 10, 25) * 86_400 + 3600;
        assert_eq!(oslo_offset(start - 1), 1);
        assert_eq!(oslo_offset(start), 2);
        assert_eq!(oslo_offset(end - 1), 2);
        assert_eq!(oslo_offset(end), 1);
        assert_eq!(oslo_offset(days_from_civil(2026, 11, 28) * 86_400), 1);
        assert_eq!(oslo_offset(days_from_civil(2026, 7, 1) * 86_400), 2);
    }
}
