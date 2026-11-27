//! Rolling 30-day per-item stats in UTC hour buckets.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::infer::{infer, Inference};
use crate::snapshot::Snapshot;
use crate::WINDOW_HOURS;

/// Current stats format. Bump it when the layout changes.
pub const VERSION: u32 = 1;

/// One item in one UTC hour (hours since the Unix epoch).
///
/// `sold` and `gold` are estimated sales in that hour (gold in copper). `min_price` is the
/// lowest unit price seen in that hour (0: not listed) and `supply` the units listed at the
/// last export of that hour. Stored as a JSON array to keep the file small.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(from = "(u32, u32, u64, u64, u32)", into = "(u32, u32, u64, u64, u32)")]
pub struct HourRow {
    pub hour: u32,
    pub sold: u32,
    pub gold: u64,
    pub min_price: u64,
    pub supply: u32,
}

impl From<(u32, u32, u64, u64, u32)> for HourRow {
    fn from((hour, sold, gold, min_price, supply): (u32, u32, u64, u64, u32)) -> Self {
        HourRow {
            hour,
            sold,
            gold,
            min_price,
            supply,
        }
    }
}

impl From<HourRow> for (u32, u32, u64, u64, u32) {
    fn from(r: HourRow) -> Self {
        (r.hour, r.sold, r.gold, r.min_price, r.supply)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Stats {
    pub version: u32,
    /// First export ever applied (Unix seconds).
    pub collecting_since: Option<i64>,
    /// Latest export applied (Unix seconds, house `Last-Modified`).
    pub last_export: Option<i64>,
    /// Commodities `Last-Modified` of the latest export applied.
    #[serde(default)]
    pub last_commodities_export: Option<i64>,
    /// Per item, rows sorted by hour, covering at most the last 30 days.
    pub items: BTreeMap<u32, Vec<HourRow>>,
    /// Item names from the static API; `None` when the API has no entry for the item.
    pub names: BTreeMap<u32, Option<String>>,
}

/// What applying one export did.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Applied {
    /// The house or the commodities export is not newer than the last one applied
    /// (a repeat, or one half still stale): nothing changed.
    Repeated,
    /// Supply and prices were recorded, but there was no usable previous snapshot to
    /// compare with (first run, lost or mismatched cache, or a gap over 3 hours), so no sales.
    Baseline,
    /// Supply, prices and estimated sales were recorded. `units_unknown` vanished but may
    /// have expired, so they are not counted as sold.
    Updated { units_sold: u64, units_unknown: u64 },
}

fn hour_of(t: i64) -> u32 {
    u32::try_from(t.div_euclid(3600)).unwrap_or(0)
}

impl Stats {
    pub fn new() -> Stats {
        Stats {
            version: VERSION,
            ..Stats::default()
        }
    }

    /// Records `next`, comparing it with `prev` (the previous export) when there is one.
    pub fn apply(&mut self, prev: Option<&Snapshot>, next: &Snapshot) -> Applied {
        if self.last_export.is_some_and(|t| next.exported_at <= t)
            || self
                .last_commodities_export
                .is_some_and(|t| next.commodities_at <= t)
        {
            return Applied::Repeated;
        }
        self.collecting_since.get_or_insert(next.exported_at);
        let next_hour = hour_of(next.exported_at);

        // Lowest unit price and total supply per item at this export.
        let mut seen: BTreeMap<u32, (u64, u32)> = BTreeMap::new();
        for l in &next.listings {
            let e = seen.entry(l.item).or_insert((u64::MAX, 0));
            e.0 = e.0.min(l.unit_price);
            e.1 = e.1.saturating_add(l.quantity);
        }
        for (&item, &(min_price, supply)) in &seen {
            let row = self.row(item, next_hour);
            row.min_price = if row.min_price == 0 {
                min_price
            } else {
                row.min_price.min(min_price)
            };
            row.supply = supply;
        }
        // Items listed earlier this hour but gone now: their supply is 0.
        for (item, rows) in self.items.iter_mut() {
            if let Some(last) = rows.last_mut() {
                if last.hour == next_hour && !seen.contains_key(item) {
                    last.supply = 0;
                }
            }
        }

        // Only the snapshot of the last applied export may be compared, or sales between
        // the two would be counted twice.
        let prev = prev.filter(|p| Some(p.exported_at) == self.last_export);
        let result = match prev.map(|p| (p, infer(p, next))) {
            Some((
                p,
                Inference::Compared {
                    sales,
                    unknown_units,
                },
            )) => {
                // Sales happened somewhere between the two exports: book them at the midpoint.
                let sale_hour = hour_of(p.exported_at + (next.exported_at - p.exported_at) / 2);
                let mut units_sold = 0u64;
                for s in sales {
                    let row = self.row(s.item, sale_hour);
                    row.sold = row.sold.saturating_add(s.units);
                    row.gold = row.gold.saturating_add(s.gold);
                    units_sold += u64::from(s.units);
                }
                Applied::Updated {
                    units_sold,
                    units_unknown: unknown_units,
                }
            }
            _ => Applied::Baseline,
        };

        self.last_export = Some(next.exported_at);
        self.last_commodities_export = Some(next.commodities_at);
        self.prune(next_hour);
        result
    }

