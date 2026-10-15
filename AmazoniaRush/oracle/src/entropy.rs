//! Deterministic noise source. Hand-rolled so no external crate can be swapped
//! out by a tamperer, and so a chamber layout can be rebuilt from its seed alone.

#[derive(Clone, Copy)]
pub struct Drift {
    hi: u64,
    lo: u64,
}

impl Drift {
    pub fn seeded(seed: u64) -> Self {
        let mut shell = Drift {
            hi: seed ^ 0x9E37_79B9_7F4A_7C15,
            lo: seed.rotate_left(29) ^ 0xBF58_476D_1CE4_E5B9,
        };
        if shell.hi == 0 {
            shell.hi = 0x2545_F491_4F6C_DD1D;
        }
        if shell.lo == 0 {
            shell.lo = 0x1405_7B7E_F767_814F;
        }
        for _ in 0..6 {
            shell.churn();
        }
        shell
    }

    fn churn(&mut self) -> u64 {
        let mut a = self.hi;
        let b = self.lo;
        self.hi = b;
        a ^= a << 23;
        a ^= a >> 17;
        a ^= b;
        a = a.wrapping_add(b);
        self.lo = a;
        a.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    pub fn raw(&mut self) -> u64 {
        self.churn()
    }

    /// Unbiased value in `0..span`. Falls back to zero for an empty span so a
    /// caller never has to guard the degenerate case.
    pub fn below(&mut self, span: u32) -> u32 {
        if span <= 1 {
            return 0;
        }
        let span64 = span as u64;
        let ceiling = u64::MAX - (u64::MAX % span64);
        loop {
            let draw = self.churn();
            if draw < ceiling {
                return (draw % span64) as u32;
            }
        }
    }

    pub fn between(&mut self, low: i32, high: i32) -> i32 {
        if high <= low {
            return low;
        }
        low + self.below((high - low) as u32) as i32
    }

    /// True with probability `permille / 1000`.
    pub fn leans(&mut self, permille: u32) -> bool {
        self.below(1000) < permille
    }

    pub fn pick<T: Copy>(&mut self, pool: &[T]) -> Option<T> {
        if pool.is_empty() {
            return None;
        }
        let at = self.below(pool.len() as u32) as usize;
        pool.get(at).copied()
    }

    pub fn jumble<T>(&mut self, pool: &mut [T]) {
        let count = pool.len();
        if count < 2 {
            return;
        }
        let mut at = count - 1;
        while at > 0 {
            let other = self.below((at + 1) as u32) as usize;
            pool.swap(at, other);
            at -= 1;
        }
    }
}

/// Stable 64-bit fingerprint of a byte run. Used for seeds and save digests.
pub fn imprint(bytes: &[u8], salt: u64) -> u64 {
    let mut acc = 0xCBF2_9CE4_8422_2325 ^ salt;
    for byte in bytes {
        acc ^= *byte as u64;
        acc = acc.wrapping_mul(0x1000_0000_01B3);
        acc ^= acc >> 29;
    }
    acc ^= acc >> 31;
    acc = acc.wrapping_mul(0x7FB5_D329_728E_A185);
    acc ^ (acc >> 27)
}

/// Mixes several scalars into one seed without any allocation.
pub fn braid_seed(parts: &[u64]) -> u64 {
    let mut acc = 0x8E3F_1A27_C4B9_6D05;
    for (index, part) in parts.iter().enumerate() {
        acc ^= part.wrapping_add(0x9E37_79B9_7F4A_7C15 ^ (index as u64).wrapping_mul(0x51_7CC1));
        acc = acc.rotate_left(23).wrapping_mul(0xFF51_AFD7_ED55_8CCD);
    }
    acc ^ (acc >> 33)
}
