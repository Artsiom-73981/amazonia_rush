//! The profile and everything the player permanently owns, plus the assembly of
//! run modifiers. The on-disk form is a shrouded binary blob, so editing the
//! container by hand produces a digest mismatch and the oracle refuses it.

use crate::atlas::*;
use crate::codec::{Reader, Scribe};
use crate::crypt::{hearth_key, shroud, unshroud};
use crate::entropy::Drift;
use crate::delve::Mantle;

pub const SAVE_MARK: u32 = 0x4152_5531;
pub const NODE_TOTAL: usize = REGION_COUNT * NODES_PER_REGION;

pub mod purse {
    pub const SHARDS: usize = 0;
    pub const CORES: usize = 1;
    pub const RESIN: usize = 2;
    pub const SEALS: usize = 3;
}

pub mod toggle {
    pub const SOUND: u32 = 1 << 0;
    pub const MUSIC: u32 = 1 << 1;
    pub const HAPTICS: u32 = 1 << 2;
    pub const HINTS: u32 = 1 << 3;
    pub const LEFT_HAND: u32 = 1 << 4;
    pub const BOLD: u32 = 1 << 5;
    pub const GORE: u32 = 1 << 6;
}

#[derive(Clone, Copy, Default)]
pub struct EdictSlot {
    pub shape: u32,
    pub need: u64,
    pub baseline: u64,
    pub taken: bool,
}

pub struct Profile {
    pub purse: [u64; 4],
    pub light: u64,
    pub attunement: u32,
    pub lattice: [u32; LATTICE_COUNT],
    pub cadre: [u32; SCARAB_COUNT],
    pub bench: [i32; CADRE_SLOTS],
    pub powers: [i32; POWER_SLOTS],
    pub relics: u32,
    pub seals_won: [u8; NODE_TOTAL],
    pub stats: [u64; 18],
    pub untouched: u64,
    pub keystone_clean: u64,
    pub shards_spent: u64,
    pub dawn_slot: u32,
    pub dawn_streak: u32,
    pub dawn_day: i64,
    pub ascent_light: u64,
    pub ascent_taken: u64,
    pub dawn_edicts: [EdictSlot; 3],
    pub moon_edicts: [EdictSlot; 3],
    pub rerolls: u32,
    pub day_stamp: i64,
    pub week_stamp: i64,
    pub medals: u32,
    pub chronicles: u32,
    pub codex: u32,
    pub recipes: [u32; RECIPE_COUNT],
    pub caravan_day: i64,
    pub caravan_rack: [u8; 4],
    pub caravan_taken: u32,
    pub skins: u32,
    pub skin_worn: u32,
    pub reawakenings: u32,
    pub switches: u32,
    pub tutor_step: u32,
    pub clock_unix: i64,
    pub clock_shift: i32,
    pub last_day: i64,
}

impl Profile {
    pub fn newborn() -> Self {
        Profile {
            purse: [220, 0, 20, 0],
            light: 0,
            attunement: 1,
            lattice: [0; LATTICE_COUNT],
            cadre: {
                let mut roster = [0u32; SCARAB_COUNT];
                roster[0] = 1;
                roster
            },
            bench: [0, -1, -1],
            powers: [0, 1, 3, -1],
            relics: 0,
            seals_won: [0; NODE_TOTAL],
            stats: [0; 18],
            untouched: 0,
            keystone_clean: 0,
            shards_spent: 0,
            dawn_slot: 0,
            dawn_streak: 0,
            dawn_day: -1,
            ascent_light: 0,
            ascent_taken: 0,
            dawn_edicts: [EdictSlot::default(); 3],
            moon_edicts: [EdictSlot::default(); 3],
            rerolls: 2,
            day_stamp: -1,
            week_stamp: -1,
            medals: 0,
            chronicles: 0,
            codex: 1 | (1 << 1) | (1 << 8),
            recipes: [0; RECIPE_COUNT],
            caravan_day: -1,
            caravan_rack: [0, 1, 2, 3],
            caravan_taken: 0,
            skins: 1,
            skin_worn: 0,
            reawakenings: 0,
            switches: toggle::SOUND | toggle::MUSIC | toggle::HAPTICS | toggle::HINTS | toggle::GORE,
            tutor_step: 0,
            clock_unix: 0,
            clock_shift: 0,
            last_day: -1,
        }
    }

