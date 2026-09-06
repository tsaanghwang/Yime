//! Process-bound maintenance stop protocol for the Rime/PIME product.
//!
//! This channel is deliberately separate from the historical shared quit event.
//! A request is accepted only by the selected worker process, for the same
//! installed root, user SID, watchdog/worker PIDs and process start identities.

use crate::acl::PipeSecurityAttributes;
use crate::client_identity::{inspect_named_pipe_client, ClientTrust};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::ffi::c_void;
use std::path::PathBuf;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::windows::named_pipe::{PipeMode, ServerOptions};
use windows::core::PWSTR;
use windows::Win32::Foundation::{CloseHandle, LocalFree, FILETIME, HANDLE, HLOCAL};
use windows::Win32::Security::Authorization::ConvertSidToStringSidW;
use windows::Win32::Security::{GetTokenInformation, TokenUser, TOKEN_QUERY, TOKEN_USER};
use windows::Win32::System::Threading::{
    GetCurrentProcess, GetProcessTimes, OpenProcess, OpenProcessToken,
    PROCESS_QUERY_LIMITED_INFORMATION,
};

pub const DIRECTED_MAINTENANCE_EXIT_CODE: i32 = 73;
const REQUEST_SCHEMA: &str = "yime-rime-directed-stop-request-v1";
const ACK_SCHEMA: &str = "yime-rime-directed-stop-ack-v1";
const MAX_REQUEST_BYTES: usize = 32 * 1024;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ObservedProcess {
    pub path: String,
    pub pid: u32,
    pub start_utc: String,
    pub start_filetime_utc: String,
    pub owner_sid: String,
    pub parent_pid: u32,
    pub role: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct DirectedStopRequest {
    pub schema_version: String,
    pub request_id: String,
    pub install_root: String,
    pub target_user_sid: String,
    pub launcher_pid: u32,
    pub launcher_start_utc: String,
    pub launcher_start_filetime_utc: String,
    pub worker_pid: u32,
    pub worker_start_utc: String,
    pub worker_start_filetime_utc: String,
    pub observation_sha256: String,
    pub observed_processes: Vec<ObservedProcess>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct DirectedStopAck {
    pub schema_version: String,
    pub request_id: String,
    pub accepted: bool,
    pub install_root: String,
    pub target_user_sid: String,
    pub launcher_pid: u32,
    pub launcher_start_utc: String,
    pub launcher_start_filetime_utc: String,
    pub worker_pid: u32,
    pub worker_start_utc: String,
    pub worker_start_filetime_utc: String,
    pub observation_sha256: String,
    pub watchdog_restart_suppressed: bool,
}

#[derive(Clone, Debug)]
pub struct MaintenanceIdentity {
    pub install_root: PathBuf,
    pub user_sid: String,
    pub watchdog_pid: u32,
    pub watchdog_start_filetime_utc: String,
    pub worker_pid: u32,
    pub worker_start_filetime_utc: String,
}

impl DirectedStopRequest {
    fn acknowledgement(&self) -> DirectedStopAck {
        DirectedStopAck {
            schema_version: ACK_SCHEMA.to_string(),
            request_id: self.request_id.clone(),
            accepted: true,
            install_root: self.install_root.clone(),
            target_user_sid: self.target_user_sid.clone(),
            launcher_pid: self.launcher_pid,
            launcher_start_utc: self.launcher_start_utc.clone(),
            launcher_start_filetime_utc: self.launcher_start_filetime_utc.clone(),
            worker_pid: self.worker_pid,
            worker_start_utc: self.worker_start_utc.clone(),
            worker_start_filetime_utc: self.worker_start_filetime_utc.clone(),
            observation_sha256: self.observation_sha256.clone(),
            watchdog_restart_suppressed: true,
        }
    }
}

fn normalized_path(path: &str) -> String {
    path.replace('/', "\\")
        .trim_end_matches('\\')
        .to_lowercase()
}

fn is_lower_hex(value: &str, length: usize) -> bool {
    value.len() == length
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn is_decimal(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit())
}

pub fn pipe_name(worker_pid: u32) -> String {
    format!(r"\\.\pipe\PIME\Maintenance\{worker_pid}")
}

pub fn validate_request(
    request: &DirectedStopRequest,
    identity: &MaintenanceIdentity,
) -> Result<(), String> {
    if request.schema_version != REQUEST_SCHEMA {
        return Err("unsupported maintenance request schema".to_string());
    }
    if !is_lower_hex(&request.request_id, 32) || !is_lower_hex(&request.observation_sha256, 64) {
        return Err("invalid maintenance correlation identity".to_string());
    }
    if normalized_path(&request.install_root)
        != normalized_path(&identity.install_root.to_string_lossy())
        || request.target_user_sid != identity.user_sid
        || request.launcher_pid != identity.watchdog_pid
        || request.launcher_start_filetime_utc != identity.watchdog_start_filetime_utc
        || request.worker_pid != identity.worker_pid
        || request.worker_start_filetime_utc != identity.worker_start_filetime_utc
    {
        return Err(
            "maintenance request targets another root, SID or process instance".to_string(),
        );
    }
    if request.launcher_start_utc.is_empty()
        || request.worker_start_utc.is_empty()
        || !is_decimal(&request.launcher_start_filetime_utc)
        || !is_decimal(&request.worker_start_filetime_utc)
        || request.observed_processes.len() < 2
        || request.observed_processes.len() > 3
    {
        return Err("maintenance process observation is incomplete".to_string());
    }

    let expected_launcher = normalized_path(
        &identity
            .install_root
            .join("PIMELauncher.exe")
            .to_string_lossy(),
    );
    let expected_root = normalized_path(&identity.install_root.to_string_lossy());
    let expected_backend = normalized_path(
        &identity
            .install_root
            .join("go-backend")
            .join("server.exe")
            .to_string_lossy(),
    );
    let mut pids = HashSet::new();
    let mut watchdogs = 0;
    let mut workers = 0;
    for process in &request.observed_processes {
        let path = normalized_path(&process.path);
        if !pids.insert(process.pid)
            || process.pid == 0
            || process.owner_sid != identity.user_sid
            || process.start_utc.is_empty()
            || !is_decimal(&process.start_filetime_utc)
            || !(path == expected_root || path.starts_with(&(expected_root.clone() + "\\")))
        {
            return Err("maintenance process observation contains a foreign identity".to_string());
        }
        match process.role.as_str() {
            "watchdog" => {
                watchdogs += 1;
                if path != expected_launcher
                    || process.pid != identity.watchdog_pid
                    || process.start_utc != request.launcher_start_utc
                    || process.start_filetime_utc != identity.watchdog_start_filetime_utc
                {
                    return Err("watchdog observation does not match the live instance".to_string());
                }
            }
            "worker" => {
                workers += 1;
                if path != expected_launcher
                    || process.pid != identity.worker_pid
                    || process.parent_pid != identity.watchdog_pid
                    || process.start_utc != request.worker_start_utc
                    || process.start_filetime_utc != identity.worker_start_filetime_utc
                {
                    return Err("worker observation does not match the live instance".to_string());
                }
            }
            "backend" => {
                if path != expected_backend || process.parent_pid != identity.worker_pid {
                    return Err("backend observation is not the selected worker child".to_string());
                }
            }
            _ => return Err("unknown maintenance process role".to_string()),
        }
    }
    if watchdogs != 1 || workers != 1 {
        return Err("maintenance request must bind one watchdog and one worker".to_string());
    }
    Ok(())
}

pub fn current_process_start_filetime() -> Result<String, String> {
    let mut creation = FILETIME::default();
    let mut exit = FILETIME::default();
    let mut kernel = FILETIME::default();
    let mut user = FILETIME::default();
    unsafe {
        GetProcessTimes(
            GetCurrentProcess(),
            &mut creation,
            &mut exit,
            &mut kernel,
            &mut user,
        )
        .map_err(|error| format!("query current process start time: {error}"))?;
    }
    let value = ((creation.dwHighDateTime as u64) << 32) | creation.dwLowDateTime as u64;
    Ok(value.to_string())
}

fn sid_for_process(process_id: u32) -> Result<String, String> {
    let process = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, process_id) }
        .map_err(|error| format!("open maintenance client process: {error}"))?;
    let mut token = HANDLE::default();
    let token_result = unsafe { OpenProcessToken(process, TOKEN_QUERY, &mut token) };
    unsafe {
        let _ = CloseHandle(process);
    }
    token_result.map_err(|error| format!("open maintenance client token: {error}"))?;

    let result = (|| {
        let mut required = 0u32;
        unsafe {
            let _ = GetTokenInformation(token, TokenUser, None, 0, &mut required);
        }
        if required < std::mem::size_of::<TOKEN_USER>() as u32 {
            return Err("maintenance client token has no user SID".to_string());
        }
        let mut buffer = vec![0u8; required as usize];
        unsafe {
            GetTokenInformation(
                token,
                TokenUser,
                Some(buffer.as_mut_ptr() as *mut c_void),
                required,
                &mut required,
            )
            .map_err(|error| format!("read maintenance client SID: {error}"))?;
            let token_user = &*(buffer.as_ptr() as *const TOKEN_USER);
            let mut sid_text = PWSTR::null();
            ConvertSidToStringSidW(token_user.User.Sid, &mut sid_text)
                .map_err(|error| format!("format maintenance client SID: {error}"))?;
            let sid = sid_text
                .to_string()
                .map_err(|error| format!("decode maintenance client SID: {error}"));
            let _ = LocalFree(HLOCAL(sid_text.0 as _));
            sid
        }
    })();
    unsafe {
        let _ = CloseHandle(token);
    }
    result
}

