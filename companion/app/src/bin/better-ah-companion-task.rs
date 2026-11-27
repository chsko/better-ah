//! Windowless `sync` for the scheduled task (#220): same as `better-ah-companion sync`, but
//! built for the Windows GUI subsystem so no console window flashes up every hour. It writes
//! one line per run to `%LOCALAPPDATA%\better-ah-companion\sync.log` instead of the console.
#![cfg_attr(windows, windows_subsystem = "windows")]

#[path = "../sync.rs"]
mod sync;

use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::SystemTime;

/// Lines of history kept in the log.
const LOG_LINES: usize = 200;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let rest = match args.first().map(String::as_str) {
        Some("sync") => &args[1..],
        _ => &args[..],
    };
    let result =
        sync::parse_sync_args(rest).and_then(|a| sync::sync(&sync::Http, &a.url, &a.target));
    let line = match &result {
        Ok(sync::Outcome::Written(n)) => format!("updated {} ({n} bytes)", sync::FILE_NAME),
        Ok(sync::Outcome::Unchanged) => "unchanged".to_string(),
        Err(e) => format!("error: {e}"),
    };
    log(&line);
    if result.is_ok() {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn log(line: &str) {
    let Some(dir) =
        std::env::var_os("LOCALAPPDATA").map(|d| PathBuf::from(d).join("better-ah-companion"))
    else {
        return;
    };
    let _ = fs::create_dir_all(&dir);
    let path = dir.join("sync.log");
    let old = fs::read_to_string(&path).unwrap_or_default();
    let mut lines: Vec<&str> = old.lines().collect();
    let entry = format!("{} {line}", httpdate::fmt_http_date(SystemTime::now()));
    lines.push(&entry);
    let start = lines.len().saturating_sub(LOG_LINES);
    let _ = fs::write(&path, lines[start..].join("\n") + "\n");
}
