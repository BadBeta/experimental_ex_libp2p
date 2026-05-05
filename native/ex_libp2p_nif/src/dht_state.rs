//! DHT routing-table snapshot wire format (v1).
//!
//! Used by the `kad_export_routing_table` and `kad_import_routing_table`
//! NIFs to persist Kademlia bucket entries across node restarts so a
//! freshly-booted node doesn't have to re-discover peers from scratch.
//!
//! # Format (v1)
//!
//! All multi-byte integers are big-endian.
//!
//! ```text
//! file        := HEADER ENTRY_COUNT ENTRY*
//! HEADER      := MAGIC(4) VERSION(1)         ; "L2DT" + 0x01
//! ENTRY_COUNT := u32                          ; number of routing entries
//! ENTRY       := PEER_ID_LEN(u16) PEER_ID(bytes)
//!                ADDR_COUNT(u16)
//!                ADDR*
//! ADDR        := ADDR_LEN(u16) ADDR_BYTES(bytes)
//! ```
//!
//! Why hand-rolled and not protobuf: the structure is trivial (list of
//! length-prefixed bytes); pulling `prost` + `prost-build` for this
//! shape would add a build-script dep and ~50 transitive crates.
//! When schema evolution becomes a real concern, revisit.
//!
//! Endianness is big-endian throughout for portability and to make the
//! file readable with `xxd` for debugging.
//!
//! # Allocation guard
//!
//! [`MAX_DHT_EXPORT_BYTES`] caps the import side. Any input larger than
//! the cap is rejected with a typed error before allocation, per
//! rust-implementing Rule 20 (validate user-controlled allocation
//! sizes BEFORE allocating).

use crate::policy::MAX_DHT_EXPORT_BYTES;

const MAGIC: &[u8; 4] = b"L2DT";
const VERSION: u8 = 1;
const HEADER_LEN: usize = MAGIC.len() + 1; // 4 + 1 = 5

/// One peer entry in the snapshot: peer id (multihash bytes) + multiaddr bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoutingEntry {
    pub peer_id: Vec<u8>,
    pub addresses: Vec<Vec<u8>>,
}

/// Decode-side errors. Encode is infallible on well-formed input.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum DhtStateError {
    #[error("input too large: got {got} bytes, max {max}")]
    InputTooLarge { got: usize, max: usize },
    #[error("truncated input at offset {offset} (need {need} bytes)")]
    Truncated { offset: usize, need: usize },
    #[error("bad magic: expected {:?}, got {got:?}", MAGIC)]
    BadMagic { got: [u8; 4] },
    #[error("unsupported version: {version}")]
    UnsupportedVersion { version: u8 },
}

/// Encode a list of routing entries to bytes.
pub fn encode(entries: &[RoutingEntry]) -> Vec<u8> {
    // Estimate size: header + count + per-entry header + addresses
    let est = HEADER_LEN
        + 4
        + entries
            .iter()
            .map(|e| 2 + e.peer_id.len() + 2 + e.addresses.iter().map(|a| 2 + a.len()).sum::<usize>())
            .sum::<usize>();
    let mut buf = Vec::with_capacity(est);

    buf.extend_from_slice(MAGIC);
    buf.push(VERSION);
    buf.extend_from_slice(&(entries.len() as u32).to_be_bytes());

    for entry in entries {
        // PEER_ID
        buf.extend_from_slice(&(entry.peer_id.len() as u16).to_be_bytes());
        buf.extend_from_slice(&entry.peer_id);
        // ADDR_COUNT
        buf.extend_from_slice(&(entry.addresses.len() as u16).to_be_bytes());
        for addr in &entry.addresses {
            buf.extend_from_slice(&(addr.len() as u16).to_be_bytes());
            buf.extend_from_slice(addr);
        }
    }

    buf
}

