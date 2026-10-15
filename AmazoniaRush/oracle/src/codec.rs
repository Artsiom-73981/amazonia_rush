//! Compact binary transport between the oracle and the presentation layer.
//! No JSON, no field names: a dump of the traffic reveals nothing but numbers.

pub struct Scribe {
    pub bytes: Vec<u8>,
}

impl Scribe {
    pub fn fresh() -> Self {
        Scribe {
            bytes: Vec::with_capacity(256),
        }
    }

    pub fn byte(&mut self, value: u8) -> &mut Self {
        self.bytes.push(value);
        self

    }

    pub fn flag(&mut self, value: bool) -> &mut Self {
        self.bytes.push(if value { 1 } else { 0 });
        self
    }

    pub fn pair(&mut self, value: u16) -> &mut Self {
        self.bytes.extend_from_slice(&value.to_le_bytes());
        self
    }

    pub fn quad(&mut self, value: u32) -> &mut Self {
        self.bytes.extend_from_slice(&value.to_le_bytes());
        self
    }

    pub fn signed(&mut self, value: i32) -> &mut Self {
        self.bytes.extend_from_slice(&value.to_le_bytes());
        self
    }

    pub fn octet(&mut self, value: u64) -> &mut Self {
        self.bytes.extend_from_slice(&value.to_le_bytes());
        self
    }

    pub fn ratio(&mut self, value: f32) -> &mut Self {
        self.bytes.extend_from_slice(&value.to_le_bytes());
        self
    }

    pub fn run(&mut self, value: &[u8]) -> &mut Self {
        let span = value.len().min(u16::MAX as usize) as u16;
        self.pair(span);
        self.bytes.extend_from_slice(&value[..span as usize]);
        self
    }

    pub fn tally(&mut self, value: usize) -> &mut Self {
        self.pair(value.min(u16::MAX as usize) as u16);
        self
    }

    pub fn into_bytes(self) -> Vec<u8> {
        self.bytes
    }
}

pub struct Reader<'a> {
    slab: &'a [u8],
    head: usize,
}

impl<'a> Reader<'a> {
    pub fn over(slab: &'a [u8]) -> Self {
        Reader { slab, head: 0 }
    }

    fn take(&mut self, span: usize) -> &'a [u8] {
        let start = self.head.min(self.slab.len());
        let stop = (self.head + span).min(self.slab.len());
        self.head = stop;
        &self.slab[start..stop]
    }

    pub fn byte(&mut self) -> u8 {
        self.take(1).first().copied().unwrap_or(0)
    }

    pub fn flag(&mut self) -> bool {
        self.byte() != 0
    }

    pub fn pair(&mut self) -> u16 {
        let slice = self.take(2);
        if slice.len() < 2 {
            return 0;
        }
        u16::from_le_bytes([slice[0], slice[1]])
    }

    pub fn quad(&mut self) -> u32 {
        let slice = self.take(4);
        if slice.len() < 4 {
            return 0;
        }
        u32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]])
    }

    pub fn signed(&mut self) -> i32 {
        self.quad() as i32
    }

    pub fn octet(&mut self) -> u64 {
        let slice = self.take(8);
        if slice.len() < 8 {
            return 0;
        }
        let mut raw = [0u8; 8];
        raw.copy_from_slice(slice);
        u64::from_le_bytes(raw)
    }

    pub fn ratio(&mut self) -> f32 {
        let slice = self.take(4);
        if slice.len() < 4 {
            return 0.0;
        }
        f32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]])
    }

    pub fn run(&mut self) -> &'a [u8] {
        let span = self.pair() as usize;
        self.take(span)
    }

    pub fn drained(&self) -> bool {
        self.head >= self.slab.len()
    }
}
