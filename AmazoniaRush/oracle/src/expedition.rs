//! An expedition: one descent through a branching temple map. The hero's
//! wounds carry from room to room, the map forks so two runs never read the
//! same, and a death ends the descent while leaving the meta progress alone.
//!
//! The chamber in `delve` knows nothing about any of this. It is handed a
//! brief, it reports a result, and this module decides what that costs.

use crate::almanac::{open_codex, strike_medals};
use crate::atlas::*;
use crate::codec::Scribe;
use crate::arena::Arena;
use crate::delve::{brood, goal as room_goal, Brief, Mantle};
use crate::entropy::{braid_seed, Drift};
use crate::ledger::{purse, Profile};

/// Where the expedition currently sits. The presentation layer draws one of
/// these five faces and nothing else.
pub mod stride {
    /// A chamber is live and waiting for the hero's next action.
    pub const FIGHT: u8 = 0;
    /// Chamber finished, the result card is up.
    pub const CARD: u8 = 1;
    /// Pick one of three blessings.
    pub const CACHE: u8 = 2;
    /// Pick which way to go on the branch map.
    pub const FORK: u8 = 3;
    /// A quiet room: rest, or trade with the caravan.
    pub const HAVEN: u8 = 4;
    /// The whole descent is done.
    pub const CROWNED: u8 = 5;
    /// The hero fell.
    pub const FALLEN: u8 = 6;
}

/// Room shapes as they sit on the branch map.
pub mod lair {
    pub const SKIRMISH: u8 = 0;
    pub const ELITE: u8 = 1;
    pub const SNARE: u8 = 2;
    pub const TROVE: u8 = 3;
    pub const SWARM: u8 = 4;
    pub const SIEGE: u8 = 5;
    pub const CAMP: u8 = 6;
    pub const TRADER: u8 = 7;
    pub const CROWN: u8 = 8;

    pub const KINDS: usize = 9;
}

/// What a trader sells, paid for out of the shards the hero is carrying right
/// now. Spending here means banking less at the end: that is the whole choice.
pub mod ware {
    pub const POULTICE: u32 = 0;
    pub const PLATING: u32 = 1;
    pub const VIGOUR: u32 = 2;
    pub const WHETSTONE: u32 = 3;
    pub const LANTERN: u32 = 4;
    pub const ANKH: u32 = 5;
    pub const KEG: u32 = 6;
    pub const LOTUS: u32 = 7;
}

pub const LANES: usize = 3;

#[derive(Clone, Copy, Default)]
pub struct Spoils {
    pub shards: u64,
    pub cores: u64,
    pub resin: u64,
    pub seals: u64,
    pub light: u64,
    pub relic: i32,
    pub medals: u32,
}

/// One slot on the branch map.
#[derive(Clone, Copy)]
pub struct Stop {
    pub kind: u8,
    pub real: bool,
    pub done: bool,
}

pub struct Delve {
    pub seed: u64,
    pub region: u32,
    pub node: u32,
    pub rows: u32,
    pub depth: u32,
    pub lane: u32,
    pub map: Vec<Stop>,
    pub forks: Vec<u32>,
    pub stride: u8,
    /// The chamber being fought in, in open ground.
    pub pit: Arena,
    pub boons: Vec<u32>,
    pub cache: Vec<u32>,
    pub wares: Vec<u32>,
    pub rest: [u32; POWER_SLOTS],
    /// The jar is not one of the seats the skill tree doles out: it is hers
    /// from the entrance, so it keeps its own clock.
    pub brew_rest: u32,
    pub spoils: Spoils,
    pub hp: i32,
    pub hp_cap: i32,
    pub vigor: i32,
    pub vigor_cap: i32,
    pub rooms_cleared: u32,
    pub best_mastery: u32,
    pub last_mastery: u32,
    pub last_shards: u64,
    pub flawless_run: bool,
    /// Bonuses bought mid-run from a trader. Separate from the profile so they
    /// evaporate when the expedition ends.
    pub bought_hp: i32,
    pub bought_ward: i32,
    pub bought_vigor: i32,
    pub bought_bite: i32,
    pub bought_chest: u32,
    pub bought_revive: u32,
}

