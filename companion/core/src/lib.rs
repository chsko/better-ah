//! Pure logic for the Better AH companion (spec #215).
//!
//! Nothing in this crate does I/O: snapshots go in, sales and stats come out.
//! The `better-ah-companion` binary wraps it with HTTP and files.

pub mod export;
pub mod infer;
pub mod rank;
pub mod snapshot;
pub mod stats;
pub mod tz;

pub use infer::{infer, Inference, Sale};
pub use snapshot::{Listing, Snapshot, TimeLeft};
pub use stats::{Applied, HourRow, Stats};

/// Hours in the rolling stats window.
pub const WINDOW_HOURS: u32 = 30 * 24;
