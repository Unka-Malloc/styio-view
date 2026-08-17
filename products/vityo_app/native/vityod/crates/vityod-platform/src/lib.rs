#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndpointKind {
    UnixDomainSocket,
    WindowsNamedPipe,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EndpointDescriptor {
    pub kind: EndpointKind,
    pub instance_id: String,
    pub protocol_min: u16,
    pub protocol_max: u16,
}

impl EndpointDescriptor {
    pub fn validate(&self) -> Result<(), EndpointError> {
        if self.instance_id.is_empty() || self.protocol_min > self.protocol_max {
            return Err(EndpointError::InvalidDescriptor);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndpointError {
    InvalidDescriptor,
}
