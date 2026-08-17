use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const PROTOCOL_VERSION: u16 = 1;
pub const FRAME_HEADER_BYTES: usize = 24;
pub const MAX_CONTROL_PAYLOAD_BYTES: u32 = 1024 * 1024;
pub const MAX_BINARY_PAYLOAD_BYTES: u32 = 4 * 1024 * 1024;
pub const SUPPORTED_CAPABILITIES: &[&str] = &[
    "handshake.negotiate",
    "health.get",
    "event.resume",
    "workspace.snapshot",
    "workspace.open",
    "workspace.files.list",
    "workspace.watch",
    "snapshot.get",
    "buffer.delta",
    "fs.scope.open",
    "fs.scope.close",
    "fs.stat",
    "fs.read",
    "fs.write",
    "fs.createDirectory",
    "fs.delete",
    "fs.copy",
    "fs.move",
    "fs.list",
    "fs.isExecutable",
    "fs.setExecutable",
    "fs.watch.start",
    "fs.watch.poll",
    "fs.watch.stop",
    "cancellation.cancel",
    "pty.start",
    "pty.resize",
    "pty.close",
    "task.start",
    "task.cancel",
    "task.output",
    "task.close",
    "dap.start",
    "dap.request",
    "dap.stop",
    "lsp.start",
    "lsp.request",
    "lsp.stop",
    "agent.connection.open",
    "agent.connection.close",
    "agent.session.new",
    "agent.session.load",
    "agent.session.prompt",
    "agent.session.poll",
    "agent.acp.session.cancel",
    "agent.acp.permission.decide",
    "agent.extension.invoke",
    "workspace.read",
    "workspace.search",
    "workspace.transaction.commit",
    "workspace.delete",
    "git.start",
    "git.output",
    "git.close",
    "styio.request",
    "pafio.request",
    "agent.session.start",
    "agent.session.resume",
    "agent.session.cancel",
    "agent.permission.decide",
    "agent.permission.request",
    "agent.mcp.invoke",
];

pub const METHOD_CATALOG: &[&str] = &[
    "handshake.negotiate",
    "health.get",
    "event.resume",
    "event.ack",
    "snapshot.get",
    "workspace.open",
    "workspace.read",
    "workspace.search",
    "workspace.transaction.commit",
    "workspace.delete",
    "workspace.watch",
    "workspace.files.list",
    "fs.scope.open",
    "fs.scope.close",
    "fs.stat",
    "fs.read",
    "fs.write",
    "fs.createDirectory",
    "fs.delete",
    "fs.copy",
    "fs.move",
    "fs.list",
    "fs.isExecutable",
    "fs.setExecutable",
    "fs.watch.start",
    "fs.watch.poll",
    "fs.watch.stop",
    "buffer.delta",
    "buffer.ack",
    "git.start",
    "git.output",
    "git.close",
    "styio.request",
    "pafio.request",
    "lsp.start",
    "lsp.request",
    "lsp.stop",
    "dap.start",
    "dap.request",
    "dap.stop",
    "task.start",
    "task.cancel",
    "task.output",
    "task.close",
    "pty.start",
    "pty.write",
    "pty.resize",
    "pty.close",
    "agent.session.start",
    "agent.session.resume",
    "agent.session.cancel",
    "agent.permission.decide",
    "agent.permission.request",
    "agent.mcp.invoke",
    "agent.connection.open",
    "agent.connection.close",
    "agent.session.new",
    "agent.session.load",
    "agent.session.prompt",
    "agent.session.poll",
    "agent.acp.session.cancel",
    "agent.acp.permission.decide",
    "agent.extension.invoke",
    "cancellation.cancel",
    "credit.grant",
    "upgrade.prepare",
];