    // --- persistence -------------------------------------------------------

    pub fn seal(&self) -> Vec<u8> {
        let mut pen = Scribe::fresh();
        pen.quad(SAVE_MARK);
        for coin in self.purse {
            pen.octet(coin);
        }
        pen.octet(self.light).quad(self.attunement);
        for rank in self.lattice {
            pen.quad(rank);
        }
        for rank in self.cadre {
            pen.quad(rank);
        }
        for seat in self.bench {
            pen.signed(seat);
        }
        for seat in self.powers {
            pen.signed(seat);
        }
        pen.quad(self.relics);
        for seals in self.seals_won {
            pen.byte(seals);
        }
        for value in self.stats {
            pen.octet(value);
        }
        pen.octet(self.untouched)
            .octet(self.keystone_clean)
            .octet(self.shards_spent)
            .quad(self.dawn_slot)
            .quad(self.dawn_streak)
            .octet(self.dawn_day as u64)
            .octet(self.ascent_light)
            .octet(self.ascent_taken);
        for slot in self.dawn_edicts.iter().chain(self.moon_edicts.iter()) {
            pen.quad(slot.shape)
                .octet(slot.need)
                .octet(slot.baseline)
                .flag(slot.taken);
        }
        pen.quad(self.rerolls)
            .octet(self.day_stamp as u64)
            .octet(self.week_stamp as u64)
            .quad(self.medals)
            .quad(self.chronicles)
            .quad(self.codex);
        for charges in self.recipes {
            pen.quad(charges);
        }
        pen.octet(self.caravan_day as u64);
        for slot in self.caravan_rack {
            pen.byte(slot);
        }
        pen.quad(self.caravan_taken)
            .quad(self.skins)
            .quad(self.skin_worn)
            .quad(self.reawakenings)
            .quad(self.switches)
            .quad(self.tutor_step)
            .octet(self.last_day as u64);
        shroud(&pen.into_bytes(), hearth_key())
    }

    pub fn unseal(blob: &[u8]) -> Option<Self> {
        let plain = unshroud(blob, hearth_key())?;
        let mut eye = Reader::over(&plain);
        if eye.quad() != SAVE_MARK {
            return None;
        }
        let mut shell = Profile::newborn();
        for slot in 0..4 {
            shell.purse[slot] = eye.octet();
        }
        shell.light = eye.octet();
        shell.attunement = eye.quad().max(1);
        for slot in 0..LATTICE_COUNT {
            shell.lattice[slot] = eye.quad();
        }
        for slot in 0..SCARAB_COUNT {
            shell.cadre[slot] = eye.quad();
        }
        for slot in 0..CADRE_SLOTS {
            shell.bench[slot] = eye.signed();
        }
        for slot in 0..POWER_SLOTS {
            shell.powers[slot] = eye.signed();
        }
        shell.relics = eye.quad();
        for slot in 0..NODE_TOTAL {
            shell.seals_won[slot] = eye.byte();
        }
        for slot in 0..18 {
            shell.stats[slot] = eye.octet();
        }
        shell.untouched = eye.octet();
        shell.keystone_clean = eye.octet();
        shell.shards_spent = eye.octet();
        shell.dawn_slot = eye.quad();
        shell.dawn_streak = eye.quad();
        shell.dawn_day = eye.octet() as i64;
        shell.ascent_light = eye.octet();
        shell.ascent_taken = eye.octet();
        for slot in 0..6 {
            let bundle = EdictSlot {
                shape: eye.quad(),
                need: eye.octet(),
                baseline: eye.octet(),
                taken: eye.flag(),
            };
            if slot < 3 {
                shell.dawn_edicts[slot] = bundle;
            } else {
                shell.moon_edicts[slot - 3] = bundle;
            }
        }
        shell.rerolls = eye.quad();
        shell.day_stamp = eye.octet() as i64;
        shell.week_stamp = eye.octet() as i64;
        shell.medals = eye.quad();
        shell.chronicles = eye.quad();
        shell.codex = eye.quad();
        for slot in 0..RECIPE_COUNT {
            shell.recipes[slot] = eye.quad();
        }
        shell.caravan_day = eye.octet() as i64;
        for slot in 0..4 {
            shell.caravan_rack[slot] = eye.byte();
        }
        shell.caravan_taken = eye.quad();
        shell.skins = eye.quad().max(1);
        shell.skin_worn = eye.quad();
        shell.reawakenings = eye.quad();
        shell.switches = eye.quad();
        shell.tutor_step = eye.quad();
        shell.last_day = eye.octet() as i64;
        // An older save was written when a scarab carried one ability. Give it
        // the seats it has earned rather than leaving them blank.
        shell.fill_empty_seats();
        Some(shell)
    }

