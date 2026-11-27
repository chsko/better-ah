//! Better AH companion (spec #215).
//!
//! `better-ah-companion collect` runs on GitHub Actions: it reads Blizzard's Forever
//! auction house export, updates the rolling stats and writes the Pages site.
//! `sync`, `install` and `uninstall` run on the player's PC: they copy the addon's data file
//! from the Pages site into the BetterAH folder, by hand or from a scheduled task (#220).

mod install;
mod sync;

use std::env;
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{Duration, SystemTime};

use bah_core::export::{lua_data, page_files};
use bah_core::{Applied, Snapshot, Stats};
use base64::Engine;
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use serde_json::Value;

/// Most item names looked up per run, to stay far below the API's hourly quota.
const NAME_LOOKUPS_PER_RUN: usize = 1500;
/// Longest time a run spends on name lookups.
const NAME_LOOKUP_TIME: Duration = Duration::from_secs(6 * 60);
/// Where item names come from, in order. Forever's own static data lacks many items (#219),
/// so items it lacks are looked up in Classic Era's, which shares item IDs with Classic.
const NAME_NAMESPACES: [&str; 2] = ["static-forever", "static-classic1x"];

type Res<T> = Result<T, String>;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("collect") => Collect::from_args(&args[1..]).and_then(|c| c.run()),
        Some("sync") => sync::parse_sync_args(&args[1..]).and_then(|a| {
            let out = sync::sync(&sync::Http, &a.url, &a.target)?;
            match out {
                sync::Outcome::Written(n) => println!("updated {} ({n} bytes)", a.target.join(sync::FILE_NAME).display()),
                sync::Outcome::Unchanged => println!("{} is up to date", a.target.join(sync::FILE_NAME).display()),
            }
            Ok(())
        }),
        Some("install") => sync::parse_sync_args(&args[1..]).and_then(|a| {
            install::install(&a.url, &a.target)?;
            println!(
                "Installed the \"{}\" task: it syncs {} hourly and at logon. Log: %LOCALAPPDATA%\\better-ah-companion\\sync.log",
                install::TASK_NAME,
                a.target.display()
            );
            Ok(())
        }),
        Some("uninstall") => install::uninstall().map(|()| println!("Removed the \"{}\" task.", install::TASK_NAME)),
        _ => Err(USAGE.to_string()),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}

const USAGE: &str =
    "usage: better-ah-companion collect --out <dir> --cache <dir> [--pages-url <url>]
       better-ah-companion sync [--target <BetterAH folder>] [--url <data file url>]
       better-ah-companion install [--target <BetterAH folder>] [--url <data file url>]
       better-ah-companion uninstall

sync copies the sell times data file into the BetterAH folder (default
%USERPROFILE%\\better-ah\\BetterAH). install copies the app to
%LOCALAPPDATA%\\better-ah-companion and adds a scheduled task that syncs hourly and at logon.

collect:

Environment: BLIZZARD_CLIENT_ID, BLIZZARD_CLIENT_SECRET (required),
REGION (eu), RULESET (2), HOUSE (114), MARKET (/Normal/Horde).";

struct Collect {
    out: PathBuf,
    cache: PathBuf,
    pages_url: Option<String>,
    region: String,
    ruleset: String,
    house: String,
    market: String,
}

impl Collect {
    fn from_args(args: &[String]) -> Res<Collect> {
        let mut out = None;
        let mut cache = None;
        let mut pages_url = None;
        let mut it = args.iter();
        while let Some(a) = it.next() {
            let mut value = || it.next().cloned().ok_or(format!("{a} needs a value"));
            match a.as_str() {
                "--out" => out = Some(PathBuf::from(value()?)),
                "--cache" => cache = Some(PathBuf::from(value()?)),
                "--pages-url" => pages_url = Some(value()?.trim_end_matches('/').to_string()),
                _ => return Err(format!("unknown argument {a}\n\n{USAGE}")),
            }
        }
        Ok(Collect {
            out: out.ok_or(USAGE)?,
            cache: cache.ok_or(USAGE)?,
            pages_url,
            region: env_or("REGION", "eu"),
            ruleset: env_or("RULESET", "2"),
            house: env_or("HOUSE", "114"),
            // Better AH's market key for this house (ADR 0005).
            market: env_or("MARKET", "/Normal/Horde"),
        })
    }

