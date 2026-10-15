//! One tactical chamber: the hero, the brood that hunts him, the hazards that
//! hunt everybody, and the single `act` call the presentation layer is allowed
//! to make. Nothing here trusts the caller: an illegal move is simply refused.
//!
//! The whole chamber is a turn sandwich. The player spends one action, the
//! room's machinery ticks, then every beast carries out the intent it declared
//! on the previous turn and declares a fresh one. Because intents are published
//! a full turn ahead, the player can always read the danger before stepping
//! into it, which is what makes the fight a puzzle rather than a dice roll.

use crate::atlas::*;
use crate::codec::Scribe;
use crate::entropy::Drift;
use crate::lexicon_table as lx;

pub const WARD_WIDE: i32 = 7;
pub const WARD_TALL: i32 = 9;
pub const WARD_CELLS: usize = (WARD_WIDE * WARD_TALL) as usize;

/// Turns between two volleys from one dart engine. Long enough to walk out of
/// the lane, short enough that standing still is never free.
pub const DART_CADENCE: u8 = 3;

/// What a tile is made of.
pub mod ground {
    pub const SAND: u8 = 0;
    /// Collapsed masonry: blocks everything, including sight.
    pub const RUBBLE: u8 = 1;
    /// A hole. Walkers refuse it, pushed bodies fall in and are gone.
    pub const PIT: u8 = 2;
    /// Spike bed on a fuse. Harmless while the fuse runs, lethal on zero.
    pub const SPIKES: u8 = 3;
    /// Pressure plate. Held by a block or a body.
    pub const PLATE: u8 = 4;
    /// Stone door, opens when every plate in the room is held.
    pub const GATE: u8 = 5;
    /// Lit brazier: a wall that also lets beams through.
    pub const BRAZIER: u8 = 6;
    /// Pushable cube.
    pub const BLOCK: u8 = 7;
    /// Turnable mirror. Even spin reflects "/", odd reflects "\".
    pub const MIRROR: u8 = 8;
    /// Sun lens. Fires a beam along `spin` every turn.
    pub const EMITTER: u8 = 9;
    /// Shrine. One drink: mends the hero and tops up vigour.
    pub const SHRINE: u8 = 10;
    /// Chest. One open: shards and resin.
    pub const CHEST: u8 = 11;
    /// The way out. Only passable once the room's goal is met.
    pub const STAIR: u8 = 12;
    /// Carved symbol. One step: a random blessing.
    pub const GLYPH: u8 = 13;
    /// Sand vortex. Drags whatever stands beside it one tile inward.
    pub const VORTEX: u8 = 14;
    /// Vent that coughs up a fresh husk on a timer.
    pub const VENT: u8 = 15;
    /// Wall-mounted dart engine. Winds up in plain sight, then rakes its whole
    /// lane. Solid, so a shoved cube can be parked in front of it.
    pub const DART: u8 = 16;

    pub const KINDS: usize = 17;
}

/// Beast families. Each one reads differently on the board and has to be
/// answered differently, which is where the tactics live.
pub mod brood {
    /// Shuffles straight at the hero, hits for little.
    pub const HUSK: u8 = 0;
    /// Closes two tiles when it has a clean lane, hits hard.
    pub const JACKAL: u8 = 1;
    /// Stands off and spits along a lane after a turn of winding up.
    pub const SPITTER: u8 = 2;
    /// Moves on the diagonal only, ignores spikes.
    pub const HOPPER: u8 = 3;
    /// Armoured and slow: acts every other turn, hits like a mallet.
    pub const WARDEN: u8 = 4;
    /// Keeps its distance and hatches husks.
    pub const BROODER: u8 = 5;
    /// Rooted statue that sweeps its own row and column.
    pub const SENTINEL: u8 = 6;
    /// Region boss. Cycles between a summon, a sweep and a lunge.
    pub const REVENANT: u8 = 7;

    pub const KINDS: usize = 8;
}

/// What a beast has announced it will do next turn.
pub mod plan {
    pub const HOLD: u8 = 0;
    pub const STEP: u8 = 1;
    pub const STRIKE: u8 = 2;
    pub const SHOOT: u8 = 3;
    pub const HATCH: u8 = 4;
    pub const SWEEP: u8 = 5;
    pub const LUNGE: u8 = 6;
}

/// Why a room is considered finished.
pub mod goal {
    /// Put the whole brood down.
    pub const CULL: u8 = 0;
    /// Reach the stair while vents keep coughing up husks.
    pub const FLEE: u8 = 1;
    /// Stay standing for a fixed number of turns.
    pub const ENDURE: u8 = 2;
    /// Hold every pressure plate at once.
    pub const PRESS: u8 = 3;
    /// Open every chest in the room.
    pub const HOARD: u8 = 4;
    /// Fell the revenant.
    pub const CROWN: u8 = 5;

    pub const KINDS: usize = 6;
}

/// Things worth animating. The room appends these and the renderer drains them,
/// so the Swift side never has to diff two snapshots to find out what happened.
pub mod omen {
    pub const HERO_HURT: u8 = 0;
    pub const BEAST_HURT: u8 = 1;
    pub const BEAST_DOWN: u8 = 2;
    pub const SHOVE: u8 = 3;
    pub const FELL: u8 = 4;
    pub const SPIKED: u8 = 5;
    pub const BEAM: u8 = 6;
    pub const MEND: u8 = 7;
    pub const LOOT: u8 = 8;
    pub const HATCHED: u8 = 9;
    pub const WARD_UP: u8 = 10;
    pub const GLYPH_READ: u8 = 11;
    pub const GATE_OPEN: u8 = 12;
    pub const STAIR_LIT: u8 = 13;
    pub const ABILITY: u8 = 14;
    pub const REFUSED: u8 = 15;
    pub const BLOCK_MOVED: u8 = 16;
    pub const PLATE_HELD: u8 = 17;
    pub const CRIT: u8 = 18;
    pub const VORTEX_PULL: u8 = 19;
}

/// Player actions. One per turn, no exceptions.
pub mod deed {
    pub const STEP: u8 = 0;
    pub const WAIT: u8 = 1;
    pub const TURN_MIRROR: u8 = 2;
    pub const ABILITY: u8 = 3;
}

/// Hero abilities, mirrored by `POWER_*` in the atlas.
pub mod knack {
    /// Charge up to `dash_span`, shoving and cutting the first body hit.
    pub const CHARGE: u32 = 0;
    /// Strike every adjacent tile at once.
    pub const SWEEP: u32 = 1;
    /// Shove every adjacent body `push_power` tiles away.
    pub const SHOCK: u32 = 2;
    /// Sun bolt down a lane.
    pub const BOLT: u32 = 3;
    /// Raise a ward and mend a little.
    pub const BULWARK: u32 = 4;
}

/// Per-breed tuning. Health scales with depth in `carve`.
pub struct BreedSpec {
    pub name: u16,
    pub blurb: u16,
    pub hp: i32,
    pub ward: i32,
    pub bite: i32,
    pub reach: i32,
    pub pace: u8,
    pub bounty: u32,
}

pub const BREEDS: [BreedSpec; brood::KINDS] = [
    BreedSpec { name: lx::L_BREED_NAME_0, blurb: lx::L_BREED_BLURB_0, hp: 3,  ward: 0, bite: 1, reach: 1, pace: 1, bounty: 6 },
    BreedSpec { name: lx::L_BREED_NAME_1, blurb: lx::L_BREED_BLURB_1, hp: 4,  ward: 0, bite: 2, reach: 1, pace: 1, bounty: 9 },
    BreedSpec { name: lx::L_BREED_NAME_2, blurb: lx::L_BREED_BLURB_2, hp: 3,  ward: 0, bite: 2, reach: 5, pace: 1, bounty: 11 },
    BreedSpec { name: lx::L_BREED_NAME_3, blurb: lx::L_BREED_BLURB_3, hp: 3,  ward: 0, bite: 1, reach: 1, pace: 1, bounty: 8 },
    BreedSpec { name: lx::L_BREED_NAME_4, blurb: lx::L_BREED_BLURB_4, hp: 7,  ward: 2, bite: 3, reach: 1, pace: 2, bounty: 16 },
    BreedSpec { name: lx::L_BREED_NAME_5, blurb: lx::L_BREED_BLURB_5, hp: 5,  ward: 0, bite: 1, reach: 1, pace: 1, bounty: 14 },
    BreedSpec { name: lx::L_BREED_NAME_6, blurb: lx::L_BREED_BLURB_6, hp: 6,  ward: 1, bite: 2, reach: 7, pace: 2, bounty: 15 },
    BreedSpec { name: lx::L_BREED_NAME_7, blurb: lx::L_BREED_BLURB_7, hp: 34, ward: 2, bite: 4, reach: 7, pace: 1, bounty: 90 },
];

