//! Amazonia Rush — the oracle.
//!
//! Every rule, price, payout and board layout lives on this side of the bridge.
//! The Swift app is a renderer: it sends numbered requests and draws whatever
//! binary frame comes back. There is no JSON, no field names and no readable
//! text in the shipped library, so pulling the binary apart tells an attacker
//! very little about the economy.

pub mod almanac;
pub mod arena;
pub mod atlas;
pub mod codec;
pub mod crypt;
pub mod delve;
pub mod entropy;
pub mod expedition;
pub mod ledger;
pub mod lexicon;
pub mod lexicon_table;

use almanac::*;
use atlas::*;
use codec::{Reader, Scribe};
use expedition::Delve;
use ledger::{purse, Profile, NODE_TOTAL};
use lexicon::Lexicon;

pub mod rite {
    pub const HEARTBEAT: u32 = 1;
    pub const HUB: u32 = 2;
    pub const MAP: u32 = 3;
    pub const DELVE_OPEN: u32 = 4;
    pub const DELVE_ACT: u32 = 5;
    pub const DELVE_KNACK: u32 = 6;
    pub const DELVE_PRESS: u32 = 7;
    pub const DELVE_BOON: u32 = 8;
    pub const DELVE_FORK: u32 = 9;
    pub const DELVE_TRADE: u32 = 10;
    pub const DELVE_ABANDON: u32 = 11;
    pub const DELVE_VIEW: u32 = 12;
    pub const LATTICE: u32 = 13;
    pub const LATTICE_BUY: u32 = 14;
    pub const CADRE: u32 = 15;
    pub const SCARAB_RANK: u32 = 16;
    pub const SCARAB_DEPLOY: u32 = 17;
    pub const POWER_ASSIGN: u32 = 18;
    pub const RELICS: u32 = 19;
    pub const FORGE: u32 = 20;
    pub const FORGE_MAKE: u32 = 21;
    pub const CARAVAN: u32 = 22;
    pub const CARAVAN_TRADE: u32 = 23;
    pub const SKIN_WEAR: u32 = 24;
    pub const RITES: u32 = 25;
    pub const RITE_CLAIM: u32 = 26;
    pub const ASCENT: u32 = 27;
    pub const ASCENT_CLAIM: u32 = 28;
    pub const EDICTS: u32 = 29;
    pub const EDICT_CLAIM: u32 = 30;
    pub const EDICT_REROLL: u32 = 31;
    pub const CHRONICLE_CLAIM: u32 = 32;
    pub const MEDALS: u32 = 33;
    pub const CODEX: u32 = 34;
    pub const RECORDS: u32 = 35;
    pub const SWITCH_SET: u32 = 36;
    pub const TUTOR_SET: u32 = 37;
    pub const WIPE: u32 = 38;
    pub const REAWAKEN: u32 = 39;
    pub const SAVE_BLOB: u32 = 40;
    pub const TEXT: u32 = 41;
    pub const TEXT_SPAN: u32 = 42;
}

pub struct Oracle {
    profile: Profile,
    words: Lexicon,
    quest: Option<Delve>,
    dirty: bool,
}

impl Oracle {
    fn wake(blob: &[u8], tongue: u8) -> Self {
        let profile = Profile::unseal(blob).unwrap_or_else(Profile::newborn);
        Oracle {
            profile,
            words: Lexicon::unwrap_scroll(tongue),
            quest: None,
            dirty: false,
        }
    }

