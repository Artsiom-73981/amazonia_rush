//! The fight, in open ground. Nothing here snaps to a grid: the hero runs on
//! a continuous floor, the brood runs after her, shots fly, coins scatter, and
//! the whole thing is stepped forward in fixed slices so the result is the same
//! on every device no matter how the frames land.
//!
//! All of it is integer arithmetic in world units. A chamber is `SPAN_X` by
//! `SPAN_Y` units wide and the drawing side scales that to whatever glass it
//! has, which is why the simulation never learns a pixel.

use crate::codec::Scribe;
use crate::delve::{brood, goal, Brief, Mantle};
use crate::entropy::{braid_seed, Drift};

/// Chamber size in world units, a tall rectangle like the glass it is drawn on.
pub const SPAN_X: i32 = 1000;
pub const SPAN_Y: i32 = 1600;

/// One simulation slice. Short enough that a dash cannot step through a body.
const SLICE: u32 = 20;
/// Most slices one call may run, so a stalled frame cannot freeze the app
/// trying to catch up with real time.
const SLICE_CAP: u32 = 10;

const HERO_GIRTH: i32 = 38;
const HERO_PACE: i32 = 340;
const SWING_REACH: i32 = 132;
const SWING_REST: u32 = 400;
const HURT_MERCY: u32 = 620;
/// How long one jar of temple beer runs the fight.
const BREW_SPAN: u32 = 6000;
const FOCUS_BEAT: u32 = 2100;
const MAGNET: i32 = 130;
const SHOT_GIRTH: i32 = 16;

/// What a mote on the floor is worth when the hero runs over it.
pub mod trove {
    pub const COIN: u8 = 0;
    pub const HEART: u8 = 1;
    pub const FOCUS: u8 = 2;
    /// The urn nobody told you about. Pays in shards and in a chronicle line.
    pub const RELIC: u8 = 3;
    pub const CHEST: u8 = 4;
}

/// One-off events the drawing side turns into dust, sparks and numbers. They
/// are drained every time a frame is written, so nothing accumulates.
pub mod spark {
    pub const SWING: u8 = 0;
    pub const BITE: u8 = 1;
    pub const SLAY: u8 = 2;
    pub const TAKE: u8 = 3;
    pub const COIN: u8 = 4;
    pub const MEND: u8 = 5;
    pub const CAST: u8 = 6;
    pub const BOOM: u8 = 7;
    pub const HATCH: u8 = 8;
    pub const SWILL: u8 = 9;
}

pub mod mood {
    pub const WALK: u8 = 0;
    pub const WIND: u8 = 1;
    pub const LUNGE: u8 = 2;
    pub const HURT: u8 = 3;
}

#[derive(Clone, Copy)]
pub struct Runner {
    pub x: i32,
    pub y: i32,
    pub hp: i32,
    pub cap: i32,
    pub shield: i32,
    pub focus: i32,
    pub focus_cap: i32,
    pub look_x: i32,
    pub look_y: i32,
    pub swing: u32,
    pub mercy: u32,
    pub dash: u32,
    pub dash_x: i32,
    pub dash_y: i32,
    /// Milliseconds the temple beer is still in charge of her.
    pub swill: u32,
}

#[derive(Clone, Copy)]
pub struct Foe {
    pub tag: u32,
    pub breed: u8,
    pub x: i32,
    pub y: i32,
    pub hp: i32,
    pub cap: i32,
    pub girth: i32,
    pub pace: i32,
    pub bite: i32,
    pub armour: i32,
    pub wind: u32,
    pub rest: u32,
    pub touch: u32,
    pub flinch: u32,
    pub lunge: u32,
    pub lunge_x: i32,
    pub lunge_y: i32,
    pub look_x: i32,
    pub look_y: i32,
    pub boss: bool,
    pub stage: u8,
    pub hatched: u32,
}

#[derive(Clone, Copy)]
pub struct Shot {
    pub tag: u32,
    pub x: i32,
    pub y: i32,
    pub vx: i32,
    pub vy: i32,
    pub life: u32,
    pub hurt: i32,
    pub mine: bool,
    pub pierce: u8,
}

#[derive(Clone, Copy)]
pub struct Mote {
    pub tag: u32,
    pub kind: u8,
    pub x: i32,
    pub y: i32,
    pub heft: i32,
    pub drawn: bool,
}

/// Standing stone. Blocks bodies and eats shots, which is what gives the floor
/// its shape without any grid behind it.
#[derive(Clone, Copy)]
pub struct Stone {
    pub x: i32,
    pub y: i32,
    pub girth: i32,
    pub look: u8,
}

#[derive(Clone, Copy)]
pub struct Spark {
    pub kind: u8,
    pub x: i32,
    pub y: i32,
    pub heft: i32,
}

pub struct Arena {
    pub brief: Brief,
    pub mantle: Mantle,
    pub hero: Runner,
    pub foes: Vec<Foe>,
    pub shots: Vec<Shot>,
    pub motes: Vec<Mote>,
    pub stones: Vec<Stone>,
    pub sparks: Vec<Spark>,
    /// Bodies still owed to the room, wave by wave.
    pub pending: Vec<u8>,
    pub wave: u32,
    pub waves: u32,
    pub hatch_rest: u32,
    pub portal: bool,
    pub portal_x: i32,
    pub portal_y: i32,
    pub resolved: u8,
    pub flawless: bool,
    /// Seconds of fighting. The run bookkeeping outside still counts in these.
    pub turn: u32,
    pub clock: u32,
    pub hold: u32,
    pub kills: u32,
    pub felled: u32,
    pub taken: i32,
    pub dealt: u64,
    pub shoves: u32,
    pub chests: u32,
    /// Jars drained and censers breathed. Counted because the hero's habits
    /// are hers, and the almanac keeps the receipt.
    pub drank: u32,
    pub smoked: u32,
    pub coins: u32,
    pub shards: u64,
    pub resin: u64,
    spill: u32,
    beat: u32,
    stamp: u32,
    drift: Drift,
}