impl Delve {
    pub fn open(profile: &Profile, region: u32, node: u32) -> Self {
        let region_index = (region as usize).min(REGION_COUNT - 1);
        let spec = &REGIONS[region_index];
        let keystone = node as usize == NODES_PER_REGION - 1;
        let rows = spec.rooms_open + spec.rooms_bite * (node / 4) + u32::from(keystone);
        let seed = braid_seed(&[
            region as u64,
            node as u64,
            profile.reawakenings as u64,
            profile.stats[0],
            0x5D1A_7F03_B2C6_9E48,
        ]);

        let mut shell = Delve {
            seed,
            region,
            node,
            rows: rows.max(3),
            depth: 0,
            lane: 1,
            map: Vec::new(),
            forks: Vec::new(),
            stride: stride::FIGHT,
            pit: Arena::carve(
                Brief {
                    seed,
                    region,
                    depth: 0,
                    goal: room_goal::CULL,
                    foes: 1,
                    features: 0,
                    turn_cap: 0,
                    boss: false,
                },
                Mantle::plain(),
            ),
            boons: Vec::new(),
            cache: Vec::new(),
            wares: Vec::new(),
            rest: [0; POWER_SLOTS],
            brew_rest: 0,
            spoils: Spoils { relic: -1, ..Spoils::default() },
            hp: 1,
            hp_cap: 1,
            vigor: 0,
            vigor_cap: 1,
            rooms_cleared: 0,
            best_mastery: 0,
            last_mastery: 0,
            last_shards: 0,
            flawless_run: true,
            bought_hp: 0,
            bought_ward: 0,
            bought_vigor: 0,
            bought_bite: 0,
            bought_chest: 0,
            bought_revive: 0,
        };

        shell.draw_map(profile);
        let mantle = shell.mantle(profile);
        shell.hp_cap = base_vitality(profile) + mantle.hp_bonus;
        shell.hp = shell.hp_cap;
        shell.vigor_cap = mantle.vigor_cap;
        shell.vigor = mantle.vigor_open.min(mantle.vigor_cap);
        shell.raise_room(profile);
        shell
    }

    // --- the branch map ----------------------------------------------------

    /// Lays out the whole descent up front: the first and last rows are single
    /// rooms, everything between forks two or three ways.
    fn draw_map(&mut self, profile: &Profile) {
        let region_index = (self.region as usize).min(REGION_COUNT - 1);
        let allowed = REGIONS[region_index].haunts;
        let mut drift = Drift::seeded(braid_seed(&[self.seed, 0x9A41_7C03_DD15_2E6B]));
        let mut pool: Vec<u8> = Vec::new();
        for (bit, kind) in [
            (haunt::SKIRMISH, lair::SKIRMISH),
            (haunt::ELITE, lair::ELITE),
            (haunt::SNARE, lair::SNARE),
            (haunt::TROVE, lair::TROVE),
            (haunt::SWARM, lair::SWARM),
            (haunt::SIEGE, lair::SIEGE),
        ] {
            if allowed & bit != 0 {
                pool.push(kind);
            }
        }
        if pool.is_empty() {
            pool.push(lair::SKIRMISH);
        }

        self.map = vec![Stop { kind: lair::SKIRMISH, real: false, done: false }; (self.rows as usize) * LANES];
        // Entrance.
        self.write_stop(0, 1, lair::SKIRMISH, true);
        // The crown sits alone at the bottom of the descent.
        let last = self.rows - 1;
        self.write_stop(last, 1, lair::CROWN, true);

        let mut rested = false;
        for row in 1..last {
            let width = if row == last - 1 { 2 } else { 2 + usize::from(drift.leans(420)) };
            let mut lanes: Vec<u32> = (0..LANES as u32).collect();
            drift.jumble(&mut lanes);
            lanes.truncate(width.min(LANES));
            lanes.sort();
            // Every other row offers one lane where nothing wants to kill you:
            // a camp to mend at, or a trader to spend the run's shards with.
            let breather = if rested { lair::TRADER } else { lair::CAMP };
            let bit = if breather == lair::CAMP { haunt::CAMP } else { haunt::TRADER };
            let give_breather = row % 2 == 0 && allowed & bit != 0;
            if give_breather {
                rested = !rested;
            }
            for (slot, lane) in lanes.iter().copied().enumerate() {
                let kind = if give_breather && slot == 0 {
                    breather
                } else {
                    drift.pick(&pool).unwrap_or(lair::SKIRMISH)
                };
                self.write_stop(row, lane, kind, true);
            }
        }
        let _ = profile;
    }

