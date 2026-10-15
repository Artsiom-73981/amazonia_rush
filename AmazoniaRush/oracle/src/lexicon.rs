//! Every word the player ever sees lives here as one shrouded blob that is
//! unwrapped once at startup. The Swift layer owns no literals at all: it asks
//! for a lexeme by number and renders whatever comes back.

use crate::crypt::{lexicon_key, unshroud};
use crate::lexicon_table::SCROLLS;

pub struct Lexicon {
    plain: Vec<u8>,
    spans: Vec<(u32, u16)>,
}

impl Lexicon {
    /// `tongue` indexes `SCROLLS`: 0 is English, 1 is Russian. Anything out of
    /// range falls back to English rather than showing the player nothing.
    pub fn unwrap_scroll(tongue: u8) -> Self {
        let blob = SCROLLS
            .get(tongue as usize)
            .copied()
            .unwrap_or(SCROLLS[0]);
        let Some(payload) = unshroud(blob, lexicon_key()) else {
            return Lexicon {
                plain: Vec::new(),
                spans: Vec::new(),
            };
        };
        if payload.len() < 2 {
            return Lexicon {
                plain: Vec::new(),
                spans: Vec::new(),
            };
        }
        let count = u16::from_le_bytes([payload[0], payload[1]]) as usize;
        let table_end = 2 + count * 6;
        if payload.len() < table_end {
            return Lexicon {
                plain: Vec::new(),
                spans: Vec::new(),
            };
        }
        let mut spans = Vec::with_capacity(count);
        for slot in 0..count {
            let at = 2 + slot * 6;
            let offset = u32::from_le_bytes([
                payload[at],
                payload[at + 1],
                payload[at + 2],
                payload[at + 3],
            ]);
            let span = u16::from_le_bytes([payload[at + 4], payload[at + 5]]);
            spans.push((offset, span));
        }
        Lexicon {
            plain: payload,
            spans,
        }
    }

    pub fn bytes_for(&self, lexeme: u16) -> &[u8] {
        let Some((offset, span)) = self.spans.get(lexeme as usize).copied() else {
            return &[];
        };
        let start = offset as usize;
        let stop = start + span as usize;
        if stop > self.plain.len() {
            return &[];
        }
        &self.plain[start..stop]
    }

    pub fn phrase(&self, lexeme: u16) -> &str {
        core::str::from_utf8(self.bytes_for(lexeme)).unwrap_or("")
    }

    pub fn count(&self) -> usize {
        self.spans.len()
    }
}