    // --- clock -------------------------------------------------------------

    pub fn wind_clock(&mut self, unix: i64, shift: i32) {
        self.clock_unix = unix;
        self.clock_shift = shift;
        let today = self.today();
        // A clock pushed backwards never rewinds progress windows.
        if today > self.last_day {
            self.last_day = today;
        }
    }

    pub fn today(&self) -> i64 {
        let shifted = self
            .clock_unix
            .saturating_add((self.clock_shift as i64) * 60);
        shifted.div_euclid(86_400)
    }

    pub fn this_week(&self) -> i64 {
        self.today().div_euclid(7)
    }

    // --- purse -------------------------------------------------------------

    pub fn shard_ceiling(&self) -> u64 {
        40_000 + (self.lattice[17] as u64) * 2_000 + (self.reawakenings as u64) * 20_000
    }

    pub fn gain(&mut self, slot: usize, amount: u64) {
        if slot >= 4 || amount == 0 {
            return;
        }
        self.purse[slot] = self.purse[slot].saturating_add(amount);
        if slot == purse::SHARDS {
            let cap = self.shard_ceiling();
            if self.purse[slot] > cap {
                self.purse[slot] = cap;
            }
            self.stats[9] = self.stats[9].saturating_add(amount);
        }
        if slot == purse::CORES {
            self.stats[10] = self.stats[10].saturating_add(amount);
        }
        if slot == purse::RESIN {
            self.stats[11] = self.stats[11].saturating_add(amount);
        }
    }

    pub fn can_pay(&self, slot: usize, amount: u64) -> bool {
        slot < 4 && self.purse[slot] >= amount
    }

    pub fn pay(&mut self, slot: usize, amount: u64) -> bool {
        if !self.can_pay(slot, amount) {
            return false;
        }
        self.purse[slot] -= amount;
        if slot == purse::SHARDS {
            self.shards_spent = self.shards_spent.saturating_add(amount);
        }
        true
    }

    pub fn absorb_light(&mut self, light: u64) {
        self.light = self.light.saturating_add(light);
        self.ascent_light = self.ascent_light.saturating_add(light);
        while self.attunement < 400 && self.light >= self.light_for(self.attunement + 1) {
            self.attunement += 1;
        }
        self.fill_empty_seats();
    }

    pub fn light_for(&self, level: u32) -> u64 {
        let mut total = 0u64;
        for step in 1..level {
            total = total.saturating_add(attunement_bar(step));
        }
        total
    }

    // --- map ---------------------------------------------------------------

    pub fn node_seat(region: usize, node: usize) -> usize {
        region * NODES_PER_REGION + node
    }

    pub fn region_cleared(&self, region: usize) -> u32 {
        (0..NODES_PER_REGION)
            .filter(|node| self.seals_won[Profile::node_seat(region, *node)] > 0)
            .count() as u32
    }

    pub fn region_open(&self, region: usize) -> bool {
        if region == 0 {
            return true;
        }
        self.region_cleared(region - 1) >= 8
    }

    pub fn node_open(&self, region: usize, node: usize) -> bool {
        if !self.region_open(region) {
            return false;
        }
        if node == 0 {
            return true;
        }
        self.seals_won[Profile::node_seat(region, node - 1)] > 0
    }