    fn run(&self) -> Res<()> {
        // One clock reading for the whole run, so pruning and ranking agree on the hour.
        let now = system_to_unix(SystemTime::now());
        let api = Api::connect(&self.region)?;
        let base = format!("/data/wow/ruleset/{}/auctions/{}", self.ruleset, self.house);
        let house = api.dynamic(&base)?;
        let commodities = api.dynamic(&format!("{base}/commodities"))?;
        let exported_at = house
            .modified
            .ok_or("the house export has no Last-Modified header; can't tell exports apart")?;
        let commodities_at = commodities.modified.unwrap_or(exported_at);
        let next = Snapshot::from_api(exported_at, commodities_at, &house.body, &commodities.body);
        println!(
            "export at={} listings={}",
            httpdate::fmt_http_date(unix_to_system(exported_at)),
            next.listings.len()
        );

        let state_path = self.cache.join("state.json.gz");
        let prev_path = self.cache.join("snapshot.json.gz");
        let mut stats = self.load_stats(&state_path)?;
        let prev: Option<Snapshot> = read_gz_json(&prev_path)?;

        if let Some((auctions, commodities)) = prev
            .as_ref()
            .and_then(|p| bah_core::infer::breakdown(p, &next))
        {
            println!("auctions {auctions:?}");
            println!("commodities {commodities:?}");
        }
        let applied = stats.apply(prev.as_ref(), &next);
        println!("applied {applied:?}");
        // Even without a new export, nothing older than 30 days may stay published.
        let expired = stats.prune_at(now);
        if applied == Applied::Repeated && !expired {
            set_output("changed", "false");
            return Ok(());
        }
        if applied != Applied::Repeated {
            self.lookup_names(&api, &mut stats);
        }

        fs::create_dir_all(&self.cache).map_err(|e| format!("cache dir: {e}"))?;
        fs::create_dir_all(&self.out).map_err(|e| format!("out dir: {e}"))?;
        write_gz_json(&state_path, &stats)?;
        if applied != Applied::Repeated {
            write_gz_json(&prev_path, &next)?;
        }
        fs::copy(&state_path, self.out.join("state.json.gz"))
            .map_err(|e| format!("copy state: {e}"))?;
        let files = page_files(&stats, now, &self.market);
        fs::create_dir_all(self.out.join("items")).map_err(|e| format!("items dir: {e}"))?;
        let mut page_bytes = 0;
        for (path, value) in &files {
            let text = value.to_string();
            page_bytes += text.len();
            fs::write(self.out.join(path), text).map_err(|e| format!("{path}: {e}"))?;
        }
        let lua = lua_data(&stats, now, &self.market);
        fs::write(self.out.join("SellTimes.lua"), &lua)
            .map_err(|e| format!("SellTimes.lua: {e}"))?;
        println!(
            "page items={} bytes={page_bytes} addon file bytes={}",
            files.len() - 1,
            lua.len()
        );
        fs::write(self.out.join("index.html"), INDEX_HTML).map_err(|e| format!("index: {e}"))?;
        fs::write(self.out.join(".nojekyll"), "").map_err(|e| format!(".nojekyll: {e}"))?;
        println!(
            "items={} rows={}",
            stats.items.len(),
            stats.items.values().map(Vec::len).sum::<usize>()
        );
        set_output("changed", "true");
        Ok(())
    }

