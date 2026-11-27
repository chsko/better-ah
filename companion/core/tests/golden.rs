//! Golden test: the addon data file and page JSON for a fixed four-week fixture.
//! Run with `UPDATE_GOLDEN=1 cargo test` to rewrite the expected files after a deliberate change.

use std::fs;
use std::path::PathBuf;

use bah_core::export::{lua_data, page_files};
use bah_core::{HourRow, Stats};

/// 2026-11-16 00:00 UTC, a Monday.
const MONDAY: i64 = 1_794_787_200;

fn fixture() -> (Stats, i64) {
    let mut s = Stats::new();
    s.collecting_since = Some(MONDAY);
    let h0 = (MONDAY / 3600) as u32;
    let mut rows = Vec::new();
    for week in 0..4u32 {
        // Arcane Dust sells best Sunday 19:00-22:00 UTC, some on Wednesday noon.
        for (w, sold) in [(163u32, 6u32), (164, 5), (165, 4), (60, 2)] {
            rows.push(HourRow {
                hour: h0 + week * 168 + w,
                sold,
                gold: u64::from(sold) * 9500,
                min_price: 9500,
                supply: 40,
            });
        }
    }
    s.items.insert(16204, rows);
    // Sold too little for hints: page only.
    s.items.insert(
        720,
        vec![HourRow {
            hour: h0 + 30,
            sold: 1,
            gold: 5000,
            min_price: 5000,
            supply: 1,
        }],
    );
    // Never sold: neither output.
    s.items.insert(
        2770,
        vec![HourRow {
            hour: h0 + 31,
            sold: 0,
            gold: 0,
            min_price: 12,
            supply: 200,
        }],
    );
    s.names.insert(16204, Some("Illusion Dust".into()));
    s.names.insert(720, None);
    let now = MONDAY + 4 * 7 * 86_400 - 3600;
    s.last_export = Some(now);
    (s, now)
}

fn check(name: &str, actual: &str) {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/golden")
        .join(name);
    if std::env::var_os("UPDATE_GOLDEN").is_some() {
        fs::write(&path, actual).unwrap();
    }
    let expected = fs::read_to_string(&path).unwrap_or_default();
    assert_eq!(
        actual, expected,
        "{name} differs; rerun with UPDATE_GOLDEN=1 if intended"
    );
}

#[test]
fn addon_data_file() {
    let (s, now) = fixture();
    check("SellTimes.lua", &lua_data(&s, now, "/Normal/Horde"));
}

#[test]
fn page_files_index_and_items() {
    let (s, now) = fixture();
    let files = page_files(&s, now, "/Normal/Horde");
    let names: Vec<&str> = files.iter().map(|(p, _)| p.as_str()).collect();
    assert_eq!(
        names,
        vec!["index.json", "items/720.json", "items/16204.json"]
    );
    let index = &files[0].1;
    assert!(
        index["items"].get("2770").is_none(),
        "never sold: not on the page"
    );
    assert!(
        index["items"]["720"][2].is_null(),
        "too little data: no best window"
    );
    check("index.json", &serde_json::to_string_pretty(index).unwrap());
    check(
        "item-16204.json",
        &serde_json::to_string_pretty(&files[2].1).unwrap(),
    );
}
