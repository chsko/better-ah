//! Estimates sales by comparing two consecutive snapshots of one house.
//!
//! The API has no sales feed. Blizzard's time-left buckets give the least time a listing
//! still had when last seen: MEDIUM at least 30 min, LONG at least 2 h, VERY_LONG at least
//! 12 h. So:
//! - a listing that is gone counts as sold only when the gap between the two exports is
//!   shorter than that least remaining time, because it can't have expired yet;
//! - a gone listing that could have run out in the gap (any SHORT one, or a MEDIUM one over
//!   an hourly gap) counts as expired-or-unknown, not as a sale;
//! - a commodity listing whose quantity dropped counts the difference as sold.
//!
//! Cancels look exactly like sales; that noise is accepted (spec #215). Listings bought
//! during their last 30 minutes to 2 hours are missed at an hourly cadence, so sales of
//! 2-hour posts are undercounted (ADR 0006).

use std::collections::HashMap;

use crate::snapshot::{Snapshot, TimeLeft};

/// Longest gap between two exports that still gets compared.
pub const MAX_GAP_SECONDS: i64 = 3 * 3600;

/// Least time a listing in this bucket still has, in seconds.
fn least_remaining(t: TimeLeft) -> i64 {
    match t {
        TimeLeft::Short => 0,
        TimeLeft::Medium => 30 * 60,
        TimeLeft::Long => 2 * 3600,
        TimeLeft::VeryLong => 12 * 3600,
    }
}

/// Units of one item that most likely sold between two exports, and the copper paid.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Sale {
    pub item: u32,
    pub units: u32,
    pub gold: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Inference {
    /// The two snapshots were compared. `unknown_units` vanished but may have expired.
    Compared {
        sales: Vec<Sale>,
        unknown_units: u64,
    },
    /// The gap was too long (or not forward) to compare; nothing is counted.
    Gap,
}

pub fn infer(prev: &Snapshot, next: &Snapshot) -> Inference {
    let gap = next.exported_at - prev.exported_at;
    if gap <= 0 || gap > MAX_GAP_SECONDS {
        return Inference::Gap;
    }
    // Auction and commodity IDs are separate number spaces.
    let now: HashMap<(bool, u64), (u32, u32)> = next
        .listings
        .iter()
        .map(|l| ((l.commodity, l.id), (l.item, l.quantity)))
        .collect();
    let mut sales = Vec::new();
    let mut unknown_units = 0u64;
    for l in &prev.listings {
        match now.get(&(l.commodity, l.id)) {
            None if gap < least_remaining(l.time_left) => sales.push(Sale {
                item: l.item,
                units: l.quantity,
                gold: l.price,
            }),
            None => unknown_units += u64::from(l.quantity),
            Some(&(item, q)) if item == l.item && l.commodity && q < l.quantity => {
                let units = l.quantity - q;
                sales.push(Sale {
                    item: l.item,
                    units,
                    gold: l.unit_price.saturating_mul(u64::from(units)),
                })
            }
            // Same listing still up, or an ID reused for another item: no sale.
            Some(_) => {}
        }
    }
    Inference::Compared {
        sales,
        unknown_units,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::snapshot::Listing;

    const HOUR: i64 = 3600;

    fn l(id: u64, item: u32, quantity: u32, price: u64, t: TimeLeft, commodity: bool) -> Listing {
        Listing {
            id,
            item,
            quantity,
            unit_price: price,
            price: price * u64::from(quantity),
            time_left: t,
            commodity,
        }
    }

    fn snap(at: i64, listings: Vec<Listing>) -> Snapshot {
        Snapshot {
            exported_at: at,
            commodities_at: at,
            listings,
        }
    }

    fn sold(item: u32, units: u32, gold: u64) -> Sale {
        Sale { item, units, gold }
    }

    #[test]
    fn gone_long_listing_after_an_hour_counts_as_sold() {
        let prev = snap(0, vec![l(1, 720, 2, 2500, TimeLeft::Long, false)]);
        assert_eq!(
            infer(&prev, &snap(HOUR, vec![])),
            Inference::Compared {
                sales: vec![sold(720, 2, 5000)],
                unknown_units: 0
            }
        );
    }

    #[test]
    fn gone_listing_that_could_have_expired_is_unknown() {
        let prev = snap(
            0,
            vec![
                l(1, 720, 3, 5000, TimeLeft::Short, false),
                l(2, 720, 1, 5000, TimeLeft::Medium, false),
            ],
        );
        assert_eq!(
            infer(&prev, &snap(HOUR, vec![])),
            Inference::Compared {
                sales: vec![],
                unknown_units: 4
            }
        );
    }

    #[test]
    fn medium_listing_gone_within_30_minutes_counts_as_sold() {
        let prev = snap(0, vec![l(2, 720, 1, 5000, TimeLeft::Medium, false)]);
        assert_eq!(
            infer(&prev, &snap(15 * 60, vec![])),
            Inference::Compared {
                sales: vec![sold(720, 1, 5000)],
                unknown_units: 0
            }
        );
    }

    #[test]
    fn long_listing_gone_over_a_three_hour_gap_is_unknown() {
        let prev = snap(0, vec![l(1, 720, 1, 5000, TimeLeft::Long, false)]);
        assert_eq!(
            infer(&prev, &snap(3 * HOUR, vec![])),
            Inference::Compared {
                sales: vec![],
                unknown_units: 1
            }
        );
    }

    #[test]
    fn commodity_quantity_drop_is_a_partial_sale() {
        let prev = snap(0, vec![l(9, 10940, 20, 100, TimeLeft::VeryLong, true)]);
        let next = snap(HOUR, vec![l(9, 10940, 15, 100, TimeLeft::VeryLong, true)]);
        assert_eq!(
            infer(&prev, &next),
            Inference::Compared {
                sales: vec![sold(10940, 5, 500)],
                unknown_units: 0
            }
        );
    }

    #[test]
    fn unchanged_new_and_reused_listings_are_not_sales() {
        let prev = snap(
            0,
            vec![
                l(1, 720, 1, 5000, TimeLeft::Long, false),
                l(5, 10940, 20, 100, TimeLeft::VeryLong, true),
            ],
        );
        let next = snap(
            HOUR,
            vec![
                l(1, 720, 1, 5000, TimeLeft::Medium, false),
                l(2, 720, 1, 4000, TimeLeft::VeryLong, false),
                // Commodity ID 5 reused for another item.
                l(5, 2770, 3, 10, TimeLeft::VeryLong, true),
            ],
        );
        assert_eq!(
            infer(&prev, &next),
            Inference::Compared {
                sales: vec![],
                unknown_units: 0
            }
        );
    }

    #[test]
    fn auction_and_commodity_ids_do_not_collide() {
        let prev = snap(0, vec![l(7, 720, 1, 5000, TimeLeft::Long, false)]);
        let next = snap(HOUR, vec![l(7, 10940, 20, 100, TimeLeft::VeryLong, true)]);
        assert_eq!(
            infer(&prev, &next),
            Inference::Compared {
                sales: vec![sold(720, 1, 5000)],
                unknown_units: 0
            }
        );
    }

    #[test]
    fn long_or_backwards_gap_is_not_compared() {
        let prev = snap(0, vec![l(1, 720, 1, 5000, TimeLeft::Long, false)]);
        assert_eq!(
            infer(&prev, &snap(MAX_GAP_SECONDS + 1, vec![])),
            Inference::Gap
        );
        assert_eq!(infer(&prev, &snap(0, vec![])), Inference::Gap);
        assert_eq!(infer(&prev, &snap(-5, vec![])), Inference::Gap);
    }
}