/// Everything the profile contributes to a single run. Built once per room by
/// `Profile::outfit`, never read back by the meta layer.
#[derive(Clone, Copy)]
pub struct Mantle {
    pub hp_bonus: i32,
    pub ward_open: i32,
    pub ward_per_room: i32,
    pub vigor_cap: i32,
    pub vigor_open: i32,
    pub vigor_per_kill: i32,
    pub bite_bonus: i32,
    pub crit_permille: u32,
    pub push_power: i32,
    pub dash_span: i32,
    pub bolt_span: i32,
    pub cool_scale: f32,
    pub loot_scale: f32,
    pub light_scale: f32,
    pub mend_per_room: i32,
    pub thorns: i32,
    pub slay_bonus: i32,
    pub drowse: u8,
    pub chest_luck: u32,
    pub trap_sight: bool,
    pub spike_proof: bool,
    pub beam_proof: bool,
    pub shrine_power: f32,
    pub revives: u32,
    pub first_strike: bool,
    pub extra_chest: u32,
    pub mercy: i32,
}

impl Mantle {
    pub fn plain() -> Self {
        Mantle {
            hp_bonus: 0,
            ward_open: 0,
            ward_per_room: 0,
            vigor_cap: 6,
            vigor_open: 3,
            vigor_per_kill: 1,
            bite_bonus: 0,
            crit_permille: 60,
            push_power: 1,
            dash_span: 3,
            bolt_span: 5,
            cool_scale: 1.0,
            loot_scale: 1.0,
            light_scale: 1.0,
            mend_per_room: 0,
            thorns: 0,
            slay_bonus: 0,
            drowse: 0,
            chest_luck: 0,
            trap_sight: false,
            spike_proof: false,
            beam_proof: false,
            shrine_power: 1.0,
            revives: 0,
            first_strike: false,
            extra_chest: 0,
            mercy: 0,
        }
    }
}

#[derive(Clone, Copy)]
pub struct Cell {
    pub ground: u8,
    pub spin: u8,
    pub fuse: u8,
    pub spent: bool,
    pub glow: u8,
}

impl Cell {
    fn sand() -> Self {
        Cell { ground: ground::SAND, spin: 0, fuse: 0, spent: false, glow: 0 }
    }

    /// A dart engine aimed down `way`, counting `fuse` turns to its volley.
    pub fn dart(way: u8, fuse: u8) -> Self {
        Cell { ground: ground::DART, spin: way & 3, fuse, spent: false, glow: 0 }
    }

    /// Can a walking body stand here right now?
    pub fn standable(&self, gates_open: bool) -> bool {
        match self.ground {
            ground::RUBBLE | ground::BRAZIER | ground::BLOCK | ground::MIRROR
            | ground::EMITTER | ground::DART | ground::PIT => false,
            ground::GATE => gates_open,
            _ => true,
        }
    }

    /// Does this tile stop a beam?
    fn opaque(&self) -> bool {
        matches!(
            self.ground,
            ground::RUBBLE | ground::BLOCK | ground::GATE | ground::DART
        )
    }

    /// Can a shoved cube occupy this tile?
    fn cube_room(&self) -> bool {
        matches!(
            self.ground,
            ground::SAND | ground::SPIKES | ground::PLATE | ground::PIT | ground::GLYPH
        )
    }
}

#[derive(Clone, Copy)]
pub struct Hero {
    pub at: i32,
    pub hp: i32,
    pub cap: i32,
    pub ward: i32,
    pub vigor: i32,
    pub vigor_cap: i32,
    pub face: u8,
    pub revives: u32,
}

#[derive(Clone, Copy)]
pub struct Beast {
    pub breed: u8,
    pub at: i32,
    pub hp: i32,
    pub cap: i32,
    pub ward: i32,
    pub plan: u8,
    pub plan_at: i32,
    pub beat: u8,
    pub drowse: u8,
    pub alive: bool,
}

#[derive(Clone, Copy)]
pub struct Flash {
    pub kind: u8,
    pub at: i32,
    pub value: i32,
}

/// What the expedition asks for when it raises a room.
#[derive(Clone, Copy)]
pub struct Brief {
    pub seed: u64,
    pub region: u32,
    pub depth: u32,
    pub goal: u8,
    pub foes: u32,
    pub features: u32,
    pub turn_cap: u32,
    pub boss: bool,
}

pub const STRIDES: [i32; 4] = [-WARD_WIDE, 1, WARD_WIDE, -1];
const DIAGONALS: [(i32, i32); 4] = [(1, -1), (1, 1), (-1, 1), (-1, -1)];

pub fn column(at: i32) -> i32 {
    at.rem_euclid(WARD_WIDE)
}

pub fn row(at: i32) -> i32 {
    at.div_euclid(WARD_WIDE)
}

pub fn inside(x: i32, y: i32) -> bool {
    x >= 0 && x < WARD_WIDE && y >= 0 && y < WARD_TALL
}

pub fn seat_of(x: i32, y: i32) -> Option<i32> {
    if inside(x, y) {
        Some(y * WARD_WIDE + x)
    } else {
        None
    }
}

/// One tile along a cardinal direction, or `None` at the wall.
pub fn nudge(at: i32, way: u8) -> Option<i32> {
    let (x, y) = (column(at), row(at));
    match way & 3 {
        0 => seat_of(x, y - 1),
        1 => seat_of(x + 1, y),
        2 => seat_of(x, y + 1),
        _ => seat_of(x - 1, y),
    }
}

pub fn gap(a: i32, b: i32) -> i32 {
    (column(a) - column(b)).abs() + (row(a) - row(b)).abs()
}

pub struct Ward {
    pub brief: Brief,
    pub mantle: Mantle,
    pub cells: [Cell; WARD_CELLS],
    pub hero: Hero,
    pub brood: Vec<Beast>,
    pub flashes: Vec<Flash>,
    pub turn: u32,
    /// 0 live, 1 won, 2 lost.
    pub resolved: u8,
    pub gates_open: bool,
    pub stair_open: bool,
    pub kills: u32,
    pub felled: u32,
    pub taken: u32,
    pub dealt: u64,
    pub shoves: u32,
    pub chests: u32,
    pub plates_held: u32,
    pub plates_total: u32,
    pub shards: u64,
    pub resin: u64,
    pub flawless: bool,
    pub drift: Drift,
}

impl Ward {
    // --- raising -----------------------------------------------------------

    pub fn carve(brief: Brief, mantle: Mantle) -> Self {
        let mut drift = Drift::seeded(brief.seed);
        let mut shell = Ward {
            brief,
            mantle,
            cells: [Cell::sand(); WARD_CELLS],
            hero: Hero {
                at: 0,
                hp: 1,
                cap: 1,
                ward: 0,
                vigor: 0,
                vigor_cap: 1,
                face: 0,
                revives: mantle.revives,
            },
            brood: Vec::new(),
            flashes: Vec::new(),
            turn: 0,
            resolved: 0,
            gates_open: false,
            stair_open: false,
            kills: 0,
            felled: 0,
            taken: 0,
            dealt: 0,
            shoves: 0,
            chests: 0,
            plates_held: 0,
            plates_total: 0,
            shards: 0,
            resin: 0,
            flawless: true,
            drift,
        };

        shell.lay_stone(&mut drift);
        let (start, exit) = shell.pick_ends(&mut drift);
        shell.cells[exit as usize] = Cell { ground: ground::STAIR, ..Cell::sand() };
        let lane = shell.clear_lane(start, exit);
        shell.dress_features(&mut drift, start, exit, &lane);
        shell.open_errands(start);
        shell.seat_brood(&mut drift, start);

        shell.hero.at = start;
        shell.drift = drift;
        shell.settle_plates();
        shell.stair_open = matches!(brief.goal, goal::FLEE);
        if shell.stair_open {
            shell.flashes.push(Flash { kind: omen::STAIR_LIT, at: exit, value: 0 });
        }
        shell.declare_all();
        shell
    }

