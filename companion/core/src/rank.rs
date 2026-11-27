//! Weekday-hour scores, the best window and the "post now or wait" hints (spec #215).
//!
//! Everything here is in UTC weekday-hours: index 0 is Monday 00:00-01:00 UTC and 167
//! is Sunday 23:00-24:00 UTC. Displays convert to local time.

use crate::stats::HourRow;
use crate::WINDOW_HOURS;

pub const WEEK_HOURS: usize = 168;
/// Length of the best window, in hours.
pub const WINDOW_LEN: usize = 3;
/// An item gets hints only with at least this many estimated sales...
pub const MIN_SALES: u64 = 10;
/// ...over at least this many days of collected data.
pub const MIN_DAYS: u32 = 7;

/// The weekday-hour (0 = Monday 00 UTC) of an hour counted from the Unix epoch.
/// 1970-01-01 was a Thursday, so day 0 is weekday 3.
pub fn week_hour(hour: u32) -> usize {
    let day = (hour / 24 + 3) % 7;
    (day * 24 + hour % 24) as usize
}

/// One weekday-hour of one item, averaged over the weeks collected.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Cell {
    /// Average estimated units sold in this hour of the week.
    pub sales: f64,
    /// Median of the hourly average sale price (copper per unit) in this hour of the week,
    /// or the item's overall median when it never sold in this hour.
    pub price: u64,
    /// `sales × price`: expected copper earned in this hour of the week.
    pub score: f64,
    /// Average lowest listed unit price (copper) in the hours it was listed, 0 if never listed.
    pub min_price: u64,
    /// Average units listed in the hours it was listed.
    pub supply: f64,
}

/// How now compares with the best window.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Rating {
    /// Now is inside the best window.
    Best,
    Good,
    Average,
    Slow,
}

/// Which duration to post with, or wait.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Advice {
    /// Post now for this many hours (2, 8 or 24): the shortest that is still up when the
    /// best window starts.
    Post(u8),
    /// The best window starts more than 24 hours from now.
    Wait,
}

/// The hint for posting at one weekday-hour.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Hint {
    pub rating: Rating,
    /// How much better the best window is than the next 3 hours, in percent; `None` when the
    /// next 3 hours have no expected sales at all.
    pub better_by: Option<u32>,
    pub advice: Advice,
}

/// An item's 168 cells, best window and hints.
#[derive(Clone, Debug, PartialEq)]
pub struct Ranked {
    pub cells: Vec<Cell>,
    /// Units estimated sold in the window.
    pub sold: u64,
    /// Weekday-hour the best window starts at.
    pub best_start: usize,
    /// 168 hints, one per weekday-hour, or `None` when there is too little data.
    pub hints: Option<Vec<Hint>>,
}

fn median(mut v: Vec<u64>) -> Option<u64> {
    if v.is_empty() {
        return None;
    }
    v.sort_unstable();
    let n = v.len();
    Some(if n % 2 == 1 {
        v[n / 2]
    } else {
        (v[n / 2 - 1] + v[n / 2]) / 2
    })
}

/// How often each weekday-hour occurs in the collected hours `[first, now]`, capped to
/// the 30-day window.
fn occurrences(first_hour: u32, now_hour: u32) -> [u32; WEEK_HOURS] {
    let mut n = [0u32; WEEK_HOURS];
    let start = first_hour.max(now_hour.saturating_sub(WINDOW_HOURS - 1));
    for h in start..=now_hour {
        n[week_hour(h)] += 1;
    }
    n
}