/// Square root for whole numbers. Newton's method, six rounds, no float.
fn root(value: i64) -> i32 {
    if value <= 0 {
        return 0;
    }
    let mut guess = value.min(1 << 30) as i64;
    let mut step = (guess >> 1).max(1);
    for _ in 0..24 {
        let next = (step + value / step) >> 1;
        if next == step {
            break;
        }
        step = next.max(1);
    }
    guess = step;
    guess as i32
}

fn reach(dx: i32, dy: i32) -> i32 {
    root(dx as i64 * dx as i64 + dy as i64 * dy as i64)
}

/// Scales a direction to the 1000 units the rest of the file speaks in.
fn aim(dx: i32, dy: i32) -> (i32, i32) {
    let span = reach(dx, dy);
    if span == 0 {
        return (0, 1000);
    }
    (dx * 1000 / span, dy * 1000 / span)
}

fn clamp(value: i32, low: i32, high: i32) -> i32 {
    value.max(low).min(high)
}

impl Arena {
    pub fn carve(brief: Brief, mantle: Mantle) -> Self {
        let mut drift = Drift::seeded(braid_seed(&[brief.seed, 0x51A7_C03D_9E42_6B18]));
        let mut floor = Arena {
            brief,
            mantle,
            drank: 0,
            smoked: 0,
            hero: Runner {
                x: SPAN_X / 2,
                y: SPAN_Y - 240,
                hp: 1,
                cap: 1,
                shield: mantle.ward_open,
                focus: mantle.vigor_open,
                focus_cap: mantle.vigor_cap.max(1),
                look_x: 0,
                look_y: -1000,
                swing: 0,
                mercy: 0,
                dash: 0,
                dash_x: 0,
                dash_y: 0,
                swill: 0,
            },
            foes: Vec::new(),
            shots: Vec::new(),
            motes: Vec::new(),
            stones: Vec::new(),
            sparks: Vec::new(),
            pending: Vec::new(),
            wave: 0,
            waves: 0,
            hatch_rest: 500,
            portal: false,
            portal_x: SPAN_X / 2,
            portal_y: 170,
            resolved: 0,
            flawless: true,
            turn: 0,
            clock: 0,
            hold: 0,
            kills: 0,
            felled: 0,
            taken: 0,
            dealt: 0,
            shoves: 0,
            chests: 0,
            coins: 0,
            shards: 0,
            resin: 0,
            spill: 0,
            beat: 0,
            stamp: 1,
            drift,
        };

        floor.waves = match brief.goal {
            goal::ENDURE | goal::FLEE => 99,
            _ => 2 + brief.depth / 3 + u32::from(brief.boss),
        };
        floor.hold = match brief.goal {
            goal::ENDURE | goal::FLEE => 20 + brief.depth * 4,
            _ => 0,
        };
        floor.raise_stones(&mut drift);
        floor.scatter_troves(&mut drift);
        floor.drift = drift;
        floor.call_wave();
        floor
    }

    /// Pillars and fallen blocks. They are kept off the middle of the floor so
    /// a player always has somewhere to run.
    fn raise_stones(&mut self, drift: &mut Drift) {
        let count = 4 + drift.below(4) as i32 + (self.brief.depth as i32 / 3).min(3);
        for _ in 0..count {
            let mut tries = 0;
            while tries < 16 {
                tries += 1;
                let x = drift.between(230, SPAN_X - 230);
                let y = drift.between(250, SPAN_Y - 360);
                let girth = drift.between(52, 86);
                if reach(x - self.hero.x, y - self.hero.y) < 240 {
                    continue;
                }
                if reach(x - self.portal_x, y - self.portal_y) < 230 {
                    continue;
                }
                if self
                    .stones
                    .iter()
                    .any(|stone| reach(x - stone.x, y - stone.y) < girth + stone.girth + 150)
                {
                    continue;
                }
                self.stones.push(Stone {
                    x,
                    y,
                    girth,
                    look: drift.below(4) as u8,
                });
                break;
            }
        }
    }

    /// What is lying about before the fight starts: the odd urn to find, and
    /// the chests a hoarding room is built around.
    fn scatter_troves(&mut self, drift: &mut Drift) {
        let chests = match self.brief.goal {
            goal::HOARD => 3 + self.brief.depth / 4 + self.mantle.extra_chest,
            _ => u32::from(drift.leans(420)) + self.mantle.extra_chest,
        };
        for _ in 0..chests {
            if let Some((x, y)) = self.open_spot(drift, 150) {
                self.add_mote(trove::CHEST, x, y, 0);
            }
        }
        // One hidden urn per chamber. It is not on any objective, it is just
        // there for the player who bothers to look in the corners.
        if drift.leans(700) {
            if let Some((x, y)) = self.corner_spot(drift) {
                self.add_mote(trove::RELIC, x, y, 0);
            }
        }
    }

