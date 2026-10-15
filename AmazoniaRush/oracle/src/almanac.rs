//! Retention systems: dawn rites, the obelisk ascent, edicts, chronicles,
//! medals and the codex. Every window is measured against the device clock and
//! a stored baseline, so none of it needs a server and none of it breaks when
//! the player is in a tunnel for a week.

use crate::atlas::*;
use crate::entropy::Drift;
use crate::ledger::{purse, EdictSlot, Profile};

/// One probe table feeds medals, edicts and chronicles alike. Indices 0..15 are
/// the plain records; above that they are derived.
pub fn probe(profile: &Profile, index: u32) -> u64 {
    match index {
        0..=15 => profile.stats.get(index as usize).copied().unwrap_or(0),
        16 => profile.lattice_ranks() as u64,
        17 => profile.cadre_size() as u64,
        18 => profile.relic_count() as u64,
        19 => ascent_tier(profile) as u64,
        20 => profile.regions_woken() as u64,
        21 => profile.untouched,
        22 => profile.clusters_full() as u64,
        23 => profile.keystone_clean,
        24 => profile.cadre_ranks() as u64,
        25 => profile.shards_spent,
        _ => 0,
    }
}

// --- dawn rites ------------------------------------------------------------

pub fn rite_ready(profile: &Profile) -> bool {
    profile.today() > profile.dawn_day
}

pub fn claim_rite(profile: &mut Profile) -> Option<(u32, u32, u32, u32)> {
    if !rite_ready(profile) {
        return None;
    }
    let today = profile.today();
    let gap = if profile.dawn_day < 0 {
        1
    } else {
        today - profile.dawn_day
    };
    if gap == 1 {
        profile.dawn_streak += 1;
    } else {
        profile.dawn_streak = 1;
    }
    profile.dawn_day = today;
    let prize = rite_prize(profile.dawn_slot, profile.dawn_streak);
    profile.dawn_slot = profile.dawn_slot.wrapping_add(1);
    profile.gain(purse::SHARDS, prize.0 as u64);
    profile.gain(purse::CORES, prize.1 as u64);
    profile.gain(purse::RESIN, prize.2 as u64);
    profile.gain(purse::SEALS, prize.3 as u64);
    profile.stats[12] = profile.stats[12].saturating_add(1);
    Some(prize)
}

/// Seconds until the next local dawn, so the UI can show a countdown offline.
pub fn until_dawn(profile: &Profile) -> u64 {
    let shifted = profile
        .clock_unix
        .saturating_add((profile.clock_shift as i64) * 60);
    let into_day = shifted.rem_euclid(86_400);
    (86_400 - into_day).max(0) as u64
}

// --- obelisk ascent --------------------------------------------------------

pub fn ascent_tier(profile: &Profile) -> u32 {
    let mut tier = 0u32;
    let mut bar = 0u64;
    while tier < ASCENT_TIERS as u32 {
        bar = bar.saturating_add(ascent_bar(tier));
        if profile.ascent_light < bar {
            break;
        }
        tier += 1;
    }
    tier
}

pub fn ascent_floor(tier: u32) -> u64 {
    let mut bar = 0u64;
    for step in 0..tier {
        bar = bar.saturating_add(ascent_bar(step));
    }
    bar
}

pub fn ascent_claimable(profile: &Profile, tier: u32) -> bool {
    tier < ASCENT_TIERS as u32
        && ascent_tier(profile) > tier
        && profile.ascent_taken & (1u64 << tier) == 0
}

pub fn claim_ascent(profile: &mut Profile, tier: u32) -> bool {
    if !ascent_claimable(profile, tier) {
        return false;
    }
    profile.ascent_taken |= 1u64 << tier;
    let prize = ascent_prize(tier);
    profile.gain(purse::SHARDS, prize.0 as u64);
    profile.gain(purse::CORES, prize.1 as u64);
    profile.gain(purse::RESIN, prize.2 as u64);
    profile.gain(purse::SEALS, prize.3 as u64);
    true
}

// --- edicts ----------------------------------------------------------------

fn roll_edicts(profile: &mut Profile, moon: bool, salt: u64) {
    let stamp = if moon {
        profile.this_week()
    } else {
        profile.today()
    };
    let mut drift = Drift::seeded((stamp as u64).wrapping_mul(0x51_7CC1_B727_220A) ^ salt);
    let mut pool: Vec<u32> = (0..EDICT_SHAPES as u32).collect();
    drift.jumble(&mut pool);
    for seat in 0..3 {
        let shape = pool.get(seat).copied().unwrap_or(0);
        let spec = &EDICT_SHAPES_TABLE[shape as usize];
        let need = if moon {
            spec.moon_need as u64
        } else {
            spec.dawn_need as u64
        };
        let slot = EdictSlot {
            shape,
            need,
            baseline: probe(profile, spec.probe),
            taken: false,
        };
        if moon {
            profile.moon_edicts[seat] = slot;
        } else {
            profile.dawn_edicts[seat] = slot;
        }
    }
}