    /// Walls, rubble and pits. The border is always solid so nothing has to
    /// bounds-check a wrap-around.
    fn lay_stone(&mut self, drift: &mut Drift) {
        for y in 0..WARD_TALL {
            for x in 0..WARD_WIDE {
                let edge = x == 0 || y == 0 || x == WARD_WIDE - 1 || y == WARD_TALL - 1;
                if edge {
                    self.cells[(y * WARD_WIDE + x) as usize].ground = ground::RUBBLE;
                }
            }
        }
        let clumps = 3 + drift.below(4) as i32 + self.brief.depth.min(3) as i32;
        for _ in 0..clumps {
            let x = 1 + drift.below((WARD_WIDE - 2) as u32) as i32;
            let y = 2 + drift.below((WARD_TALL - 4) as u32) as i32;
            let span = 1 + drift.below(3) as i32;
            for step in 0..span {
                let (cx, cy) = if drift.leans(500) { (x + step, y) } else { (x, y + step) };
                if let Some(seat) = seat_of(cx, cy) {
                    if cy > 0 && cy < WARD_TALL - 1 && cx > 0 && cx < WARD_WIDE - 1 {
                        self.cells[seat as usize].ground = ground::RUBBLE;
                    }
                }
            }
        }
        let holes = if self.brief.features & fixture::PIT == 0 {
            0
        } else {
            1 + drift.below(3) as i32
        };
        for _ in 0..holes {
            let x = 1 + drift.below((WARD_WIDE - 2) as u32) as i32;
            let y = 3 + drift.below((WARD_TALL - 5) as u32) as i32;
            if let Some(seat) = seat_of(x, y) {
                if self.cells[seat as usize].ground == ground::SAND {
                    self.cells[seat as usize].ground = ground::PIT;
                }
            }
        }
    }

    fn pick_ends(&mut self, drift: &mut Drift) -> (i32, i32) {
        let start_x = 1 + drift.below((WARD_WIDE - 2) as u32) as i32;
        let exit_x = 1 + drift.below((WARD_WIDE - 2) as u32) as i32;
        let start = seat_of(start_x, WARD_TALL - 2).unwrap_or(0);
        let exit = seat_of(exit_x, 1).unwrap_or(0);
        self.cells[start as usize] = Cell::sand();
        (start, exit)
    }

    /// Cuts an L-shaped corridor so a tile is reachable no matter what the
    /// rubble roll produced. Only stone is removed, so the same cut can be
    /// reused after the furniture is down without destroying any of it.
    fn clear_lane(&mut self, from: i32, to: i32) -> Vec<i32> {
        let (mut x, y) = (column(from), row(from));
        let (tx, ty) = (column(to), row(to));
        let mut lane = vec![from];
        while x != tx {
            x += if tx > x { 1 } else { -1 };
            if let Some(seat) = seat_of(x, y) {
                self.unblock(seat);
                lane.push(seat);
            }
        }
        let mut cy = y;
        while cy != ty {
            cy += if ty > cy { 1 } else { -1 };
            if let Some(seat) = seat_of(x, cy) {
                self.unblock(seat);
                lane.push(seat);
            }
        }
        lane
    }

    /// Turns stone back into floor. Cubes stay: they can be shoved, and a plate
    /// without its cube would be a goal nobody could finish.
    fn unblock(&mut self, seat: i32) {
        let tile = self.cells[seat as usize].ground;
        if tile == ground::BLOCK || self.cells[seat as usize].standable(true) {
            return;
        }
        self.cells[seat as usize] = Cell::sand();
    }

    /// Chests, altars and the stair are things a room can demand. Each one gets
    /// its own cut if the dice walled it off.
    fn open_errands(&mut self, start: i32) {
        for seat in 0..WARD_CELLS as i32 {
            let wanted = matches!(
                self.cells[seat as usize].ground,
                ground::CHEST | ground::SHRINE | ground::GLYPH | ground::STAIR
            );
            if wanted && !self.reachable(start, seat) {
                self.clear_lane(start, seat);
            }
        }
    }

    fn vacant(&self, seat: i32) -> bool {
        self.cells[seat as usize].ground == ground::SAND
    }

    /// True when some square a body could stand on can no longer be walked to
    /// from the entrance.
    fn walls_off(&self, start: i32) -> bool {
        (0..WARD_CELLS as i32).any(|seat| {
            self.cells[seat as usize].standable(true) && !self.reachable(start, seat)
        })
    }

    fn free_seats(&self, drift: &mut Drift, keep_clear: i32) -> Vec<i32> {
        let mut pool: Vec<i32> = (0..WARD_CELLS as i32)
            .filter(|seat| self.vacant(*seat) && *seat != keep_clear)
            .collect();
        drift.jumble(&mut pool);
        pool
    }

    /// Furniture. Which pieces may appear is the region's business, so a player
    /// meets one new idea at a time instead of all twelve at once.
    fn dress_features(&mut self, drift: &mut Drift, start: i32, exit: i32, lane: &[i32]) {
        let mask = self.brief.features;
        let mut pool = self.free_seats(drift, start);
        pool.retain(|seat| *seat != exit && gap(*seat, start) > 1 && !lane.contains(seat));

        let take = |pool: &mut Vec<i32>| pool.pop();

        // Pressure plates come as a matched pair with their cube, placed so one
        // straight shove always solves them.
        if mask & fixture::PLATE != 0 || self.brief.goal == goal::PRESS {
            let want = if self.brief.goal == goal::PRESS {
                2 + (self.brief.depth / 3).min(2)
            } else {
                1
            };
            for _ in 0..want {
                if let Some(plate) = take(&mut pool) {
                    let way = drift.below(4) as u8;
                    let cube = nudge(plate, way);
                    let behind = cube.and_then(|seat| nudge(seat, (way + 2) & 3));
                    match (cube, behind) {
                        (Some(cube), Some(behind))
                            if self.vacant(cube)
                                && self.vacant(behind)
                                && !lane.contains(&cube) =>
                        {
                            self.cells[plate as usize].ground = ground::PLATE;
                            self.cells[cube as usize].ground = ground::BLOCK;
                            pool.retain(|seat| *seat != cube && *seat != behind);
                            self.plates_total += 1;
                        }
                        _ => {}
                    }
                }
            }
            if self.plates_total > 0 {
                if let Some(gate) = take(&mut pool) {
                    self.cells[gate as usize].ground = ground::GATE;
                }
            }
        }

        // Dart engines: bolted to the stone, aimed down the longest open lane
        // they can see, so the warning is always a straight line. They are
        // seated before the softer furniture, because an engine with nothing
        // to shoot down is worse than no engine at all.
        if mask & fixture::DART != 0 {
            let engines = 1 + drift.below(2) + self.brief.depth.min(2);
            let mut seated = 0;
            let mut tries = 0;
            while seated < engines && tries < 24 {
                tries += 1;
                let Some(seat) = take(&mut pool) else { break };
                let mut best = (0u8, 0i32);
                for way in 0..4u8 {
                    let mut reach = 0;
                    let mut here = seat;
                    while let Some(next) = nudge(here, way) {
                        if self.cells[next as usize].opaque() || next == exit {
                            break;
                        }
                        reach += 1;
                        here = next;
                    }
                    if reach > best.1 {
                        best = (way, reach);
                    }
                }
                // Two squares of lane is enough to be worth dodging; the rooms
                // are tight enough that asking for more leaves most of them
                // without an engine at all.
                if best.1 < 2 {
                    pool.push(seat);
                    continue;
                }
                let engine = Cell {
                    ground: ground::DART,
                    spin: best.0,
                    fuse: 2 + drift.below(3) as u8,
                    ..Cell::sand()
                };
                self.cells[seat as usize] = engine;
                // An engine is solid stone. If bolting it down walls off part
                // of the room, the last beast could end up somewhere nobody
                // can reach, so the seat goes back to sand.
                if self.walls_off(start) {
                    self.cells[seat as usize] = Cell::sand();
                    continue;
                }
                seated += 1;
            }
            // A region that promises engines should always show at least one,
            // so a tight room gets a sweep over whatever seats are left.
            if seated == 0 {
                let spare: Vec<i32> = pool.clone();
                for seat in spare {
                    let mut best = (0u8, 0i32);
                    for way in 0..4u8 {
                        let mut reach = 0;
                        let mut here = seat;
                        while let Some(next) = nudge(here, way) {
                            if self.cells[next as usize].opaque() || next == exit {
                                break;
                            }
                            reach += 1;
                            here = next;
                        }
                        if reach > best.1 {
                            best = (way, reach);
                        }
                    }
                    if best.1 < 2 {
                        continue;
                    }
                    self.cells[seat as usize] = Cell {
                        ground: ground::DART,
                        spin: best.0,
                        fuse: 2 + drift.below(3) as u8,
                        ..Cell::sand()
                    };
                    if self.walls_off(start) {
                        self.cells[seat as usize] = Cell::sand();
                        continue;
                    }
                    pool.retain(|spot| *spot != seat);
                    break;
                }
            }
        }

        if mask & fixture::SPIKES != 0 {
            let beds = 2 + drift.below(3) + self.brief.depth.min(3);
            for _ in 0..beds {
                if let Some(seat) = take(&mut pool) {
                    self.cells[seat as usize] = Cell {
                        ground: ground::SPIKES,
                        fuse: 1 + drift.below(3) as u8,
                        ..Cell::sand()
                    };
                }
            }
        }

        if mask & fixture::LENS != 0 {
            let lenses = 1 + drift.below(2);
            for _ in 0..lenses {
                if let Some(seat) = take(&mut pool) {
                    self.cells[seat as usize] = Cell {
                        ground: ground::EMITTER,
                        spin: drift.below(4) as u8,
                        ..Cell::sand()
                    };
                }
            }
        }

        if mask & fixture::MIRROR != 0 {
            let mirrors = 1 + drift.below(3);
            for _ in 0..mirrors {
                if let Some(seat) = take(&mut pool) {
                    self.cells[seat as usize] = Cell {
                        ground: ground::MIRROR,
                        spin: drift.below(4) as u8,
                        ..Cell::sand()
                    };
                }
            }
        }

        if mask & fixture::VORTEX != 0 {
            if let Some(seat) = take(&mut pool) {
                self.cells[seat as usize].ground = ground::VORTEX;
            }
        }

        if mask & fixture::GLYPH != 0 {
            let glyphs = 1 + drift.below(2);
            for _ in 0..glyphs {
                if let Some(seat) = take(&mut pool) {
                    self.cells[seat as usize].ground = ground::GLYPH;
                }
            }
        }

        if mask & fixture::BRAZIER != 0 {
            if let Some(seat) = take(&mut pool) {
                self.cells[seat as usize].ground = ground::BRAZIER;
            }
        }

        if self.brief.goal == goal::FLEE || mask & fixture::VENT != 0 {
            let vents = if self.brief.goal == goal::FLEE { 2 } else { 1 };
            for _ in 0..vents {
                if let Some(seat) = take(&mut pool) {
                    self.cells[seat as usize] = Cell {
                        ground: ground::VENT,
                        fuse: 2,
                        ..Cell::sand()
                    };
                }
            }
        }

        let chests = match self.brief.goal {
            goal::HOARD => 3,
            _ => u32::from(drift.leans(420)),
        } + self.mantle.extra_chest;
        for _ in 0..chests {
            if let Some(seat) = take(&mut pool) {
                self.cells[seat as usize].ground = ground::CHEST;
            }
        }

        if drift.leans(if self.brief.depth > 1 { 520 } else { 260 }) {
            if let Some(seat) = take(&mut pool) {
                self.cells[seat as usize].ground = ground::SHRINE;
            }
        }

        // A cube or two to shove around even when no plate asked for one.
        let cubes = if mask & fixture::CUBE == 0 { 0 } else { 1 + drift.below(2) };
        for _ in 0..cubes {
            if let Some(seat) = take(&mut pool) {
                if nudge(seat, 0)
                    .map(|s| self.vacant(s) && !lane.contains(&s))
                    .unwrap_or(false)
                {
                    self.cells[seat as usize].ground = ground::BLOCK;
                }
            }
        }
    }