    fn open_spot(&self, drift: &mut Drift, clear: i32) -> Option<(i32, i32)> {
        let mut tries = 0;
        while tries < 24 {
            tries += 1;
            let x = drift.between(120, SPAN_X - 120);
            let y = drift.between(180, SPAN_Y - 260);
            if self
                .stones
                .iter()
                .any(|stone| reach(x - stone.x, y - stone.y) < stone.girth + 70)
            {
                continue;
            }
            if reach(x - self.hero.x, y - self.hero.y) < clear {
                continue;
            }
            if self
                .motes
                .iter()
                .any(|mote| reach(x - mote.x, y - mote.y) < 120)
            {
                continue;
            }
            return Some((x, y));
        }
        None
    }

    fn corner_spot(&self, drift: &mut Drift) -> Option<(i32, i32)> {
        let corners = [
            (130, 240),
            (SPAN_X - 130, 240),
            (130, SPAN_Y - 300),
            (SPAN_X - 130, SPAN_Y - 300),
        ];
        let (x, y) = drift.pick(&corners)?;
        if self
            .stones
            .iter()
            .any(|stone| reach(x - stone.x, y - stone.y) < stone.girth + 60)
        {
            return None;
        }
        Some((x, y))
    }

    fn add_mote(&mut self, kind: u8, x: i32, y: i32, heft: i32) {
        let tag = self.stamp;
        self.stamp += 1;
        self.motes.push(Mote {
            tag,
            kind,
            x: clamp(x, 60, SPAN_X - 60),
            y: clamp(y, 140, SPAN_Y - 120),
            heft,
            drawn: kind == trove::CHEST || kind == trove::RELIC,
        });
    }

    fn mark(&mut self, kind: u8, x: i32, y: i32, heft: i32) {
        if self.sparks.len() < 48 {
            self.sparks.push(Spark { kind, x, y, heft });
        }
    }

    // --- the brood ---------------------------------------------------------

    fn breed_sheet(&self, breed: u8) -> (i32, i32, i32, i32, i32) {
        // hp, pace, bite, girth, armour
        let rung = self.brief.depth as i32;
        match breed {
            brood::JACKAL => (5 + rung, 165, 2, 34, 0),
            brood::SPITTER => (4 + rung, 110, 2, 34, 0),
            brood::HOPPER => (4 + rung, 230, 1, 30, 0),
            brood::WARDEN => (12 + rung * 2, 95, 3, 46, 1),
            brood::BROODER => (8 + rung, 120, 1, 40, 0),
            brood::SENTINEL => (10 + rung * 2, 0, 2, 44, 1),
            brood::REVENANT => (40 + rung * 8, 135, 3, 64, 1),
            _ => (4 + rung, 130, 1, 32, 0),
        }
    }

    fn spawn(&mut self, breed: u8, x: i32, y: i32) {
        let (hp, pace, bite, girth, armour) = self.breed_sheet(breed);
        let boss = breed == brood::REVENANT || (self.brief.boss && self.foes.is_empty());
        let tag = self.stamp;
        self.stamp += 1;
        self.foes.push(Foe {
            tag,
            breed,
            x: clamp(x, 70, SPAN_X - 70),
            y: clamp(y, 150, SPAN_Y - 100),
            hp: if boss { hp * 2 } else { hp },
            cap: if boss { hp * 2 } else { hp },
            girth: if boss { girth + 10 } else { girth },
            pace,
            bite,
            armour,
            wind: 0,
            rest: 400 + self.drift.below(600),
            touch: 0,
            flinch: 0,
            lunge: 0,
            lunge_x: 0,
            lunge_y: 0,
            look_x: 0,
            look_y: 1000,
            boss,
            stage: 0,
            hatched: 0,
        });
        self.mark(spark::HATCH, x, y, i32::from(boss));
    }

    /// Where a body walks in from: an edge, away from the hero, so nothing is
    /// ever dropped on the player's head.
    fn gate(&mut self) -> (i32, i32) {
        for _ in 0..12 {
            let side = self.drift.below(4);
            let (x, y) = match side {
                0 => (self.drift.between(90, SPAN_X - 90), 160),
                1 => (SPAN_X - 80, self.drift.between(190, SPAN_Y - 180)),
                2 => (self.drift.between(90, SPAN_X - 90), SPAN_Y - 130),
                _ => (80, self.drift.between(190, SPAN_Y - 180)),
            };
            if reach(x - self.hero.x, y - self.hero.y) > 320 {
                return (x, y);
            }
        }
        (SPAN_X / 2, 180)
    }

    fn call_wave(&mut self) {
        if self.wave >= self.waves {
            return;
        }
        self.wave += 1;
        let pool = crate::delve::breed_pool(self.brief.region, self.brief.boss);
        let heads = (self.brief.foes.max(1) + self.wave / 2).min(10);
        let mut list: Vec<u8> = Vec::new();
        if self.brief.boss && self.wave == self.waves {
            list.push(brood::REVENANT);
        }
        for _ in 0..heads {
            list.push(self.drift.pick(&pool).unwrap_or(brood::HUSK));
        }
        self.pending = list;
        self.hatch_rest = 450;
    }

    // --- the player --------------------------------------------------------

    pub fn equip_hero(&mut self, hp: i32, focus: i32, cap: i32) {
        self.hero.hp = hp.max(1);
        self.hero.focus = focus;
        self.hero.focus_cap = cap.max(1);
    }