    fn write_stop(&mut self, row: u32, lane: u32, kind: u8, real: bool) {
        let at = row as usize * LANES + lane as usize;
        if let Some(slot) = self.map.get_mut(at) {
            *slot = Stop { kind, real, done: false };
        }
    }

    pub fn stop_at(&self, row: u32, lane: u32) -> Stop {
        self.map
            .get(row as usize * LANES + lane as usize)
            .copied()
            .unwrap_or(Stop { kind: lair::SKIRMISH, real: false, done: false })
    }

    /// Reachable lanes on the next row: straight on, or one step sideways.
    fn open_forks(&self) -> Vec<u32> {
        let next = self.depth + 1;
        if next >= self.rows {
            return Vec::new();
        }
        let mut found = Vec::new();
        for lane in 0..LANES as u32 {
            let reachable = (lane as i32 - self.lane as i32).abs() <= 1;
            if reachable && self.stop_at(next, lane).real {
                found.push(lane);
            }
        }
        if found.is_empty() {
            for lane in 0..LANES as u32 {
                if self.stop_at(next, lane).real {
                    found.push(lane);
                }
            }
        }
        found
    }

    // --- room briefs -------------------------------------------------------

    fn mantle(&self, profile: &Profile) -> Mantle {
        let boss = self.stop_at(self.depth, self.lane).kind == lair::CROWN;
        let mut sheet = profile.outfit(&self.boons, self.depth, boss);
        sheet.hp_bonus += self.bought_hp;
        sheet.ward_open += self.bought_ward;
        sheet.vigor_cap += self.bought_vigor;
        sheet.bite_bonus += self.bought_bite;
        sheet.extra_chest += self.bought_chest;
        sheet.revives += self.bought_revive;
        // Opening mercy: the first few nodes a player ever plays are softer,
        // and it fades out once the seals start coming in.
        let won = profile.total_seals();
        if won == 0 {
            sheet.mercy += 1;
            sheet.trap_sight = true;
        }
        sheet
    }

    fn brief_for(&self, depth: u32) -> Brief {
        let region_index = (self.region as usize).min(REGION_COUNT - 1);
        let spec = &REGIONS[region_index];
        let kind = self.stop_at(depth, self.lane).kind;
        let rung = self.node / 3 + depth;
        let boss = kind == lair::CROWN;
        let foes = match kind {
            lair::CROWN => 2 + rung / 3,
            lair::ELITE => spec.foes_open + spec.foes_bite * rung / 2 + 2,
            lair::TROVE => (spec.foes_open + rung / 3).max(1),
            lair::SNARE => (spec.foes_open + rung / 4).max(1),
            lair::SWARM => 2,
            lair::SIEGE => spec.foes_open,
            _ => spec.foes_open + spec.foes_bite * rung / 2,
        };
        let goal = match kind {
            lair::SNARE => room_goal::PRESS,
            lair::TROVE => room_goal::HOARD,
            lair::SWARM => room_goal::FLEE,
            lair::SIEGE => room_goal::ENDURE,
            lair::CROWN => room_goal::CROWN,
            _ => room_goal::CULL,
        };
        Brief {
            seed: braid_seed(&[self.seed, depth as u64, self.lane as u64, 0x3C9E_1D55_A074_26BF]),
            region: self.region,
            depth,
            goal,
            foes: foes.min(9),
            features: spec.features,
            turn_cap: spec.endure_turns + depth,
            boss,
        }
    }

