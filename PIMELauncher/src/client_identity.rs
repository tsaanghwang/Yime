use std::collections::HashMap;
use std::os::windows::io::AsRawHandle;
use std::sync::{Arc, Mutex};

use tokio::net::windows::named_pipe::NamedPipeServer;
use windows::Win32::Foundation::{CloseHandle, HANDLE};
use windows::Win32::Security::{
    GetSidSubAuthority, GetSidSubAuthorityCount, GetTokenInformation, TokenIntegrityLevel,
    TokenIsAppContainer, TOKEN_MANDATORY_LABEL, TOKEN_QUERY,
};
use windows::Win32::System::Pipes::GetNamedPipeClientProcessId;
use windows::Win32::System::SystemServices::SECURITY_MANDATORY_MEDIUM_RID;
use windows::Win32::System::Threading::{
    OpenProcess, OpenProcessToken, PROCESS_QUERY_LIMITED_INFORMATION,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ClientTrust {
    Restricted,
    Desktop,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ClientIdentity {
    pub process_id: u32,
    pub trust: ClientTrust,
}

impl ClientIdentity {
    pub fn restricted(process_id: u32) -> Self {
        Self {
            process_id,
            trust: ClientTrust::Restricted,
        }
    }

    pub fn trusted_for_tests() -> Self {
        Self {
            process_id: u32::MAX,
            trust: ClientTrust::Desktop,
        }
    }

    pub fn allows_sensitive_commands(self) -> bool {
        self.trust == ClientTrust::Desktop
    }

    pub fn trust_label(self) -> &'static str {
        match self.trust {
            ClientTrust::Restricted => "restricted",
            ClientTrust::Desktop => "desktop",
        }
    }
}

pub fn inspect_named_pipe_client(server: &NamedPipeServer) -> ClientIdentity {
    let pipe = HANDLE(server.as_raw_handle() as isize);
    let mut process_id = 0u32;
    if unsafe { GetNamedPipeClientProcessId(pipe, &mut process_id) }.is_err() || process_id == 0 {
        return ClientIdentity::restricted(0);
    }
    match inspect_process_trust(process_id) {
        Some(ClientTrust::Desktop) => ClientIdentity {
            process_id,
            trust: ClientTrust::Desktop,
        },
        _ => ClientIdentity::restricted(process_id),
    }
}

fn inspect_process_trust(process_id: u32) -> Option<ClientTrust> {
    let process =
        unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, process_id) }.ok()?;
    let mut token = HANDLE::default();
    let opened = unsafe { OpenProcessToken(process, TOKEN_QUERY, &mut token) }.is_ok();
    unsafe {
        let _ = CloseHandle(process);
    }
    if !opened {
        return None;
    }

    let result = inspect_token_trust(token);
    unsafe {
        let _ = CloseHandle(token);
    }
    result
}

fn inspect_token_trust(token: HANDLE) -> Option<ClientTrust> {
    let mut is_app_container = 0u32;
    let mut returned = 0u32;
    unsafe {
        GetTokenInformation(
            token,
            TokenIsAppContainer,
            Some(&mut is_app_container as *mut _ as *mut _),
            std::mem::size_of::<u32>() as u32,
            &mut returned,
        )
        .ok()?;
    }
    if is_app_container != 0 {
        return Some(ClientTrust::Restricted);
    }

    let mut required = 0u32;
    let _ = unsafe { GetTokenInformation(token, TokenIntegrityLevel, None, 0, &mut required) };
    if required < std::mem::size_of::<TOKEN_MANDATORY_LABEL>() as u32 {
        return None;
    }
    let mut buffer = vec![0u8; required as usize];
    unsafe {
        GetTokenInformation(
            token,
            TokenIntegrityLevel,
            Some(buffer.as_mut_ptr() as *mut _),
            required,
            &mut returned,
        )
        .ok()?;
        let label = &*(buffer.as_ptr() as *const TOKEN_MANDATORY_LABEL);
        let sid = label.Label.Sid;
        let count = *GetSidSubAuthorityCount(sid);
        if count == 0 {
            return None;
        }
        let integrity_rid = *GetSidSubAuthority(sid, (count - 1) as u32);
        if integrity_rid < SECURITY_MANDATORY_MEDIUM_RID as u32 {
            Some(ClientTrust::Restricted)
        } else {
            Some(ClientTrust::Desktop)
        }
    }
}

#[derive(Default)]
struct LimiterState {
    total: usize,
    by_process: HashMap<u32, usize>,
}

pub struct ConnectionLimiter {
    state: Mutex<LimiterState>,
    max_total: usize,
    max_per_process: usize,
}

impl ConnectionLimiter {
    pub fn new(max_total: usize, max_per_process: usize) -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(LimiterState::default()),
            max_total,
            max_per_process,
        })
    }

    pub fn try_acquire(self: &Arc<Self>, process_id: u32) -> Option<ConnectionPermit> {
        let mut state = self.state.lock().ok()?;
        let current = state.by_process.get(&process_id).copied().unwrap_or(0);
        if state.total >= self.max_total || current >= self.max_per_process {
            return None;
        }
        state.total += 1;
        state.by_process.insert(process_id, current + 1);
        Some(ConnectionPermit {
            limiter: self.clone(),
            process_id,
        })
    }
}

pub struct ConnectionPermit {
    limiter: Arc<ConnectionLimiter>,
    process_id: u32,
}

impl Drop for ConnectionPermit {
    fn drop(&mut self) {
        if let Ok(mut state) = self.limiter.state.lock() {
            state.total = state.total.saturating_sub(1);
            if let Some(current) = state.by_process.get_mut(&self.process_id) {
                *current = current.saturating_sub(1);
                if *current == 0 {
                    state.by_process.remove(&self.process_id);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn limiter_bounds_each_process_and_releases_capacity() {
        let limiter = ConnectionLimiter::new(3, 2);
        let first = limiter.try_acquire(10).expect("first permit");
        let second = limiter.try_acquire(10).expect("second permit");
        assert!(limiter.try_acquire(10).is_none());
        let other = limiter.try_acquire(20).expect("global third permit");
        assert!(limiter.try_acquire(30).is_none());
        drop(first);
        assert!(limiter.try_acquire(10).is_some());
        drop(second);
        drop(other);
    }
}