    fn respond(&mut self, op: u32, body: &[u8]) -> Vec<u8> {
        let mut eye = Reader::over(body);
        let mut pen = Scribe::fresh();
        pen.byte(1); // frame version
        pen.byte(0); // dirty placeholder, patched below
        pen.quad(op);

        match op {
            rite::HEARTBEAT => {
                let unix = eye.octet() as i64;
                let shift = eye.signed();
                self.profile.wind_clock(unix, shift);
                turn_windows(&mut self.profile);
                self.profile.refresh_caravan();
                strike_medals(&mut self.profile);
                self.dirty = true;
                self.write_hub(&mut pen);
            }
            rite::HUB => self.write_hub(&mut pen),
            rite::MAP => self.write_map(&mut pen),
            rite::DELVE_OPEN => {
                let region = eye.quad();
                let node = eye.quad();
                let allowed = self
                    .profile
                    .node_open((region as usize).min(REGION_COUNT - 1), node as usize);
                if allowed {
                    self.quest = Some(Delve::open(&self.profile, region, node));
                    self.dirty = true;
                }
                pen.flag(allowed);
                self.write_delve(&mut pen);
            }
            rite::DELVE_ACT => {
                // One frame of the fight: where the stick is pushed, and how
                // much real time the frame covered.
                let push_x = eye.signed();
                let push_y = eye.signed();
                let span = eye.quad();
                let spent = match self.quest.as_mut() {
                    Some(quest) => quest.steer(&mut self.profile, push_x, push_y, span),
                    None => false,
                };
                self.dirty |= spent;
                pen.flag(spent);
                self.write_delve(&mut pen);
            }
            rite::DELVE_KNACK => {
                let slot = eye.byte() as usize;
                let aim_x = eye.signed();
                let aim_y = eye.signed();
                let spent = match self.quest.as_mut() {
                    Some(quest) => quest.unleash(&mut self.profile, slot, aim_x, aim_y),
                    None => false,
                };
                self.dirty |= spent;
                pen.flag(spent);
                self.write_delve(&mut pen);
            }
            rite::DELVE_PRESS => {
                let moved = match self.quest.as_mut() {
                    Some(quest) => quest.press_on(&self.profile),
                    None => false,
                };
                pen.flag(moved);
                self.write_delve(&mut pen);
            }
            rite::DELVE_BOON => {
                let choice = eye.quad() as usize;
                let taken = match self.quest.as_mut() {
                    Some(quest) => quest.take_boon(&self.profile, choice),
                    None => false,
                };
                pen.flag(taken);
                self.write_delve(&mut pen);
            }
            rite::DELVE_FORK => {
                let lane = eye.quad();
                let walked = match self.quest.as_mut() {
                    Some(quest) => quest.choose_fork(&self.profile, lane),
                    None => false,
                };
                pen.flag(walked);
                self.write_delve(&mut pen);
            }
            rite::DELVE_TRADE => {
                let seat = eye.quad() as usize;
                let bought = match self.quest.as_mut() {
                    Some(quest) => quest.trade(seat),
                    None => false,
                };
                pen.flag(bought);
                self.write_delve(&mut pen);
            }
            rite::DELVE_ABANDON => {
                if let Some(quest) = self.quest.as_mut() {
                    quest.abandon(&mut self.profile);
                }
                self.dirty = true;
                self.write_delve(&mut pen);
                self.quest = None;
            }
            rite::DELVE_VIEW => self.write_delve(&mut pen),
            rite::LATTICE => self.write_lattice(&mut pen),
            rite::LATTICE_BUY => {
                let node = eye.quad() as usize;
                let bought = self.profile.lattice_buy(node);
                if bought {
                    strike_medals(&mut self.profile);
                    self.dirty = true;
                }
                pen.flag(bought);
                self.write_lattice(&mut pen);
            }
            rite::CADRE => self.write_cadre(&mut pen),
            rite::SCARAB_RANK => {
                let index = eye.quad() as usize;
                let done = self.profile.scarab_rankup(index);
                if done {
                    strike_medals(&mut self.profile);
                    self.dirty = true;
                }
                pen.flag(done);
                self.write_cadre(&mut pen);
            }
            rite::SCARAB_DEPLOY => {
                let index = eye.signed();
                let seat = eye.quad() as usize;
                let done = self.profile.scarab_deploy(index, seat);
                self.dirty |= done;
                pen.flag(done);
                self.write_cadre(&mut pen);
            }
            rite::POWER_ASSIGN => {
                let power = eye.signed();
                let seat = eye.quad() as usize;
                let done = self.profile.power_assign(power, seat);
                self.dirty |= done;
                pen.flag(done);
                self.write_cadre(&mut pen);
            }
            rite::RELICS => self.write_relics(&mut pen),
            rite::FORGE => self.write_forge(&mut pen),
            rite::FORGE_MAKE => {
                let recipe = eye.quad() as usize;
                let made = self.profile.forge(recipe);
                self.dirty |= made;
                pen.flag(made);
                self.write_forge(&mut pen);
            }
            rite::CARAVAN => {
                self.profile.refresh_caravan();
                self.write_caravan(&mut pen);
            }
            rite::CARAVAN_TRADE => {
                let seat = eye.quad() as usize;
                let traded = self.profile.trade(seat);
                self.dirty |= traded;
                pen.flag(traded);
                self.write_caravan(&mut pen);
            }
            rite::SKIN_WEAR => {
                let skin = eye.quad();
                let worn = self.profile.wear_skin(skin);
                self.dirty |= worn;
                pen.flag(worn);
                self.write_caravan(&mut pen);
            }
            rite::RITES => self.write_rites(&mut pen),
            rite::RITE_CLAIM => {
                let prize = claim_rite(&mut self.profile);
                if prize.is_some() {
                    strike_medals(&mut self.profile);
                    self.dirty = true;
                }
                let prize = prize.unwrap_or((0, 0, 0, 0));
                pen.quad(prize.0)
                    .quad(prize.1)
                    .quad(prize.2)
                    .quad(prize.3);
                self.write_rites(&mut pen);
            }
            rite::ASCENT => self.write_ascent(&mut pen),
            rite::ASCENT_CLAIM => {
                let tier = eye.quad();
                let taken = claim_ascent(&mut self.profile, tier);
                if taken {
                    strike_medals(&mut self.profile);
                    self.dirty = true;
                }
                pen.flag(taken);
                self.write_ascent(&mut pen);
            }
            rite::EDICTS => self.write_edicts(&mut pen),
            rite::EDICT_CLAIM => {
                let moon = eye.flag();
                let seat = eye.quad() as usize;
                let taken = claim_edict(&mut self.profile, moon, seat);
                if taken {
                    strike_medals(&mut self.profile);
                    self.dirty = true;
                }
                pen.flag(taken);
                self.write_edicts(&mut pen);
            }
            rite::EDICT_REROLL => {
                let seat = eye.quad() as usize;
                let rolled = reroll_edict(&mut self.profile, seat);
                self.dirty |= rolled;
                pen.flag(rolled);
                self.write_edicts(&mut pen);
            }
            rite::CHRONICLE_CLAIM => {
                let index = eye.quad() as usize;
                let taken = claim_chronicle(&mut self.profile, index);
                if taken {
                    strike_medals(&mut self.profile);
                    self.dirty = true;
                }
                pen.flag(taken);
                self.write_edicts(&mut pen);
            }
            rite::MEDALS => self.write_medals(&mut pen),
            rite::CODEX => self.write_codex(&mut pen),
            rite::RECORDS => self.write_records(&mut pen),
            rite::SWITCH_SET => {
                let flag = eye.quad();
                let on = eye.flag();
                if on {
                    self.profile.switches |= flag;
                } else {
                    self.profile.switches &= !flag;
                }
                self.dirty = true;
                self.write_hub(&mut pen);
            }
            rite::TUTOR_SET => {
                self.profile.tutor_step = eye.quad();
                self.dirty = true;
                self.write_hub(&mut pen);
            }
            rite::WIPE => {
                let clock = (
                    self.profile.clock_unix,
                    self.profile.clock_shift,
                    self.profile.last_day,
                );
                self.profile = Profile::newborn();
                self.profile.wind_clock(clock.0, clock.1);
                self.profile.last_day = clock.2;
                turn_windows(&mut self.profile);
                self.profile.refresh_caravan();
                self.quest = None;
                self.dirty = true;
                self.write_hub(&mut pen);
            }
            rite::REAWAKEN => {
                let done = self.profile.reawaken();
                if done {
                    turn_windows(&mut self.profile);
                    self.profile.refresh_caravan();
                    strike_medals(&mut self.profile);
                    self.quest = None;
                    self.dirty = true;
                }
                pen.flag(done);
                self.write_hub(&mut pen);
            }
            rite::SAVE_BLOB => {
                let blob = self.profile.seal();
                pen.pair(blob.len().min(u16::MAX as usize) as u16);
                pen.bytes.extend_from_slice(&blob);
                self.dirty = false;
            }
            rite::TEXT => {
                let lexeme = eye.pair();
                pen.run(self.words.bytes_for(lexeme));
            }
            rite::TEXT_SPAN => {
                pen.quad(self.words.count() as u32);
            }
            _ => {}
        }

        let mut frame = pen.into_bytes();
        if frame.len() > 1 {
            frame[1] = if self.dirty { 1 } else { 0 };
        }
        frame
    }