/// Ranks one item's rows. `first_hour` is the hour collection started (Unix hours) and
/// `now_hour` the current hour.
pub fn rank(rows: &[HourRow], first_hour: u32, now_hour: u32) -> Ranked {
    let occ = occurrences(first_hour, now_hour);
    // Only rows inside the hours that were counted.
    let oldest = first_hour.max(now_hour.saturating_sub(WINDOW_HOURS - 1));
    let rows: Vec<HourRow> = rows
        .iter()
        .filter(|r| r.hour >= oldest && r.hour <= now_hour)
        .copied()
        .collect();
    let mut sold = [0u64; WEEK_HOURS];
    let mut prices: Vec<Vec<u64>> = vec![Vec::new(); WEEK_HOURS];
    let mut all_prices = Vec::new();
    let mut min_sum = [0u64; WEEK_HOURS];
    let mut supply_sum = [0u64; WEEK_HOURS];
    let mut listed = [0u32; WEEK_HOURS];
    let mut total = 0u64;
    for r in &rows {
        let w = week_hour(r.hour);
        if r.sold > 0 {
            let p = r.gold / u64::from(r.sold);
            sold[w] += u64::from(r.sold);
            prices[w].push(p);
            all_prices.push(p);
            total += u64::from(r.sold);
        }
        if r.min_price > 0 {
            min_sum[w] = min_sum[w].saturating_add(r.min_price);
            supply_sum[w] += u64::from(r.supply);
            listed[w] += 1;
        }
    }
    let overall = median(all_prices).unwrap_or(0);
    let cells: Vec<Cell> = (0..WEEK_HOURS)
        .map(|w| {
            let sales = if occ[w] > 0 {
                sold[w] as f64 / f64::from(occ[w])
            } else {
                0.0
            };
            let price = median(prices[w].clone()).unwrap_or(overall);
            Cell {
                sales,
                price,
                score: sales * price as f64,
                min_price: if listed[w] > 0 {
                    min_sum[w] / u64::from(listed[w])
                } else {
                    0
                },
                supply: if listed[w] > 0 {
                    supply_sum[w] as f64 / f64::from(listed[w])
                } else {
                    0.0
                },
            }
        })
        .collect();

    let window = |start: usize| -> f64 {
        (0..WINDOW_LEN)
            .map(|i| cells[(start + i) % WEEK_HOURS].score)
            .sum()
    };
    // Highest window wins. Among equal windows, the one whose first hour scores most wins,
    // so a lone peak starts its window instead of ending it; then the earliest in the week.
    let key = |s: usize| (window(s), cells[s].score);
    let best_start = (0..WEEK_HOURS).fold(0, |best, s| if key(s) > key(best) { s } else { best });
    let best = window(best_start);

    // Days this item has been seen, so an item new to the auction house waits too.
    let seen_from = rows.first().map_or(now_hour, |r| r.hour);
    let days = now_hour.saturating_sub(seen_from) / 24;
    let enough = total >= MIN_SALES && days >= MIN_DAYS && best > 0.0;
    let hints = enough.then(|| {
        (0..WEEK_HOURS)
            .map(|n| hint(n, best_start, best, window(n)))
            .collect()
    });

    Ranked {
        cells,
        sold: total,
        best_start,
        hints,
    }
}

