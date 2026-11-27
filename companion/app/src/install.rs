//! `install` / `uninstall`: a Windows Task Scheduler task that runs `sync` hourly and at
//! logon (#220). The task runs the windowless `better-ah-companion-task` binary, so no console
//! window pops up every hour.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::sync::{check_target, Res};

pub const TASK_NAME: &str = "Better AH sync";
pub const TASK_EXE: &str = "better-ah-companion-task.exe";

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// Quotes one command-line argument for Windows (CommandLineToArgvW rules).
fn quote_arg(s: &str) -> String {
    let mut out = String::from("\"");
    let mut slashes = 0;
    for ch in s.chars() {
        match ch {
            '\\' => slashes += 1,
            '"' => {
                out.push_str(&"\\".repeat(slashes * 2 + 1));
                out.push('"');
                slashes = 0;
            }
            _ => {
                out.push_str(&"\\".repeat(slashes));
                out.push(ch);
                slashes = 0;
            }
        }
    }
    out.push_str(&"\\".repeat(slashes * 2));
    out.push('"');
    out
}

/// The task definition: hourly at :45 (the export lands around :22 and the site updates a few
/// minutes after the next collect run), plus a minute after logon, catching up on missed runs.
pub fn task_xml(user: &str, exe: &Path, url: &str, target: &Path) -> String {
    let args = format!(
        "sync --target {} --url {}",
        quote_arg(&target.display().to_string()),
        quote_arg(url)
    );
    format!(
        r#"<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Better AH: downloads the sell times data file into the BetterAH addon folder.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>{user}</UserId>
      <Delay>PT1M</Delay>
    </LogonTrigger>
    <TimeTrigger>
      <Repetition>
        <Interval>PT1H</Interval>
      </Repetition>
      <StartBoundary>2026-01-01T00:45:00</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>{user}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>{exe}</Command>
      <Arguments>{args}</Arguments>
    </Exec>
  </Actions>
</Task>
"#,
        user = xml_escape(user),
        exe = xml_escape(&exe.display().to_string()),
        args = xml_escape(&args),
    )
}

/// UTF-16 LE with a byte order mark, the encoding schtasks reads task XML in.
pub fn utf16le(s: &str) -> Vec<u8> {
    let mut out = vec![0xFF, 0xFE];
    for unit in s.encode_utf16() {
        out.extend(unit.to_le_bytes());
    }
    out
}

/// Where `install` copies the binaries, so the task keeps working after the download is
/// deleted: `%LOCALAPPDATA%\better-ah-companion`.
pub fn install_dir() -> Res<PathBuf> {
    std::env::var_os("LOCALAPPDATA")
        .map(|d| PathBuf::from(d).join("better-ah-companion"))
        .ok_or_else(|| "install only works on Windows (LOCALAPPDATA is not set)".into())
}

fn schtasks(args: &[&str]) -> Res<()> {
    let out = Command::new("schtasks")
        .args(args)
        .output()
        .map_err(|e| format!("couldn't run schtasks (install only works on Windows): {e}"))?;
    if out.status.success() {
        Ok(())
    } else {
        Err(format!(
            "schtasks failed: {}{}",
            String::from_utf8_lossy(&out.stderr).trim(),
            String::from_utf8_lossy(&out.stdout).trim()
        ))
    }
}

pub fn install(url: &str, target: &Path) -> Res<()> {
    // The task runs from another folder, so a relative --target must become absolute.
    let target = &std::path::absolute(target).map_err(|e| format!("{}: {e}", target.display()))?;
    check_target(target)?;
    let dir = install_dir()?;
    fs::create_dir_all(&dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
    let here = std::env::current_exe().map_err(|e| format!("current exe: {e}"))?;
    let from = here.parent().ok_or("current exe has no folder")?;
    for name in ["better-ah-companion.exe", TASK_EXE] {
        let src = from.join(name);
        let dst = dir.join(name);
        // Re-running install from the install folder must not copy a running exe onto itself.
        if same_file(&src, &dst) {
            continue;
        }
        fs::copy(&src, &dst).map_err(|e| {
            format!(
                "copy {} to {}: {e} (if the task is running, wait a minute and try again)",
                src.display(),
                dst.display()
            )
        })?;
    }
    let user = match (std::env::var("USERDOMAIN"), std::env::var("USERNAME")) {
        (Ok(d), Ok(u)) => format!("{d}\\{u}"),
        (_, Ok(u)) => u,
        _ => return Err("USERNAME is not set".into()),
    };
    let xml_path = dir.join("task.xml");
    let xml = task_xml(&user, &dir.join(TASK_EXE), url, target);
    fs::write(&xml_path, utf16le(&xml))
        .map_err(|e| format!("write {}: {e}", xml_path.display()))?;
    let xml_arg = xml_path.display().to_string();
    schtasks(&["/Create", "/TN", TASK_NAME, "/XML", &xml_arg, "/F"])?;
    // Run once now so the file is there without waiting for the next hour.
    let _ = schtasks(&["/Run", "/TN", TASK_NAME]);
    Ok(())
}

fn same_file(a: &Path, b: &Path) -> bool {
    matches!((fs::canonicalize(a), fs::canonicalize(b)), (Ok(x), Ok(y)) if x == y)
}

pub fn uninstall() -> Res<()> {
    schtasks(&["/Delete", "/TN", TASK_NAME, "/F"])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn task_runs_sync_with_quoted_paths_hourly_and_at_logon() {
        let xml = task_xml(
            "PC\\chris",
            Path::new("C:\\Users\\chris\\AppData\\Local\\better-ah-companion\\better-ah-companion-task.exe"),
            "https://chsko.github.io/better-ah/SellTimes.lua",
            Path::new("C:\\Users\\chris\\better-ah\\BetterAH"),
        );
        assert!(xml.contains("<UserId>PC\\chris</UserId>"));
        assert!(xml.contains("<LogonTrigger>"));
        assert!(xml.contains("<Interval>PT1H</Interval>"));
        // triggerBaseType's element order: Repetition, StartBoundary, ..., Enabled.
        let t = &xml[xml.find("<TimeTrigger>").unwrap()..];
        assert!(t.find("<Repetition>") < t.find("<StartBoundary>"));
        assert!(t.find("<StartBoundary>") < t.find("<Enabled>"));
        assert!(xml.contains("<StartWhenAvailable>true</StartWhenAvailable>"));
        assert!(xml.contains(
            "<Arguments>sync --target &quot;C:\\Users\\chris\\better-ah\\BetterAH&quot; --url &quot;https://chsko.github.io/better-ah/SellTimes.lua&quot;</Arguments>"
        ));
    }

    #[test]
    fn escapes_xml_in_names_and_paths() {
        let xml = task_xml(
            "A&B\\x",
            Path::new("C:\\a<b>\\t.exe"),
            "u",
            Path::new("C:\\x"),
        );
        assert!(xml.contains("<UserId>A&amp;B\\x</UserId>"));
        assert!(xml.contains("<Command>C:\\a&lt;b&gt;\\t.exe</Command>"));
    }

    #[test]
    fn quotes_arguments_like_windows_parses_them() {
        assert_eq!(quote_arg("C:\\a b\\"), "\"C:\\a b\\\\\"");
        assert_eq!(quote_arg("x\"y"), "\"x\\\"y\"");
        assert_eq!(quote_arg("C:\\x\\y"), "\"C:\\x\\y\"");
    }

    #[test]
    fn writes_utf16_with_bom() {
        assert_eq!(utf16le("<a"), vec![0xFF, 0xFE, b'<', 0, b'a', 0]);
    }
}