    fn raise_room(&mut self, profile: &Profile) {
        let kind = self.stop_at(self.depth, self.lane).kind;
        if kind == lair::CAMP || kind == lair::TRADER {
            self.enter_haven(profile, kind);
            return;
        }
        let brief = self.brief_for(self.depth);
        let mantle = self.mantle(profile);
        self.hp_cap = base_vitality(profile) + mantle.hp_bonus;
        self.hp = self.hp.min(self.hp_cap).max(1);
        if mantle.mend_per_room > 0 {
            self.hp = (self.hp + mantle.mend_per_room).min(self.hp_cap);
        }
        self.vigor_cap = mantle.vigor_cap;
        self.vigor = (self.vigor + 1).min(self.vigor_cap);
        self.pit = Arena::carve(brief, mantle);
        self.pit.equip_hero(self.hp, self.vigor, self.vigor_cap);
        self.pit.hero.cap = self.hp_cap;
        self.pit.hero.hp = self.hp;
        self.rest = [0; POWER_SLOTS];
        self.brew_rest = 0;
        self.stride = stride::FIGHT;
    }

    /// A quiet stop. No chamber is raised: the card does the talking.
    fn enter_haven(&mut self, profile: &Profile, kind: u8) {
        self.stride = stride::HAVEN;
        self.wares.clear();
        if kind == lair::CAMP {
            let mend = (self.hp_cap as f32 * 0.4).round() as i32;
            self.hp = (self.hp + mend.max(3)).min(self.hp_cap);
            self.vigor = self.vigor_cap;
        } else {
            let mut drift = Drift::seeded(braid_seed(&[
                self.seed,
                self.depth as u64,
                0x4F27_B091_CA63_18DE,
            ]));
            let mut pool: Vec<u32> = (0..WARE_COUNT as u32).collect();
            drift.jumble(&mut pool);
            self.wares = pool.into_iter().take(3).collect();
        }
        let _ = profile;
    }

    // --- the player's hands ------------------------------------------------

    /// One frame of the fight. `push` is the thumbstick, each axis in
    /// -1000..1000, `span` the milliseconds of real time the frame covered.
    pub fn steer(&mut self, profile: &mut Profile, push_x: i32, push_y: i32, span: u32) -> bool {
        if self.stride != stride::FIGHT {
            return false;
        }
        let beats = self.pit.advance(push_x, push_y, span);
        let bled = span.min(400);
        for slot in 0..POWER_SLOTS {
            self.rest[slot] = self.rest[slot].saturating_sub(bled);
        }
        self.brew_rest = self.brew_rest.saturating_sub(bled);
        self.settle_frame(profile, beats);
        true
    }

    /// Spends a knack. `aim` is a direction in -1000..1000 per axis; zero means
    /// "wherever the hero is already facing".
    pub fn unleash(&mut self, profile: &mut Profile, slot: usize, aim_x: i32, aim_y: i32) -> bool {
        if self.stride != stride::FIGHT {
            return false;
        }
        // The seat past the last one the tree granted is always the jar.
        if slot == profile.power_seats() {
            return self.drink(profile, aim_x, aim_y);
        }
        if slot >= profile.power_seats() {
            return false;
        }
        if self.rest[slot] > 0 {
            return false;
        }
        let power = profile.powers.get(slot).copied().unwrap_or(-1);
        if power < 0 {
            return false;
        }
        let index = power as usize;
        if !profile.power_unlocked(index) {
            return false;
        }
        let toll = POWER_TOLL.get(index).copied().unwrap_or(1);
        if !self.pit.cast(power as u32, aim_x, aim_y, toll) {
            return false;
        }
        let cool = POWER_REST.get(index).copied().unwrap_or(4) as f32 * 420.0;
        self.rest[slot] = (cool * self.pit.mantle.cool_scale).round().max(300.0) as u32;
        profile.stats[8] = profile.stats[8].saturating_add(1);
        self.settle_frame(profile, 0);
        true
    }