    pub fn regions_woken(&self) -> u32 {
        (0..REGION_COUNT)
            .filter(|region| self.seals_won[Profile::node_seat(*region, NODES_PER_REGION - 1)] > 0)
            .count() as u32
    }

    pub fn total_seals(&self) -> u32 {
        self.seals_won.iter().map(|seals| *seals as u32).sum()
    }

    pub fn relic_count(&self) -> u32 {
        self.relics.count_ones()
    }

    pub fn cluster_full(&self, cluster: u32) -> bool {
        RELICS
            .iter()
            .enumerate()
            .filter(|(_, spec)| spec.cluster == cluster)
            .all(|(index, _)| self.relics & (1 << index) != 0)
    }

    pub fn clusters_full(&self) -> u32 {
        (0..RELIC_SETS as u32)
            .filter(|cluster| self.cluster_full(*cluster))
            .count() as u32
    }

    pub fn cadre_size(&self) -> u32 {
        self.cadre.iter().filter(|rank| **rank > 0).count() as u32
    }

    pub fn cadre_ranks(&self) -> u32 {
        self.cadre.iter().sum()
    }

    pub fn lattice_ranks(&self) -> u32 {
        self.lattice.iter().sum()
    }

    pub fn power_seats(&self) -> usize {
        if self.lattice[19] > 0 {
            4
        } else {
            3
        }
    }

    pub fn power_unlocked(&self, power: usize) -> bool {
        match power {
            // A scarab leaves the entrance with a charge, a spin and a bolt:
            // one ability is not a fight, it is a walk.
            0 | 1 | 3 => true,
            2 => self.attunement >= 3,
            4 => self.lattice[22] > 0,
            _ => false,
        }
    }

    /// Seats whatever the player has earned but never slotted, so an unlocked
    /// ability is never sitting idle behind a menu.
    pub fn fill_empty_seats(&mut self) {
        for seat in 0..self.power_seats() {
            if self.powers[seat] >= 0 {
                continue;
            }
            for power in 0..POWER_COUNT {
                if !self.power_unlocked(power) {
                    continue;
                }
                if self.powers.iter().any(|held| *held == power as i32) {
                    continue;
                }
                self.powers[seat] = power as i32;
                break;
            }
        }
    }

    pub fn dominion_scale(&self) -> f32 {
        1.0 + self.reawakenings as f32 * 0.35
    }

    pub fn switched(&self, flag: u32) -> bool {
        self.switches & flag != 0
    }

    // --- modifiers ---------------------------------------------------------