    // --- snapshots ---------------------------------------------------------

    fn write_purse(&self, pen: &mut Scribe) {
        for coin in self.profile.purse {
            pen.octet(coin);
        }
        pen.octet(self.profile.shard_ceiling());
    }

    fn write_hub(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        let level = profile.attunement;
        let floor = profile.light_for(level);
        let ceiling = profile.light_for(level + 1);
        pen.quad(level)
            .octet(profile.light)
            .octet(floor)
            .octet(ceiling.max(floor + 1))
            .quad(profile.reawakenings)
            .ratio(profile.dominion_scale())
            .quad(profile.switches)
            .quad(profile.tutor_step)
            .quad(profile.skin_worn)
            .quad(profile.skins)
            .quad(profile.total_seals())
            .quad(profile.regions_woken())
            .quad(profile.relic_count())
            .quad(profile.cadre_size())
            .quad(profile.lattice_ranks())
            .quad(profile.medals.count_ones())
            .quad(MEDAL_COUNT as u32)
            .flag(rite_ready(profile))
            .octet(until_dawn(profile))
            .quad(profile.dawn_streak)
            .quad(ascent_tier(profile))
            .quad(ASCENT_TIERS as u32);

        let mut ready = 0u32;
        for seat in 0..3 {
            let (done, need) = edict_progress(profile, false, seat);
            if done >= need && !profile.dawn_edicts[seat].taken {
                ready += 1;
            }
            let (done, need) = edict_progress(profile, true, seat);
            if done >= need && !profile.moon_edicts[seat].taken {
                ready += 1;
            }
        }
        for tier in 0..ASCENT_TIERS as u32 {
            if ascent_claimable(profile, tier) {
                ready += 1;
                break;
            }
        }
        pen.quad(ready);

        let greet = (profile.stats[0] % GREET_LINES.len() as u64) as usize;
        pen.pair(GREET_LINES[greet]);

        match self.quest.as_ref() {
            Some(quest) if quest.live() => {
                pen.flag(true)
                    .quad(quest.region)
                    .quad(quest.node)
                    .quad(quest.depth)
                    .quad(quest.rows);
            }
            _ => {
                pen.flag(false).quad(0).quad(0).quad(0).quad(0);
            }
        }
    }

    fn write_map(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        pen.tally(REGION_COUNT);
        for region in 0..REGION_COUNT {
            let spec = &REGIONS[region];
            pen.pair(spec.name)
                .pair(spec.blurb)
                .flag(profile.region_open(region))
                .quad(profile.region_cleared(region))
                .quad(NODES_PER_REGION as u32)
                .quad(spec.foes_open)
                .quad(spec.features)
                .tally(NODES_PER_REGION);
            for node in 0..NODES_PER_REGION {
                let seat = Profile::node_seat(region, node);
                pen.flag(profile.node_open(region, node))
                    .byte(profile.seals_won[seat])
                    .flag(node == NODES_PER_REGION - 1)
                    .quad(
                        REGIONS[region].foes_open
                            + REGIONS[region].foes_bite * (node as u32 / 3),
                    )
                    .quad(REGIONS[region].shard_pay);
            }
        }
        pen.quad(NODE_TOTAL as u32)
            .quad(profile.total_seals())
            .quad((NODE_TOTAL * 3) as u32);
    }