    pub fn bite(&self) -> i32 {
        let honest = (2 + self.mantle.bite_bonus).max(1);
        if self.hero.swill > 0 {
            // Half again, and a floor of one extra, so the brew is worth
            // drinking on the very first chamber as well as the last.
            (honest * 3 / 2).max(honest + 1)
        } else {
            honest
        }
    }

    /// Runs the world forward. `push` is the stick, each axis in -1000..1000,
    /// `span` is how many milliseconds of real time to answer for. Returns the
    /// whole seconds that went by, which is the beat the run outside counts in.
    pub fn advance(&mut self, push_x: i32, push_y: i32, span: u32) -> u32 {
        if self.resolved != 0 {
            return 0;
        }
        let before = self.turn;
        self.spill += span.min(400);
        let mut slices = 0;
        while self.spill >= SLICE && slices < SLICE_CAP {
            self.spill -= SLICE;
            slices += 1;
            self.step(push_x, push_y);
            if self.resolved != 0 {
                break;
            }
        }
        self.turn.saturating_sub(before)
    }

    fn step(&mut self, push_x: i32, push_y: i32) {
        self.clock += SLICE;
        self.beat += SLICE;
        if self.beat >= 1000 {
            self.beat -= 1000;
            self.turn += 1;
            if self.hold > 0 {
                self.hold -= 1;
                if self.hold == 0 {
                    self.win();
                    return;
                }
            }
        }
        self.cool_hero();
        self.walk_hero(push_x, push_y);
        self.swing_hero();
        self.march_brood();
        self.fly_shots();
        self.gather();
        self.feed_wave();
        self.judge();
    }

    fn cool_hero(&mut self) {
        self.hero.swing = self.hero.swing.saturating_sub(SLICE);
        self.hero.mercy = self.hero.mercy.saturating_sub(SLICE);
        self.hero.dash = self.hero.dash.saturating_sub(SLICE);
        self.hero.swill = self.hero.swill.saturating_sub(SLICE);
        if self.hero.focus < self.hero.focus_cap {
            self.stamp = self.stamp.max(1);
            if self.clock % FOCUS_BEAT < SLICE {
                self.hero.focus += 1;
            }
        }
    }

    fn walk_hero(&mut self, push_x: i32, push_y: i32) {
        let pace = HERO_PACE + self.mantle.dash_span * 4;
        let (mut step_x, mut step_y) = if self.hero.dash > 0 {
            (
                self.hero.dash_x * (pace * 3) / 1000,
                self.hero.dash_y * (pace * 3) / 1000,
            )
        } else {
            let span = reach(push_x, push_y).min(1000);
            if span < 90 {
                (0, 0)
            } else {
                let (nx, ny) = aim(push_x, push_y);
                self.hero.look_x = nx;
                self.hero.look_y = ny;
                (nx * pace * span / 1_000_000, ny * pace * span / 1_000_000)
            }
        };
        if self.hero.swill > 0 && self.hero.dash == 0 {
            // Faster, and never quite where she aimed: the step gets nudged
            // sideways, and the side keeps changing.
            step_x = step_x * 6 / 5;
            step_y = step_y * 6 / 5;
            let tilt = if (self.clock / 360) % 2 == 0 { 1 } else { -1 };
            let lurch_x = -step_y * tilt * 3 / 10;
            let lurch_y = step_x * tilt * 3 / 10;
            step_x += lurch_x;
            step_y += lurch_y;
        }
        step_x = step_x * SLICE as i32 / 1000;
        step_y = step_y * SLICE as i32 / 1000;
        let want_x = clamp(self.hero.x + step_x, HERO_GIRTH + 20, SPAN_X - HERO_GIRTH - 20);
        let want_y = clamp(self.hero.y + step_y, HERO_GIRTH + 90, SPAN_Y - HERO_GIRTH - 40);
        let (x, y) = self.slide(want_x, want_y, 0, 0, HERO_GIRTH);
        self.hero.x = x;
        self.hero.y = y;
    }

    /// Moves a body and pushes it back out of any stone it would have entered.
    fn slide(&self, x: i32, y: i32, dx: i32, dy: i32, girth: i32) -> (i32, i32) {
        let mut at_x = x + dx;
        let mut at_y = y + dy;
        for stone in self.stones.iter() {
            let gap = reach(at_x - stone.x, at_y - stone.y);
            let want = stone.girth + girth;
            if gap < want && gap > 0 {
                let (nx, ny) = aim(at_x - stone.x, at_y - stone.y);
                at_x = stone.x + nx * want / 1000;
                at_y = stone.y + ny * want / 1000;
            }
        }
        (at_x, at_y)
    }

    fn swing_hero(&mut self) {
        if self.hero.swing > 0 {
            return;
        }
        let reach_now = SWING_REACH + self.mantle.push_power * 6;
        let mut closest: Option<usize> = None;
        let mut best = i32::MAX;
        for (slot, foe) in self.foes.iter().enumerate() {
            let gap = reach(foe.x - self.hero.x, foe.y - self.hero.y) - foe.girth;
            if gap <= reach_now && gap < best {
                best = gap;
                closest = Some(slot);
            }
        }
        let Some(slot) = closest else { return };
        let hurt = self.bite();
        let (fx, fy) = (self.foes[slot].x, self.foes[slot].y);
        let (nx, ny) = aim(fx - self.hero.x, fy - self.hero.y);
        self.hero.look_x = nx;
        self.hero.look_y = ny;
        self.hero.swing = (SWING_REST as f32 * self.mantle.cool_scale).max(180.0) as u32;
        self.mark(spark::SWING, (self.hero.x + fx) / 2, (self.hero.y + fy) / 2, hurt);
        self.wound(slot, hurt);
    }

