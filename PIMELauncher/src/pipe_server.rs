use crate::acl::PipeSecurityAttributes;
use crate::backend_manager::BackendManager;
use crate::client_identity::{inspect_named_pipe_client, ClientIdentity, ConnectionLimiter};
use crate::client_session::ClientSession;
use crate::protocol::{self};
use futures::StreamExt; // For next() on FramedRead
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::windows::named_pipe::{PipeMode, ServerOptions};
use tokio_util::codec::{FramedRead, FramedWrite, LinesCodec};
use tracing::{error, info, warn};
use uuid::Uuid;

#[derive(Clone)]
pub struct PipeServer {
    pipe_name: String,
    manager: BackendManager,
    limiter: Arc<ConnectionLimiter>,
}

#[cfg(not(test))]
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(3);
#[cfg(test)]
const HANDSHAKE_TIMEOUT: Duration = Duration::from_millis(100);
const MAX_ACTIVE_CLIENTS: usize = 64;
const MAX_CONNECTIONS_PER_PROCESS: usize = 4;

impl PipeServer {
    pub fn new(pipe_name: String, manager: BackendManager) -> Self {
        Self {
            pipe_name,
            manager,
            limiter: ConnectionLimiter::new(MAX_ACTIVE_CLIENTS, MAX_CONNECTIONS_PER_PROCESS),
        }
    }

    /// Starts the named pipe server loop.
    ///
    /// This function creates the pipe instances, applies security attributes,
    /// and spawns a handler for each connected client.
    pub async fn run(&self) {
        let sa = PipeSecurityAttributes::new().expect("Failed to create PipeSecurityAttributes");
        let mut is_first_instance = true;

        loop {
            let mut options = ServerOptions::new();
            options.first_pipe_instance(is_first_instance);
            options.max_instances(254);
            options.pipe_mode(PipeMode::Byte);

            // Tokio 1.x allows creating with raw security attributes
            let server = match unsafe {
                options.create_with_security_attributes_raw(
                    &self.pipe_name,
                    &sa.sa as *const _ as *mut std::ffi::c_void,
                )
            } {
                Ok(server) => server,
                Err(e) => {
                    error!("Failed to create named pipe server: {}", e);
                    tokio::time::sleep(std::time::Duration::from_secs(1)).await;
                    continue;
                }
            };

            match server.connect().await {
                Ok(_) => {
                    let identity = inspect_named_pipe_client(&server);
                    let permit = match self.limiter.try_acquire(identity.process_id) {
                        Some(permit) => permit,
                        None => {
                            warn!(
                                "Rejecting pipe client pid={} because its connection quota is exhausted",
                                identity.process_id
                            );
                            continue;
                        }
                    };
                    info!(
                        "Client connection accepted on pipe instance (first_instance={}, pid={}, trust={}).",
                        is_first_instance,
                        identity.process_id,
                        identity.trust_label(),
                    );
                    is_first_instance = false;
                    let manager = self.manager.clone();
                    tokio::spawn(async move {
                        let _permit = permit;
                        let (reader, writer) = tokio::io::split(server);
                        Self::handle_client_with_identity(manager, reader, writer, identity).await;
                    });
                }
                Err(e) => {
                    error!("Failed to accept client connection: {}", e);
                    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                }
            }
        }
    }
    /// Generic implementation of the client handler to allow unit testing with mocked I/O.
    pub async fn handle_client<R, W>(manager: BackendManager, pipe_reader: R, pipe_writer: W)
    where
        R: AsyncRead + Unpin + Send + 'static,
        W: AsyncWrite + Unpin + Send + 'static,
    {
        Self::handle_client_with_identity(
            manager,
            pipe_reader,
            pipe_writer,
            ClientIdentity::trusted_for_tests(),
        )
        .await;
    }