    fn write_delve(&mut self, pen: &mut Scribe) {
        match self.quest.as_mut() {
            Some(quest) => {
                pen.flag(true);
                let profile = &self.profile;
                quest.inscribe(profile, pen);
            }
            None => {
                pen.flag(false);
            }
        }
        self.write_purse(pen);
        pen.quad(self.profile.attunement)
            .quad(self.profile.tutor_step)
            .quad(self.profile.switches)
            .quad(self.profile.skin_worn);
    }

    fn write_lattice(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        pen.quad(profile.attunement).tally(BRANCH_LINES.len());
        for (index, line) in BRANCH_LINES.iter().copied().enumerate() {
            pen.pair(line).pair(BRANCH_BLURBS[index]);
        }
        pen.tally(LATTICE_COUNT);
        for node in 0..LATTICE_COUNT {
            let spec = &LATTICE[node];
            let (shards, cores) = profile.lattice_toll(node);
            let rank = profile.lattice[node];
            let maxed = rank >= spec.ceiling;
            pen.pair(spec.name)
                .pair(spec.blurb)
                .quad(spec.branch)
                .quad(rank)
                .quad(spec.ceiling)
                .octet(shards)
                .octet(cores)
                .quad(spec.attunement)
                .flag(maxed)
                .flag(profile.attunement >= spec.attunement)
                .flag(
                    !maxed
                        && profile.attunement >= spec.attunement
                        && profile.can_pay(purse::SHARDS, shards)
                        && profile.can_pay(purse::CORES, cores),
                );
        }
        pen.quad(profile.lattice_ranks()).quad(
            LATTICE
                .iter()
                .map(|spec| spec.ceiling)
                .sum::<u32>(),
        );
    }

    fn write_cadre(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        pen.tally(SCARAB_COUNT);
        for index in 0..SCARAB_COUNT {
            let spec = &CADRE[index];
            let rank = profile.cadre[index];
            let feed = profile.scarab_feed(index);
            let resin = 6 + rank.max(1) as u64 * 2;
            let seat = profile
                .bench
                .iter()
                .position(|held| *held == index as i32)
                .map(|seat| seat as i32)
                .unwrap_or(-1);
            pen.pair(spec.name)
                .pair(spec.blurb)
                .pair(spec.trait_line)
                .quad(spec.grade)
                .quad(rank)
                .quad(spec.ceiling)
                .octet(feed)
                .octet(resin)
                .signed(seat)
                .flag(rank > 0)
                .flag(
                    rank > 0
                        && rank < spec.ceiling
                        && profile.can_pay(purse::SHARDS, feed)
                        && profile.can_pay(purse::RESIN, resin),
                )
                .quad(spec.wakes_at_region);
        }
        pen.tally(CADRE_SLOTS);
        for seat in profile.bench {
            pen.signed(seat);
        }
        let seats = profile.power_seats();
        pen.tally(seats);
        for seat in 0..seats {
            pen.signed(profile.powers.get(seat).copied().unwrap_or(-1));
        }
        pen.tally(POWER_COUNT);
        for power in 0..POWER_COUNT {
            pen.pair(POWER_NAMES[power])
                .pair(POWER_BLURBS[power])
                .quad(POWER_REST[power])
                .flag(profile.power_unlocked(power));
        }
    }

    fn write_relics(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        pen.tally(RELIC_COUNT);
        for index in 0..RELIC_COUNT {
            let spec = &RELICS[index];
            pen.pair(spec.name)
                .quad(spec.cluster)
                .quad(spec.home)
                .pair(REGIONS[(spec.home as usize).min(REGION_COUNT - 1)].name)
                .flag(profile.relics & (1 << index) != 0);
        }
        pen.tally(RELIC_SETS);
        for cluster in 0..RELIC_SETS {
            let held = RELICS
                .iter()
                .enumerate()
                .filter(|(index, spec)| {
                    spec.cluster == cluster as u32 && profile.relics & (1 << index) != 0
                })
                .count() as u32;
            let total = RELICS
                .iter()
                .filter(|spec| spec.cluster == cluster as u32)
                .count() as u32;
            pen.pair(RELIC_CLUSTER_NAMES[cluster])
                .pair(RELIC_CLUSTER_BLURBS[cluster])
                .quad(held)
                .quad(total)
                .flag(held == total);
        }
    }

    fn write_forge(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        pen.tally(RECIPE_COUNT);
        for index in 0..RECIPE_COUNT {
            let spec = &RECIPES[index];
            pen.pair(spec.name)
                .pair(spec.blurb)
                .quad(spec.resin_toll)
                .quad(spec.shard_toll)
                .quad(profile.recipes[index])
                .flag(
                    profile.recipes[index] < 9
                        && profile.can_pay(purse::RESIN, spec.resin_toll as u64)
                        && profile.can_pay(purse::SHARDS, spec.shard_toll as u64),
                );
        }
    }