    /// Temple beer, which nobody has to earn and nobody can trade away.
    fn drink(&mut self, profile: &mut Profile, aim_x: i32, aim_y: i32) -> bool {
        if self.brew_rest > 0 {
            return false;
        }
        let toll = POWER_TOLL.get(BREW_POWER).copied().unwrap_or(2);
        if !self.pit.cast(BREW_POWER as u32, aim_x, aim_y, toll) {
            return false;
        }
        self.brew_rest = self.rest_span(BREW_POWER);
        profile.stats[8] = profile.stats[8].saturating_add(1);
        profile.stats[16] = profile.stats[16].saturating_add(1);
        self.settle_frame(profile, 0);
        true
    }

    /// How long a knack rests, in milliseconds, so the dial on screen has
    /// something to fill against.
    pub fn rest_span(&self, power: usize) -> u32 {
        let cool = POWER_REST.get(power).copied().unwrap_or(4) as f32 * 420.0;
        (cool * self.pit.mantle.cool_scale).round().max(300.0) as u32
    }

    fn settle_frame(&mut self, profile: &mut Profile, beats: u32) {
        if beats > 0 {
            profile.stats[13] = profile.stats[13].saturating_add(beats as u64);
        }
        self.hp = self.pit.hero.hp;
        self.vigor = self.pit.hero.focus;
        if self.pit.resolved == 1 {
            self.bank_room(profile);
        } else if self.pit.resolved == 2 {
            self.flawless_run = false;
            self.stride = stride::FALLEN;
            self.fold_records(profile);
        }
    }

    // --- scoring -----------------------------------------------------------

    fn bank_room(&mut self, profile: &mut Profile) {
        let region_index = (self.region as usize).min(REGION_COUNT - 1);
        let spec = &REGIONS[region_index];
        let mastery = self.pit.mastery();
        self.last_mastery = mastery;
        self.best_mastery = self.best_mastery.max(mastery);
        self.rooms_cleared += 1;
        if !self.pit.flawless {
            self.flawless_run = false;
        }

        let kind = self.stop_at(self.depth, self.lane).kind;
        let bonus = match kind {
            lair::ELITE => 1.6,
            lair::CROWN => 2.4,
            _ => 1.0,
        };
        let raw = self.pit.shards as f32 + spec.shard_pay as f32 * (1.0 + self.depth as f32 * 0.2);
        let shards = (raw * bonus * profile.shard_scale()).round() as u64;
        let resin = ((self.pit.resin + spec.resin_pay as u64 / 2 + mastery as u64) as f32
            * profile.resin_scale())
        .round() as u64;
        let light = ((60 + self.depth * 40 + self.pit.kills * 12) as f32
            * self.pit.mantle.light_scale)
            .round() as u64;

        let mut drift = Drift::seeded(braid_seed(&[
            self.seed,
            self.depth as u64,
            self.pit.dealt,
            profile.stats[0],
        ]));
        let cores = u64::from(drift.leans(profile.core_odds(region_index)));
        let seals = u64::from(drift.leans(profile.seal_odds(region_index)));

        self.last_shards = shards;
        self.spoils.shards += shards;
        self.spoils.resin += resin;
        self.spoils.light += light;
        self.spoils.cores += cores;
        self.spoils.seals += seals;

        profile.stats[0] = profile.stats[0].saturating_add(1);
        profile.stats[1] = profile.stats[1].saturating_add(self.pit.kills as u64);
        profile.stats[2] = profile.stats[2].saturating_add(self.pit.taken as u64);
        profile.stats[3] = profile.stats[3].max(self.rooms_cleared as u64);
        profile.stats[4] = profile.stats[4].max(shards);
        profile.stats[5] = profile.stats[5].saturating_add(self.pit.shoves as u64);
        profile.stats[6] = profile.stats[6].saturating_add(self.pit.chests as u64);
        profile.stats[7] = profile.stats[7].saturating_add(self.pit.dealt);
        profile.stats[16] = profile.stats[16].saturating_add(self.pit.drank as u64);
        profile.stats[17] = profile.stats[17].saturating_add(self.pit.smoked as u64);
        if self.pit.flawless {
            profile.untouched = profile.untouched.saturating_add(1);
        }
        if self.pit.felled > 0 {
            profile.stats[14] = profile.stats[14].saturating_add(self.pit.felled as u64);
            if self.pit.flawless {
                profile.keystone_clean = profile.keystone_clean.saturating_add(1);
            }
        }

        let at_bottom = self.depth + 1 >= self.rows;
        if let Some(slot) = self.map.get_mut(self.depth as usize * LANES + self.lane as usize) {
            slot.done = true;
        }
        if at_bottom {
            self.stride = stride::CROWNED;
            self.settle(profile);
        } else {
            self.stride = stride::CARD;
        }
    }