    fn wound(&mut self, slot: usize, hurt: i32) {
        let Some(foe) = self.foes.get_mut(slot) else { return };
        let bite = (hurt - foe.armour).max(1);
        foe.hp -= bite;
        foe.flinch = 160;
        let (x, y, boss, breed) = (foe.x, foe.y, foe.boss, foe.breed);
        self.dealt = self.dealt.saturating_add(bite as u64);
        self.mark(spark::BITE, x, y, bite);
        if self.foes[slot].hp <= 0 {
            self.foes.remove(slot);
            self.kills += 1;
            if boss {
                self.felled += 1;
            }
            self.mark(spark::SLAY, x, y, i32::from(boss));
            self.drop_loot(x, y, boss, breed);
        }
    }

    fn drop_loot(&mut self, x: i32, y: i32, boss: bool, breed: u8) {
        let purse = if boss {
            6 + self.brief.depth as i32
        } else {
            1 + i32::from(breed == brood::WARDEN) + self.drift.below(2) as i32
        };
        for index in 0..purse.min(8) {
            let swing = self.drift.between(-70, 70);
            let lift = self.drift.between(-70, 70);
            self.add_mote(trove::COIN, x + swing, y + lift, 1 + index / 3);
        }
        if self.drift.leans(if boss { 1000 } else { 130 }) {
            self.add_mote(trove::HEART, x, y, 0);
        }
        if self.drift.leans(150) {
            self.add_mote(trove::FOCUS, x, y, 0);
        }
        if self.mantle.vigor_per_kill > 0 {
            self.hero.focus = (self.hero.focus + self.mantle.vigor_per_kill)
                .min(self.hero.focus_cap);
        }
    }

    // --- abilities ---------------------------------------------------------

    /// Spends focus on one of the hero's knacks. `aim` is a direction in
    /// -1000..1000 per axis; a zero vector falls back to where she is looking.
    pub fn cast(&mut self, power: u32, aim_x: i32, aim_y: i32, toll: i32) -> bool {
        if self.resolved != 0 || self.hero.focus < toll {
            return false;
        }
        let (dx, dy) = if aim_x == 0 && aim_y == 0 {
            (self.hero.look_x, self.hero.look_y)
        } else {
            aim(aim_x, aim_y)
        };
        // The order is the lexicon's: charge, sweep, shockwave, sun bolt,
        // bulwark.
        let spent = match power {
            0 => self.hurl_dash(dx, dy),
            1 => self.sweep(),
            2 => self.quake(),
            3 => self.hurl_bolt(dx, dy),
            5 => self.drain_jar(),
            _ => self.raise_ward(),
        };
        if spent {
            self.hero.focus -= toll;
            self.hero.look_x = dx;
            self.hero.look_y = dy;
            self.mark(spark::CAST, self.hero.x, self.hero.y, power as i32);
        }
        spent
    }

    fn hurl_dash(&mut self, dx: i32, dy: i32) -> bool {
        self.hero.dash = 220;
        self.hero.dash_x = dx;
        self.hero.dash_y = dy;
        self.hero.mercy = self.hero.mercy.max(260);
        self.shoves += 1;
        true
    }

    fn sweep(&mut self) -> bool {
        let span = 210 + self.mantle.push_power * 8;
        let hurt = self.bite() * 2;
        self.mark(spark::BOOM, self.hero.x, self.hero.y, span);
        let mut slot = 0;
        while slot < self.foes.len() {
            let before = self.foes.len();
            let gap = reach(
                self.foes[slot].x - self.hero.x,
                self.foes[slot].y - self.hero.y,
            ) - self.foes[slot].girth;
            if gap <= span {
                self.wound(slot, hurt);
            }
            if self.foes.len() == before {
                slot += 1;
            }
        }
        true
    }

    fn hurl_bolt(&mut self, dx: i32, dy: i32) -> bool {
        let tag = self.stamp;
        self.stamp += 1;
        self.shots.push(Shot {
            tag,
            x: self.hero.x,
            y: self.hero.y,
            vx: dx * 760 / 1000,
            vy: dy * 760 / 1000,
            life: 1400,
            hurt: self.bite() + 2 + self.mantle.bolt_span,
            mine: true,
            pierce: 2,
        });
        true
    }

    /// Temple beer. Everything she had left of caution goes into the sand
    /// with the froth: for six seconds she hits half again as hard and feels
    /// nothing, and for six seconds she cannot walk a straight line or hold a
    /// guard. The temple brewed it for the dead; she drinks it anyway.
    fn drain_jar(&mut self) -> bool {
        self.hero.swill = BREW_SPAN;
        self.hero.mercy = self.hero.mercy.max(600);
        self.drank += 1;
        self.mark(spark::SWILL, self.hero.x, self.hero.y, 0);
        true
    }

    fn raise_ward(&mut self) -> bool {
        self.hero.shield += 3 + self.mantle.ward_per_room;
        self.mark(spark::MEND, self.hero.x, self.hero.y, 0);
        true
    }