    fn write_caravan(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        pen.octet(until_dawn(profile)).tally(4);
        for seat in 0..4 {
            let offer = (profile.caravan_rack[seat] as usize).min(OFFER_COUNT - 1);
            let spec = &OFFERS[offer];
            pen.quad(offer as u32)
                .pair(spec.name)
                .pair(spec.blurb)
                .quad(spec.pay_purse)
                .quad(spec.pay_amount)
                .quad(spec.get_purse)
                .quad(spec.get_amount)
                .flag(profile.caravan_taken & (1 << seat) != 0)
                .flag(profile.can_pay(spec.pay_purse as usize, spec.pay_amount as u64));
        }
        pen.quad(profile.skins).quad(profile.skin_worn);
    }

    fn write_rites(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        let slot = profile.dawn_slot % RITE_CYCLE as u32;
        pen.quad(slot)
            .quad(profile.dawn_streak)
            .flag(rite_ready(profile))
            .octet(until_dawn(profile))
            .octet(profile.stats[12])
            .tally(RITE_CYCLE);
        for day in 0..RITE_CYCLE as u32 {
            let prize = rite_prize(day, profile.dawn_streak.max(1));
            pen.quad(prize.0)
                .quad(prize.1)
                .quad(prize.2)
                .quad(prize.3)
                .flag(day == slot);
        }
    }

    fn write_ascent(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        let tier = ascent_tier(profile);
        let floor = ascent_floor(tier);
        let next = floor + ascent_bar(tier);
        pen.quad(tier)
            .quad(ASCENT_TIERS as u32)
            .octet(profile.ascent_light)
            .octet(floor)
            .octet(next)
            .tally(ASCENT_TIERS);
        for step in 0..ASCENT_TIERS as u32 {
            let prize = ascent_prize(step);
            pen.quad(prize.0)
                .quad(prize.1)
                .quad(prize.2)
                .quad(prize.3)
                .flag(profile.ascent_taken & (1u64 << step) != 0)
                .flag(ascent_claimable(profile, step));
        }
    }

    fn write_edicts(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        pen.quad(profile.rerolls);
        for moon in [false, true] {
            pen.tally(3);
            for seat in 0..3 {
                let slot = if moon {
                    profile.moon_edicts[seat]
                } else {
                    profile.dawn_edicts[seat]
                };
                let shape = (slot.shape as usize).min(EDICT_SHAPES - 1);
                let (done, need) = edict_progress(profile, moon, seat);
                let (shards, cores, resin) = edict_prize(moon, slot.shape);
                pen.pair(EDICT_SHAPES_TABLE[shape].line)
                    .octet(done)
                    .octet(need)
                    .flag(slot.taken)
                    .flag(done >= need && !slot.taken)
                    .octet(shards)
                    .octet(cores)
                    .octet(resin);
            }
        }
        pen.tally(CHRONICLE_COUNT);
        for index in 0..CHRONICLE_COUNT {
            let spec = &CHRONICLES[index];
            let (done, need) = chronicle_progress(profile, index);
            let taken = profile.chronicles & (1 << index) != 0;
            pen.pair(spec.line)
                .octet(done)
                .octet(need)
                .flag(taken)
                .flag(done >= need && !taken)
                .quad(spec.shard_prize)
                .quad(spec.core_prize);
        }
        pen.octet(until_dawn(profile));
    }

    fn write_medals(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        pen.tally(MEDAL_COUNT);
        for index in 0..MEDAL_COUNT {
            let spec = &MEDALS[index];
            let (done, need) = medal_progress(profile, index);
            pen.pair(spec.name)
                .pair(spec.blurb)
                .octet(done)
                .octet(need)
                .flag(profile.medals & (1 << index) != 0)
                .quad(spec.shard_prize)
                .quad(spec.core_prize);
        }
    }

    fn write_codex(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        pen.tally(CODEX_COUNT);
        for index in 0..CODEX_COUNT {
            pen.pair(CODEX_TITLES[index])
                .pair(CODEX_BODIES[index])
                .flag(profile.codex & (1 << index) != 0);
        }
        pen.tally(TILE_LINES.len());
        for index in 0..TILE_LINES.len() {
            pen.pair(TILE_LINES[index]).pair(TILE_BLURBS[index]);
        }
        pen.tally(BREED_NAMES.len());
        for index in 0..BREED_NAMES.len() {
            pen.pair(BREED_NAMES[index]).pair(BREED_BLURBS[index]);
        }
        pen.tally(GOAL_LINES.len());
        for index in 0..GOAL_LINES.len() {
            pen.pair(GOAL_LINES[index]).pair(GOAL_HINTS[index]);
        }
    }

    fn write_records(&mut self, pen: &mut Scribe) {
        let profile = &self.profile;
        self.write_purse(pen);
        pen.tally(STAT_LINES.len());
        for index in 0..STAT_LINES.len() {
            pen.pair(STAT_LINES[index])
                .octet(profile.stats.get(index).copied().unwrap_or(0));
        }
        pen.octet(profile.untouched)
            .octet(profile.keystone_clean)
            .octet(profile.shards_spent)
            .quad(profile.total_seals())
            .quad((NODE_TOTAL * 3) as u32)
            .quad(profile.relic_count())
            .quad(RELIC_COUNT as u32)
            .quad(profile.medals.count_ones())
            .quad(MEDAL_COUNT as u32)
            .quad(profile.lattice_ranks())
            .quad(LATTICE.iter().map(|spec| spec.ceiling).sum::<u32>())
            .quad(profile.cadre_ranks())
            .quad(profile.reawakenings)
            .flag(profile.regions_woken() >= REGION_COUNT as u32);
    }
}

