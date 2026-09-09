#![windows_subsystem = "windows"]

use pimelauncher::backend_manager::BackendManager;
use pimelauncher::backend_registry::BackendRegistry;
use pimelauncher::maintenance::{self, MaintenanceIdentity, DIRECTED_MAINTENANCE_EXIT_CODE};
use pimelauncher::pipe_server;
use std::path::PathBuf;
use tracing::{error, info, warn};

/// Spawns and monitors the worker process, restarting it if it exits.
async fn run_watchdog(original_args: &[String]) {
    let exe = std::env::current_exe().expect("Failed to get current exe");
    let watchdog_pid = std::process::id();
    let watchdog_start = maintenance::current_process_start_filetime()
        .expect("Failed to bind watchdog process start identity");

    // Strip internal lifecycle arguments before adding the identities owned by
    // this watchdog. A caller cannot choose the worker's parent binding.
    let mut worker_args = sanitized_worker_args(original_args);
    worker_args.push("/worker".to_string());
    worker_args.push("/watchdog-pid".to_string());
    worker_args.push(watchdog_pid.to_string());
    worker_args.push("/watchdog-start-filetime-utc".to_string());
    worker_args.push(watchdog_start);

    info!("Watchdog started. Monitoring worker...");

    const CREATE_NEW_CONSOLE: u32 = 0x00000010;

    loop {
        info!("Spawning worker process...");
        let mut command = tokio::process::Command::new(&exe);
        command.args(&worker_args);

        // If /console was requested, spawn the worker in its own new console window
        if original_args.iter().any(|arg| arg == "/console") {
            command.creation_flags(CREATE_NEW_CONSOLE);
        } else {
            // In background mode, we MUST detach I/O. If we inherit invalid handles
            // (e.g. when running as a service), logging to stdout/stderr can block the process.
            command.stdout(std::process::Stdio::null());
            command.stderr(std::process::Stdio::null());
            command.stdin(std::process::Stdio::null());
        }

        let mut child = match command.spawn() {
            Ok(c) => c,
            Err(e) => {
                error!("Failed to spawn worker process: {}. Retrying in 5s...", e);
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                continue;
            }
        };

        tokio::select! {
            status = child.wait() => {
                if matches!(status, Ok(ref status) if status.code() == Some(DIRECTED_MAINTENANCE_EXIT_CODE)) {
                    info!("Worker completed identity-bound maintenance shutdown; watchdog restart is suppressed.");
                    return;
                }
                warn!("Worker process exited with status: {:?}. Restarting in 1s...", status);
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            }
            _ = wait_for_quit_event() => {
                info!("Quit event received. Terminating worker and watchdog...");
                let _ = child.kill().await;
                return;
            }
        }
    }
}

/// Signals the named quit event to notify all running instances to exit.
fn signal_quit_event() {
    use windows::core::w;
    use windows::Win32::Foundation::CloseHandle;
    use windows::Win32::System::Threading::{CreateEventW, SetEvent};

    unsafe {
        // Create or open the event
        if let Ok(handle) = CreateEventW(None, true, false, w!("PIMELauncher2_QuitEvent")) {
            let _ = SetEvent(handle);
            let _ = CloseHandle(handle);
            println!("Quit signal sent.");
        }
    }
}

fn sanitized_worker_args(original_args: &[String]) -> Vec<String> {
    let mut result = Vec::new();
    let mut index = 1;
    while index < original_args.len() {
        match original_args[index].as_str() {
            "/worker" => index += 1,
            "/watchdog-pid" | "/watchdog-start-filetime-utc" => index += 2,
            _ => {
                result.push(original_args[index].clone());
                index += 1;
            }
        }
    }
    result
}

fn argument_value<'a>(args: &'a [String], name: &str) -> Option<&'a str> {
    args.windows(2)
        .find(|pair| pair[0].eq_ignore_ascii_case(name))
        .map(|pair| pair[1].as_str())
}

/// Clears any stale quit signal left by a previous `/quit` invocation.
fn reset_quit_event() {
    use windows::core::w;
    use windows::Win32::Foundation::CloseHandle;
    use windows::Win32::System::Threading::{CreateEventW, ResetEvent};

    unsafe {
        if let Ok(handle) = CreateEventW(None, true, false, w!("PIMELauncher2_QuitEvent")) {
            let _ = ResetEvent(handle);
            let _ = CloseHandle(handle);
        }
    }
}