pub fn is_known_method(method: &str) -> bool {
    METHOD_CATALOG.contains(&method)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum FrameKind {
    Control = 1,
    Pty = 2,
    Credit = 3,
}

impl TryFrom<u8> for FrameKind {
    type Error = ProtocolError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(Self::Control),
            2 => Ok(Self::Pty),
            3 => Ok(Self::Credit),
            _ => Err(ProtocolError::UnknownFrameKind(value)),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FrameHeader {
    pub version: u16,
    pub kind: FrameKind,
    pub flags: u8,
    pub stream_id: u32,
    pub sequence: u64,
    pub payload_length: u32,
}

impl FrameHeader {
    pub fn encode(&self) -> Result<[u8; FRAME_HEADER_BYTES], ProtocolError> {
        self.validate()?;
        let mut bytes = [0_u8; FRAME_HEADER_BYTES];
        bytes[0..2].copy_from_slice(&self.version.to_be_bytes());
        bytes[2] = self.kind as u8;
        bytes[3] = self.flags;
        bytes[4..8].copy_from_slice(&self.stream_id.to_be_bytes());
        bytes[8..16].copy_from_slice(&self.sequence.to_be_bytes());
        bytes[16..20].copy_from_slice(&self.payload_length.to_be_bytes());
        Ok(bytes)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, ProtocolError> {
        if bytes.len() != FRAME_HEADER_BYTES {
            return Err(ProtocolError::InvalidHeaderLength(bytes.len()));
        }
        let header = Self {
            version: u16::from_be_bytes([bytes[0], bytes[1]]),
            kind: FrameKind::try_from(bytes[2])?,
            flags: bytes[3],
            stream_id: u32::from_be_bytes(bytes[4..8].try_into().expect("fixed slice")),
            sequence: u64::from_be_bytes(bytes[8..16].try_into().expect("fixed slice")),
            payload_length: u32::from_be_bytes(bytes[16..20].try_into().expect("fixed slice")),
        };
        header.validate()?;
        Ok(header)
    }

    fn validate(&self) -> Result<(), ProtocolError> {
        if self.version != PROTOCOL_VERSION {
            return Err(ProtocolError::UnsupportedVersion(self.version));
        }
        let maximum = match self.kind {
            FrameKind::Control => MAX_CONTROL_PAYLOAD_BYTES,
            FrameKind::Pty | FrameKind::Credit => MAX_BINARY_PAYLOAD_BYTES,
        };
        if self.payload_length > maximum {
            return Err(ProtocolError::FrameTooLarge {
                actual: self.payload_length,
                maximum,
            });
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ControlEnvelope {
    pub protocol_version: u16,
    pub method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,
    pub client_instance_id: String,
    pub idempotency_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workspace_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workspace_revision: Option<u64>,
    pub deadline_unix_millis: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cancellation_id: Option<String>,
    pub params: BTreeMap<String, Value>,
    pub capabilities: Vec<String>,
    #[serde(flatten)]
    pub unknown_fields: BTreeMap<String, Value>,
}

impl ControlEnvelope {
    pub fn decode(bytes: &[u8]) -> Result<Self, ProtocolError> {
        if bytes.len() > MAX_CONTROL_PAYLOAD_BYTES as usize {
            return Err(ProtocolError::FrameTooLarge {
                actual: bytes.len() as u32,
                maximum: MAX_CONTROL_PAYLOAD_BYTES,
            });
        }
        let envelope: Self = serde_json::from_slice(bytes)
            .map_err(|error| ProtocolError::InvalidJson(error.to_string()))?;
        envelope.validate()?;
        Ok(envelope)
    }

    pub fn encode(&self) -> Result<Vec<u8>, ProtocolError> {
        self.validate()?;
        let bytes = serde_json::to_vec(self)
            .map_err(|error| ProtocolError::InvalidJson(error.to_string()))?;
        if bytes.len() > MAX_CONTROL_PAYLOAD_BYTES as usize {
            return Err(ProtocolError::FrameTooLarge {
                actual: bytes.len() as u32,
                maximum: MAX_CONTROL_PAYLOAD_BYTES,
            });
        }
        Ok(bytes)
    }

    fn validate(&self) -> Result<(), ProtocolError> {
        if self.protocol_version != PROTOCOL_VERSION {
            return Err(ProtocolError::UnsupportedVersion(self.protocol_version));
        }
        if self.method.is_empty()
            || self.client_instance_id.is_empty()
            || self.idempotency_key.is_empty()
        {
            return Err(ProtocolError::InvalidEnvelope(
                "method, clientInstanceId, and idempotencyKey are required",
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProtocolError {
    InvalidHeaderLength(usize),
    UnknownFrameKind(u8),
    UnsupportedVersion(u16),
    FrameTooLarge { actual: u32, maximum: u32 },
    InvalidJson(String),
    InvalidEnvelope(&'static str),
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decode_hex(value: &str) -> Vec<u8> {
        value
            .as_bytes()
            .chunks_exact(2)
            .map(|pair| {
                u8::from_str_radix(std::str::from_utf8(pair).expect("fixture hex"), 16)
                    .expect("fixture byte")
            })
            .collect()
    }

    #[test]
    fn frame_header_round_trips() {
        let header = FrameHeader {
            version: PROTOCOL_VERSION,
            kind: FrameKind::Pty,
            flags: 3,
            stream_id: 42,
            sequence: 99,
            payload_length: 4096,
        };
        assert_eq!(
            FrameHeader::decode(&header.encode().unwrap()).unwrap(),
            header
        );
    }

    #[test]
    fn unknown_control_fields_survive_round_trip() {
        let source = include_bytes!(
            "../../../../../../../packages/vityo_daemon_protocol/test/fixtures/control_roundtrip.json"
        );
        let envelope = ControlEnvelope::decode(source).unwrap();
        assert_eq!(envelope.workspace_revision, Some(7));
        assert!(envelope.unknown_fields.contains_key("futureField"));
        let round_trip = ControlEnvelope::decode(&envelope.encode().unwrap()).unwrap();
        assert_eq!(round_trip, envelope);
    }

    #[test]
    fn method_catalog_covers_both_backend_lines() {
        for method in [
            "workspace.transaction.commit",
            "pty.start",
            "lsp.request",
            "agent.session.start",
            "agent.mcp.invoke",
            "cancellation.cancel",
        ] {
            assert!(is_known_method(method), "missing method {method}");
        }
        assert_eq!(
            METHOD_CATALOG
                .iter()
                .copied()
                .collect::<std::collections::HashSet<_>>()
                .len(),
            METHOD_CATALOG.len()
        );
        assert!(
            METHOD_CATALOG
                .iter()
                .all(|method| !method.starts_with("agent.process."))
        );
    }

    #[test]
    fn shared_conformance_corpus_covers_versions_framing_and_capabilities() {
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../../../../../packages/vityo_daemon_protocol/test/fixtures/conformance_cases.json"
        ))
        .unwrap();
        for value in fixture["validFrameHeaders"].as_array().unwrap() {
            let bytes = decode_hex(value["hex"].as_str().unwrap());
            let header = FrameHeader::decode(&bytes).unwrap();
            assert_eq!(header.flags as u64, value["flags"].as_u64().unwrap());
            assert_eq!(header.stream_id as u64, value["streamId"].as_u64().unwrap());
            assert_eq!(header.sequence, value["sequence"].as_u64().unwrap());
            assert_eq!(
                header.payload_length as u64,
                value["payloadLength"].as_u64().unwrap()
            );
            assert_eq!(header.encode().unwrap().as_slice(), bytes);
        }
        for value in fixture["invalidFrameHeaders"].as_array().unwrap() {
            let error =
                FrameHeader::decode(&decode_hex(value["hex"].as_str().unwrap())).unwrap_err();
            let code = match error {
                ProtocolError::UnsupportedVersion(_) => "unsupported_protocol_version",
                ProtocolError::UnknownFrameKind(_) => "unknown_frame_kind",
                ProtocolError::FrameTooLarge { .. } => "frame_too_large",
                other => panic!("unexpected fixture error: {other:?}"),
            };
            assert_eq!(code, value["expected"].as_str().unwrap());
        }

        let source: Value = serde_json::from_slice(include_bytes!(
            "../../../../../../../packages/vityo_daemon_protocol/test/fixtures/control_roundtrip.json"
        ))
        .unwrap();
        for version in fixture["invalidControlVersions"].as_array().unwrap() {
            let mut invalid = source.clone();
            invalid["protocolVersion"] = version.clone();
            assert!(matches!(
                ControlEnvelope::decode(&serde_json::to_vec(&invalid).unwrap()),
                Err(ProtocolError::UnsupportedVersion(_))
            ));
        }
        assert!(matches!(
            ControlEnvelope::decode(fixture["malformedControl"].as_str().unwrap().as_bytes()),
            Err(ProtocolError::InvalidJson(_))
        ));

        let negotiation = &fixture["capabilityNegotiation"];
        let offered = negotiation["offered"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(Value::as_str)
            .collect::<std::collections::HashSet<_>>();
        assert!(
            negotiation["requiredSupported"]
                .as_array()
                .unwrap()
                .iter()
                .filter_map(Value::as_str)
                .all(|capability| offered.contains(capability))
        );
        assert!(!offered.contains(negotiation["requiredUnsupported"].as_str().unwrap()));
    }
}