    fn quake(&mut self) -> bool {
        let hurt = self.bite() * 3;
        self.mark(spark::BOOM, self.hero.x, self.hero.y, 420);
        let mut slot = 0;
        while slot < self.foes.len() {
            let before = self.foes.len();
            if reach(
                self.foes[slot].x - self.hero.x,
                self.foes[slot].y - self.hero.y,
            ) <= 420
            {
                self.foes[slot].rest = self.foes[slot].rest.max(700);
                self.wound(slot, hurt);
            }
            if self.foes.len() == before {
                slot += 1;
            }
        }
        true
    }

    // --- the brood's turn, every slice -------------------------------------

    fn march_brood(&mut self) {
        let hero_x = self.hero.x;
        let hero_y = self.hero.y;
        let mut hatchlings: Vec<(i32, i32)> = Vec::new();
        let mut volleys: Vec<(i32, i32, i32, i32, i32)> = Vec::new();
        let mut strikes: Vec<i32> = Vec::new();

        for slot in 0..self.foes.len() {
            let mut foe = self.foes[slot];
            foe.flinch = foe.flinch.saturating_sub(SLICE);
            foe.touch = foe.touch.saturating_sub(SLICE);
            foe.rest = foe.rest.saturating_sub(SLICE);
            foe.wind = foe.wind.saturating_sub(SLICE);
            foe.lunge = foe.lunge.saturating_sub(SLICE);

            let gap = reach(hero_x - foe.x, hero_y - foe.y);
            let (nx, ny) = aim(hero_x - foe.x, hero_y - foe.y);
            foe.look_x = nx;
            foe.look_y = ny;

            let mut pace = foe.pace;
            let mut drive_x = nx;
            let mut drive_y = ny;

            match foe.breed {
                brood::SPITTER | brood::BROODER => {
                    // Standoffish: backs away when the hero closes in.
                    if gap < 420 {
                        drive_x = -nx;
                        drive_y = -ny;
                    } else if gap < 620 {
                        drive_x = -ny;
                        drive_y = nx;
                    }
                    if foe.rest == 0 && foe.breed == brood::SPITTER {
                        foe.wind = 420;
                        foe.rest = 1700;
                    }
                    if foe.wind > 0 && foe.wind <= SLICE {
                        volleys.push((foe.x, foe.y, nx, ny, foe.bite));
                    }
                    if foe.breed == brood::BROODER && foe.rest == 0 && foe.hatched < 4 {
                        foe.rest = 3200;
                        foe.hatched += 1;
                        hatchlings.push((foe.x + 60, foe.y));
                    }
                }
                brood::SENTINEL => {
                    pace = 0;
                    if foe.rest == 0 {
                        foe.wind = 500;
                        foe.rest = 2600;
                    }
                    if foe.wind > 0 && foe.wind <= SLICE {
                        for turn in 0..8 {
                            let (sx, sy) = SPOKES[turn];
                            volleys.push((foe.x, foe.y, sx, sy, foe.bite));
                        }
                    }
                }
                brood::JACKAL | brood::HOPPER => {
                    if foe.lunge > 0 {
                        drive_x = foe.lunge_x;
                        drive_y = foe.lunge_y;
                        pace = foe.pace * 4;
                    } else if foe.wind > 0 {
                        pace = 0;
                        if foe.wind <= SLICE {
                            foe.lunge = 300;
                            foe.lunge_x = nx;
                            foe.lunge_y = ny;
                        }
                    } else if gap < 520 && foe.rest == 0 {
                        foe.wind = 380;
                        foe.rest = 2100;
                    }
                }
                brood::REVENANT => {
                    // Three moods, by how much of it is left: it chases, then
                    // it opens up in every direction, then it calls for help.
                    let third = (foe.cap / 3).max(1);
                    foe.stage = if foe.hp > third * 2 {
                        0
                    } else if foe.hp > third {
                        1
                    } else {
                        2
                    };
                    if foe.rest == 0 {
                        foe.wind = 620;
                        foe.rest = 2400;
                    }
                    if foe.wind > 0 {
                        pace = foe.pace / 3;
                        if foe.wind <= SLICE {
                            match foe.stage {
                                0 => strikes.push(slot as i32),
                                1 => {
                                    for turn in 0..8 {
                                        let (sx, sy) = SPOKES[turn];
                                        volleys.push((foe.x, foe.y, sx, sy, foe.bite));
                                    }
                                }
                                _ => {
                                    hatchlings.push((foe.x - 80, foe.y + 40));
                                    hatchlings.push((foe.x + 80, foe.y + 40));
                                }
                            }
                        }
                    }
                }
                _ => {}
            }

            if foe.flinch > 0 {
                pace = pace / 3;
            }
            if pace > 0 {
                let dx = drive_x * pace * SLICE as i32 / 1_000_000;
                let dy = drive_y * pace * SLICE as i32 / 1_000_000;
                let want_x = clamp(foe.x + dx, foe.girth + 20, SPAN_X - foe.girth - 20);
                let want_y = clamp(foe.y + dy, foe.girth + 110, SPAN_Y - foe.girth - 30);
                let (x, y) = self.slide(want_x, want_y, 0, 0, foe.girth);
                foe.x = x;
                foe.y = y;
            }

            // Running into the hero hurts, with a pause so a body cannot grind
            // her down in a single second.
            if gap < foe.girth + HERO_GIRTH && foe.touch == 0 {
                foe.touch = 900;
                let bite = foe.bite;
                self.foes[slot] = foe;
                self.harm(bite, foe.x, foe.y);
                continue;
            }
            self.foes[slot] = foe;
        }

        for slot in strikes {
            let Some(foe) = self.foes.get(slot as usize) else { continue };
            let (x, y, bite) = (foe.x, foe.y, foe.bite);
            self.mark(spark::BOOM, x, y, 300);
            if reach(self.hero.x - x, self.hero.y - y) < 300 {
                self.harm(bite, x, y);
            }
        }
        for (x, y, dx, dy, bite) in volleys {
            let tag = self.stamp;
            self.stamp += 1;
            if self.shots.len() < 64 {
                self.shots.push(Shot {
                    tag,
                    x,
                    y,
                    vx: dx * 420 / 1000,
                    vy: dy * 420 / 1000,
                    life: 2600,
                    hurt: bite,
                    mine: false,
                    pierce: 0,
                });
            }
        }
        for (x, y) in hatchlings {
            if self.foes.len() < 24 {
                self.spawn(brood::HUSK, x, y);
            }
        }
    }