/// Waits asynchronously for the named quit event to be signaled.
async fn wait_for_quit_event() {
    use windows::core::w;
    use windows::Win32::Foundation::CloseHandle;
    use windows::Win32::System::Threading::{CreateEventW, WaitForSingleObject, INFINITE};

    // We use a dedicated thread to wait because WaitForSingleObject is blocking.
    tokio::task::spawn_blocking(move || {
        unsafe {
            // Create or open the event (manual reset = true)
            if let Ok(handle) = CreateEventW(None, true, false, w!("PIMELauncher2_QuitEvent")) {
                let _ = WaitForSingleObject(handle, INFINITE);
                let _ = CloseHandle(handle);
            }
        }
    })
    .await
    .ok();
}

#[tokio::main]
async fn main() {
    setup_error_mode();

    // Candidate builds require their installed, SID-bound state configuration
    // on every entry path, including TSF auto-launch and watchdog restart.
    #[cfg(feature = "dp1-candidate")]
    if let Err(error) = pimelauncher::candidate_state::apply() {
        eprintln!("Candidate state configuration rejected: {error}");
        std::process::exit(2);
    }

    let args: Vec<String> = std::env::args().collect();
    let is_worker = args.iter().any(|arg| arg == "/worker");
    let show_console = args.iter().any(|arg| arg == "/console");
    let is_quit = args.iter().any(|arg| arg == "/quit");

    if is_quit {
        signal_quit_event();
        return;
    }

    if show_console {
        setup_console();
        tracing_subscriber::fmt().with_ansi(true).init();
    } else {
        // In background mode, we MUST use a sink for tracing.
        // Writing to a non-existent stdout in a GUI subsystem app can cause hangs.
        tracing_subscriber::fmt()
            .with_ansi(false)
            .with_writer(std::io::sink)
            .init();
    }

    // Ensure single instance (using a named mutex)
    // The Watchdog process (parent) holds this mutex.
    let _mutex = if !is_worker {
        match create_single_instance_mutex("PIMELauncher2_WatchdogMutex") {
            Ok(m) => Some(m),
            Err(_) => {
                error!("Another instance of PIMELauncher2 Watchdog is already running.");
                std::process::exit(1);
            }
        }
    } else {
        None
    };

    if !is_worker {
        reset_quit_event();
        run_watchdog(&args).await;
    } else {
        match run_worker(&args).await {
            Ok(true) => std::process::exit(DIRECTED_MAINTENANCE_EXIT_CODE),
            Ok(false) => {}
            Err(error) => {
                error!("Worker failed: {}", error);
                std::process::exit(1);
            }
        }
    }
}

/// Disables Windows error reporting dialogs to prevent blocking background processes.
fn setup_error_mode() {
    use windows::Win32::System::Diagnostics::Debug::{
        SetErrorMode, SEM_FAILCRITICALERRORS, SEM_NOALIGNMENTFAULTEXCEPT, SEM_NOGPFAULTERRORBOX,
        SEM_NOOPENFILEERRORBOX,
    };
    unsafe {
        SetErrorMode(
            SEM_FAILCRITICALERRORS
                | SEM_NOGPFAULTERRORBOX
                | SEM_NOALIGNMENTFAULTEXCEPT
                | SEM_NOOPENFILEERRORBOX,
        );
    }
}