    /// Flattens the whole profile, the run's blessings and the workshop's
    /// charges into the one sheet a chamber reads. Everything that makes the
    /// hero stronger ends up here, and nothing here is readable from Swift.
    pub fn outfit(&self, boons: &[u32], depth: u32, boss: bool) -> Mantle {
        let mut sheet = Mantle::plain();
        let lat = &self.lattice;

        // Body: staying alive.
        sheet.hp_bonus += lat[0] as i32 * 3;
        sheet.ward_open += lat[1] as i32;
        sheet.mend_per_room += lat[2] as i32;
        sheet.revives += lat[3];
        sheet.slay_bonus += lat[4] as i32;
        sheet.thorns += lat[5] as i32;

        // Blade: putting things down.
        sheet.bite_bonus += lat[6] as i32;
        sheet.crit_permille += lat[7] * 60;
        sheet.push_power += (lat[8] / 3) as i32;
        sheet.bolt_span += lat[9] as i32;
        sheet.vigor_per_kill += (lat[10] / 2) as i32;
        if boss {
            sheet.bite_bonus += (lat[11] / 2) as i32;
        }

        // Hoard: what a run is worth.
        sheet.loot_scale += lat[12] as f32 * 0.05;
        sheet.light_scale += lat[13] as f32 * 0.04;
        sheet.chest_luck += lat[15];

        // Lore: reading the room.
        sheet.cool_scale -= lat[18] as f32 * 0.05;
        sheet.vigor_cap += (lat[18] / 3) as i32;
        if lat[20] > 0 {
            sheet.trap_sight = true;
        }
        if lat[21] > 0 {
            sheet.spike_proof = true;
        }
        if lat[23] > 0 {
            sheet.beam_proof = true;
        }

        // The deployed cadre. A scarab on the bench does nothing: it has to be
        // carried to matter.
        for (index, rank) in self.cadre.iter().copied().enumerate() {
            if rank == 0 || !self.bench.contains(&(index as i32)) {
                continue;
            }
            let step = (rank - 1) as i32;
            match index {
                0 => sheet.loot_scale += step as f32 * 0.08,
                1 => sheet.cool_scale -= step as f32 * 0.04,
                2 => sheet.bite_bonus += step / 2,
                3 => sheet.ward_per_room += 1 + step / 2,
                4 => sheet.dash_span += step / 4,
                5 => {
                    sheet.trap_sight = true;
                    sheet.mercy += step / 3;
                }
                6 => sheet.vigor_cap += 1 + step / 3,
                7 => {
                    sheet.first_strike = true;
                    sheet.drowse = sheet.drowse.saturating_add(1);
                }
                _ => {}
            }
        }

        // Relic sets.
        if self.cluster_full(0) {
            sheet.hp_bonus += 4;
        }
        if self.cluster_full(1) {
            sheet.loot_scale += 0.1;
        }
        if self.cluster_full(3) {
            sheet.vigor_cap += 2;
        }

        // Workshop charges, spent one run at a time.
        for recipe in 0..RECIPE_COUNT {
            if self.recipes[recipe] == 0 {
                continue;
            }
            match recipe {
                0 => sheet.extra_chest += 1,
                1 => sheet.ward_open += 3,
                2 => sheet.mend_per_room += 2,
                3 => sheet.drowse = sheet.drowse.saturating_add(1),
                4 => sheet.vigor_open += 2,
                5 => sheet.revives += 1,
                6 => sheet.bite_bonus += 1,
                7 => sheet.trap_sight = true,
                _ => {}
            }
        }

        // Blessings picked during this descent.
        for boon in boons.iter().copied() {
            match boon {
                0 => sheet.bite_bonus += 2,
                1 => sheet.hp_bonus += 6,
                2 => sheet.crit_permille += 120,
                3 => sheet.push_power += 1,
                4 => sheet.dash_span += 1,
                5 => sheet.ward_per_room += 2,
                6 => {
                    sheet.vigor_cap += 2;
                    sheet.vigor_open += 2;
                }
                7 => sheet.loot_scale += 0.3,
                8 => sheet.cool_scale -= 0.2,
                9 => sheet.slay_bonus += 2,
                10 => sheet.thorns += 2,
                11 => {
                    sheet.spike_proof = true;
                    sheet.beam_proof = true;
                }
                // Drunk: hits harder, guards worse, and the hands are slow.
                12 => {
                    sheet.bite_bonus += 4;
                    sheet.mercy -= 2;
                    sheet.cool_scale += 0.15;
                }
                // Lotus: the pain is somewhere else, and so is the edge.
                13 => {
                    sheet.mercy += 3;
                    sheet.vigor_cap += 3;
                    sheet.vigor_open += 3;
                    sheet.bite_bonus -= 1;
                }
                _ => {}
            }
        }

        // A descent that has already run long gets a little heavier, so the
        // deep rooms stay a threat however good the loadout is.
        sheet.mercy -= (depth / 4) as i32;
        sheet.loot_scale *= self.dominion_scale();
        sheet.cool_scale = sheet.cool_scale.clamp(0.4, 1.2);
        sheet.vigor_cap = sheet.vigor_cap.clamp(3, 14);
        sheet.vigor_open = sheet.vigor_open.min(sheet.vigor_cap);
        sheet.push_power = sheet.push_power.clamp(1, 4);
        sheet.dash_span = sheet.dash_span.clamp(2, 6);
        sheet.bolt_span = sheet.bolt_span.clamp(3, 8);
        sheet.crit_permille = sheet.crit_permille.min(600);
        sheet
    }