    fn seat_brood(&mut self, drift: &mut Drift, start: i32) {
        let region = (self.brief.region as usize).min(REGION_COUNT - 1);
        let roster = breed_pool(region as u32, self.brief.boss);
        let mut pool = self.free_seats(drift, start);
        pool.retain(|seat| gap(*seat, start) >= 3);

        if self.brief.boss {
            if let Some(seat) = pool.pop() {
                self.push_beast(brood::REVENANT, seat);
            }
        }
        let count = self.brief.foes.min(10);
        for _ in 0..count {
            let Some(seat) = pool.pop() else { break };
            let breed = drift.pick(&roster).unwrap_or(brood::HUSK);
            self.push_beast(breed, seat);
        }
    }

    fn push_beast(&mut self, breed: u8, seat: i32) {
        let spec = &BREEDS[(breed as usize).min(brood::KINDS - 1)];
        let climb = self.brief.depth as i32 + self.brief.region as i32;
        let hp = (spec.hp + climb / 2 - self.mantle.mercy).max(1);
        self.brood.push(Beast {
            breed,
            at: seat,
            hp,
            cap: hp,
            ward: spec.ward,
            plan: plan::HOLD,
            plan_at: seat,
            beat: 0,
            drowse: self.mantle.drowse,
            alive: true,
        });
    }

    /// Drops a beast on a tile with a known health. The proofs use it to build
    /// an exact situation instead of fishing for one in the rolls.
    pub fn push_test_beast(&mut self, breed: u8, seat: i32, hp: i32) {
        self.push_beast(breed, seat);
        if let Some(beast) = self.brood.last_mut() {
            beast.hp = hp;
            beast.cap = hp;
            beast.ward = 0;
        }
    }

    pub fn equip_hero(&mut self, hp: i32, vigor: i32, vigor_cap: i32) {
        self.hero.hp = hp.max(1);
        self.hero.cap = hp.max(1);
        self.hero.vigor = vigor;
        self.hero.vigor_cap = vigor_cap.max(1);
        self.hero.ward = self.mantle.ward_open + self.mantle.ward_per_room;
    }

    // --- queries -----------------------------------------------------------

    pub fn beast_at(&self, seat: i32) -> Option<usize> {
        self.brood
            .iter()
            .position(|beast| beast.alive && beast.at == seat)
    }

    fn body_at(&self, seat: i32) -> bool {
        self.hero.at == seat || self.beast_at(seat).is_some()
    }

    fn walkable(&self, seat: i32) -> bool {
        self.cells[seat as usize].standable(self.gates_open)
    }

    /// What kind of ground a tile is right now, for the view layer and proofs.
    pub fn tile_at(&self, seat: i32) -> u8 {
        self.cells[seat as usize].ground
    }

    /// Turns left on whatever this tile is counting down.
    pub fn tile_fuse(&self, seat: i32) -> u8 {
        self.cells[seat as usize].fuse
    }

    /// Runs one round of the room's own machinery. The proofs use it to watch
    /// a single hazard without walking a whole turn.
    pub fn tick_hazards_for_proof(&mut self) {
        self.tick_hazards();
    }

    /// Has this chest, altar or glyph already been used up?
    pub fn used_up(&self, seat: i32) -> bool {
        self.cells[seat as usize].spent
    }

    /// Can a body stand here with the gates in their current state?
    pub fn standable(&self, seat: i32) -> bool {
        self.walkable(seat)
    }

    /// Breadth-first distance field from one tile, used by every walker so the
    /// brood never gets stuck behind a cube.
    fn tide(&self, from: i32) -> [i32; WARD_CELLS] {
        let mut field = [-1i32; WARD_CELLS];
        let mut queue: Vec<i32> = Vec::with_capacity(WARD_CELLS);
        field[from as usize] = 0;
        queue.push(from);
        let mut head = 0;
        while head < queue.len() {
            let here = queue[head];
            head += 1;
            let depth = field[here as usize];
            for way in 0..4u8 {
                let Some(next) = nudge(here, way) else { continue };
                if field[next as usize] >= 0 || !self.walkable(next) {
                    continue;
                }
                field[next as usize] = depth + 1;
                queue.push(next);
            }
        }
        field
    }

    /// Is there any walking route between two tiles right now? The exit tile
    /// itself is not walkable until the goal is met, so a neighbour counts.
    pub fn reachable(&self, from: i32, to: i32) -> bool {
        if from == to {
            return true;
        }
        let field = self.tide(from);
        if field[to as usize] >= 0 {
            return true;
        }
        (0..4u8)
            .filter_map(|way| nudge(to, way))
            .any(|seat| field[seat as usize] >= 0)
    }

    /// First direction along the shortest route, used by the hint arrow and by
    /// the harness that plays whole descents unattended.
    pub fn route_step(&self, from: i32, to: i32) -> Option<u8> {
        let field = self.tide(to);
        let mut best: Option<(i32, u8)> = None;
        for way in 0..4u8 {
            let Some(next) = nudge(from, way) else { continue };
            if next == to {
                return Some(way);
            }
            if !self.walkable(next) || self.body_at(next) {
                continue;
            }
            let mark = field[next as usize];
            if mark < 0 {
                continue;
            }
            if best.map(|(score, _)| mark < score).unwrap_or(true) {
                best = Some((mark, way));
            }
        }
        best.map(|(_, way)| way)
    }