    /// Stats from the Actions cache, else from the published site, else empty. Anything
    /// but a clean 404 from the site is an error, so a hiccup never wipes 30 days.
    fn load_stats(&self, cached: &Path) -> Res<Stats> {
        if let Some(s) = read_gz_json::<Stats>(cached)? {
            println!("stats from cache");
            return check_version(s);
        }
        let Some(url) = &self.pages_url else {
            println!("no cache and no --pages-url: starting fresh");
            return Ok(Stats::new());
        };
        match agent().get(&format!("{url}/state.json.gz")).call() {
            Ok(resp) => {
                let mut bytes = Vec::new();
                resp.into_reader()
                    .read_to_end(&mut bytes)
                    .map_err(|e| format!("read published stats: {e}"))?;
                // The HTTP client may already have undone the gzip.
                let s: Stats = if bytes.starts_with(&[0x1f, 0x8b]) {
                    serde_json::from_reader(GzDecoder::new(&bytes[..]))
                } else {
                    serde_json::from_slice(&bytes)
                }
                .map_err(|e| format!("parse published stats: {e}"))?;
                println!("stats from {url}");
                check_version(s)
            }
            Err(ureq::Error::Status(404, _)) => {
                println!("nothing published yet: starting fresh");
                Ok(Stats::new())
            }
            Err(e) => Err(format!("download published stats: {e}")),
        }
    }

    fn lookup_names(&self, api: &Api, stats: &mut Stats) {
        stats.forget_missing_names(NAME_NAMESPACES.len() as u32);
        let todo = stats.unnamed();
        let mut done = 0;
        let started = std::time::Instant::now();
        for item in todo.into_iter().take(NAME_LOOKUPS_PER_RUN) {
            // Leave time to save the run well inside the job's 20-minute limit.
            if started.elapsed() > NAME_LOOKUP_TIME {
                println!("name lookups stopped: time is up");
                break;
            }
            match api.item_name(item) {
                Ok(name) => {
                    stats.names.insert(item, name);
                    done += 1;
                }
                Err(e) => {
                    println!("name lookups stopped: {e}");
                    break;
                }
            }
        }
        println!(
            "names looked up={done} still unnamed={}",
            stats.unnamed().len()
        );
    }
}

fn check_version(s: Stats) -> Res<Stats> {
    if s.version != bah_core::stats::VERSION {
        return Err(format!(
            "stats version {} but this build reads {}",
            s.version,
            bah_core::stats::VERSION
        ));
    }
    Ok(s)
}

struct Api {
    agent: ureq::Agent,
    host: String,
    region: String,
    token: String,
}

struct Fetched {
    body: Value,
    modified: Option<i64>,
}

impl Api {
    fn connect(region: &str) -> Res<Api> {
        let id = env::var("BLIZZARD_CLIENT_ID").unwrap_or_default();
        let secret = env::var("BLIZZARD_CLIENT_SECRET").unwrap_or_default();
        if id.is_empty() || secret.is_empty() {
            return Err("BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET must both be set".into());
        }
        let basic = base64::engine::general_purpose::STANDARD.encode(format!("{id}:{secret}"));
        let agent = agent();
        let resp = agent
            .post(&env_or(
                "BLIZZARD_OAUTH_URL",
                "https://oauth.battle.net/token",
            ))
            .set("Authorization", &format!("Basic {basic}"))
            .send_form(&[("grant_type", "client_credentials")])
            .map_err(|e| format!("token request failed: {}", status_only(&e)))?;
        let v: Value = resp
            .into_json()
            .map_err(|e| format!("token response: {e}"))?;
        let token = v
            .get("access_token")
            .and_then(Value::as_str)
            .ok_or("token response has no access_token")?
            .to_string();
        Ok(Api {
            agent,
            // The two overrides exist for local tests against a fake server.
            host: env_or(
                "BLIZZARD_API_HOST",
                &format!("https://{region}.api.blizzard.com"),
            ),
            region: region.to_string(),
            token,
        })
    }

    fn get(&self, path: &str, namespace: &str) -> Result<ureq::Response, Box<ureq::Error>> {
        self.agent
            .get(&format!("{}{path}", self.host))
            .set("Authorization", &format!("Bearer {}", self.token))
            .set("Battlenet-Namespace", namespace)
            .call()
            .map_err(Box::new)
    }