pub fn current_user_sid() -> Result<String, String> {
    sid_for_process(std::process::id())
}

async fn read_request_line(
    server: &mut tokio::net::windows::named_pipe::NamedPipeServer,
) -> Result<String, String> {
    let mut bytes = Vec::new();
    let mut buffer = [0u8; 4096];
    loop {
        let count = server
            .read(&mut buffer)
            .await
            .map_err(|error| format!("read maintenance request: {error}"))?;
        if count == 0 {
            return Err("maintenance client disconnected before request".to_string());
        }
        bytes.extend_from_slice(&buffer[..count]);
        if bytes.len() > MAX_REQUEST_BYTES {
            return Err("maintenance request is oversized".to_string());
        }
        if let Some(newline) = bytes.iter().position(|byte| *byte == b'\n') {
            if bytes[newline + 1..]
                .iter()
                .any(|byte| !byte.is_ascii_whitespace())
            {
                return Err("maintenance channel accepts one request only".to_string());
            }
            bytes.truncate(newline);
            if bytes.last() == Some(&b'\r') {
                bytes.pop();
            }
            return String::from_utf8(bytes)
                .map_err(|_| "maintenance request is not UTF-8".to_string());
        }
    }
}

pub async fn wait_for_directed_stop(
    identity: &MaintenanceIdentity,
) -> Result<DirectedStopRequest, String> {
    let security = PipeSecurityAttributes::new()
        .ok_or_else(|| "create maintenance pipe security descriptor".to_string())?;
    let pipe = pipe_name(identity.worker_pid);
    let mut first_instance = true;
    loop {
        let mut options = ServerOptions::new();
        options.first_pipe_instance(first_instance);
        options.max_instances(1);
        options.pipe_mode(PipeMode::Byte);
        let mut server = unsafe {
            options
                .create_with_security_attributes_raw(&pipe, &security.sa as *const _ as *mut c_void)
        }
        .map_err(|error| format!("create directed maintenance pipe: {error}"))?;
        first_instance = false;
        server
            .connect()
            .await
            .map_err(|error| format!("accept directed maintenance client: {error}"))?;

        let client = inspect_named_pipe_client(&server);
        if client.trust != ClientTrust::Desktop || client.process_id == 0 {
            continue;
        }
        let client_sid = match sid_for_process(client.process_id) {
            Ok(sid) => sid,
            Err(_) => continue,
        };
        if client_sid != identity.user_sid {
            continue;
        }
        let line = match tokio::time::timeout(
            Duration::from_secs(3),
            read_request_line(&mut server),
        )
        .await
        {
            Ok(Ok(line)) => line,
            _ => continue,
        };
        let request: DirectedStopRequest = match serde_json::from_str(&line) {
            Ok(request) => request,
            Err(_) => continue,
        };
        if validate_request(&request, identity).is_err() {
            continue;
        }
        let mut acknowledgement = serde_json::to_vec(&request.acknowledgement())
            .map_err(|error| format!("serialize maintenance acknowledgement: {error}"))?;
        acknowledgement.push(b'\n');
        tokio::time::timeout(Duration::from_secs(3), async {
            server.write_all(&acknowledgement).await?;
            server.flush().await
        })
        .await
        .map_err(|_| "write maintenance acknowledgement timed out".to_string())?
        .map_err(|error| format!("write maintenance acknowledgement: {error}"))?;
        return Ok(request);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::AsyncBufReadExt;
    use tokio::net::windows::named_pipe::ClientOptions;

    fn fixture() -> (DirectedStopRequest, MaintenanceIdentity) {
        let root = std::path::Path::new(r"C:\Program Files (x86)\YIME").to_path_buf();
        let sid = "S-1-5-21-100-200-300-1001".to_string();
        let processes = vec![
            ObservedProcess {
                path: root.join("PIMELauncher.exe").to_string_lossy().into_owned(),
                pid: 101,
                start_utc: "2026-09-05T12:00:00.0000000Z".to_string(),
                start_filetime_utc: "134016336000000000".to_string(),
                owner_sid: sid.clone(),
                parent_pid: 50,
                role: "watchdog".to_string(),
            },
            ObservedProcess {
                path: root.join("PIMELauncher.exe").to_string_lossy().into_owned(),
                pid: 102,
                start_utc: "2026-09-05T12:00:01.0000000Z".to_string(),
                start_filetime_utc: "134016336010000000".to_string(),
                owner_sid: sid.clone(),
                parent_pid: 101,
                role: "worker".to_string(),
            },
        ];
        let request = DirectedStopRequest {
            schema_version: REQUEST_SCHEMA.to_string(),
            request_id: "0123456789abcdef0123456789abcdef".to_string(),
            install_root: root.to_string_lossy().into_owned(),
            target_user_sid: sid.clone(),
            launcher_pid: 101,
            launcher_start_utc: processes[0].start_utc.clone(),
            launcher_start_filetime_utc: processes[0].start_filetime_utc.clone(),
            worker_pid: 102,
            worker_start_utc: processes[1].start_utc.clone(),
            worker_start_filetime_utc: processes[1].start_filetime_utc.clone(),
            observation_sha256: "a".repeat(64),
            observed_processes: processes,
        };
        let identity = MaintenanceIdentity {
            install_root: root,
            user_sid: sid,
            watchdog_pid: 101,
            watchdog_start_filetime_utc: "134016336000000000".to_string(),
            worker_pid: 102,
            worker_start_filetime_utc: "134016336010000000".to_string(),
        };
        (request, identity)
    }

    #[test]
    fn exact_process_bound_request_is_accepted_and_acknowledged() {
        let (request, identity) = fixture();
        validate_request(&request, &identity).expect("valid request");
        let ack = request.acknowledgement();
        assert!(ack.accepted && ack.watchdog_restart_suppressed);
        assert_eq!(ack.request_id, request.request_id);
        assert_eq!(ack.observation_sha256, request.observation_sha256);
    }

    #[test]
    fn every_root_sid_pid_start_binding_is_fail_closed() {
        type Mutation = Box<dyn Fn(&mut DirectedStopRequest)>;
        let mutations: Vec<Mutation> = vec![
            Box::new(|r| r.install_root = r"C:\other\YIME".to_string()),
            Box::new(|r| r.target_user_sid.push('9')),
            Box::new(|r| r.launcher_pid += 1),
            Box::new(|r| r.launcher_start_filetime_utc.push('1')),
            Box::new(|r| r.worker_pid += 1),
            Box::new(|r| r.worker_start_filetime_utc.push('1')),
            Box::new(|r| r.observed_processes[0].owner_sid.push('9')),
            Box::new(|r| r.observed_processes[1].parent_pid += 1),
            Box::new(|r| r.observed_processes[1].path = r"C:\other\PIMELauncher.exe".to_string()),
        ];
        for mutate in mutations {
            let (mut request, identity) = fixture();
            mutate(&mut request);
            assert!(validate_request(&request, &identity).is_err());
        }
    }

    #[test]
    fn unknown_json_fields_and_duplicate_processes_are_rejected() {
        let (mut request, identity) = fixture();
        request.observed_processes[1].pid = request.observed_processes[0].pid;
        assert!(validate_request(&request, &identity).is_err());

        let mut value = serde_json::to_value(fixture().0).expect("request JSON");
        value["unexpected"] = serde_json::json!(true);
        assert!(serde_json::from_value::<DirectedStopRequest>(value).is_err());
    }

    #[test]
    fn maintenance_pipe_is_worker_process_specific() {
        assert_eq!(pipe_name(1234), r"\\.\pipe\PIME\Maintenance\1234");
        assert_ne!(pipe_name(1234), pipe_name(1235));
    }

    #[tokio::test]
    async fn synthetic_pipe_round_trip_returns_exact_ack() {
        let (mut request, mut identity) = fixture();
        identity.user_sid = current_user_sid().expect("current test SID");
        identity.worker_pid = std::process::id();
        identity.watchdog_pid = identity.worker_pid.saturating_add(1);
        request.target_user_sid = identity.user_sid.clone();
        request.worker_pid = identity.worker_pid;
        request.launcher_pid = identity.watchdog_pid;
        request.observed_processes[0].pid = identity.watchdog_pid;
        request.observed_processes[0].owner_sid = identity.user_sid.clone();
        request.observed_processes[1].pid = identity.worker_pid;
        request.observed_processes[1].parent_pid = identity.watchdog_pid;
        request.observed_processes[1].owner_sid = identity.user_sid.clone();

        let server_identity = identity.clone();
        let server = tokio::spawn(async move { wait_for_directed_stop(&server_identity).await });
        let pipe = pipe_name(identity.worker_pid);
        let mut client = None;
        for _ in 0..20 {
            match ClientOptions::new().pipe_mode(PipeMode::Byte).open(&pipe) {
                Ok(opened) => {
                    client = Some(opened);
                    break;
                }
                Err(_) => tokio::time::sleep(Duration::from_millis(25)).await,
            }
        }
        let client = client.expect("connect synthetic maintenance pipe");
        let (reader, mut writer) = tokio::io::split(client);
        let mut payload = serde_json::to_vec(&request).expect("request JSON");
        payload.push(b'\n');
        writer.write_all(&payload).await.expect("write request");
        writer.flush().await.expect("flush request");
        let mut lines = tokio::io::BufReader::new(reader).lines();
        let line = tokio::time::timeout(Duration::from_secs(3), lines.next_line())
            .await
            .expect("ack timeout")
            .expect("ack read")
            .expect("ack EOF");
        let acknowledgement: DirectedStopAck =
            serde_json::from_str(&line).expect("acknowledgement JSON");
        assert_eq!(acknowledgement, request.acknowledgement());
        let accepted = server.await.expect("server task").expect("server result");
        assert_eq!(accepted.request_id, request.request_id);
    }
}