    // --- the player's turn -------------------------------------------------

    /// The only way in. Returns false when the action was illegal, in which
    /// case no time passes and the board is untouched.
    pub fn act(&mut self, kind: u8, a: u8) -> bool {
        if self.resolved != 0 {
            return false;
        }
        self.flashes.clear();
        let spent = match kind {
            deed::STEP => self.walk(a),
            deed::WAIT => {
                self.hero.vigor = (self.hero.vigor + 1).min(self.hero.vigor_cap);
                true
            }
            deed::TURN_MIRROR => self.twist(a as i32),
            _ => false,
        };
        if !spent {
            self.flashes.push(Flash { kind: omen::REFUSED, at: self.hero.at, value: 0 });
            return false;
        }
        self.close_turn();
        true
    }

    fn walk(&mut self, way: u8) -> bool {
        let Some(target) = nudge(self.hero.at, way) else { return false };
        self.hero.face = way & 3;
        if let Some(index) = self.beast_at(target) {
            let bite = 2 + self.mantle.bite_bonus;
            self.wound_beast(index, bite, true);
            return true;
        }
        let tile = self.cells[target as usize].ground;
        if tile == ground::BLOCK {
            return self.shove_cube(target, way);
        }
        if tile == ground::STAIR {
            if !self.stair_open {
                return false;
            }
            self.hero.at = target;
            self.resolved = 1;
            return true;
        }
        if !self.walkable(target) {
            return false;
        }
        self.hero.at = target;
        self.tread(target);
        true
    }

    /// Pushing a cube: one tile, and only into room. A cube shoved over a pit
    /// fills it, which is how a blocked route gets opened.
    fn shove_cube(&mut self, cube: i32, way: u8) -> bool {
        let Some(behind) = nudge(cube, way) else { return false };
        if self.body_at(behind) {
            return false;
        }
        if !self.cells[behind as usize].cube_room() {
            return false;
        }
        let landing = self.cells[behind as usize].ground;
        self.cells[cube as usize] = Cell::sand();
        if landing == ground::PIT {
            self.cells[behind as usize] = Cell::sand();
            self.flashes.push(Flash { kind: omen::FELL, at: behind, value: 0 });
        } else {
            let keep = self.cells[behind as usize];
            self.cells[behind as usize] = Cell {
                ground: ground::BLOCK,
                fuse: keep.fuse,
                spin: keep.spin,
                spent: keep.spent,
                glow: 0,
            };
            // Remember the plate under a cube so lifting it later still works.
            if landing == ground::PLATE {
                self.cells[behind as usize].spin = 9;
                self.flashes.push(Flash { kind: omen::PLATE_HELD, at: behind, value: 0 });
            }
        }
        self.hero.at = cube;
        self.shoves += 1;
        self.flashes.push(Flash { kind: omen::BLOCK_MOVED, at: behind, value: 0 });
        self.tread(cube);
        true
    }

    /// Whatever the tile the hero just entered wants to do about it.
    fn tread(&mut self, seat: i32) {
        let cell = self.cells[seat as usize];
        match cell.ground {
            ground::CHEST if !cell.spent => {
                self.cells[seat as usize].spent = true;
                let roll = 18 + self.drift.below(22 + self.mantle.chest_luck * 6);
                let shards = (roll as f32 * self.mantle.loot_scale).round() as u64;
                let resin = 2 + self.drift.below(4 + self.mantle.chest_luck) as u64;
                self.shards += shards;
                self.resin += resin;
                self.chests += 1;
                self.flashes.push(Flash { kind: omen::LOOT, at: seat, value: shards as i32 });
            }
            ground::SHRINE if !cell.spent => {
                self.cells[seat as usize].spent = true;
                let mend = ((self.hero.cap as f32 * 0.3) * self.mantle.shrine_power).round() as i32;
                self.mend(mend.max(2));
                self.hero.vigor = self.hero.vigor_cap;
                self.flashes.push(Flash { kind: omen::MEND, at: seat, value: mend });
            }
            ground::GLYPH if !cell.spent => {
                self.cells[seat as usize].spent = true;
                self.read_glyph(seat);
            }
            _ => {}
        }
    }

    fn read_glyph(&mut self, seat: i32) {
        let flavour = self.drift.below(6);
        match flavour {
            0 => {
                self.mend(3);
                self.flashes.push(Flash { kind: omen::MEND, at: seat, value: 3 });
            }
            1 => {
                self.hero.ward += 3;
                self.flashes.push(Flash { kind: omen::WARD_UP, at: seat, value: 3 });
            }
            2 => {
                self.hero.vigor = (self.hero.vigor + 2).min(self.hero.vigor_cap);
            }
            3 => {
                for index in 0..self.brood.len() {
                    if self.brood[index].alive {
                        self.wound_beast(index, 1, false);
                    }
                }
            }
            4 => {
                for beast in self.brood.iter_mut() {
                    beast.drowse = beast.drowse.saturating_add(2);
                }
            }
            _ => {
                let bonus = 20 + self.drift.below(40);
                self.shards += bonus as u64;
                self.flashes.push(Flash { kind: omen::LOOT, at: seat, value: bonus as i32 });
            }
        }
        self.flashes.push(Flash { kind: omen::GLYPH_READ, at: seat, value: flavour as i32 });
    }

    fn twist(&mut self, seat: i32) -> bool {
        if seat < 0 || seat >= WARD_CELLS as i32 {
            return false;
        }
        if self.cells[seat as usize].ground != ground::MIRROR
            && self.cells[seat as usize].ground != ground::EMITTER
        {
            return false;
        }
        if gap(seat, self.hero.at) > 2 {
            return false;
        }
        self.cells[seat as usize].spin = (self.cells[seat as usize].spin + 1) & 3;
        true
    }

    // --- abilities ---------------------------------------------------------

    /// Spends an ability. The expedition owns cooldowns, so it checks them and
    /// then asks the room to resolve the effect.
    pub fn unleash(&mut self, power: u32, way: u8, toll: i32) -> bool {
        if self.resolved != 0 || self.hero.vigor < toll {
            return false;
        }
        self.flashes.clear();
        let landed = match power {
            knack::CHARGE => self.charge(way),
            knack::SWEEP => self.sweep(),
            knack::SHOCK => self.shock(),
            knack::BOLT => self.bolt(way),
            knack::BULWARK => self.bulwark(),
            _ => false,
        };
        if !landed {
            self.flashes.push(Flash { kind: omen::REFUSED, at: self.hero.at, value: 0 });
            return false;
        }
        self.hero.vigor -= toll;
        self.flashes.push(Flash { kind: omen::ABILITY, at: self.hero.at, value: power as i32 });
        self.close_turn();
        true
    }

    fn charge(&mut self, way: u8) -> bool {
        self.hero.face = way & 3;
        let mut here = self.hero.at;
        let mut travelled = 0;
        while travelled < self.mantle.dash_span {
            let Some(next) = nudge(here, way) else { break };
            if let Some(index) = self.beast_at(next) {
                let bite = 3 + self.mantle.bite_bonus;
                self.wound_beast(index, bite, true);
                self.heave(next, way, self.mantle.push_power);
                self.hero.at = here;
                return true;
            }
            if self.cells[next as usize].ground == ground::BLOCK {
                break;
            }
            if !self.walkable(next) {
                break;
            }
            here = next;
            travelled += 1;
        }
        if travelled == 0 {
            return false;
        }
        self.hero.at = here;
        self.tread(here);
        true
    }

    fn sweep(&mut self) -> bool {
        let mut hit = false;
        for way in 0..4u8 {
            let Some(seat) = nudge(self.hero.at, way) else { continue };
            if let Some(index) = self.beast_at(seat) {
                let bite = 3 + self.mantle.bite_bonus;
                self.wound_beast(index, bite, true);
                hit = true;
            }
        }
        hit
    }

    fn shock(&mut self) -> bool {
        let mut hit = false;
        for way in 0..4u8 {
            let Some(seat) = nudge(self.hero.at, way) else { continue };
            if self.beast_at(seat).is_some() {
                self.heave(seat, way, self.mantle.push_power + 1);
                hit = true;
            } else if self.cells[seat as usize].ground == ground::BLOCK {
                let _ = self.slide_cube(seat, way);
                hit = true;
            }
        }
        if hit {
            self.hero.ward += 1;
        }
        hit
    }