/// Core logic for the PIME Worker process.
async fn run_worker(args: &[String]) -> Result<bool, String> {
    let username = std::env::var("USERNAME").expect("USERNAME environment variable must be set");
    let pipe_name = format!(r"\\.\pipe\{}\PIME\Launcher", username);

    info!("Starting PIMELauncher2 Worker on pipe: {}", pipe_name);

    let pime_root = resolve_pime_root_dir();
    info!("Using PIME root directory: {:?}", pime_root);

    let registry = BackendRegistry::load(&pime_root);
    print_diagnostics(&registry);

    let backend_manager = BackendManager::new(registry);
    let server = pipe_server::PipeServer::new(pipe_name, backend_manager.clone());
    let watchdog_pid = argument_value(args, "/watchdog-pid")
        .ok_or_else(|| "worker is missing watchdog PID binding".to_string())?
        .parse::<u32>()
        .map_err(|_| "worker watchdog PID binding is invalid".to_string())?;
    let watchdog_start_filetime_utc = argument_value(args, "/watchdog-start-filetime-utc")
        .filter(|value| !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit()))
        .ok_or_else(|| "worker is missing watchdog start identity".to_string())?
        .to_string();
    let identity = MaintenanceIdentity {
        install_root: pime_root,
        user_sid: maintenance::current_user_sid()?,
        watchdog_pid,
        watchdog_start_filetime_utc,
        worker_pid: std::process::id(),
        worker_start_filetime_utc: maintenance::current_process_start_filetime()?,
    };

    match tokio::select! {
        _ = server.run() => return Ok(false),
        request = maintenance::wait_for_directed_stop(&identity) => request,
    } {
        Ok(request) => {
            info!(
                "Accepted directed maintenance request {} for this exact worker.",
                request.request_id
            );
            backend_manager.shutdown_gracefully().await?;
            info!("Backend exited from EOF; worker will use the maintenance exit code.");
            Ok(true)
        }
        Err(error) => {
            // Failure to create the optional maintenance channel must not stop
            // input service. It only keeps automatic maintenance fail-closed.
            error!("Directed maintenance channel unavailable: {}", error);
            server.run().await;
            Ok(false)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn internal_worker_identity_arguments_cannot_be_injected() {
        let args = vec![
            "PIMELauncher.exe".to_string(),
            "/console".to_string(),
            "/worker".to_string(),
            "/watchdog-pid".to_string(),
            "999".to_string(),
            "/watchdog-start-filetime-utc".to_string(),
            "888".to_string(),
        ];
        assert_eq!(sanitized_worker_args(&args), vec!["/console"]);
    }

    #[test]
    fn argument_value_requires_a_following_value() {
        let args = vec!["PIMELauncher.exe".to_string(), "/watchdog-pid".to_string()];
        assert_eq!(argument_value(&args, "/watchdog-pid"), None);
    }
}

/// Prints available backends and GUID mappings for debugging.
fn print_diagnostics(registry: &BackendRegistry) {
    info!("Available Backends:");
    for (name, config) in &registry.backends {
        info!("  - {}:", name);
        info!("      Command: {}", config.command);
        info!("      Params:  {}", config.params);
        info!("      CWD:     {}", config.working_dir);
    }

    info!("GUID Mappings:");
    for (guid, backend) in &registry.guid_to_backend {
        info!("  {} -> {}", guid, backend);
    }
}

/// Resolves the PIME root directory.
fn resolve_pime_root_dir() -> PathBuf {
    let exe_path = std::env::current_exe().unwrap_or_default();
    let pime_root = exe_path
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));

    info!("Executable path: {:?}", exe_path);
    info!("Resolved PIME root: {:?}", pime_root);

    pime_root
}

/// Creates a named mutex to ensure only one instance of the launcher is running.
fn create_single_instance_mutex(
    name: &str,
) -> Result<windows::Win32::Foundation::HANDLE, std::io::Error> {
    use windows::core::PCWSTR;
    use windows::Win32::Foundation::{CloseHandle, GetLastError, ERROR_ALREADY_EXISTS};
    use windows::Win32::System::Threading::CreateMutexW;

    let mut name_utf16: Vec<u16> = name.encode_utf16().collect();
    name_utf16.push(0);

    unsafe {
        match CreateMutexW(None, false, PCWSTR(name_utf16.as_ptr())) {
            Ok(handle) => {
                if let Err(e) = GetLastError() {
                    if e.code() == windows::core::HRESULT::from_win32(ERROR_ALREADY_EXISTS.0) {
                        let _ = CloseHandle(handle);
                        return Err(std::io::Error::from_raw_os_error(
                            ERROR_ALREADY_EXISTS.0 as i32,
                        ));
                    }
                }
                Ok(handle)
            }
            Err(e) => Err(std::io::Error::new(
                std::io::ErrorKind::Other,
                e.to_string(),
            )),
        }
    }
}

/// Allocates a console window and enables ANSI color support.
fn setup_console() {
    use windows::Win32::System::Console::{
        AllocConsole, AttachConsole, GetConsoleMode, GetStdHandle, SetConsoleMode,
        ATTACH_PARENT_PROCESS, ENABLE_VIRTUAL_TERMINAL_PROCESSING, STD_ERROR_HANDLE,
        STD_OUTPUT_HANDLE,
    };
    unsafe {
        // Try to allocate a new console window first (as requested for separate windows)
        if AllocConsole().is_err() {
            // If AllocConsole fails (e.g. already has one), try attaching to parent as fallback
            if AttachConsole(ATTACH_PARENT_PROCESS).is_err() {
                return;
            }
        }

        // Enable ANSI support for both stdout and stderr
        for handle_type in [STD_OUTPUT_HANDLE, STD_ERROR_HANDLE] {
            if let Ok(handle) = GetStdHandle(handle_type) {
                let mut mode = Default::default();
                if GetConsoleMode(handle, &mut mode).is_ok() {
                    mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
                    let _ = SetConsoleMode(handle, mode);
                }
            }
        }
    }
}