    /// Dismisses the result card. Rooms hand out a blessing, quiet stops go
    /// straight to the fork.
    pub fn press_on(&mut self, profile: &Profile) -> bool {
        match self.stride {
            stride::CARD => {
                self.deal_cache(profile);
                true
            }
            stride::HAVEN => {
                self.offer_fork(profile);
                true
            }
            _ => false,
        }
    }

    fn deal_cache(&mut self, profile: &Profile) {
        let width = if profile.cluster_full(2) { 4 } else { 3 };
        let mut drift = Drift::seeded(braid_seed(&[
            self.seed,
            self.depth as u64,
            0x6B1F_904C_2EA7_D835,
        ]));
        let mut pool: Vec<u32> = (0..BOON_COUNT as u32)
            .filter(|boon| !self.boons.contains(boon))
            .collect();
        drift.jumble(&mut pool);
        self.cache = pool.into_iter().take(width).collect();
        if self.cache.is_empty() {
            self.offer_fork(profile);
        } else {
            self.stride = stride::CACHE;
        }
    }

    pub fn take_boon(&mut self, profile: &Profile, choice: usize) -> bool {
        if self.stride != stride::CACHE {
            return false;
        }
        let Some(boon) = self.cache.get(choice).copied() else {
            return false;
        };
        self.boons.push(boon);
        self.cache.clear();
        self.offer_fork(profile);
        true
    }

    /// With one way on there is nothing to decide, so the expedition walks it
    /// itself rather than making the player tap a single button.
    fn offer_fork(&mut self, profile: &Profile) {
        self.forks = self.open_forks();
        if self.forks.is_empty() {
            self.stride = stride::CROWNED;
        } else if self.forks.len() == 1 {
            let only = self.forks[0];
            self.walk_on(profile, only);
        } else {
            self.stride = stride::FORK;
        }
    }

    /// Takes a fork. The caller passes the lane it tapped on the map.
    pub fn choose_fork(&mut self, profile: &Profile, lane: u32) -> bool {
        if self.stride != stride::FORK || !self.forks.contains(&lane) {
            return false;
        }
        self.walk_on(profile, lane);
        true
    }

    fn walk_on(&mut self, profile: &Profile, lane: u32) {
        self.depth += 1;
        self.lane = lane;
        self.forks.clear();
        self.raise_room(profile);
    }

    /// Buys from a trader out of the shards carried so far.
    pub fn trade(&mut self, seat: usize) -> bool {
        if self.stride != stride::HAVEN {
            return false;
        }
        let Some(item) = self.wares.get(seat).copied() else {
            return false;
        };
        let toll = WARE_TOLL
            .get(item as usize)
            .copied()
            .unwrap_or(u64::MAX);
        if self.spoils.shards < toll {
            return false;
        }
        self.spoils.shards -= toll;
        match item {
            ware::POULTICE => {
                self.bought_hp += 6;
                self.hp_cap += 6;
                self.hp = (self.hp + 10).min(self.hp_cap);
            }
            ware::PLATING => self.bought_ward += 4,
            ware::VIGOUR => {
                self.bought_vigor += 2;
                self.vigor_cap += 2;
                self.vigor = self.vigor_cap;
            }
            ware::WHETSTONE => self.bought_bite += 1,
            ware::LANTERN => self.bought_chest += 1,
            ware::ANKH => self.bought_revive += 1,
            // A keg and a bundle of lotus. The trader sells what the temple
            // ran on, and it works as well on the hero as it did on the priests.
            ware::KEG => {
                self.bought_hp += 10;
                self.hp_cap += 10;
                self.hp = (self.hp + 14).min(self.hp_cap);
                self.pit.drank += 2;
            }
            ware::LOTUS => {
                self.bought_vigor += 3;
                self.vigor_cap += 3;
                self.vigor = self.vigor_cap;
                self.pit.smoked += 2;
            }
            _ => return false,
        }
        self.wares.remove(seat);
        true
    }