    pub fn shard_scale(&self) -> f32 {
        let mut scale = 1.0 + self.lattice[12] as f32 * 0.05;
        for (index, rank) in self.cadre.iter().copied().enumerate() {
            if index == 0 && rank > 0 && self.bench.contains(&0) {
                scale += (rank - 1) as f32 * 0.1;
            }
        }
        scale * self.dominion_scale()
    }

    pub fn resin_scale(&self) -> f32 {
        let mut scale = 1.0 + self.lattice[14] as f32 * 0.05;
        if self.cadre[4] > 0 && self.bench.contains(&4) {
            scale += (self.cadre[4] - 1) as f32 * 0.1;
        }
        scale
    }

    pub fn core_odds(&self, region: usize) -> u32 {
        let base = REGIONS.get(region).map(|spec| spec.core_odds).unwrap_or(0);
        base + self.lattice[13] * 25
    }

    pub fn seal_odds(&self, region: usize) -> u32 {
        let base = REGIONS.get(region).map(|spec| spec.seal_odds).unwrap_or(0);
        base + self.lattice[16] * 25
    }

    /// Extra health the hero carries into a boss room.
    pub fn crown_grit(&self) -> i32 {
        self.lattice[11] as i32 * 2
    }

    // --- shopping ----------------------------------------------------------

    pub fn lattice_toll(&self, node: usize) -> (u64, u64) {
        let Some(spec) = LATTICE.get(node) else {
            return (0, 0);
        };
        let rank = self.lattice[node] as u64;
        let shards = spec.toll_open as u64 + rank * spec.toll_climb as u64;
        let cores = spec.core_toll as u64 * (rank + 1);
        (shards, cores)
    }

    pub fn lattice_buy(&mut self, node: usize) -> bool {
        let Some(spec) = LATTICE.get(node) else {
            return false;
        };
        if self.lattice[node] >= spec.ceiling || self.attunement < spec.attunement {
            return false;
        }
        let (shards, cores) = self.lattice_toll(node);
        if !self.can_pay(purse::SHARDS, shards) || !self.can_pay(purse::CORES, cores) {
            return false;
        }
        self.pay(purse::SHARDS, shards);
        self.pay(purse::CORES, cores);
        self.lattice[node] += 1;
        self.fill_empty_seats();
        true
    }

    pub fn scarab_feed(&self, index: usize) -> u64 {
        let Some(spec) = CADRE.get(index) else {
            return 0;
        };
        let rank = self.cadre[index].max(1) as u64;
        spec.feed_open as u64 + (rank - 1) * spec.feed_climb as u64
    }

    pub fn scarab_rankup(&mut self, index: usize) -> bool {
        let Some(spec) = CADRE.get(index) else {
            return false;
        };
        if self.cadre[index] == 0 || self.cadre[index] >= spec.ceiling {
            return false;
        }
        let toll = self.scarab_feed(index);
        let resin = 6 + self.cadre[index] as u64 * 2;
        if !self.can_pay(purse::SHARDS, toll) || !self.can_pay(purse::RESIN, resin) {
            return false;
        }
        self.pay(purse::SHARDS, toll);
        self.pay(purse::RESIN, resin);
        self.cadre[index] += 1;
        true
    }

    pub fn scarab_deploy(&mut self, index: i32, seat: usize) -> bool {
        if seat >= CADRE_SLOTS {
            return false;
        }
        if index < 0 {
            self.bench[seat] = -1;
            return true;
        }
        let slot = index as usize;
        if slot >= SCARAB_COUNT || self.cadre[slot] == 0 {
            return false;
        }
        if let Some(other) = self.bench.iter().position(|seated| *seated == index) {
            self.bench[other] = self.bench[seat];
        }
        self.bench[seat] = index;
        true
    }

    pub fn power_assign(&mut self, power: i32, seat: usize) -> bool {
        if seat >= self.power_seats() {
            return false;
        }
        if power < 0 {
            self.powers[seat] = -1;
            return true;
        }
        let slot = power as usize;
        if slot >= POWER_COUNT || !self.power_unlocked(slot) {
            return false;
        }
        if let Some(other) = self.powers.iter().position(|held| *held == power) {
            self.powers[other] = self.powers[seat];
        }
        self.powers[seat] = power;
        true
    }