    fn bolt(&mut self, way: u8) -> bool {
        self.hero.face = way & 3;
        let mut here = self.hero.at;
        for _ in 0..self.mantle.bolt_span {
            let Some(next) = nudge(here, way) else { break };
            self.flashes.push(Flash { kind: omen::BEAM, at: next, value: 0 });
            if let Some(index) = self.beast_at(next) {
                let bite = 4 + self.mantle.bite_bonus;
                self.wound_beast(index, bite, true);
                return true;
            }
            if self.cells[next as usize].opaque() {
                return true;
            }
            here = next;
        }
        true
    }

    fn bulwark(&mut self) -> bool {
        self.hero.ward += 4;
        self.mend(2);
        self.flashes.push(Flash { kind: omen::WARD_UP, at: self.hero.at, value: 4 });
        true
    }

    // --- damage ------------------------------------------------------------

    fn wound_beast(&mut self, index: usize, bite: i32, may_crit: bool) {
        if index >= self.brood.len() || !self.brood[index].alive {
            return;
        }
        let mut blow = bite;
        let mut crit = false;
        if may_crit && self.drift.leans(self.mantle.crit_permille) {
            blow *= 2;
            crit = true;
        }
        let beast = &mut self.brood[index];
        let soaked = blow.saturating_sub(beast.ward).max(1);
        beast.hp -= soaked;
        let seat = beast.at;
        self.dealt = self.dealt.saturating_add(soaked as u64);
        if crit {
            self.flashes.push(Flash { kind: omen::CRIT, at: seat, value: soaked });
        }
        self.flashes.push(Flash { kind: omen::BEAST_HURT, at: seat, value: soaked });
        if self.brood[index].hp <= 0 {
            self.slay(index, false);
        }
    }

    fn slay(&mut self, index: usize, by_hazard: bool) {
        if !self.brood[index].alive {
            return;
        }
        let beast = self.brood[index];
        self.brood[index].alive = false;
        self.kills += 1;
        if beast.breed == brood::REVENANT {
            self.felled += 1;
        }
        if by_hazard {
            self.shoves += 1;
        }
        let spec = &BREEDS[(beast.breed as usize).min(brood::KINDS - 1)];
        let bounty = (spec.bounty as f32 * self.mantle.loot_scale).round() as u64;
        self.shards += bounty;
        self.hero.vigor = (self.hero.vigor + self.mantle.vigor_per_kill).min(self.hero.vigor_cap);
        if self.mantle.slay_bonus > 0 {
            self.mend(self.mantle.slay_bonus);
        }
        self.flashes.push(Flash { kind: omen::BEAST_DOWN, at: beast.at, value: beast.breed as i32 });
    }

    fn wound_hero(&mut self, bite: i32) {
        if bite <= 0 || self.resolved != 0 {
            return;
        }
        let mut left = bite;
        if self.hero.ward > 0 {
            let soaked = self.hero.ward.min(left);
            self.hero.ward -= soaked;
            left -= soaked;
        }
        if left > 0 {
            self.hero.hp -= left;
            self.taken += 1;
            self.flawless = false;
        }
        self.flashes.push(Flash { kind: omen::HERO_HURT, at: self.hero.at, value: bite });
        if self.hero.hp <= 0 {
            if self.hero.revives > 0 {
                self.hero.revives -= 1;
                self.hero.hp = (self.hero.cap / 2).max(1);
                self.hero.ward += 3;
                self.flashes.push(Flash { kind: omen::MEND, at: self.hero.at, value: self.hero.hp });
            } else {
                self.hero.hp = 0;
                self.resolved = 2;
            }
        }
    }

    fn mend(&mut self, amount: i32) {
        if amount <= 0 {
            return;
        }
        self.hero.hp = (self.hero.hp + amount).min(self.hero.cap);
    }

    /// Shoves a body along a direction, tile by tile, stopping at anything
    /// solid. A body shoved over a pit or onto armed spikes is simply gone.
    fn heave(&mut self, from: i32, way: u8, span: i32) {
        let Some(index) = self.beast_at(from) else { return };
        let mut here = from;
        for _ in 0..span.max(0) {
            let Some(next) = nudge(here, way) else { break };
            if self.body_at(next) {
                break;
            }
            let tile = self.cells[next as usize].ground;
            if tile == ground::PIT {
                self.brood[index].at = next;
                self.flashes.push(Flash { kind: omen::FELL, at: next, value: 0 });
                self.slay(index, true);
                return;
            }
            if !self.walkable(next) {
                break;
            }
            here = next;
        }
        if here != from {
            self.brood[index].at = here;
            self.shoves += 1;
            self.flashes.push(Flash { kind: omen::SHOVE, at: here, value: 0 });
            if self.cells[here as usize].ground == ground::SPIKES
                && self.cells[here as usize].fuse == 0
            {
                self.wound_beast(index, 3, false);
            }
        }
    }

    fn slide_cube(&mut self, cube: i32, way: u8) -> bool {
        let Some(behind) = nudge(cube, way) else { return false };
        if self.body_at(behind) || !self.cells[behind as usize].cube_room() {
            return false;
        }
        let landing = self.cells[behind as usize].ground;
        self.cells[cube as usize] = Cell::sand();
        if landing == ground::PIT {
            self.cells[behind as usize] = Cell::sand();
        } else {
            self.cells[behind as usize].ground = ground::BLOCK;
            if landing == ground::PLATE {
                self.cells[behind as usize].spin = 9;
            }
        }
        true
    }

    // --- the room's turn ---------------------------------------------------

    fn close_turn(&mut self) {
        if self.resolved != 0 {
            self.score_goal();
            return;
        }
        self.turn += 1;
        self.tick_hazards();
        if self.resolved == 0 {
            self.brood_turn();
        }
        if self.resolved == 0 {
            self.settle_plates();
            self.score_goal();
        }
    }

    fn tick_hazards(&mut self) {
        // Spikes: the fuse runs down, zero bites everything standing on it.
        for seat in 0..WARD_CELLS as i32 {
            if self.cells[seat as usize].ground != ground::SPIKES {
                continue;
            }
            let fuse = self.cells[seat as usize].fuse;
            if fuse > 0 {
                self.cells[seat as usize].fuse = fuse - 1;
                continue;
            }
            self.cells[seat as usize].fuse = 3;
            if self.hero.at == seat && !self.mantle.spike_proof {
                self.flashes.push(Flash { kind: omen::SPIKED, at: seat, value: 3 });
                self.wound_hero(3);
            }
            if let Some(index) = self.beast_at(seat) {
                if self.brood[index].breed != brood::HOPPER {
                    self.flashes.push(Flash { kind: omen::SPIKED, at: seat, value: 3 });
                    self.wound_beast(index, 3, false);
                }
            }
        }

        self.run_beams();
        self.rake_lanes();
        self.pull_vortices();
        self.work_vents();
    }

    /// Clears the glow, then traces every emitter through the mirrors. Lenses
    /// are the one hazard the player can aim, which is why mirrors are worth a
    /// whole turn to rotate.
    fn run_beams(&mut self) {
        for cell in self.cells.iter_mut() {
            cell.glow = 0;
        }
        let sources: Vec<(i32, u8)> = (0..WARD_CELLS as i32)
            .filter(|seat| self.cells[*seat as usize].ground == ground::EMITTER)
            .map(|seat| (seat, self.cells[seat as usize].spin))
            .collect();
        for (seat, spin) in sources {
            let mut here = seat;
            let mut way = spin & 3;
            for _ in 0..(WARD_CELLS * 2) {
                let Some(next) = nudge(here, way) else { break };
                let cell = self.cells[next as usize];
                if cell.opaque() {
                    break;
                }
                if cell.ground == ground::EMITTER {
                    break;
                }
                if cell.ground == ground::MIRROR {
                    way = bounce(way, cell.spin);
                    here = next;
                    continue;
                }
                self.cells[next as usize].glow = 1;
                if self.hero.at == next && !self.mantle.beam_proof {
                    self.flashes.push(Flash { kind: omen::BEAM, at: next, value: 2 });
                    self.wound_hero(2);
                }
                if let Some(index) = self.beast_at(next) {
                    self.flashes.push(Flash { kind: omen::BEAM, at: next, value: 2 });
                    self.wound_beast(index, 2, false);
                }
                here = next;
            }
        }
    }