    /// Final bookkeeping for a finished descent.
    fn settle(&mut self, profile: &mut Profile) {
        let seat = Profile::node_seat(
            (self.region as usize).min(REGION_COUNT - 1),
            (self.node as usize).min(NODES_PER_REGION - 1),
        );
        let first_light = profile.seals_won[seat] == 0;
        if first_light {
            self.spoils.shards = (self.spoils.shards as f32 * 1.8).round() as u64;
        }
        let earned = self.best_mastery.max(1) as u8;
        if profile.seals_won[seat] < earned {
            profile.seals_won[seat] = earned;
        }

        self.spoils.relic = -1;
        if self.node as usize == NODES_PER_REGION - 1 {
            for (index, spec) in RELICS.iter().enumerate() {
                if spec.home == self.region && profile.relics & (1 << index) == 0 {
                    profile.relics |= 1 << index;
                    self.spoils.relic = index as i32;
                    break;
                }
            }
            for (index, spec) in CADRE.iter().enumerate() {
                if spec.wakes_at_region == self.region && profile.cadre[index] == 0 {
                    profile.cadre[index] = 1;
                }
            }
        }
        self.fold_records(profile);
    }

    fn fold_records(&mut self, profile: &mut Profile) {
        profile.gain(purse::SHARDS, self.spoils.shards);
        profile.gain(purse::CORES, self.spoils.cores);
        profile.gain(purse::RESIN, self.spoils.resin);
        profile.gain(purse::SEALS, self.spoils.seals);
        profile.absorb_light(self.spoils.light);
        profile.burn_charges();
        open_codex(profile, self.region);
        self.spoils.medals = strike_medals(profile);
    }

    pub fn abandon(&mut self, profile: &mut Profile) {
        if self.stride == stride::CROWNED || self.stride == stride::FALLEN {
            return;
        }
        self.stride = stride::FALLEN;
        self.flawless_run = false;
        self.fold_records(profile);
    }

    pub fn live(&self) -> bool {
        self.stride != stride::CROWNED && self.stride != stride::FALLEN
    }

    // --- transport ---------------------------------------------------------