    fn fly_shots(&mut self) {
        let mut slot = 0;
        while slot < self.shots.len() {
            let mut shot = self.shots[slot];
            shot.life = shot.life.saturating_sub(SLICE);
            shot.x += shot.vx * SLICE as i32 / 1000;
            shot.y += shot.vy * SLICE as i32 / 1000;
            let spent = shot.life == 0
                || shot.x < 40
                || shot.x > SPAN_X - 40
                || shot.y < 110
                || shot.y > SPAN_Y - 20
                || self
                    .stones
                    .iter()
                    .any(|stone| reach(shot.x - stone.x, shot.y - stone.y) < stone.girth);
            if spent {
                self.mark(spark::BOOM, shot.x, shot.y, 40);
                self.shots.remove(slot);
                continue;
            }
            if shot.mine {
                let mut hit = false;
                let mut at = 0;
                while at < self.foes.len() {
                    let foe = self.foes[at];
                    if reach(shot.x - foe.x, shot.y - foe.y) < foe.girth + SHOT_GIRTH {
                        let hurt = shot.hurt;
                        self.wound(at, hurt);
                        hit = true;
                        break;
                    }
                    at += 1;
                }
                if hit {
                    if shot.pierce == 0 {
                        self.shots.remove(slot);
                        continue;
                    }
                    shot.pierce -= 1;
                }
            } else if reach(shot.x - self.hero.x, shot.y - self.hero.y) < HERO_GIRTH + SHOT_GIRTH {
                let hurt = shot.hurt;
                let (x, y) = (shot.x, shot.y);
                self.shots.remove(slot);
                self.harm(hurt, x, y);
                continue;
            }
            self.shots[slot] = shot;
            slot += 1;
        }
    }

    fn harm(&mut self, hurt: i32, x: i32, y: i32) {
        if self.hero.mercy > 0 || hurt <= 0 {
            return;
        }
        let mut bite = hurt;
        if self.hero.swill > 0 {
            bite += 1 + bite / 4;
        }
        if self.mantle.mercy > 0 {
            bite = (bite - self.mantle.mercy).max(1);
        }
        if self.hero.shield > 0 {
            let soak = bite.min(self.hero.shield);
            self.hero.shield -= soak;
            bite -= soak;
        }
        if bite > 0 {
            self.hero.hp -= bite;
            self.taken += bite;
            self.flawless = false;
            self.mark(spark::TAKE, self.hero.x, self.hero.y, bite);
        }
        self.hero.mercy = HURT_MERCY;
        let _ = (x, y);
        if self.hero.hp <= 0 {
            self.hero.hp = 0;
            self.resolved = 2;
        }
    }

    // --- pickups, waves, verdict -------------------------------------------

    fn gather(&mut self) {
        let mut slot = 0;
        while slot < self.motes.len() {
            let mote = self.motes[slot];
            let gap = reach(mote.x - self.hero.x, mote.y - self.hero.y);
            let pull = if mote.kind == trove::COIN { MAGNET } else { HERO_GIRTH + 30 };
            if gap > pull {
                slot += 1;
                continue;
            }
            match mote.kind {
                trove::COIN => {
                    self.coins += 1;
                    self.shards += (1 + mote.heft as u64) * 2;
                    self.mark(spark::COIN, mote.x, mote.y, mote.heft);
                }
                trove::HEART => {
                    self.drank += 1;
                    self.hero.hp = (self.hero.hp + 3).min(self.hero.cap);
                    self.mark(spark::MEND, mote.x, mote.y, 3);
                }
                trove::FOCUS => {
                    self.smoked += 1;
                    self.hero.focus = (self.hero.focus + 2).min(self.hero.focus_cap);
                    self.mark(spark::MEND, mote.x, mote.y, 0);
                }
                trove::RELIC => {
                    self.resin += 6 + self.brief.depth as u64 * 2;
                    self.shards += 20;
                    self.mark(spark::COIN, mote.x, mote.y, 4);
                }
                _ => {
                    self.chests += 1;
                    self.shards += 12 + self.brief.depth as u64 * 3;
                    self.mark(spark::COIN, mote.x, mote.y, 3);
                    for _ in 0..3 {
                        let swing = self.drift.between(-80, 80);
                        let lift = self.drift.between(-80, 80);
                        self.add_mote(trove::COIN, mote.x + swing, mote.y + lift, 2);
                    }
                }
            }
            self.motes.retain(|other| other.tag != mote.tag);
        }
    }