    async fn handle_client_with_identity<R, W>(
        manager: BackendManager,
        pipe_reader: R,
        pipe_writer: W,
        identity: ClientIdentity,
    ) where
        R: AsyncRead + Unpin + Send + 'static,
        W: AsyncWrite + Unpin + Send + 'static,
    {
        let (mut client, backend_name) =
            match Self::accept_client(&manager, pipe_reader, pipe_writer, identity).await {
                Ok(v) => v,
                Err(e) => {
                    error!("Failed to accept client: {}", e);
                    return;
                }
            };

        // Run the session
        client.run().await;

        // Phase 3: Cleanup on disconnect
        info!(
            "Client disconnected: id={}, backend={}",
            client.id(),
            backend_name
        );
        manager.unregister_client(client.id(), &backend_name).await;
    }

    /// Performs the handshake and initializes the client session.
    async fn accept_client<R, W>(
        manager: &BackendManager,
        pipe_reader: R,
        pipe_writer: W,
        identity: ClientIdentity,
    ) -> Result<(ClientSession<R, W>, String), String>
    where
        R: AsyncRead + Unpin + Send + 'static,
        W: AsyncWrite + Unpin + Send + 'static,
    {
        let client_id = Uuid::new_v4().to_string();
        info!("Client connected: id={}", client_id);

        let mut line_reader = FramedRead::new(
            pipe_reader,
            LinesCodec::new_with_max_length(protocol::MAX_CLIENT_MESSAGE_LINE_LENGTH),
        );
        let line_writer = FramedWrite::new(
            pipe_writer,
            LinesCodec::new_with_max_length(protocol::MAX_CLIENT_MESSAGE_LINE_LENGTH),
        );

        // Phase 1: Wait for initial handshake
        let (input_method_guid, handshake_line) = tokio::time::timeout(HANDSHAKE_TIMEOUT, async {
            while let Some(result) = line_reader.next().await {
                match result {
                    Ok(line) if line.is_empty() => continue,
                    Ok(line) => {
                        return protocol::prepare_client_handshake(
                            &line,
                            identity.trust_label(),
                            identity.allows_sensitive_commands(),
                        )
                        .map_err(|e| format!("Handshake error from {}: {}", client_id, e));
                    }
                    Err(e) => {
                        return Err(format!("Error reading from client {}: {}", client_id, e));
                    }
                }
            }
            Err(format!(
                "Client disconnected before handshake: id={}",
                client_id
            ))
        })
        .await
        .map_err(|_| format!("Client handshake timed out: id={}", client_id))??;

        let backend_name = manager.resolve_backend(&input_method_guid).ok_or_else(|| {
            format!(
                "Backend not found for text service GUID: {} from {}",
                input_method_guid, client_id
            )
        })?;
        info!(
            "Client {} handshake successful, mapped to backend: {}, trust={}",
            client_id,
            backend_name,
            identity.trust_label(),
        );

        let backend_writer = match manager.get_backend_input(&backend_name).await {
            Some(tx) => tx,
            None => {
                return Err(format!(
                    "Failed to get backend input channel for {}",
                    backend_name
                ));
            }
        };
        let backend_reader = manager.register_client(client_id.clone()).await;

        // Phase 2: Construct the fully authenticated session and run it
        let session = ClientSession::new(
            client_id.clone(),
            line_reader,
            line_writer,
            backend_writer.clone(),
            backend_reader,
        );

        // Forward the handshake itself to the backend directly via channel
        let formatted_handshake = protocol::format_backend_input(&client_id, &handshake_line);
        if let Err(e) = backend_writer.send(formatted_handshake).await {
            return Err(format!("Failed to forward handshake to backend: {}", e));
        }

        Ok((session, backend_name))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend_registry::BackendRegistry;
    use tokio_test::io::Builder;

    #[tokio::test]
    async fn test_handle_client_fragmented() {
        // Setup manager with an empty registry and manually add test mapping
        let mut registry = BackendRegistry::new();
        registry.guid_to_backend.insert(
            crate::testing::GUID_TEST_ECHO.to_lowercase(),
            "echo".to_string(),
        );
        registry.backends.insert(
            "echo".to_string(),
            crate::backend_registry::BackendConfig {
                name: "echo".to_string(),
                command: "echo".to_string(),
                working_dir: "".to_string(),
                params: "".to_string(),
            },
        );
        let manager = BackendManager::new(registry);
        // Simulate a client sending data in multiple small chunks
        // 1. Handshake split: {"method": "init", "id": "{...}"}\n
        // 2. Data split: "Hello " + "World\nNext" + " Message\n"
        let handshake = format!(
            r#"{{"method": "init", "id": "{}"}}"#,
            crate::testing::GUID_TEST_ECHO
        );
        let h1 = &handshake[..handshake.len() / 2];
        let h2 = &handshake[handshake.len() / 2..];

        let reader = Builder::new()
            .read(h1.as_bytes())
            .read(format!("{}\n", h2).as_bytes())
            .read(b"Hello ")
            .read(b"World\nNext")
            .read(b" Message\n")
            .build();

        let writer = Builder::new().build();

        // Run the handler. It should process all lines and exit on EOF.
        let result = tokio::time::timeout(
            std::time::Duration::from_secs(2),
            PipeServer::handle_client(manager, reader, writer),
        )
        .await;

        assert!(result.is_ok(), "Handler hung or took too long");
    }

    #[tokio::test]
    async fn test_handle_client_utf8_split() {
        let mut registry = BackendRegistry::new();
        registry.guid_to_backend.insert(
            crate::testing::GUID_TEST_ECHO.to_lowercase(),
            "echo".to_string(),
        );
        registry.backends.insert(
            "echo".to_string(),
            crate::backend_registry::BackendConfig {
                name: "echo".to_string(),
                command: "echo".to_string(),
                working_dir: "".to_string(),
                params: "".to_string(),
            },
        );
        let manager = BackendManager::new(registry);
        // '中' is [0xE4, 0xB8, 0xAD]
        // We split it across two reads.
        let handshake = format!(
            r#"{{"method": "init", "id": "{}"}}"#,
            crate::testing::GUID_TEST_ECHO
        );
        let reader = Builder::new()
            .read(format!("{}\n", handshake).as_bytes())
            .read(b"\xE4")
            .read(b"\xB8\xAD\n")
            .build();

        let writer = Builder::new().build();

        let result = tokio::time::timeout(
            std::time::Duration::from_secs(2),
            PipeServer::handle_client(manager, reader, writer),
        )
        .await;

        assert!(
            result.is_ok(),
            "Handler failed to process split UTF-8 character"
        );
    }

    #[tokio::test]
    async fn test_idle_client_is_rejected_after_handshake_timeout() {
        let manager = BackendManager::new(BackendRegistry::new());
        let (_client, server) = tokio::io::duplex(64);
        let (reader, writer) = tokio::io::split(server);

        let error = match PipeServer::accept_client(
            &manager,
            reader,
            writer,
            ClientIdentity::trusted_for_tests(),
        )
        .await
        {
            Ok(_) => panic!("an idle pre-authentication client must time out"),
            Err(error) => error,
        };

        assert!(
            error.contains("handshake timed out"),
            "unexpected error: {error}"
        );
    }

    #[tokio::test]
    async fn test_oversized_pre_authentication_line_is_rejected() {
        let manager = BackendManager::new(BackendRegistry::new());
        let oversized = "x".repeat(protocol::MAX_CLIENT_MESSAGE_LINE_LENGTH + 1) + "\n";
        let reader = Builder::new().read(oversized.as_bytes()).build();
        let writer = Builder::new().build();

        let error = match PipeServer::accept_client(
            &manager,
            reader,
            writer,
            ClientIdentity::trusted_for_tests(),
        )
        .await
        {
            Ok(_) => panic!("an oversized pre-authentication line must be rejected"),
            Err(error) => error,
        };

        assert!(
            error.contains("max line length exceeded"),
            "unexpected error: {error}"
        );
    }
}