    pub fn forge(&mut self, recipe: usize) -> bool {
        let Some(spec) = RECIPES.get(recipe) else {
            return false;
        };
        if self.recipes[recipe] >= 9 {
            return false;
        }
        if !self.can_pay(purse::RESIN, spec.resin_toll as u64)
            || !self.can_pay(purse::SHARDS, spec.shard_toll as u64)
        {
            return false;
        }
        self.pay(purse::RESIN, spec.resin_toll as u64);
        self.pay(purse::SHARDS, spec.shard_toll as u64);
        self.recipes[recipe] += 1;
        true
    }

    pub fn burn_charges(&mut self) {
        for charges in self.recipes.iter_mut() {
            if *charges > 0 {
                *charges -= 1;
            }
        }
    }

    pub fn refresh_caravan(&mut self) {
        let today = self.today();
        if self.caravan_day == today {
            return;
        }
        self.caravan_day = today;
        self.caravan_taken = 0;
        let mut drift = Drift::seeded((today as u64).wrapping_mul(0x9E37_79B9) ^ 0x5CA4_AB01);
        let mut pool: Vec<u8> = (0..OFFER_COUNT as u8).collect();
        drift.jumble(&mut pool);
        for seat in 0..4 {
            self.caravan_rack[seat] = pool.get(seat).copied().unwrap_or(0);
        }
    }

    pub fn trade(&mut self, seat: usize) -> bool {
        if seat >= 4 || self.caravan_taken & (1 << seat) != 0 {
            return false;
        }
        let offer = self.caravan_rack[seat] as usize;
        let Some(spec) = OFFERS.get(offer) else {
            return false;
        };
        if !self.can_pay(spec.pay_purse as usize, spec.pay_amount as u64) {
            return false;
        }
        match spec.get_purse {
            4 => {
                let Some(seated) = self.bench.iter().copied().find(|seat| *seat >= 0) else {
                    return false;
                };
                let slot = seated as usize;
                if self.cadre[slot] >= CADRE[slot].ceiling {
                    return false;
                }
                self.pay(spec.pay_purse as usize, spec.pay_amount as u64);
                self.cadre[slot] += 1;
            }
            5 => {
                let next = self.skins.count_ones();
                if next >= 6 {
                    return false;
                }
                self.pay(spec.pay_purse as usize, spec.pay_amount as u64);
                self.skins |= 1 << next;
            }
            other => {
                self.pay(spec.pay_purse as usize, spec.pay_amount as u64);
                self.gain(other as usize, spec.get_amount as u64);
            }
        }
        self.caravan_taken |= 1 << seat;
        true
    }

    pub fn wear_skin(&mut self, skin: u32) -> bool {
        if skin >= 6 || self.skins & (1 << skin) == 0 {
            return false;
        }
        self.skin_worn = skin;
        true
    }

    pub fn reawaken(&mut self) -> bool {
        if self.regions_woken() < REGION_COUNT as u32 {
            return false;
        }
        let kept_relics = self.relics;
        let kept_cadre = self.cadre;
        let kept_medals = self.medals;
        let kept_stats = self.stats;
        let kept_codex = self.codex;
        let kept_skins = self.skins;
        let count = self.reawakenings + 1;
        let switches = self.switches;
        let chronicles = self.chronicles;
        let clock = (self.clock_unix, self.clock_shift, self.last_day);

        *self = Profile::newborn();
        self.relics = kept_relics;
        self.cadre = kept_cadre;
        self.medals = kept_medals;
        self.stats = kept_stats;
        self.codex = kept_codex;
        self.skins = kept_skins;
        self.reawakenings = count;
        self.switches = switches;
        self.chronicles = chronicles;
        self.tutor_step = 99;
        self.clock_unix = clock.0;
        self.clock_shift = clock.1;
        self.last_day = clock.2;
        self.stats[15] = count as u64;
        true
    }
}