// --- C surface -------------------------------------------------------------

/// Boots an oracle from a previously sealed profile. A null or corrupt blob
/// simply yields a fresh profile rather than failing the launch. `tongue` is
/// the index into the compiled language blobs, picked from the device locale.
#[no_mangle]
pub extern "C" fn vr_awaken(blob: *const u8, span: usize, tongue: u8) -> *mut Oracle {
    let bytes = if blob.is_null() || span == 0 {
        &[][..]
    } else {
        unsafe { core::slice::from_raw_parts(blob, span) }
    };
    Box::into_raw(Box::new(Oracle::wake(bytes, tongue)))
}

/// Single entry point. `out_span` receives the length of the returned frame,
/// which the caller must hand back to `vr_reclaim`.
#[no_mangle]
pub extern "C" fn vr_relay(
    handle: *mut Oracle,
    op: u32,
    body: *const u8,
    span: usize,
    out_span: *mut usize,
) -> *mut u8 {
    if handle.is_null() || out_span.is_null() {
        return core::ptr::null_mut();
    }
    let oracle = unsafe { &mut *handle };
    let payload = if body.is_null() || span == 0 {
        &[][..]
    } else {
        unsafe { core::slice::from_raw_parts(body, span) }
    };
    let frame = oracle.respond(op, payload);
    let mut boxed = frame.into_boxed_slice();
    let length = boxed.len();
    let head = boxed.as_mut_ptr();
    core::mem::forget(boxed);
    unsafe {
        *out_span = length;
    }
    head
}

#[no_mangle]
pub extern "C" fn vr_reclaim(head: *mut u8, span: usize) {
    if head.is_null() || span == 0 {
        return;
    }
    unsafe {
        let _ = Box::from_raw(core::slice::from_raw_parts_mut(head, span));
    }
}

#[no_mangle]
pub extern "C" fn vr_slumber(handle: *mut Oracle) {
    if handle.is_null() {
        return;
    }
    unsafe {
        let _ = Box::from_raw(handle);
    }
}

#[cfg(test)]
mod proofs {
    use super::*;
    use expedition::{stride, LANES};

    fn sealed_roundtrip(profile: &Profile) -> Profile {
        let blob = profile.seal();
        Profile::unseal(&blob).expect("sealed profile should reopen")
    }

    #[test]
    fn profile_survives_the_shroud() {
        let mut profile = Profile::newborn();
        profile.gain(purse::SHARDS, 1234);
        profile.lattice[3] = 2;
        profile.relics = 0b1011;
        profile.seals_won[5] = 3;
        let back = sealed_roundtrip(&profile);
        assert_eq!(back.purse[purse::SHARDS], profile.purse[purse::SHARDS]);
        assert_eq!(back.lattice[3], 2);
        assert_eq!(back.relics, 0b1011);
        assert_eq!(back.seals_won[5], 3);
    }

    #[test]
    fn tampered_save_is_refused() {
        let profile = Profile::newborn();
        let mut blob = profile.seal();
        let tail = blob.len() / 2;
        blob[tail] ^= 0x40;
        assert!(Profile::unseal(&blob).is_none());
    }

    #[test]
    fn lexicon_unwraps() {
        let words = Lexicon::unwrap_scroll(0);
        assert!(words.count() > 100, "lexicon should hold the game's text");
        assert!(!words.phrase(0).is_empty());
    }

    /// Plays a room with a dumb but honest bot: run at the nearest body until
    /// the swing lands, pick up what drops, then walk into the portal. If a
    /// chamber cannot be finished this way it cannot be finished by a player.
    fn bot_plays(quest: &mut Delve, profile: &mut Profile, patience: u32) {
        let mut guard = 0;
        let mut stuck = 0;
        let mut was = (quest.pit.hero.x, quest.pit.hero.y);
        while quest.stride == stride::FIGHT && guard < patience {
            guard += 1;
            let want = bot_target(quest);
            let (mut px, mut py) = match want {
                Some((x, y)) => (x - quest.pit.hero.x, y - quest.pit.hero.y),
                None => (0, 0),
            };
            // Shouldered up against a pillar: slide along it rather than lean
            // on it, which is what a player does without thinking about it.
            if stuck > 6 {
                let swing = py;
                py = -px;
                px = swing;
            }
            let span = (px.abs() + py.abs()).max(1);
            if !quest.steer(profile, px * 1000 / span, py * 1000 / span, 100) {
                break;
            }
            let now = (quest.pit.hero.x, quest.pit.hero.y);
            if (now.0 - was.0).abs() + (now.1 - was.1).abs() < 6 {
                stuck += 1;
            } else {
                stuck = 0;
            }
            was = now;
            if guard % 9 == 0 {
                let _ = quest.unleash(profile, 2, px, py);
            }
            if guard % 14 == 0 {
                let _ = quest.unleash(profile, 1, 0, 0);
            }
        }
    }