/// Called whenever the oracle learns the time. Rolls fresh edicts on rollover.
pub fn turn_windows(profile: &mut Profile) {
    let today = profile.today();
    let week = profile.this_week();
    if profile.day_stamp != today {
        profile.day_stamp = today;
        profile.rerolls = 2;
        roll_edicts(profile, false, 0x1F3A_5C07_9B24_6D81);
    }
    if profile.week_stamp != week {
        profile.week_stamp = week;
        roll_edicts(profile, true, 0x7B2E_91D4_0C65_38AF);
    }
    if profile.dawn_edicts[0].need == 0 {
        roll_edicts(profile, false, 0x1F3A_5C07_9B24_6D81);
    }
    if profile.moon_edicts[0].need == 0 {
        roll_edicts(profile, true, 0x7B2E_91D4_0C65_38AF);
    }
}

pub fn edict_progress(profile: &Profile, moon: bool, seat: usize) -> (u64, u64) {
    let slot = if moon {
        profile.moon_edicts.get(seat)
    } else {
        profile.dawn_edicts.get(seat)
    };
    let Some(slot) = slot.copied() else {
        return (0, 1);
    };
    let spec = &EDICT_SHAPES_TABLE[(slot.shape as usize).min(EDICT_SHAPES - 1)];
    let now = probe(profile, spec.probe);
    let done = now.saturating_sub(slot.baseline).min(slot.need);
    (done, slot.need.max(1))
}

pub fn edict_prize(moon: bool, shape: u32) -> (u64, u64, u64) {
    let weight = 1 + shape as u64 % 3;
    if moon {
        (900 + weight * 240, 2, 26 + weight * 6)
    } else {
        (220 + weight * 60, 0, 8 + weight * 3)
    }
}

pub fn claim_edict(profile: &mut Profile, moon: bool, seat: usize) -> bool {
    if seat >= 3 {
        return false;
    }
    let (done, need) = edict_progress(profile, moon, seat);
    let slot = if moon {
        profile.moon_edicts[seat]
    } else {
        profile.dawn_edicts[seat]
    };
    if slot.taken || done < need {
        return false;
    }
    if moon {
        profile.moon_edicts[seat].taken = true;
    } else {
        profile.dawn_edicts[seat].taken = true;
    }
    let (shards, cores, resin) = edict_prize(moon, slot.shape);
    profile.gain(purse::SHARDS, shards);
    profile.gain(purse::CORES, cores);
    profile.gain(purse::RESIN, resin);
    profile.absorb_light(if moon { 1_400 } else { 420 });
    true
}

pub fn reroll_edict(profile: &mut Profile, seat: usize) -> bool {
    if seat >= 3 || profile.rerolls == 0 || profile.dawn_edicts[seat].taken {
        return false;
    }
    profile.rerolls -= 1;
    let spin = probe(profile, 0)
        .wrapping_add(seat as u64)
        .wrapping_mul(0x2545_F491_4F6C_DD1D);
    let mut drift = Drift::seeded(spin ^ (profile.today() as u64));
    let shape = drift.below(EDICT_SHAPES as u32);
    let spec = &EDICT_SHAPES_TABLE[shape as usize];
    profile.dawn_edicts[seat] = EdictSlot {
        shape,
        need: spec.dawn_need as u64,
        baseline: probe(profile, spec.probe),
        taken: false,
    };
    true
}

// --- chronicles, medals, codex --------------------------------------------

pub fn chronicle_progress(profile: &Profile, index: usize) -> (u64, u64) {
    let Some(spec) = CHRONICLES.get(index) else {
        return (0, 1);
    };
    let now = probe(profile, spec.probe);
    (now.min(spec.need as u64), spec.need as u64)
}

pub fn claim_chronicle(profile: &mut Profile, index: usize) -> bool {
    if index >= CHRONICLE_COUNT || profile.chronicles & (1 << index) != 0 {
        return false;
    }
    let (done, need) = chronicle_progress(profile, index);
    if done < need {
        return false;
    }
    profile.chronicles |= 1 << index;
    let spec = &CHRONICLES[index];
    profile.gain(purse::SHARDS, spec.shard_prize as u64);
    profile.gain(purse::CORES, spec.core_prize as u64);
    profile.absorb_light(2_600);
    true
}

pub fn medal_progress(profile: &Profile, index: usize) -> (u64, u64) {
    let Some(spec) = MEDALS.get(index) else {
        return (0, 1);
    };
    let now = probe(profile, spec.probe);
    (now.min(spec.need as u64), spec.need as u64)
}

/// Grants every medal whose condition is now satisfied. Returns how many were
/// newly struck so the UI can show a stack of pop-ups.
pub fn strike_medals(profile: &mut Profile) -> u32 {
    let mut struck = 0;
    for index in 0..MEDAL_COUNT {
        if profile.medals & (1 << index) != 0 {
            continue;
        }
        let (done, need) = medal_progress(profile, index);
        if done < need {
            continue;
        }
        profile.medals |= 1 << index;
        let spec = &MEDALS[index];
        profile.gain(purse::SHARDS, spec.shard_prize as u64);
        profile.gain(purse::CORES, spec.core_prize as u64);
        struck += 1;
    }
    struck
}

/// Codex pages open as the player actually meets the thing they describe.
pub fn open_codex(profile: &mut Profile, region: u32) -> u32 {
    let mut opened = 0;
    for index in 0..CODEX_COUNT {
        if profile.codex & (1 << index) != 0 {
            continue;
        }
        if CODEX_KEYS[index] <= region {
            profile.codex |= 1 << index;
            opened += 1;
        }
    }
    opened
}
