//! The gray side of the app: the handful of addresses and keys the app needs
//! in order to ask a backend what to show a paying visitor.
//!
//! Nothing here is readable in the shipped binary. The endpoint, the
//! attribution key, the messaging sender, the legal links and the User-Agent
//! fragments the app presents are all sealed with the same shroud the lexicon
//! uses, and are opened once at boot. Swift owns no literal that matters: it
//! asks for a slot by number and gets bytes back.

use crate::crypt::{gate_key, unshroud};
use crate::gate_table::{
    GATE_BLOB, UA_ENGINE, UA_MOBILE, UA_PLATFORM_PREFIX, UA_PLATFORM_SUFFIX, UA_PRODUCT,
    UA_SAFARI_TAIL, UA_SEP, UA_SETTER, UA_STYLE, UA_VERSION_TAIL,
};

/// Named slots inside the sealed gate blob. The order is fixed by the forge;
/// a slot that is missing simply answers empty rather than failing the launch.
pub mod slot {
    pub const ENDPOINT: u16 = 0;
    pub const PRIVACY: u16 = 1;
    pub const SUPPORT: u16 = 2;
    pub const ATTRIBUTION_KEY: u16 = 3;
    pub const SENDER: u16 = 4;
    pub const BUNDLE: u16 = 5;
    pub const STORE: u16 = 6;
    pub const TITLE: u16 = 7;
    pub const NSE_SUFFIX: u16 = 8;
    pub const FB_API_KEY: u16 = 9;
    pub const FB_PROJECT: u16 = 10;
    pub const FB_BUCKET: u16 = 11;
    pub const FB_APP_ID: u16 = 12;
    pub const SLOT_TOTAL: u16 = 13;
}

/// Opens the sealed gate blob once and hands out the slots by number.
pub struct Gate {
    plain: Vec<u8>,
    spans: Vec<(u32, u16)>,
}

impl Gate {
    pub fn unwrap_seal() -> Self {
        let Some(payload) = unshroud(GATE_BLOB, gate_key()) else {
            return Gate { plain: Vec::new(), spans: Vec::new() };
        };
        if payload.len() < 2 {
            return Gate { plain: Vec::new(), spans: Vec::new() };
        }
        let count = u16::from_le_bytes([payload[0], payload[1]]) as usize;
        let table_end = 2 + count * 6;
        if payload.len() < table_end {
            return Gate { plain: Vec::new(), spans: Vec::new() };
        }
        let mut spans = Vec::with_capacity(count);
        for entry in 0..count {
            let at = 2 + entry * 6;
            let offset = u32::from_le_bytes([
                payload[at], payload[at + 1], payload[at + 2], payload[at + 3],
            ]);
            let span = u16::from_le_bytes([payload[at + 4], payload[at + 5]]);
            spans.push((offset, span));
        }
        Gate { plain: payload, spans }
    }

    pub fn bytes_for(&self, slot: u16) -> &[u8] {
        let Some((offset, span)) = self.spans.get(slot as usize).copied() else {
            return &[];
        };
        let start = offset as usize;
        let stop = start + span as usize;
        if stop > self.plain.len() {
            return &[];
        }
        &self.plain[start..stop]
    }

    pub fn text_for(&self, slot: u16) -> &str {
        core::str::from_utf8(self.bytes_for(slot)).unwrap_or("")
    }
}

/// Names of the sealed fragments, in assembly order. Each name is hashed into
/// its fragment's key, so the ordering here is part of the protocol.
const UA_NAMES: [&str; 10] = [
    "UA_PRODUCT",
    "UA_PLATFORM_PREFIX",
    "UA_PLATFORM_SUFFIX",
    "UA_ENGINE",
    "UA_VERSION_TAIL",
    "UA_MOBILE",
    "UA_SAFARI_TAIL",
    "UA_STYLE",
    "UA_SETTER",
    "UA_SEP",
];

const UA_SEALED: [&[u8]; 10] = [
    UA_PRODUCT,
    UA_PLATFORM_PREFIX,
    UA_PLATFORM_SUFFIX,
    UA_ENGINE,
    UA_VERSION_TAIL,
    UA_MOBILE,
    UA_SAFARI_TAIL,
    UA_STYLE,
    UA_SETTER,
    UA_SEP,
];

fn ua_key(name: &str) -> u64 {
    let bytes = name.as_bytes();
    let mut acc = 0x1F3B_7E29_C4D8_5601u64;
    for byte in bytes {
        acc ^= *byte as u64;
        acc = acc.rotate_left(11).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    }
    acc ^ 0x5D02_A18C_F43E_96B7
}

/// Opens one sealed User-Agent fragment. The app assembles the header from
/// these so no recognisable scaffolding sits readable in the executable.
pub fn ua_piece(index: u16) -> Vec<u8> {
    let at = index as usize;
    let Some(sealed) = UA_SEALED.get(at).copied() else {
        return Vec::new();
    };
    unshroud(sealed, ua_key(UA_NAMES[at])).unwrap_or_default()
}

/// How many sealed User-Agent fragments exist.
pub fn ua_count() -> usize {
    UA_SEALED.len()
}

/// The spacer that joins the fragments.
pub fn ua_separator() -> Vec<u8> {
    ua_piece(9)
}