/// Decode bytes to a list of routing entries.
///
/// Rejects input larger than [`MAX_DHT_EXPORT_BYTES`] BEFORE parsing, so
/// a malicious or corrupted file can't cause excess allocation.
pub fn decode(data: &[u8]) -> Result<Vec<RoutingEntry>, DhtStateError> {
    if data.len() > MAX_DHT_EXPORT_BYTES {
        return Err(DhtStateError::InputTooLarge {
            got: data.len(),
            max: MAX_DHT_EXPORT_BYTES,
        });
    }

    let mut cur = Cursor::new(data);

    // HEADER
    let magic = cur.read_array::<4>()?;
    if &magic != MAGIC {
        return Err(DhtStateError::BadMagic { got: magic });
    }
    let version = cur.read_u8()?;
    if version != VERSION {
        return Err(DhtStateError::UnsupportedVersion { version });
    }

    // ENTRY_COUNT
    let count = cur.read_u32()? as usize;
    let mut entries = Vec::with_capacity(count.min(1024)); // cap initial alloc

    for _ in 0..count {
        let peer_id_len = cur.read_u16()? as usize;
        let peer_id = cur.read_vec(peer_id_len)?;

        let addr_count = cur.read_u16()? as usize;
        let mut addresses = Vec::with_capacity(addr_count.min(64));
        for _ in 0..addr_count {
            let addr_len = cur.read_u16()? as usize;
            let addr = cur.read_vec(addr_len)?;
            addresses.push(addr);
        }

        entries.push(RoutingEntry { peer_id, addresses });
    }

    Ok(entries)
}

struct Cursor<'a> {
    buf: &'a [u8],
    offset: usize,
}

impl<'a> Cursor<'a> {
    fn new(buf: &'a [u8]) -> Self {
        Self { buf, offset: 0 }
    }

    fn read_array<const N: usize>(&mut self) -> Result<[u8; N], DhtStateError> {
        if self.offset + N > self.buf.len() {
            return Err(DhtStateError::Truncated {
                offset: self.offset,
                need: N,
            });
        }
        let mut out = [0u8; N];
        out.copy_from_slice(&self.buf[self.offset..self.offset + N]);
        self.offset += N;
        Ok(out)
    }

    fn read_u8(&mut self) -> Result<u8, DhtStateError> {
        Ok(self.read_array::<1>()?[0])
    }

    fn read_u16(&mut self) -> Result<u16, DhtStateError> {
        Ok(u16::from_be_bytes(self.read_array::<2>()?))
    }

    fn read_u32(&mut self) -> Result<u32, DhtStateError> {
        Ok(u32::from_be_bytes(self.read_array::<4>()?))
    }