    /// Where the bot is headed: the nearest body, else the nearest thing worth
    /// picking up, else the way out.
    fn bot_target(quest: &Delve) -> Option<(i32, i32)> {
        let pit = &quest.pit;
        if let Some(foe) = pit.foes.iter().min_by_key(|foe| {
            (foe.x - pit.hero.x).abs() + (foe.y - pit.hero.y).abs()
        }) {
            return Some((foe.x, foe.y));
        }
        if let Some(mote) = pit
            .motes
            .iter()
            .filter(|mote| mote.kind == arena::trove::CHEST)
            .min_by_key(|mote| (mote.x - pit.hero.x).abs() + (mote.y - pit.hero.y).abs())
        {
            return Some((mote.x, mote.y));
        }
        if pit.portal {
            return Some((pit.portal_x, pit.portal_y));
        }
        None
    }

    #[test]
    fn the_hero_runs_where_the_stick_points_and_stops_at_the_wall() {
        let profile = Profile::newborn();
        let mut quest = Delve::open(&profile, 0, 0);
        quest.pit.stones.clear();
        let from = quest.pit.hero.x;
        quest.pit.advance(1000, 0, 200);
        assert!(quest.pit.hero.x > from, "pushing right has to move her right");
        for _ in 0..40 {
            quest.pit.advance(1000, 0, 200);
        }
        assert!(
            quest.pit.hero.x < arena::SPAN_X,
            "the edge of the chamber is a wall, not a door"
        );
    }

    #[test]
    fn a_standing_stone_cannot_be_walked_through() {
        let profile = Profile::newborn();
        let mut quest = Delve::open(&profile, 0, 0);
        let pit = &mut quest.pit;
        pit.stones.clear();
        pit.foes.clear();
        pit.hero.x = 400;
        pit.hero.y = 800;
        pit.stones.push(arena::Stone { x: 600, y: 800, girth: 70, look: 0 });
        for _ in 0..40 {
            pit.advance(1000, 0, 100);
        }
        let gap = (pit.hero.x - 600).abs();
        assert!(gap >= 70, "a body stops at stone, it does not pass through it");
    }

    #[test]
    fn a_bolt_puts_a_body_down_and_pays_coins() {
        let profile = Profile::newborn();
        let mut quest = Delve::open(&profile, 0, 0);
        let pit = &mut quest.pit;
        pit.stones.clear();
        pit.foes.clear();
        pit.motes.clear();
        pit.pending.clear();
        pit.hero.x = 500;
        pit.hero.y = 1000;
        pit.hero.focus = 9;
        pit.spawn_for_proof(delve::brood::HUSK, 500, 700);
        assert!(pit.cast(2, 0, -1000, 1), "a bolt with focus in hand has to fly");
        for _ in 0..30 {
            pit.advance(0, 0, 60);
            if pit.foes.is_empty() {
                break;
            }
        }
        assert!(pit.foes.is_empty(), "the bolt should have reached it");
        assert!(pit.kills > 0, "a felled body counts");
        assert!(
            pit.motes.iter().any(|mote| mote.kind == arena::trove::COIN) || pit.coins > 0,
            "something has to drop"
        );
    }

    #[test]
    fn a_cleared_chamber_opens_a_portal_and_closes_on_it() {
        let profile = Profile::newborn();
        let mut quest = Delve::open(&profile, 0, 0);
        let pit = &mut quest.pit;
        pit.foes.clear();
        pit.pending.clear();
        pit.motes.clear();
        pit.wave = pit.waves;
        pit.advance(0, 0, 60);
        assert!(pit.portal, "nothing left alive means a way out");
        pit.hero.x = pit.portal_x;
        pit.hero.y = pit.portal_y;
        pit.advance(0, 0, 60);
        assert_eq!(pit.resolved, 1, "standing in the portal finishes the room");
    }

    /// The drawing side tells one chamber from the next by the stones in it,
    /// and redraws the floor when they change. If two chambers in a row ever
    /// stood their stones identically, the one would be drawn with the other's
    /// cover and the player would walk through pillars that are not there.
    #[test]
    fn every_chamber_stands_its_stones_somewhere_new() {
        let profile = Profile::newborn();
        let mut seen: Vec<Vec<(i32, i32, i32)>> = Vec::new();
        for depth in 0..6 {
            let quest = Delve::open(&profile, 0, depth);
            let plan: Vec<(i32, i32, i32)> = quest
                .pit
                .stones
                .iter()
                .map(|stone| (stone.x, stone.y, stone.girth))
                .collect();
            assert!(!plan.is_empty(), "a chamber without cover is not a chamber");
            assert!(
                !seen.contains(&plan),
                "chamber {depth} repeats an earlier layout"
            );
            seen.push(plan);
        }
    }

    /// The jar belongs to nobody's skill tree: it answers on the seat past the
    /// last one the tree granted, it hits harder while it lasts, it lets more
    /// through while it lasts, and it wears off on its own.
    #[test]
    fn temple_beer_is_always_in_reach_and_always_wears_off() {
        let mut profile = Profile::newborn();
        let seat = profile.power_seats();
        let mut quest = Delve::open(&profile, 0, 0);
        quest.pit.hero.focus = quest.pit.hero.focus_cap.max(4);
        let sober = quest.pit.bite();

        assert!(
            quest.unleash(&mut profile, seat, 0, 0),
            "the jar must answer without anything unlocked"
        );
        assert!(quest.pit.bite() > sober, "the beer has to be worth drinking");
        assert!(
            !quest.unleash(&mut profile, seat, 0, 0),
            "a second jar before the first wore off"
        );

        // Six seconds of fight, and she is sober again.
        for _ in 0..80 {
            let _ = quest.steer(&mut profile, 0, 0, 100);
        }
        assert_eq!(quest.pit.bite(), sober, "the beer never wore off");
        assert!(
            profile.stats[16] > 0,
            "a drink nobody counted is a drink Apple cannot see either"
        );
    }