    pub fn inscribe(&mut self, profile: &Profile, pen: &mut Scribe) {
        pen.byte(self.stride)
            .quad(self.region)
            .quad(self.node)
            .quad(self.depth)
            .quad(self.rows)
            .quad(self.lane)
            .quad(self.rooms_cleared)
            .quad(self.best_mastery)
            .quad(self.last_mastery)
            .octet(self.last_shards)
            .flag(self.flawless_run);

        pen.signed(self.hp)
            .signed(self.hp_cap)
            .signed(self.vigor)
            .signed(self.vigor_cap);

        pen.octet(self.spoils.shards)
            .octet(self.spoils.cores)
            .octet(self.spoils.resin)
            .octet(self.spoils.seals)
            .octet(self.spoils.light)
            .signed(self.spoils.relic)
            .quad(self.spoils.medals);

        // The branch map, row by row, so the UI can draw the whole descent.
        pen.tally(self.rows as usize);
        for row in 0..self.rows {
            pen.tally(LANES);
            for lane in 0..LANES as u32 {
                let stop = self.stop_at(row, lane);
                let here = row == self.depth && lane == self.lane;
                let reachable = row == self.depth + 1 && self.forks.contains(&lane);
                pen.byte(stop.kind)
                    .flag(stop.real)
                    .flag(stop.done)
                    .flag(here)
                    .flag(reachable)
                    .pair(
                        HAUNT_LINES
                            .get(stop.kind as usize)
                            .copied()
                            .unwrap_or(0),
                    )
                    .pair(
                        HAUNT_BLURBS
                            .get(stop.kind as usize)
                            .copied()
                            .unwrap_or(0),
                    );
            }
        }

        pen.tally(self.boons.len());
        for boon in self.boons.iter().copied() {
            pen.quad(boon)
                .pair(BOON_NAMES.get(boon as usize).copied().unwrap_or(0))
                .pair(BOON_BLURBS.get(boon as usize).copied().unwrap_or(0));
        }
        pen.tally(self.cache.len());
        for boon in self.cache.iter().copied() {
            pen.quad(boon)
                .pair(BOON_NAMES.get(boon as usize).copied().unwrap_or(0))
                .pair(BOON_BLURBS.get(boon as usize).copied().unwrap_or(0));
        }
        pen.tally(self.wares.len());
        for item in self.wares.iter().copied() {
            let toll = WARE_TOLL.get(item as usize).copied().unwrap_or(0);
            pen.quad(item)
                .pair(WARE_LINES.get(item as usize).copied().unwrap_or(0))
                .pair(WARE_BLURBS.get(item as usize).copied().unwrap_or(0))
                .octet(toll)
                .flag(self.spoils.shards >= toll);
        }

        let seats = profile.power_seats();
        pen.tally(seats + 1);
        for seat in 0..seats {
            let power = profile.powers.get(seat).copied().unwrap_or(-1);
            let rest = self.rest.get(seat).copied().unwrap_or(0);
            let (name, blurb, toll, ceiling) = if power >= 0 {
                let index = power as usize;
                (
                    POWER_NAMES.get(index).copied().unwrap_or(0),
                    POWER_BLURBS.get(index).copied().unwrap_or(0),
                    POWER_TOLL.get(index).copied().unwrap_or(1),
                    self.rest_span(index),
                )
            } else {
                (0, 0, 0, 0)
            };
            pen.signed(power)
                .pair(name)
                .pair(blurb)
                .signed(toll)
                .quad(rest)
                .quad(ceiling.max(1))
                .flag(power >= 0 && rest == 0 && self.vigor >= toll);
        }

        // And last, always, the jar.
        let brew_toll = POWER_TOLL.get(BREW_POWER).copied().unwrap_or(2);
        pen.signed(BREW_POWER as i32)
            .pair(POWER_NAMES.get(BREW_POWER).copied().unwrap_or(0))
            .pair(POWER_BLURBS.get(BREW_POWER).copied().unwrap_or(0))
            .signed(brew_toll)
            .quad(self.brew_rest)
            .quad(self.rest_span(BREW_POWER).max(1))
            .flag(self.brew_rest == 0 && self.vigor >= brew_toll);

        let kind = self.stop_at(self.depth, self.lane).kind;
        pen.byte(kind)
            .pair(HAUNT_LINES.get(kind as usize).copied().unwrap_or(0))
            .pair(GOAL_LINES.get(self.pit.brief.goal as usize).copied().unwrap_or(0))
            .pair(GOAL_HINTS.get(self.pit.brief.goal as usize).copied().unwrap_or(0));

        self.pit.inscribe(pen);
    }
}

/// Hero health before any modifier. Climbs slowly with attunement so a long
/// account is not stuck with a glass hero.
pub fn base_vitality(profile: &Profile) -> i32 {
    18 + (profile.attunement as i32 / 3).min(12)
}

/// Breeds the codex should list for a region, in the order they first appear.
pub fn breeds_for(region: u32) -> Vec<u8> {
    crate::delve::breed_pool(region, false)
        .into_iter()
        .chain(if region >= 6 { vec![brood::REVENANT] } else { Vec::new() })
        .collect()
}