    fn dynamic(&self, path: &str) -> Res<Fetched> {
        let resp = self
            .get(path, &format!("dynamic-forever-{}", self.region))
            .map_err(|e| format!("GET {path}: {}", status_only(&e)))?;
        let modified = resp
            .header("Last-Modified")
            .and_then(|h| httpdate::parse_http_date(h).ok())
            .map(system_to_unix);
        println!(
            "fetched path={path} last_modified=\"{}\"",
            resp.header("Last-Modified").unwrap_or("none")
        );
        let body: Value = serde_json::from_reader(resp.into_reader())
            .map_err(|e| format!("parse {path}: {e}"))?;
        Ok(Fetched { body, modified })
    }

    /// The item's name, `None` if no static namespace in `NAME_NAMESPACES` has it (404).
    fn item_name(&self, item: u32) -> Res<Option<String>> {
        let path = format!("/data/wow/item/{item}?locale=en_GB");
        for ns in NAME_NAMESPACES {
            match self.get(&path, &format!("{ns}-{}", self.region)) {
                Ok(resp) => {
                    // An unreadable entry is treated like a missing one, so one bad item
                    // can't stop every later lookup.
                    let v: Option<Value> = resp.into_json().ok();
                    if let Some(name) = v.as_ref().and_then(|v| v.get("name")?.as_str()) {
                        return Ok(Some(name.to_string()));
                    }
                }
                Err(e) if matches!(*e, ureq::Error::Status(404, _)) => {}
                Err(e) => return Err(format!("item {item}: {}", status_only(&e))),
            }
        }
        Ok(None)
    }
}

/// An error without the request URL or headers, so nothing secret reaches the log.
fn status_only(e: &ureq::Error) -> String {
    match e {
        ureq::Error::Status(code, _) => format!("HTTP {code}"),
        ureq::Error::Transport(t) => format!("transport error ({:?})", t.kind()),
    }
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(10))
        .timeout(Duration::from_secs(120))
        .build()
}

fn env_or(key: &str, default: &str) -> String {
    env::var(key)
        .ok()
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| default.to_string())
}

fn set_output(key: &str, value: &str) {
    if let Ok(path) = env::var("GITHUB_OUTPUT") {
        if let Ok(mut f) = fs::OpenOptions::new().append(true).create(true).open(path) {
            let _ = writeln!(f, "{key}={value}");
        }
    }
}

fn read_gz_json<T: serde::de::DeserializeOwned>(path: &Path) -> Res<Option<T>> {
    match fs::File::open(path) {
        Ok(f) => serde_json::from_reader(GzDecoder::new(f))
            .map(Some)
            .map_err(|e| format!("parse {}: {e}", path.display())),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(format!("open {}: {e}", path.display())),
    }
}

fn write_gz_json<T: serde::Serialize>(path: &Path, value: &T) -> Res<()> {
    let tmp = path.with_extension("tmp");
    let f = fs::File::create(&tmp).map_err(|e| format!("create {}: {e}", tmp.display()))?;
    let mut gz = GzEncoder::new(f, Compression::default());
    serde_json::to_writer(&mut gz, value).map_err(|e| format!("write {}: {e}", tmp.display()))?;
    gz.finish()
        .map_err(|e| format!("finish {}: {e}", tmp.display()))?;
    fs::rename(&tmp, path).map_err(|e| format!("rename {}: {e}", path.display()))
}

fn unix_to_system(t: i64) -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_secs(u64::try_from(t).unwrap_or(0))
}

fn system_to_unix(t: SystemTime) -> i64 {
    t.duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| i64::try_from(d.as_secs()).unwrap_or(i64::MAX))
        .unwrap_or(0)
}

/// The sell times page (#219). It only shows the published JSON; all numbers come from `core`.
const INDEX_HTML: &str = include_str!("../site/index.html");