    /// Dart engines. Every engine counts down in the open, then rakes its lane
    /// until something solid eats the volley: stone, a gate, or a cube the
    /// player had the sense to shove into the way.
    fn rake_lanes(&mut self) {
        let engines: Vec<(i32, u8)> = (0..WARD_CELLS as i32)
            .filter(|seat| self.cells[*seat as usize].ground == ground::DART)
            .map(|seat| (seat, self.cells[seat as usize].spin & 3))
            .collect();
        let sting = 2 + (self.brief.region / 3) as i32;
        for (seat, way) in engines {
            if self.cells[seat as usize].fuse > 0 {
                self.cells[seat as usize].fuse -= 1;
                continue;
            }
            self.cells[seat as usize].fuse = DART_CADENCE;
            let mut here = seat;
            for _ in 0..WARD_CELLS {
                let Some(next) = nudge(here, way) else { break };
                if self.cells[next as usize].opaque() {
                    break;
                }
                self.flashes.push(Flash { kind: omen::BEAM, at: next, value: sting });
                if self.hero.at == next {
                    self.wound_hero(sting);
                }
                if let Some(index) = self.beast_at(next) {
                    self.wound_beast(index, sting, false);
                }
                if self.resolved != 0 {
                    return;
                }
                here = next;
            }
        }
    }

    fn pull_vortices(&mut self) {
        let eyes: Vec<i32> = (0..WARD_CELLS as i32)
            .filter(|seat| self.cells[*seat as usize].ground == ground::VORTEX)
            .collect();
        for eye in eyes {
            for way in 0..4u8 {
                let Some(edge) = nudge(eye, way) else { continue };
                let inward = (way + 2) & 3;
                if self.hero.at == edge {
                    if self.walkable(eye) && !self.body_at(eye) {
                        self.hero.at = eye;
                        self.flashes.push(Flash { kind: omen::VORTEX_PULL, at: eye, value: 0 });
                    }
                } else if self.beast_at(edge).is_some() {
                    self.heave(edge, inward, 1);
                }
            }
        }
    }

    fn work_vents(&mut self) {
        let vents: Vec<i32> = (0..WARD_CELLS as i32)
            .filter(|seat| self.cells[*seat as usize].ground == ground::VENT)
            .collect();
        let living = self.brood.iter().filter(|beast| beast.alive).count();
        for vent in vents {
            if self.cells[vent as usize].fuse > 0 {
                self.cells[vent as usize].fuse -= 1;
                continue;
            }
            self.cells[vent as usize].fuse = 3;
            if living >= 9 {
                continue;
            }
            for way in 0..4u8 {
                let Some(seat) = nudge(vent, way) else { continue };
                if self.walkable(seat) && !self.body_at(seat) {
                    self.push_beast(brood::HUSK, seat);
                    let fresh = self.brood.len() - 1;
                    self.declare(fresh);
                    self.flashes.push(Flash { kind: omen::HATCHED, at: seat, value: 0 });
                    break;
                }
            }
        }
    }

    // --- the brood ---------------------------------------------------------

    fn brood_turn(&mut self) {
        let count = self.brood.len();
        for index in 0..count {
            if self.resolved != 0 {
                break;
            }
            if !self.brood[index].alive {
                continue;
            }
            if self.brood[index].drowse > 0 {
                self.brood[index].drowse -= 1;
                self.brood[index].plan = plan::HOLD;
                continue;
            }
            let spec = &BREEDS[(self.brood[index].breed as usize).min(brood::KINDS - 1)];
            let pace = spec.pace.max(1);
            self.brood[index].beat = self.brood[index].beat.wrapping_add(1);
            if self.brood[index].beat % pace != 0 {
                continue;
            }
            self.carry_out(index);
        }
        for index in 0..self.brood.len() {
            if self.brood[index].alive && self.brood[index].drowse == 0 {
                self.declare(index);
            }
        }
    }

    /// Executes exactly what the beast announced last turn. If the hero has
    /// moved out of the way, the blow lands on empty sand — dodging is the
    /// whole point.
    fn carry_out(&mut self, index: usize) {
        let beast = self.brood[index];
        match beast.plan {
            plan::STEP => {
                let target = beast.plan_at;
                if self.walkable(target) && !self.body_at(target) {
                    self.brood[index].at = target;
                    if self.cells[target as usize].ground == ground::SPIKES
                        && self.cells[target as usize].fuse == 0
                        && beast.breed != brood::HOPPER
                    {
                        self.wound_beast(index, 3, false);
                    }
                }
            }
            plan::STRIKE => {
                let spec = &BREEDS[(beast.breed as usize).min(brood::KINDS - 1)];
                let bite = spec.bite;
                if self.hero.at == beast.plan_at {
                    self.wound_hero(bite);
                    if self.mantle.thorns > 0 {
                        self.wound_beast(index, self.mantle.thorns, false);
                    }
                }
            }
            plan::SHOOT => {
                let spec = &BREEDS[(beast.breed as usize).min(brood::KINDS - 1)];
                let bite = spec.bite;
                let way = toward(beast.at, beast.plan_at);
                let mut here = beast.at;
                for _ in 0..spec.reach {
                    let Some(next) = nudge(here, way) else { break };
                    self.flashes.push(Flash { kind: omen::BEAM, at: next, value: bite });
                    if self.hero.at == next {
                        self.wound_hero(bite);
                        break;
                    }
                    if self.cells[next as usize].opaque() {
                        break;
                    }
                    here = next;
                }
            }
            plan::SWEEP => {
                let spec = &BREEDS[(beast.breed as usize).min(brood::KINDS - 1)];
                let bite = spec.bite;
                let hero_row = row(self.hero.at) == row(beast.at);
                let hero_col = column(self.hero.at) == column(beast.at);
                for seat in 0..WARD_CELLS as i32 {
                    if row(seat) == row(beast.at) || column(seat) == column(beast.at) {
                        self.flashes.push(Flash { kind: omen::BEAM, at: seat, value: bite });
                    }
                }
                if hero_row || hero_col {
                    self.wound_hero(bite);
                }
            }
            plan::HATCH => {
                let seat = beast.plan_at;
                if self.walkable(seat) && !self.body_at(seat) {
                    self.push_beast(brood::HUSK, seat);
                    let fresh = self.brood.len() - 1;
                    self.declare(fresh);
                    self.flashes.push(Flash { kind: omen::HATCHED, at: seat, value: 0 });
                }
            }
            plan::LUNGE => {
                let way = toward(beast.at, beast.plan_at);
                let spec = &BREEDS[(beast.breed as usize).min(brood::KINDS - 1)];
                let bite = spec.bite;
                let mut here = beast.at;
                for _ in 0..3 {
                    let Some(next) = nudge(here, way) else { break };
                    if self.hero.at == next {
                        self.wound_hero(bite);
                        break;
                    }
                    if !self.walkable(next) || self.body_at(next) {
                        break;
                    }
                    here = next;
                }
                if here != beast.at {
                    self.brood[index].at = here;
                }
            }
            _ => {}
        }
    }

    /// Chooses and publishes next turn's move. Everything a beast will do is
    /// visible on the board before the player commits.
    fn declare(&mut self, index: usize) {
        if index >= self.brood.len() || !self.brood[index].alive {
            return;
        }
        let beast = self.brood[index];
        let hero = self.hero.at;
        let field = self.tide(hero);
        let distance = gap(beast.at, hero);

        let (plan_kind, seat) = match beast.breed {
            brood::SPITTER => {
                if lane_clear(self, beast.at, hero, BREEDS[2].reach) {
                    (plan::SHOOT, hero)
                } else {
                    self.stalk(beast.at, &field, true)
                }
            }
            brood::SENTINEL => {
                if beast.beat % 2 == 0 {
                    (plan::SWEEP, beast.at)
                } else {
                    (plan::HOLD, beast.at)
                }
            }
            brood::BROODER => {
                if distance <= 2 {
                    self.stalk(beast.at, &field, false)
                } else if beast.beat % 3 == 0 {
                    let nest = self.open_neighbour(beast.at);
                    match nest {
                        Some(seat) => (plan::HATCH, seat),
                        None => (plan::HOLD, beast.at),
                    }
                } else {
                    self.stalk(beast.at, &field, true)
                }
            }
            brood::HOPPER => {
                if distance == 1 {
                    (plan::STRIKE, hero)
                } else {
                    match self.hop(beast.at, hero) {
                        Some(seat) => (plan::STEP, seat),
                        None => (plan::HOLD, beast.at),
                    }
                }
            }
            brood::JACKAL => {
                if distance == 1 {
                    (plan::STRIKE, hero)
                } else if straight(beast.at, hero) && distance <= 3 {
                    (plan::LUNGE, hero)
                } else {
                    self.stalk(beast.at, &field, false)
                }
            }
            brood::REVENANT => match beast.beat % 3 {
                0 => {
                    let nest = self.open_neighbour(beast.at);
                    match nest {
                        Some(seat) => (plan::HATCH, seat),
                        None => (plan::SWEEP, beast.at),
                    }
                }
                1 => (plan::SWEEP, beast.at),
                _ => {
                    if distance == 1 {
                        (plan::STRIKE, hero)
                    } else {
                        (plan::LUNGE, hero)
                    }
                }
            },
            _ => {
                if distance == 1 {
                    (plan::STRIKE, hero)
                } else {
                    self.stalk(beast.at, &field, false)
                }
            }
        };

        self.brood[index].plan = plan_kind;
        self.brood[index].plan_at = seat;
    }