    #[test]
    fn a_hero_out_of_health_ends_the_run() {
        let mut profile = Profile::newborn();
        let mut quest = Delve::open(&profile, 0, 0);
        quest.pit.hero.hp = 1;
        quest.pit.hero.mercy = 0;
        quest.pit.foes.clear();
        quest.pit.pending.clear();
        quest.pit.spawn_for_proof(delve::brood::HUSK, quest.pit.hero.x, quest.pit.hero.y);
        for _ in 0..20 {
            let _ = quest.steer(&mut profile, 0, 0, 100);
        }
        assert_eq!(quest.stride, stride::FALLEN, "no health left is the end of it");
    }

    #[test]
    fn a_whole_descent_can_be_walked_by_a_bot() {
        // A seasoned hero, because the question here is whether the content
        // chain can be walked at all, not whether a naked run survives it.
        let mut profile = Profile::newborn();
        profile.purse[purse::SHARDS] = 0;
        profile.attunement = 30;
        profile.lattice[0] = 5;
        profile.lattice[1] = 5;
        profile.lattice[6] = 5;
        let mut quest = Delve::open(&profile, 0, 0);
        let mut guard = 0;
        while quest.live() && guard < 200 {
            guard += 1;
            match quest.stride {
                stride::FIGHT => {
                    let before = quest.depth;
                    bot_plays(&mut quest, &mut profile, 900);
                    if quest.stride == stride::FIGHT && quest.depth == before {
                        let pit = &quest.pit;
                        panic!(
                            "the bot stalled in row {before}: goal {} wave {}/{} foes {} portal {} seconds {}",
                            pit.brief.goal,
                            pit.wave,
                            pit.waves,
                            pit.foes_left(),
                            pit.portal,
                            pit.turn
                        );
                    }
                }
                stride::CARD | stride::HAVEN => {
                    assert!(quest.press_on(&profile));
                }
                stride::CACHE => {
                    assert!(quest.take_boon(&profile, 0));
                }
                stride::FORK => {
                    let lane = quest.forks[0];
                    assert!(quest.choose_fork(&profile, lane));
                }
                _ => break,
            }
        }
        assert_eq!(
            quest.stride,
            stride::CROWNED,
            "a patient hero should reach the bottom of the opening descent"
        );
        assert!(profile.purse[purse::SHARDS] > 0, "a finished descent has to pay");
    }

    #[test]
    fn the_branch_map_always_forks_and_ends_in_one_crown() {
        let profile = Profile::newborn();
        let quest = Delve::open(&profile, 2, 7);
        let crowns = (0..LANES as u32)
            .filter(|lane| {
                let stop = quest.stop_at(quest.rows - 1, *lane);
                stop.real && stop.kind == expedition::lair::CROWN
            })
            .count();
        assert_eq!(crowns, 1, "exactly one way out at the bottom");
        let middle = (0..LANES as u32)
            .filter(|lane| quest.stop_at(1, *lane).real)
            .count();
        assert!(middle >= 2, "the second row has to offer a choice");
    }

    #[test]
    fn a_trader_cannot_be_robbed() {
        let profile = Profile::newborn();
        let mut quest = Delve::open(&profile, 1, 2);
        quest.stride = stride::HAVEN;
        quest.wares = vec![expedition::ware::POULTICE];
        quest.spoils.shards = 0;
        assert!(!quest.trade(0), "no shards, no wares");
        quest.spoils.shards = 10_000;
        assert!(quest.trade(0));
        assert!(quest.spoils.shards < 10_000, "the trade has to cost something");
    }

    #[test]
    fn dawn_rite_pays_once_per_day() {
        let mut profile = Profile::newborn();
        profile.wind_clock(1_700_000_000, 0);
        turn_windows(&mut profile);
        assert!(claim_rite(&mut profile).is_some());
        assert!(claim_rite(&mut profile).is_none());
        profile.wind_clock(1_700_000_000 + 86_400, 0);
        assert!(claim_rite(&mut profile).is_some());
        assert_eq!(profile.dawn_streak, 2);
    }

    #[test]
    fn lattice_respects_attunement_and_purse() {
        let mut profile = Profile::newborn();
        profile.purse[purse::SHARDS] = 100_000;
        profile.purse[purse::CORES] = 100;
        assert!(profile.lattice_buy(0));
        // Node 23 needs attunement 18, which a newborn does not have.
        assert!(!profile.lattice_buy(23));
    }

    #[test]
    fn frames_carry_a_version_and_echo_the_opcode() {
        let mut oracle = Oracle::wake(&[], 0);
        let frame = oracle.respond(rite::HUB, &[]);
        assert_eq!(frame[0], 1);
        assert_eq!(u32::from_le_bytes([frame[2], frame[3], frame[4], frame[5]]), rite::HUB);
    }
}
