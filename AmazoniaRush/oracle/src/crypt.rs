//! Obfuscation for anything that leaves the oracle: the on-disk profile and the
//! text vault. The goal is not military secrecy, it is that a player poking at
//! the app bundle or the container finds noise instead of balance numbers.

use super::entropy::imprint;

const LATTICE_SALT: u64 = 0x5A2D_7E41_93C8_B6F7;
const SPAN_PRIME: u64 = 0x0000_0100_0000_01B3;

/// Builds a key stream from a root key. Each byte depends on its own index and
/// on the running state, so identical plaintext regions do not look identical.
struct Veil {
    state: u64,
    drum: u64,
}

impl Veil {
    fn wound(root: u64, span: usize) -> Self {
        let anchor = root ^ (span as u64).wrapping_mul(SPAN_PRIME);
        Veil {
            state: anchor.rotate_left(17) | 1,
            drum: imprint(&anchor.to_le_bytes(), LATTICE_SALT) | 1,
        }
    }

    fn next(&mut self) -> u8 {
        self.state = self
            .state
            .wrapping_mul(0x5851_F42D_4C95_7F2D)
            .wrapping_add(self.drum);
        self.drum = self.drum.rotate_left(7) ^ (self.state >> 19);
        ((self.state >> 33) ^ (self.drum >> 11)) as u8
    }
}

pub fn shroud(plain: &[u8], root: u64) -> Vec<u8> {
    let mut veil = Veil::wound(root, plain.len());
    let mut cloaked = Vec::with_capacity(plain.len() + 12);
    cloaked.extend_from_slice(&(plain.len() as u32).to_le_bytes());
    let mut carry: u8 = (root >> 7) as u8;
    for byte in plain {
        let masked = byte ^ veil.next() ^ carry;
        carry = masked.rotate_left(3);
        cloaked.push(masked);
    }
    let digest = imprint(&cloaked, root);
    cloaked.extend_from_slice(&digest.to_le_bytes());
    cloaked
}

pub fn unshroud(cloaked: &[u8], root: u64) -> Option<Vec<u8>> {
    if cloaked.len() < 12 {
        return None;
    }
    let body_end = cloaked.len() - 8;
    let claimed = {
        let tail = &cloaked[body_end..];
        let mut raw = [0u8; 8];
        raw.copy_from_slice(tail);
        u64::from_le_bytes(raw)
    };
    if imprint(&cloaked[..body_end], root) != claimed {
        return None;
    }
    let span = {
        let head = &cloaked[..4];
        u32::from_le_bytes([head[0], head[1], head[2], head[3]]) as usize
    };
    let body = &cloaked[4..body_end];
    if body.len() != span {
        return None;
    }
    let mut veil = Veil::wound(root, span);
    let mut plain = Vec::with_capacity(span);
    let mut carry: u8 = (root >> 7) as u8;
    for masked in body {
        plain.push(masked ^ veil.next() ^ carry);
        carry = masked.rotate_left(3);
    }
    Some(plain)
}

/// Key used for the on-disk profile. Derived at runtime so the constant never
/// sits in the binary in one readable piece.
pub fn hearth_key() -> u64 {
    let limbs: [u64; 4] = [
        0x3F8A_11D7_0000_0000,
        0x0000_0000_6C42_93BE,
        0x0051_0000_0000_7A00,
        0x0000_AC00_1B00_0000,
    ];
    let mut root = 0u64;
    for (index, limb) in limbs.iter().enumerate() {
        root ^= limb.rotate_left((index as u32) * 11);
    }
    root ^ imprint(b"\x17\x4b\x9e\x02\x88\x31", 0x2B7D_0F51_C3A6_9E84)
}

/// Key used for the compiled lexicon.
pub fn lexicon_key() -> u64 {
    let limbs: [u64; 3] = [
        0x9C31_0000_42AE_0000,
        0x0000_7D64_0000_15B2,
        0x0E00_0000_0000_C700,
    ];
    let mut root = 0u64;
    for (index, limb) in limbs.iter().enumerate() {
        root ^= limb.rotate_right((index as u32) * 13 + 5);
    }
    root ^ 0x44B1_82E9_57C0_3D16
}
