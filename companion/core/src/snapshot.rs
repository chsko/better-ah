//! One auction house export, reduced to the fields the stats use.

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Blizzard's coarse time-left bucket for a listing.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum TimeLeft {
    Short,
    Medium,
    Long,
    VeryLong,
}

impl TimeLeft {
    fn parse(s: &str) -> Option<TimeLeft> {
        match s {
            "SHORT" => Some(TimeLeft::Short),
            "MEDIUM" => Some(TimeLeft::Medium),
            "LONG" => Some(TimeLeft::Long),
            "VERY_LONG" => Some(TimeLeft::VeryLong),
            _ => None,
        }
    }
}

/// One listing. `unit_price` is copper per unit (at least 1); `price` is what buying all of
/// it costs (an auction's buyout, or unit price × quantity for a commodity).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Listing {
    pub id: u64,
    pub item: u32,
    pub quantity: u32,
    pub unit_price: u64,
    pub price: u64,
    pub time_left: TimeLeft,
    pub commodity: bool,
}

/// All listings of one house at one export. `exported_at` is the house response's
/// `Last-Modified` and `commodities_at` the commodities response's (Unix seconds).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Snapshot {
    pub exported_at: i64,
    pub commodities_at: i64,
    pub listings: Vec<Listing>,
}

impl Snapshot {
    /// Builds a snapshot from the house response (`auctions`) and the commodities
    /// response (`auctions` with `unit_price`). Bid-only auctions and entries with
    /// missing or odd fields are skipped.
    pub fn from_api(
        exported_at: i64,
        commodities_at: i64,
        house: &Value,
        commodities: &Value,
    ) -> Snapshot {
        let mut listings = Vec::new();
        for a in entries(house) {
            // `buyout` is the price of the whole auction.
            if let Some((id, item, quantity, time_left)) = common(a) {
                if let Some(buyout) = a.get("buyout").and_then(Value::as_u64) {
                    if buyout > 0 {
                        listings.push(Listing {
                            id,
                            item,
                            quantity,
                            unit_price: (buyout / u64::from(quantity)).max(1),
                            price: buyout,
                            time_left,
                            commodity: false,
                        });
                    }
                }
            }
        }
        for c in entries(commodities) {
            if let Some((id, item, quantity, time_left)) = common(c) {
                if let Some(unit_price) = c.get("unit_price").and_then(Value::as_u64) {
                    let unit_price = unit_price.max(1);
                    listings.push(Listing {
                        id,
                        item,
                        quantity,
                        unit_price,
                        price: unit_price.saturating_mul(u64::from(quantity)),
                        time_left,
                        commodity: true,
                    });
                }
            }
        }
        Snapshot {
            exported_at,
            commodities_at,
            listings,
        }
    }
}

fn entries(v: &Value) -> impl Iterator<Item = &Value> {
    v.get("auctions")
        .and_then(Value::as_array)
        .map(|a| a.iter())
        .into_iter()
        .flatten()
}

fn common(v: &Value) -> Option<(u64, u32, u32, TimeLeft)> {
    let id = v.get("id")?.as_u64()?;
    let item = u32::try_from(v.get("item")?.get("id")?.as_u64()?).ok()?;
    let quantity = u32::try_from(v.get("quantity")?.as_u64()?).ok()?;
    if quantity == 0 {
        return None;
    }
    let time_left = TimeLeft::parse(v.get("time_left")?.as_str()?)?;
    Some((id, item, quantity, time_left))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn reads_auctions_and_commodities_and_skips_bid_only() {
        let house = json!({ "auctions": [
            { "id": 1, "item": { "id": 720, "bonus_lists": [1] }, "buyout": 5000, "quantity": 2, "time_left": "LONG" },
            { "id": 2, "item": { "id": 721 }, "bid": 100, "quantity": 1, "time_left": "SHORT" },
            { "id": 3, "item": { "id": 722 }, "buyout": 10, "quantity": 1, "time_left": "WHATEVER" }
        ]});
        let commodities = json!({ "auctions": [
            { "id": 9, "item": { "id": 10940 }, "quantity": 20, "unit_price": 1234, "time_left": "VERY_LONG" }
        ]});
        let s = Snapshot::from_api(100, 100, &house, &commodities);
        assert_eq!(s.listings.len(), 2);
        assert_eq!(s.listings[0].unit_price, 2500);
        assert_eq!(s.listings[0].price, 5000);
        assert!(!s.listings[0].commodity);
        assert_eq!(s.listings[1].item, 10940);
        assert!(s.listings[1].commodity);
        assert_eq!(s.listings[1].price, 24680);
    }

    #[test]
    fn unit_price_never_rounds_to_zero() {
        let house = json!({ "auctions": [
            { "id": 1, "item": { "id": 720 }, "buyout": 3, "quantity": 20, "time_left": "LONG" }
        ]});
        let s = Snapshot::from_api(1, 1, &house, &json!({}));
        assert_eq!((s.listings[0].unit_price, s.listings[0].price), (1, 3));
    }

    #[test]
    fn empty_house_without_auctions_field() {
        let s = Snapshot::from_api(1, 1, &json!({ "id": 112 }), &json!({}));
        assert!(s.listings.is_empty());
    }
}