    fn feed_wave(&mut self) {
        if self.pending.is_empty() {
            return;
        }
        self.hatch_rest = self.hatch_rest.saturating_sub(SLICE);
        if self.hatch_rest > 0 || self.foes.len() >= 14 {
            return;
        }
        self.hatch_rest = 320;
        if let Some(breed) = self.pending.pop() {
            let (x, y) = self.gate();
            self.spawn(breed, x, y);
        }
    }

    fn judge(&mut self) {
        if self.resolved != 0 {
            return;
        }
        if !self.pending.is_empty() || !self.foes.is_empty() {
            return;
        }
        let chests_left = self
            .motes
            .iter()
            .any(|mote| mote.kind == trove::CHEST && self.brief.goal == goal::HOARD);
        if chests_left {
            return;
        }
        if self.wave < self.waves && self.hold == 0 {
            self.call_wave();
            return;
        }
        if self.hold > 0 {
            self.call_wave();
            return;
        }
        if !self.portal {
            self.portal = true;
            self.mark(spark::MEND, self.portal_x, self.portal_y, 9);
        }
        if reach(self.hero.x - self.portal_x, self.hero.y - self.portal_y) < 90 {
            self.win();
        }
    }

    fn win(&mut self) {
        self.resolved = 1;
        // Anything still lying on the floor is swept up, so a clean room is
        // never punished for finishing early.
        let leftovers: Vec<Mote> = self.motes.drain(..).collect();
        for mote in leftovers {
            match mote.kind {
                trove::COIN => {
                    self.coins += 1;
                    self.shards += 2;
                }
                trove::RELIC => self.resin += 6,
                _ => {}
            }
        }
    }

    pub fn mastery(&self) -> u32 {
        let mut score = self.kills * 12 + self.coins * 2 + self.chests * 15;
        if self.flawless {
            score += 40;
        }
        let swift = 90u32.saturating_sub(self.turn.min(90));
        score + swift
    }

    pub fn foes_left(&self) -> u32 {
        self.foes.len() as u32 + self.pending.len() as u32
    }

    /// Drops a body at a chosen spot. Proofs only: the game itself always
    /// walks a body in through a gate.
    pub fn spawn_for_proof(&mut self, breed: u8, x: i32, y: i32) {
        self.spawn(breed, x, y);
    }

    // --- transport ---------------------------------------------------------

    pub fn inscribe(&mut self, pen: &mut Scribe) {
        pen.quad(SPAN_X as u32)
            .quad(SPAN_Y as u32)
            .byte(self.brief.goal)
            .quad(self.wave)
            .quad(self.waves.min(9))
            .quad(self.foes_left())
            .quad(self.coins)
            .quad(self.turn)
            .quad(self.hold)
            .flag(self.portal)
            .signed(self.portal_x)
            .signed(self.portal_y)
            .flag(self.flawless);

        pen.signed(self.hero.x)
            .signed(self.hero.y)
            .signed(self.hero.hp)
            .signed(self.hero.cap)
            .signed(self.hero.shield)
            .signed(self.hero.focus)
            .signed(self.hero.focus_cap)
            .signed(self.hero.look_x)
            .signed(self.hero.look_y)
            .flag(self.hero.dash > 0)
            .flag(self.hero.mercy > 0)
            .flag(self.hero.swill > 0);

        pen.tally(self.stones.len());
        for stone in self.stones.iter() {
            pen.signed(stone.x)
                .signed(stone.y)
                .signed(stone.girth)
                .byte(stone.look);
        }

        pen.tally(self.foes.len());
        for foe in self.foes.iter() {
            let mood = if foe.flinch > 0 {
                mood::HURT
            } else if foe.lunge > 0 {
                mood::LUNGE
            } else if foe.wind > 0 {
                mood::WIND
            } else {
                mood::WALK
            };
            pen.quad(foe.tag)
                .byte(foe.breed)
                .signed(foe.x)
                .signed(foe.y)
                .signed(foe.hp)
                .signed(foe.cap)
                .signed(foe.girth)
                .byte(mood)
                .signed(foe.look_x)
                .signed(foe.look_y)
                .flag(foe.boss);
        }

        pen.tally(self.shots.len());
        for shot in self.shots.iter() {
            pen.quad(shot.tag)
                .signed(shot.x)
                .signed(shot.y)
                .signed(shot.vx)
                .signed(shot.vy)
                .flag(shot.mine);
        }

        pen.tally(self.motes.len());
        for mote in self.motes.iter() {
            pen.quad(mote.tag)
                .byte(mote.kind)
                .signed(mote.x)
                .signed(mote.y);
        }

        pen.tally(self.sparks.len());
        for spark in self.sparks.iter() {
            pen.byte(spark.kind)
                .signed(spark.x)
                .signed(spark.y)
                .signed(spark.heft);
        }
        self.sparks.clear();
    }
}

/// Eight directions, scaled to 1000, for anything that fires in a ring.
const SPOKES: [(i32, i32); 8] = [
    (0, -1000),
    (707, -707),
    (1000, 0),
    (707, 707),
    (0, 1000),
    (-707, 707),
    (-1000, 0),
    (-707, -707),
];
