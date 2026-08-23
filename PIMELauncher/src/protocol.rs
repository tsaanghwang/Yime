use serde_json::Value;

/// Client-to-launcher messages contain keystrokes and small command payloads;
/// backend responses have a separate limit. Keeping this boundary small also
/// bounds incomplete pre-authentication buffers.
pub const MAX_CLIENT_MESSAGE_LINE_LENGTH: usize = 256 * 1024;
pub const PROTOCOL_VERSION: u64 = 2;

/// Parses the first line received from a client to determine which backend to use.
///
/// Supports standard `{"method": "init", "id": "{GUID}"}`.
pub fn prepare_client_handshake(
    first_line: &str,
    trust_label: &str,
    allow_sensitive_commands: bool,
) -> Result<(String, String), String> {
    let mut json: Value = serde_json::from_str(first_line).map_err(|e| e.to_string())?;

    let client_version = json
        .get("protocolVersion")
        .and_then(Value::as_u64)
        .unwrap_or(1);
    if client_version > PROTOCOL_VERSION {
        return Err(format!(
            "Unsupported client protocol version {} (launcher supports {})",
            client_version, PROTOCOL_VERSION
        ));
    }

    if let Some(method) = json.get("method").and_then(Value::as_str) {
        if method == "init" {
            let guid = json
                .get("id")
                .and_then(Value::as_str)
                .ok_or_else(|| "Missing 'id' field in init message".to_string())?
                .to_string();
            let mut capabilities = vec![Value::String("ime.compose".to_string())];
            if allow_sensitive_commands {
                capabilities.push(Value::String("ime.command".to_string()));
            }
            json["launcher"] = serde_json::json!({
                "protocolVersion": PROTOCOL_VERSION,
                "trustLevel": trust_label,
                "capabilities": capabilities,
            });
            let prepared = serde_json::to_string(&json).map_err(|e| e.to_string())?;
            return Ok((guid, prepared));
        }
        return Err(format!("Unknown method '{}' in initial message", method));
    }
    Err("Invalid initial message format: missing 'method' field".to_string())
}

/// Parses a line of output from a backend process.
///
/// Expects the format `PIME_MSG|<client_id>|<payload>`.
/// Returns `Some((client_id, payload))` if valid.
pub fn parse_backend_output(line: &str) -> Option<(String, String)> {
    if line.starts_with("PIME_MSG|") {
        let parts: Vec<&str> = line.splitn(3, '|').collect();
        if parts.len() == 3 {
            let client_id = parts[1].to_string();
            let payload = parts[2].to_string();
            return Some((client_id, payload));
        }
    }
    None
}

/// Formats a message to be sent to a backend process.
///
/// Format: <client_id>|<payload>
pub fn format_backend_input(client_id: &str, message: &str) -> String {
    format!("{}|{}", client_id, message)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_client_handshake_init() {
        let json = format!(
            r#"{{"method": "init", "id": "{}"}}"#,
            crate::testing::GUID_TEST_ECHO
        );
        match prepare_client_handshake(&json, "desktop", true) {
            Ok((guid, prepared)) => {
                assert_eq!(guid, crate::testing::GUID_TEST_ECHO);
                let value: Value = serde_json::from_str(&prepared).unwrap();
                assert_eq!(value["launcher"]["protocolVersion"], PROTOCOL_VERSION);
                assert_eq!(value["launcher"]["trustLevel"], "desktop");
                assert_eq!(value["launcher"]["capabilities"][1], "ime.command");
            }
            _ => panic!("Expected Init handshake"),
        }
    }

    #[test]
    fn test_parse_client_handshake_invalid() {
        assert!(prepare_client_handshake("not json", "restricted", false).is_err());
        assert!(prepare_client_handshake(r#"{"method": "unknown"}"#, "restricted", false).is_err());
        assert!(prepare_client_handshake(r#"{"method": "init"}"#, "restricted", false).is_err());
        assert!(prepare_client_handshake(
            r#"{"method":"init","id":"x","protocolVersion":99}"#,
            "restricted",
            false,
        )
        .is_err());
    }

    #[test]
    fn test_launcher_overwrites_client_claimed_capabilities() {
        let (_, prepared) = prepare_client_handshake(
            r#"{"method":"init","id":"x","launcher":{"trustLevel":"desktop","capabilities":["ime.command"]}}"#,
            "restricted",
            false,
        )
        .unwrap();
        let value: Value = serde_json::from_str(&prepared).unwrap();
        assert_eq!(value["launcher"]["trustLevel"], "restricted");
        assert_eq!(
            value["launcher"]["capabilities"],
            serde_json::json!(["ime.compose"])
        );
    }

    #[test]
    fn test_parse_backend_output_valid() {
        let line = "PIME_MSG|client123|{\"status\": \"ok\"}";
        let (client_id, payload) = parse_backend_output(line).unwrap();
        assert_eq!(client_id, "client123");
        assert_eq!(payload, "{\"status\": \"ok\"}");
    }

    #[test]
    fn test_parse_backend_output_invalid() {
        assert!(parse_backend_output("JUST_TEXT").is_none());
        assert!(parse_backend_output("PIME_MSG|incomplete").is_none());
    }

    #[test]
    fn test_format_backend_input() {
        let client_id = "client123";
        let message = "{\"method\": \"test\"}";
        let formatted = format_backend_input(client_id, message);
        assert_eq!(formatted, "client123|{\"method\": \"test\"}");
    }
}