    fn read_vec(&mut self, n: usize) -> Result<Vec<u8>, DhtStateError> {
        if self.offset + n > self.buf.len() {
            return Err(DhtStateError::Truncated {
                offset: self.offset,
                need: n,
            });
        }
        let v = self.buf[self.offset..self.offset + n].to_vec();
        self.offset += n;
        Ok(v)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(peer_id: &[u8], addrs: &[&[u8]]) -> RoutingEntry {
        RoutingEntry {
            peer_id: peer_id.to_vec(),
            addresses: addrs.iter().map(|a| a.to_vec()).collect(),
        }
    }

    #[test]
    fn empty_round_trip() {
        let bytes = encode(&[]);
        assert_eq!(&bytes[0..4], MAGIC);
        assert_eq!(bytes[4], VERSION);
        // header (5) + entry_count (4) = 9 bytes
        assert_eq!(bytes.len(), 9);

        let decoded = decode(&bytes).unwrap();
        assert!(decoded.is_empty());
    }

    #[test]
    fn single_entry_round_trip() {
        let entries = vec![entry(b"peer-id-bytes", &[b"/ip4/127.0.0.1/tcp/4001"])];
        let bytes = encode(&entries);
        let decoded = decode(&bytes).unwrap();
        assert_eq!(decoded, entries);
    }

    #[test]
    fn multi_entry_multi_addr_round_trip() {
        let entries = vec![
            entry(b"peer-a", &[b"/ip4/1.2.3.4/tcp/4001", b"/ip4/1.2.3.4/udp/4001/quic-v1"]),
            entry(b"peer-b", &[]),
            entry(b"peer-c-with-longer-id-bytes", &[b"/dns4/example.com/tcp/4001"]),
        ];
        let bytes = encode(&entries);
        let decoded = decode(&bytes).unwrap();
        assert_eq!(decoded, entries);
    }

    #[test]
    fn bad_magic_rejected() {
        let mut bytes = encode(&[]);
        bytes[0] = b'X';
        assert!(matches!(decode(&bytes), Err(DhtStateError::BadMagic { .. })));
    }

    #[test]
    fn unsupported_version_rejected() {
        let mut bytes = encode(&[]);
        bytes[4] = 99;
        assert!(matches!(
            decode(&bytes),
            Err(DhtStateError::UnsupportedVersion { version: 99 })
        ));
    }

    #[test]
    fn truncated_header_rejected() {
        // Less than 4 bytes — magic read can't even start.
        for n in 0..MAGIC.len() {
            let bytes = vec![0u8; n];
            assert!(
                matches!(decode(&bytes), Err(DhtStateError::Truncated { .. })),
                "expected Truncated for {n} bytes, got {:?}",
                decode(&bytes)
            );
        }
        // Exactly 4 bytes of zero magic — magic check fires, BadMagic.
        let four_zero_bytes = vec![0u8; MAGIC.len()];
        assert!(matches!(
            decode(&four_zero_bytes),
            Err(DhtStateError::BadMagic { .. })
        ));
    }

    #[test]
    fn truncated_entry_rejected() {
        let entries = vec![entry(b"peer-id-bytes", &[b"/ip4/127.0.0.1/tcp/4001"])];
        let bytes = encode(&entries);
        // Drop the last byte — the addr will be truncated.
        let truncated = &bytes[..bytes.len() - 1];
        assert!(matches!(
            decode(truncated),
            Err(DhtStateError::Truncated { .. })
        ));
    }

    #[test]
    fn input_too_large_rejected_before_alloc() {
        // Use a buffer one byte over the cap. We don't even need a valid
        // header — the size check must fire BEFORE parsing.
        let oversized = vec![0u8; MAX_DHT_EXPORT_BYTES + 1];
        let err = decode(&oversized).unwrap_err();
        assert!(matches!(err, DhtStateError::InputTooLarge { got, max }
            if got == MAX_DHT_EXPORT_BYTES + 1 && max == MAX_DHT_EXPORT_BYTES));
    }

    #[test]
    fn at_cap_is_accepted_size_check_passes() {
        // A buffer EXACTLY at the cap passes the size guard. (It will
        // then fail the magic check because it's all zeros, but that's
        // a different error class — proves the size guard isn't off-by-one.)
        let at_cap = vec![0u8; MAX_DHT_EXPORT_BYTES];
        let err = decode(&at_cap).unwrap_err();
        // BadMagic, NOT InputTooLarge.
        assert!(
            matches!(err, DhtStateError::BadMagic { .. }),
            "expected BadMagic, got {err:?}"
        );
    }

    #[test]
    fn many_entries_no_panic_on_alloc_hint() {
        // Encode 5000 small entries to exercise the with_capacity hint
        // and confirm decode tolerates a count larger than the
        // initial-alloc cap (1024).
        let entries: Vec<_> = (0..5000)
            .map(|i| entry(format!("peer-{i}").as_bytes(), &[b"/ip4/1.2.3.4/tcp/4001"]))
            .collect();
        let bytes = encode(&entries);
        let decoded = decode(&bytes).unwrap();
        assert_eq!(decoded.len(), 5000);
        assert_eq!(decoded[42], entries[42]);
    }
}