    /// One step along the distance field, or away from it for skittish breeds.
    fn stalk(&self, from: i32, field: &[i32; WARD_CELLS], shy: bool) -> (u8, i32) {
        let here = field[from as usize];
        let mut best = from;
        let mut mark = if shy { here } else { i32::MAX };
        for way in 0..4u8 {
            let Some(next) = nudge(from, way) else { continue };
            if !self.walkable(next) || self.body_at(next) {
                continue;
            }
            let score = field[next as usize];
            if score < 0 {
                continue;
            }
            let better = if shy { score > mark } else { score < mark };
            if better {
                mark = score;
                best = next;
            }
        }
        if best == from {
            (plan::HOLD, from)
        } else {
            (plan::STEP, best)
        }
    }

    fn hop(&self, from: i32, hero: i32) -> Option<i32> {
        let mut best: Option<(i32, i32)> = None;
        for (dx, dy) in DIAGONALS {
            let Some(seat) = seat_of(column(from) + dx, row(from) + dy) else { continue };
            if !self.walkable(seat) || self.body_at(seat) {
                continue;
            }
            let score = gap(seat, hero);
            if best.map(|(mark, _)| score < mark).unwrap_or(true) {
                best = Some((score, seat));
            }
        }
        best.map(|(_, seat)| seat)
    }

    fn open_neighbour(&self, from: i32) -> Option<i32> {
        for way in 0..4u8 {
            let Some(seat) = nudge(from, way) else { continue };
            if self.walkable(seat) && !self.body_at(seat) {
                return Some(seat);
            }
        }
        None
    }

    fn declare_all(&mut self) {
        for index in 0..self.brood.len() {
            self.declare(index);
        }
    }

    // --- goals -------------------------------------------------------------

    fn settle_plates(&mut self) {
        if self.plates_total == 0 {
            return;
        }
        let mut held = 0;
        for seat in 0..WARD_CELLS as i32 {
            let cell = self.cells[seat as usize];
            let is_plate = cell.ground == ground::PLATE
                || (cell.ground == ground::BLOCK && cell.spin == 9);
            if !is_plate {
                continue;
            }
            let weighted = (cell.ground == ground::BLOCK && cell.spin == 9)
                || self.hero.at == seat
                || self.beast_at(seat).is_some();
            if weighted {
                held += 1;
            }
        }
        let was = self.gates_open;
        self.plates_held = held;
        self.gates_open = held >= self.plates_total;
        if self.gates_open && !was {
            self.flashes.push(Flash { kind: omen::GATE_OPEN, at: self.hero.at, value: 0 });
        }
    }

    fn score_goal(&mut self) {
        if self.resolved != 0 {
            return;
        }
        let standing = self.brood.iter().filter(|beast| beast.alive).count();
        let boss_down = !self
            .brood
            .iter()
            .any(|beast| beast.alive && beast.breed == brood::REVENANT);
        let met = match self.brief.goal {
            goal::CULL => standing == 0,
            goal::FLEE => true,
            goal::ENDURE => self.turn >= self.brief.turn_cap,
            goal::PRESS => self.gates_open,
            goal::HOARD => self.chests >= chest_quota(self.brief.goal, self.mantle.extra_chest),
            goal::CROWN => boss_down,
            _ => standing == 0,
        };
        if met && !self.stair_open {
            self.stair_open = true;
            self.flashes.push(Flash { kind: omen::STAIR_LIT, at: self.stair_seat(), value: 0 });
        }
    }

    pub fn stair_seat(&self) -> i32 {
        (0..WARD_CELLS as i32)
            .find(|seat| self.cells[*seat as usize].ground == ground::STAIR)
            .unwrap_or(0)
    }

    /// Score for the room, used for the result card and the payout.
    pub fn mastery(&self) -> u32 {
        let mut stars = 1;
        if self.flawless {
            stars += 1;
        }
        if self.chests > 0 && self.kills >= self.brief.foes {
            stars += 1;
        }
        stars.min(3)
    }

    // --- transport ---------------------------------------------------------

    pub fn inscribe(&self, pen: &mut Scribe) {
        pen.byte(self.brief.goal)
            .quad(self.turn)
            .quad(self.brief.turn_cap)
            .byte(self.resolved)
            .flag(self.stair_open)
            .flag(self.gates_open)
            .quad(self.plates_held)
            .quad(self.plates_total)
            .quad(self.kills)
            .quad(self.chests)
            .octet(self.shards)
            .octet(self.resin)
            .flag(self.flawless)
            .quad(self.mastery());

        pen.signed(self.hero.at)
            .signed(self.hero.hp)
            .signed(self.hero.cap)
            .signed(self.hero.ward)
            .signed(self.hero.vigor)
            .signed(self.hero.vigor_cap)
            .byte(self.hero.face)
            .quad(self.hero.revives);

        pen.tally(WARD_CELLS);
        for cell in self.cells.iter() {
            let bared = self.mantle.trap_sight || cell.ground != ground::SPIKES;
            pen.byte(cell.ground)
                .byte(cell.spin)
                .byte(if bared { cell.fuse } else { 9 })
                .flag(cell.spent)
                .byte(cell.glow);
        }

        let living: Vec<&Beast> = self.brood.iter().filter(|beast| beast.alive).collect();
        pen.tally(living.len());
        for beast in living {
            pen.byte(beast.breed)
                .signed(beast.at)
                .signed(beast.hp)
                .signed(beast.cap)
                .signed(beast.ward)
                .byte(beast.plan)
                .signed(beast.plan_at)
                .byte(beast.drowse);
        }

        pen.tally(self.flashes.len());
        for flash in self.flashes.iter() {
            pen.byte(flash.kind).signed(flash.at).signed(flash.value);
        }
    }
}

/// Mirror reflection. Even spins are "/", odd are "\".
fn bounce(way: u8, spin: u8) -> u8 {
    let slash = spin % 2 == 0;
    match (way & 3, slash) {
        (0, true) => 1,
        (1, true) => 0,
        (2, true) => 3,
        (3, true) => 2,
        (0, false) => 3,
        (3, false) => 0,
        (2, false) => 1,
        _ => 2,
    }
}

fn straight(from: i32, to: i32) -> bool {
    row(from) == row(to) || column(from) == column(to)
}

fn toward(from: i32, to: i32) -> u8 {
    if row(from) == row(to) {
        if column(to) > column(from) {
            1
        } else {
            3
        }
    } else if row(to) > row(from) {
        2
    } else {
        0
    }
}

fn lane_clear(ward: &Ward, from: i32, to: i32, reach: i32) -> bool {
    if !straight(from, to) || gap(from, to) > reach || from == to {
        return false;
    }
    let way = toward(from, to);
    let mut here = from;
    loop {
        let Some(next) = nudge(here, way) else { return false };
        if next == to {
            return true;
        }
        if ward.cells[next as usize].opaque() {
            return false;
        }
        here = next;
    }
}

fn chest_quota(kind: u8, extra: u32) -> u32 {
    if kind == goal::HOARD {
        3 + extra
    } else {
        1
    }
}

/// Which breeds a region is allowed to field. New families arrive one region at
/// a time so the player always has something fresh to read.
pub fn breed_pool(region: u32, boss: bool) -> Vec<u8> {
    // The first region already fields three families: a chamber with one kind
    // of enemy in it is a chore, not a fight.
    let mut pool = vec![brood::HUSK, brood::JACKAL, brood::SPITTER];
    if region >= 1 {
        pool.push(brood::HOPPER);
    }
    if region >= 2 {
        pool.push(brood::WARDEN);
    }
    if region >= 3 {
        pool.push(brood::BROODER);
    }
    if region >= 4 {
        pool.push(brood::SENTINEL);
        pool.push(brood::WARDEN);
    }
    if region >= 5 {
        pool.push(brood::BROODER);
        pool.push(brood::SENTINEL);
    }
    if boss {
        pool.push(brood::WARDEN);
    }
    pool
}