fn hint(now: usize, best_start: usize, best: f64, now_window: f64) -> Hint {
    let into = (now + WEEK_HOURS - best_start) % WEEK_HOURS;
    let inside = into < WINDOW_LEN;
    let until = if inside {
        0
    } else {
        (best_start + WEEK_HOURS - now) % WEEK_HOURS
    };
    let ratio = now_window / best;
    let rating = if inside {
        Rating::Best
    } else if ratio >= 0.75 {
        Rating::Good
    } else if ratio >= 0.4 {
        Rating::Average
    } else {
        Rating::Slow
    };
    let better_by = if inside {
        Some(0)
    } else {
        (now_window > 0.0).then(|| {
            let pct = ((best / now_window - 1.0) * 100.0).round();
            pct.clamp(0.0, 999.0) as u32
        })
    };
    // A listing posted now for d hours is up during hours now..now+d, so it catches the
    // start of the best window when that is fewer than d hours away. When now is nearly as
    // good as the best window, waiting a day for it isn't worth it: post 2h now.
    let fallback = if rating == Rating::Good {
        Advice::Post(2)
    } else {
        Advice::Wait
    };
    let advice = [2u8, 8, 24]
        .into_iter()
        .find(|&d| until < usize::from(d))
        .map_or(fallback, Advice::Post);
    Hint {
        rating,
        better_by,
        advice,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 2026-11-16 00:00 UTC, a Monday, in Unix hours.
    const MONDAY: u32 = 1_794_787_200 / 3600;

    fn sale(hour: u32, sold: u32, unit: u64) -> HourRow {
        HourRow {
            hour,
            sold,
            gold: unit * u64::from(sold),
            min_price: unit,
            supply: 5,
        }
    }

    /// Four weeks with `sold` units every week at weekday-hour `w`.
    fn weekly(w: u32, sold: u32, unit: u64) -> Vec<HourRow> {
        (0..4)
            .map(|k| sale(MONDAY + k * 168 + w, sold, unit))
            .collect()
    }

    fn now() -> u32 {
        MONDAY + 4 * 168 - 1
    }

    #[test]
    fn week_hour_starts_on_monday_utc() {
        assert_eq!(week_hour(MONDAY), 0);
        assert_eq!(week_hour(MONDAY + 23), 23);
        assert_eq!(week_hour(MONDAY + 6 * 24 + 23), 167);
        assert_eq!(week_hour(MONDAY + 168), 0);
    }

    #[test]
    fn best_window_is_the_highest_scoring_three_hours() {
        // Sunday 19:00 UTC (6*24+19 = 163) sells best.
        let mut rows = weekly(163, 3, 1000);
        rows.extend(weekly(20, 1, 1000));
        rows.sort_by_key(|r| r.hour);
        let r = rank(&rows, MONDAY, now());
        assert_eq!(r.sold, 16);
        assert!((r.cells[163].sales - 3.0).abs() < 1e-9);
        assert_eq!(r.cells[163].price, 1000);
        // A lone peak starts its window.
        assert_eq!(r.best_start, 163);
    }

    #[test]
    fn price_counts_not_just_sales() {
        // Two sales at 100g beat three at 10g.
        let mut rows = weekly(10, 3, 100_000);
        rows.extend(weekly(100, 2, 1_000_000));
        rows.sort_by_key(|r| r.hour);
        let r = rank(&rows, MONDAY, now());
        assert!((r.best_start..r.best_start + WINDOW_LEN).contains(&100));
    }

    #[test]
    fn best_window_wraps_from_sunday_into_monday() {
        let mut rows = weekly(167, 3, 1000);
        rows.extend(weekly(0, 3, 1000));
        rows.extend(weekly(1, 3, 1000));
        rows.sort_by_key(|r| r.hour);
        let r = rank(&rows, MONDAY, now());
        assert_eq!(r.best_start, 167);
        let hints = r.hints.unwrap();
        assert_eq!(hints[167].rating, Rating::Best);
        assert_eq!(hints[1].rating, Rating::Best);
        assert_eq!(hints[1].advice, Advice::Post(2));
    }

    #[test]
    fn advice_picks_the_shortest_duration_that_reaches_the_best_window() {
        let rows = weekly(100, 4, 1000);
        let r = rank(&rows, MONDAY, now());
        let best = r.best_start;
        assert_eq!(best, 100);
        let h = r.hints.unwrap();
        assert_eq!(h[best].advice, Advice::Post(2));
        assert_eq!(h[best - 1].advice, Advice::Post(2)); // 1 h away
        assert_eq!(h[best - 2].advice, Advice::Post(8)); // 2 h away
        assert_eq!(h[best - 7].advice, Advice::Post(8));
        assert_eq!(h[best - 8].advice, Advice::Post(24));
        assert_eq!(h[best - 23].advice, Advice::Post(24));
        assert_eq!(h[best - 24].advice, Advice::Wait);
        // Just after the window, it's six days and some away.
        assert_eq!(h[best + 3].advice, Advice::Wait);
        assert_eq!(h[best + 3].rating, Rating::Slow);
    }

    #[test]
    fn rating_and_percent_compare_now_with_the_best_window() {
        let mut rows = weekly(100, 4, 1000);
        rows.extend(weekly(50, 2, 1000));
        rows.sort_by_key(|r| r.hour);
        let r = rank(&rows, MONDAY, now());
        let h = r.hints.unwrap();
        // Window starting at 50 holds half of the best window's score.
        assert_eq!(h[50].rating, Rating::Average);
        assert_eq!(h[50].better_by, Some(100));
        // Nothing expected around weekday-hour 10.
        assert_eq!(h[10].rating, Rating::Slow);
        assert_eq!(h[10].better_by, None);
    }

    #[test]
    fn too_little_data_means_no_hints() {
        // Enough sales, but only 5 days collected.
        let rows: Vec<HourRow> = (0..5)
            .map(|d| sale(MONDAY + d * 24 + 12, 3, 1000))
            .collect();
        let r = rank(&rows, MONDAY, MONDAY + 5 * 24);
        assert!(r.hints.is_none());
        // Enough days, too few sales.
        let rows = vec![sale(MONDAY + 12, 9, 1000)];
        assert!(rank(&rows, MONDAY, now()).hints.is_none());
    }

    #[test]
    fn hours_never_collected_do_not_dilute_averages() {
        // Collection started 8 days ago: each weekday-hour occurred once or twice, not 4 times.
        let first = now() - 8 * 24;
        let rows = vec![sale(first + 10, 6, 1000), sale(first + 10 + 168, 6, 1000)];
        let r = rank(&rows, first, now());
        assert!((r.cells[week_hour(first + 10)].sales - 6.0).abs() < 1e-9);
    }

    #[test]
    fn listed_hours_give_min_price_and_supply() {
        let rows = vec![HourRow {
            hour: MONDAY + 5,
            sold: 0,
            gold: 0,
            min_price: 700,
            supply: 12,
        }];
        let r = rank(&rows, MONDAY, now());
        assert_eq!(r.cells[5].min_price, 700);
        assert!((r.cells[5].supply - 12.0).abs() < 1e-9);
        assert_eq!(r.cells[6].min_price, 0);
    }

    #[test]
    fn a_lone_peak_is_caught_by_a_2h_post_at_the_window_start() {
        let rows = weekly(30, 3, 1000);
        let r = rank(&rows, MONDAY, now());
        assert_eq!(r.best_start, 30);
        assert_eq!(r.cells[r.best_start].price, 1000);
        let h = r.hints.unwrap();
        assert_eq!(h[30].advice, Advice::Post(2));
        // Two hours before, the next three hours already include the peak.
        assert_eq!(h[28].rating, Rating::Good);
        assert_eq!(h[28].advice, Advice::Post(8));
    }

    #[test]
    fn inside_the_window_is_best_with_no_percent_and_a_2h_post() {
        let mut rows = weekly(100, 4, 1000);
        rows.extend(weekly(101, 4, 1000));
        rows.extend(weekly(102, 4, 1000));
        rows.sort_by_key(|r| r.hour);
        let h = rank(&rows, MONDAY, now()).hints.unwrap();
        for n in [100, 101, 102] {
            assert_eq!(h[n].rating, Rating::Best);
            assert_eq!(h[n].better_by, Some(0));
            assert_eq!(h[n].advice, Advice::Post(2));
        }
        assert_ne!(h[103].rating, Rating::Best);
    }

    #[test]
    fn a_nearly_as_good_hour_posts_now_instead_of_waiting() {
        // Two equal peaks three days apart.
        let mut rows = weekly(20, 4, 1000);
        rows.extend(weekly(92, 4, 1000));
        rows.sort_by_key(|r| r.hour);
        let r = rank(&rows, MONDAY, now());
        let h = r.hints.unwrap();
        let other = if r.best_start == 20 { 92 } else { 20 };
        assert_eq!(h[other].rating, Rating::Good);
        assert_eq!(h[other].better_by, Some(0));
        assert_eq!(h[other].advice, Advice::Post(2));
    }

    #[test]
    fn rating_thresholds() {
        // Best window 4000 copper; other lone hours at 3000 (0.75), 1600 (0.4), 1500 (0.375).
        let mut rows = weekly(100, 4, 1000);
        rows.extend(weekly(10, 3, 1000));
        rows.extend(weekly(40, 2, 800));
        rows.extend(weekly(70, 3, 500));
        rows.sort_by_key(|r| r.hour);
        let h = rank(&rows, MONDAY, now()).hints.unwrap();
        assert_eq!(h[10].rating, Rating::Good);
        assert_eq!(h[40].rating, Rating::Average);
        assert_eq!(h[70].rating, Rating::Slow);
    }

    #[test]
    fn the_30_day_cap_ignores_older_rows_and_hours() {
        // Collecting for 8 weeks; only the last 30 days count.
        let first = MONDAY - 4 * 168;
        let mut rows: Vec<HourRow> = (0..4)
            .map(|k| sale(first + k * 168 + 50, 100, 1000))
            .collect();
        rows.extend(weekly(50, 2, 1000));
        let r = rank(&rows, first, now());
        assert_eq!(r.sold, 8);
        // 720 hours hold weekday-hour 50 four or five times, each with at most 2 sold.
        assert!(r.cells[50].sales <= 2.0 && r.cells[50].sales >= 1.6);
    }

    #[test]
    fn threshold_boundaries() {
        let rows = vec![sale(MONDAY, 10, 1000)];
        assert!(rank(&rows, MONDAY, MONDAY + 7 * 24).hints.is_some());
        assert!(rank(&rows, MONDAY, MONDAY + 7 * 24 - 1).hints.is_none());
        let rows = vec![sale(MONDAY, 9, 1000)];
        assert!(rank(&rows, MONDAY, MONDAY + 7 * 24).hints.is_none());
    }

    #[test]
    fn an_item_new_to_the_auction_house_waits_for_its_own_seven_days() {
        let rows = vec![sale(now() - 24, 20, 1000)];
        assert!(rank(&rows, MONDAY, now()).hints.is_none());
    }
}