    /// Drops rows older than the 30-day window ending at `now_hour`, and the names of
    /// items that no longer have rows. Returns whether anything was dropped.
    pub fn prune(&mut self, now_hour: u32) -> bool {
        let oldest = now_hour.saturating_sub(WINDOW_HOURS - 1);
        let mut dropped = false;
        self.items.retain(|_, rows| {
            let before = rows.len();
            rows.retain(|r| r.hour >= oldest);
            dropped |= rows.len() != before;
            !rows.is_empty()
        });
        let items = &self.items;
        self.names.retain(|item, _| items.contains_key(item));
        dropped
    }

    /// Prunes by wall-clock time, for runs where the export did not move on. Returns
    /// whether anything was dropped.
    pub fn prune_at(&mut self, now: i64) -> bool {
        self.prune(hour_of(now))
    }

    /// Items that have rows but no name lookup yet.
    pub fn unnamed(&self) -> Vec<u32> {
        self.items
            .keys()
            .filter(|i| !self.names.contains_key(i))
            .copied()
            .collect()
    }

    fn row(&mut self, item: u32, hour: u32) -> &mut HourRow {
        let rows = self.items.entry(item).or_default();
        let at = match rows.binary_search_by_key(&hour, |r| r.hour) {
            Ok(i) => i,
            Err(i) => {
                rows.insert(
                    i,
                    HourRow {
                        hour,
                        ..HourRow::default()
                    },
                );
                i
            }
        };
        &mut rows[at]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::snapshot::{Listing, TimeLeft};

    const H: i64 = 3600;
    const T0: i64 = 1_795_000_000 / H * H; // a whole UTC hour

    fn l(id: u64, item: u32, quantity: u32, price: u64, t: TimeLeft) -> Listing {
        Listing {
            id,
            item,
            quantity,
            unit_price: price,
            price: price * u64::from(quantity),
            time_left: t,
            commodity: false,
        }
    }

    fn snap(at: i64, listings: Vec<Listing>) -> Snapshot {
        Snapshot {
            exported_at: at,
            commodities_at: at,
            listings,
        }
    }

    fn rows(s: &Stats, item: u32) -> Vec<HourRow> {
        s.items.get(&item).cloned().unwrap_or_default()
    }

    #[test]
    fn first_export_is_a_baseline_with_supply_and_min_price() {
        let mut s = Stats::new();
        let a = snap(
            T0,
            vec![
                l(1, 720, 2, 500, TimeLeft::Long),
                l(2, 720, 1, 400, TimeLeft::Long),
            ],
        );
        assert_eq!(s.apply(None, &a), Applied::Baseline);
        let h = hour_of(T0);
        assert_eq!(
            rows(&s, 720),
            vec![HourRow {
                hour: h,
                sold: 0,
                gold: 0,
                min_price: 400,
                supply: 3
            }]
        );
        assert_eq!(s.collecting_since, Some(T0));
        assert_eq!(s.last_export, Some(T0));
    }

    #[test]
    fn sales_are_booked_at_the_midpoint_hour_with_gold() {
        let mut s = Stats::new();
        let a = snap(T0 + 50 * 60, vec![l(1, 720, 2, 500, TimeLeft::Long)]);
        let b = snap(T0 + 110 * 60, vec![]);
        s.apply(None, &a);
        assert_eq!(
            s.apply(Some(&a), &b),
            Applied::Updated {
                units_sold: 2,
                units_unknown: 0
            }
        );
        // Midpoint is T0 + 80 min, so hour T0+1.
        let r = rows(&s, 720);
        let sold: Vec<_> = r.iter().filter(|r| r.sold > 0).collect();
        assert_eq!(sold.len(), 1);
        assert_eq!(sold[0].hour, hour_of(T0) + 1);
        assert_eq!(sold[0].gold, 1000);
    }

    #[test]
    fn repeated_export_changes_nothing() {
        let mut s = Stats::new();
        let a = snap(T0, vec![l(1, 720, 1, 500, TimeLeft::Long)]);
        s.apply(None, &a);
        let before = s.clone();
        assert_eq!(s.apply(Some(&a), &a), Applied::Repeated);
        let older = snap(T0 - H, vec![]);
        assert_eq!(s.apply(Some(&a), &older), Applied::Repeated);
        assert_eq!(s, before);
    }

    #[test]
    fn stale_commodities_half_waits_for_the_next_run() {
        let mut s = Stats::new();
        let a = snap(T0, vec![l(1, 720, 1, 500, TimeLeft::Long)]);
        s.apply(None, &a);
        let mut b = snap(T0 + H, vec![]);
        b.commodities_at = T0;
        assert_eq!(s.apply(Some(&a), &b), Applied::Repeated);
        assert_eq!(s.last_export, Some(T0));
    }

    #[test]
    fn snapshot_from_another_export_is_not_compared() {
        let mut s = Stats::new();
        let a = snap(T0, vec![l(1, 720, 1, 500, TimeLeft::Long)]);
        let b = snap(T0 + H, vec![l(1, 720, 1, 500, TimeLeft::Long)]);
        let c = snap(T0 + 2 * H, vec![]);
        s.apply(None, &a);
        s.apply(Some(&a), &b);
        // A stale cache hands back `a` instead of `b`.
        assert_eq!(s.apply(Some(&a), &c), Applied::Baseline);
    }

    #[test]
    fn item_sold_out_later_in_the_hour_has_zero_supply() {
        let mut s = Stats::new();
        let a = snap(T0 + 60, vec![l(1, 720, 1, 500, TimeLeft::VeryLong)]);
        let b = snap(T0 + 1800, vec![]);
        s.apply(None, &a);
        s.apply(Some(&a), &b);
        let r = rows(&s, 720);
        assert_eq!(r.len(), 1);
        assert_eq!((r[0].sold, r[0].min_price, r[0].supply), (1, 500, 0));
    }

    #[test]
    fn wall_clock_prune_drops_old_rows_when_exports_stop() {
        let mut s = Stats::new();
        s.apply(None, &snap(T0, vec![l(1, 720, 1, 500, TimeLeft::Long)]));
        assert!(!s.prune_at(T0 + H));
        assert!(s.prune_at(T0 + i64::from(WINDOW_HOURS) * H));
        assert!(s.items.is_empty());
    }

    #[test]
    fn rows_older_than_30_days_roll_off() {
        let mut s = Stats::new();
        let a = snap(T0, vec![l(1, 720, 1, 500, TimeLeft::Long)]);
        s.apply(None, &a);
        s.names.insert(720, Some("Brawler Gloves".into()));
        let in_window = snap(
            T0 + (i64::from(WINDOW_HOURS) - 1) * H,
            vec![l(2, 721, 1, 9, TimeLeft::Long)],
        );
        s.apply(None, &in_window);
        assert_eq!(
            rows(&s, 720).len(),
            1,
            "exactly 30 days later is still inside"
        );
        let out = snap(
            T0 + i64::from(WINDOW_HOURS) * H,
            vec![l(2, 721, 1, 9, TimeLeft::Long)],
        );
        s.apply(None, &out);
        assert!(rows(&s, 720).is_empty());
        assert!(!s.names.contains_key(&720), "names go with their rows");
        assert_eq!(s.unnamed(), vec![721]);
    }

    #[test]
    fn two_exports_in_one_hour_keep_lowest_price_and_latest_supply() {
        let mut s = Stats::new();
        let a = snap(T0 + 60, vec![l(1, 720, 5, 300, TimeLeft::Long)]);
        let b = snap(
            T0 + 1800,
            vec![
                l(1, 720, 5, 300, TimeLeft::Long),
                l(2, 720, 1, 450, TimeLeft::Long),
            ],
        );
        s.apply(None, &a);
        s.apply(Some(&a), &b);
        let r = rows(&s, 720);
        assert_eq!(r.len(), 1);
        assert_eq!((r[0].min_price, r[0].supply), (300, 6));
    }

    #[test]
    fn utc_day_boundary_splits_hours() {
        let midnight = 1_795_046_400; // 2026-11-19 00:00:00 UTC
        assert_eq!(midnight % 86_400, 0);
        let mut s = Stats::new();
        let a = snap(midnight - 600, vec![l(1, 720, 1, 5, TimeLeft::Long)]);
        let b = snap(midnight + 600, vec![l(1, 720, 1, 5, TimeLeft::Long)]);
        s.apply(None, &a);
        s.apply(Some(&a), &b);
        let hours: Vec<u32> = rows(&s, 720).iter().map(|r| r.hour).collect();
        assert_eq!(hours, vec![hour_of(midnight) - 1, hour_of(midnight)]);
    }

    #[test]
    fn json_round_trip_uses_compact_rows() {
        let mut s = Stats::new();
        s.apply(None, &snap(T0, vec![l(1, 720, 1, 500, TimeLeft::Long)]));
        let text = serde_json::to_string(&s).unwrap();
        assert!(text.contains(&format!("[{},0,0,500,1]", hour_of(T0))));
        let back: Stats = serde_json::from_str(&text).unwrap();
        assert_eq!(back, s);
    }
}
