//! Static content tables. Tuning lives here and nowhere else, so balance is one
//! file to read and one file to change. Art is deliberately absent: the oracle
//! speaks in numbers and the presentation layer decides what a number looks like.

use crate::lexicon_table as lx;


pub const REGION_COUNT: usize = 7;
pub const NODES_PER_REGION: usize = 12;
pub const LATTICE_COUNT: usize = 24;
pub const SCARAB_COUNT: usize = 8;
pub const RELIC_COUNT: usize = 16;
pub const RELIC_SETS: usize = 4;
pub const RECIPE_COUNT: usize = 8;
pub const OFFER_COUNT: usize = 6;
pub const BOON_COUNT: usize = 14;
pub const POWER_COUNT: usize = 6;
pub const BREED_COUNT: usize = 8;
pub const GOAL_COUNT: usize = 6;
pub const HAUNT_COUNT: usize = 9;
pub const WARE_COUNT: usize = 8;
pub const TILE_COUNT: usize = 7;
pub const MEDAL_COUNT: usize = 24;
pub const CODEX_COUNT: usize = 20;
pub const EDICT_SHAPES: usize = 12;
pub const CHRONICLE_COUNT: usize = 12;
pub const ASCENT_TIERS: usize = 60;
pub const RITE_CYCLE: usize = 7;
pub const PROBE_COUNT: usize = 26;
pub const POWER_SLOTS: usize = 4;

/// The jar. It sits outside the seats the skill tree hands out: every scarab
/// carries it from the entrance, and nothing in the tree can take it away.
pub const BREW_POWER: usize = 5;
pub const CADRE_SLOTS: usize = 3;

/// Which pieces of temple machinery a region is allowed to install. Regions
/// hand them out one at a time, so a player meets a single new idea per step
/// instead of all ten at once.
pub mod fixture {
    pub const PIT: u32 = 1 << 0;
    pub const CUBE: u32 = 1 << 1;
    pub const SPIKES: u32 = 1 << 2;
    pub const GLYPH: u32 = 1 << 3;
    pub const VORTEX: u32 = 1 << 4;
    pub const PLATE: u32 = 1 << 5;
    pub const LENS: u32 = 1 << 6;
    pub const MIRROR: u32 = 1 << 7;
    pub const BRAZIER: u32 = 1 << 8;
    pub const VENT: u32 = 1 << 9;
    pub const DART: u32 = 1 << 10;
}

/// Which room shapes a region may deal out on its branch map.
pub mod haunt {
    pub const SKIRMISH: u32 = 1 << 0;
    pub const ELITE: u32 = 1 << 1;
    pub const SNARE: u32 = 1 << 2;
    pub const TROVE: u32 = 1 << 3;
    pub const SWARM: u32 = 1 << 4;
    pub const SIEGE: u32 = 1 << 5;
    pub const CAMP: u32 = 1 << 6;
    pub const TRADER: u32 = 1 << 7;
    pub const CROWN: u32 = 1 << 8;
}

pub struct RegionSpec {
    pub name: u16,
    pub blurb: u16,
    /// Bodies in the opening room, and how many more each node adds.
    pub foes_open: u32,
    pub foes_bite: u32,
    /// Rooms on the branch map.
    pub rooms_open: u32,
    pub rooms_bite: u32,
    /// Turns a siege room asks the hero to hold out.
    pub endure_turns: u32,
    pub shard_pay: u32,
    pub core_odds: u32,
    pub seal_odds: u32,
    pub resin_pay: u32,
    pub features: u32,
    pub haunts: u32,
}

const OPENING_HAUNTS: u32 = haunt::SKIRMISH | haunt::TROVE | haunt::CAMP | haunt::CROWN;

pub const REGIONS: [RegionSpec; REGION_COUNT] = [
    RegionSpec {
        name: lx::L_REGION_NAME_0,
        blurb: lx::L_REGION_BLURB_0,
        foes_open: 3,
        foes_bite: 1,
        rooms_open: 4,
        rooms_bite: 0,
        endure_turns: 8,
        shard_pay: 10,
        core_odds: 0,
        seal_odds: 20,
        resin_pay: 4,
        features: fixture::CUBE | fixture::SPIKES | fixture::DART | fixture::GLYPH,
        haunts: OPENING_HAUNTS | haunt::ELITE | haunt::SWARM,
    },
    RegionSpec {
        name: lx::L_REGION_NAME_1,
        blurb: lx::L_REGION_BLURB_1,
        foes_open: 4,
        foes_bite: 1,
        rooms_open: 5,
        rooms_bite: 0,
        endure_turns: 9,
        shard_pay: 14,
        core_odds: 15,
        seal_odds: 35,
        resin_pay: 6,
        features: fixture::CUBE
            | fixture::PIT
            | fixture::SPIKES
            | fixture::DART
            | fixture::GLYPH
            | fixture::VENT,
        haunts: OPENING_HAUNTS | haunt::SNARE | haunt::TRADER | haunt::ELITE | haunt::SWARM,
    },
    RegionSpec {
        name: lx::L_REGION_NAME_2,
        blurb: lx::L_REGION_BLURB_2,
        foes_open: 3,
        foes_bite: 1,
        rooms_open: 5,
        rooms_bite: 1,
        endure_turns: 10,
        shard_pay: 19,
        core_odds: 30,
        seal_odds: 45,
        resin_pay: 8,
        features: fixture::CUBE
            | fixture::PIT
            | fixture::SPIKES
            | fixture::PLATE
            | fixture::GLYPH
            | fixture::DART
            | fixture::VENT
            | fixture::LENS,
        haunts: OPENING_HAUNTS | haunt::SNARE | haunt::TRADER | haunt::ELITE,
    },
    RegionSpec {
        name: lx::L_REGION_NAME_3,
        blurb: lx::L_REGION_BLURB_3,
        foes_open: 4,
        foes_bite: 1,
        rooms_open: 6,
        rooms_bite: 1,
        endure_turns: 11,
        shard_pay: 25,
        core_odds: 45,
        seal_odds: 55,
        resin_pay: 11,
        features: fixture::CUBE
            | fixture::PIT
            | fixture::SPIKES
            | fixture::PLATE
            | fixture::GLYPH
            | fixture::VORTEX
            | fixture::DART
            | fixture::VENT
            | fixture::MIRROR
            | fixture::LENS,
        haunts: OPENING_HAUNTS | haunt::SNARE | haunt::TRADER | haunt::ELITE | haunt::SWARM,
    },
    RegionSpec {
        name: lx::L_REGION_NAME_4,
        blurb: lx::L_REGION_BLURB_4,
        foes_open: 4,
        foes_bite: 2,
        rooms_open: 6,
        rooms_bite: 1,
        endure_turns: 12,
        shard_pay: 32,
        core_odds: 60,
        seal_odds: 60,
        resin_pay: 14,
        features: fixture::CUBE
            | fixture::PIT
            | fixture::SPIKES
            | fixture::PLATE
            | fixture::GLYPH
            | fixture::VORTEX
            | fixture::LENS
            | fixture::DART
            | fixture::MIRROR
            | fixture::VENT,
        haunts: OPENING_HAUNTS
            | haunt::SNARE
            | haunt::TRADER
            | haunt::ELITE
            | haunt::SWARM
            | haunt::SIEGE,
    },
    RegionSpec {
        name: lx::L_REGION_NAME_5,
        blurb: lx::L_REGION_BLURB_5,
        foes_open: 5,
        foes_bite: 2,
        rooms_open: 7,
        rooms_bite: 1,
        endure_turns: 13,
        shard_pay: 41,
        core_odds: 80,
        seal_odds: 70,
        resin_pay: 18,
        features: fixture::CUBE
            | fixture::PIT
            | fixture::SPIKES
            | fixture::PLATE
            | fixture::GLYPH
            | fixture::VORTEX
            | fixture::LENS
            | fixture::MIRROR
            | fixture::BRAZIER
            | fixture::DART
            | fixture::VENT,
        haunts: OPENING_HAUNTS
            | haunt::SNARE
            | haunt::TRADER
            | haunt::ELITE
            | haunt::SWARM
            | haunt::SIEGE,
    },
    RegionSpec {
        name: lx::L_REGION_NAME_6,
        blurb: lx::L_REGION_BLURB_6,
        foes_open: 5,
        foes_bite: 2,
        rooms_open: 8,
        rooms_bite: 1,
        endure_turns: 14,
        shard_pay: 52,
        core_odds: 110,
        seal_odds: 80,
        resin_pay: 23,
        features: fixture::CUBE
            | fixture::PIT
            | fixture::SPIKES
            | fixture::PLATE
            | fixture::GLYPH
            | fixture::VORTEX
            | fixture::LENS
            | fixture::MIRROR
            | fixture::BRAZIER
            | fixture::VENT
            | fixture::DART,
        haunts: OPENING_HAUNTS
            | haunt::SNARE
            | haunt::TRADER
            | haunt::ELITE
            | haunt::SWARM
            | haunt::SIEGE,
    },
];

pub struct LatticeSpec {
    pub name: u16,
    pub blurb: u16,
    pub branch: u32,
    pub ceiling: u32,
    pub toll_open: u32,
    pub toll_climb: u32,
    pub core_toll: u32,
    pub attunement: u32,
}

pub const LATTICE: [LatticeSpec; LATTICE_COUNT] = [
    LatticeSpec { name: lx::L_LATTICE_NODE_0,  blurb: lx::L_LATTICE_NODE_BLURB_0,  branch: 0, ceiling: 6, toll_open: 140,  toll_climb: 180,  core_toll: 0, attunement: 1 },
    LatticeSpec { name: lx::L_LATTICE_NODE_1,  blurb: lx::L_LATTICE_NODE_BLURB_1,  branch: 0, ceiling: 8, toll_open: 120,  toll_climb: 150,  core_toll: 0, attunement: 2 },
    LatticeSpec { name: lx::L_LATTICE_NODE_2,  blurb: lx::L_LATTICE_NODE_BLURB_2,  branch: 0, ceiling: 4, toll_open: 320,  toll_climb: 440,  core_toll: 1, attunement: 5 },
    LatticeSpec { name: lx::L_LATTICE_NODE_3,  blurb: lx::L_LATTICE_NODE_BLURB_3,  branch: 0, ceiling: 4, toll_open: 400,  toll_climb: 520,  core_toll: 1, attunement: 9 },
    LatticeSpec { name: lx::L_LATTICE_NODE_4,  blurb: lx::L_LATTICE_NODE_BLURB_4,  branch: 0, ceiling: 5, toll_open: 260,  toll_climb: 300,  core_toll: 0, attunement: 4 },
    LatticeSpec { name: lx::L_LATTICE_NODE_5,  blurb: lx::L_LATTICE_NODE_BLURB_5,  branch: 0, ceiling: 5, toll_open: 300,  toll_climb: 360,  core_toll: 0, attunement: 7 },
    LatticeSpec { name: lx::L_LATTICE_NODE_6,  blurb: lx::L_LATTICE_NODE_BLURB_6,  branch: 1, ceiling: 5, toll_open: 200,  toll_climb: 320,  core_toll: 0, attunement: 1 },
    LatticeSpec { name: lx::L_LATTICE_NODE_7,  blurb: lx::L_LATTICE_NODE_BLURB_7,  branch: 1, ceiling: 3, toll_open: 420,  toll_climb: 600,  core_toll: 1, attunement: 8 },
    LatticeSpec { name: lx::L_LATTICE_NODE_8,  blurb: lx::L_LATTICE_NODE_BLURB_8,  branch: 1, ceiling: 6, toll_open: 240,  toll_climb: 280,  core_toll: 0, attunement: 10 },
    LatticeSpec { name: lx::L_LATTICE_NODE_9,  blurb: lx::L_LATTICE_NODE_BLURB_9,  branch: 1, ceiling: 3, toll_open: 500,  toll_climb: 700,  core_toll: 2, attunement: 14 },
    LatticeSpec { name: lx::L_LATTICE_NODE_10, blurb: lx::L_LATTICE_NODE_BLURB_10, branch: 1, ceiling: 5, toll_open: 280,  toll_climb: 340,  core_toll: 0, attunement: 6 },
    LatticeSpec { name: lx::L_LATTICE_NODE_11, blurb: lx::L_LATTICE_NODE_BLURB_11, branch: 1, ceiling: 6, toll_open: 460,  toll_climb: 560,  core_toll: 1, attunement: 12 },
    LatticeSpec { name: lx::L_LATTICE_NODE_12, blurb: lx::L_LATTICE_NODE_BLURB_12, branch: 2, ceiling: 8, toll_open: 160,  toll_climb: 210,  core_toll: 0, attunement: 1 },
    LatticeSpec { name: lx::L_LATTICE_NODE_13, blurb: lx::L_LATTICE_NODE_BLURB_13, branch: 2, ceiling: 6, toll_open: 380,  toll_climb: 480,  core_toll: 1, attunement: 6 },
    LatticeSpec { name: lx::L_LATTICE_NODE_14, blurb: lx::L_LATTICE_NODE_BLURB_14, branch: 2, ceiling: 6, toll_open: 220,  toll_climb: 260,  core_toll: 0, attunement: 3 },
    LatticeSpec { name: lx::L_LATTICE_NODE_15, blurb: lx::L_LATTICE_NODE_BLURB_15, branch: 2, ceiling: 8, toll_open: 300,  toll_climb: 340,  core_toll: 0, attunement: 5 },
    LatticeSpec { name: lx::L_LATTICE_NODE_16, blurb: lx::L_LATTICE_NODE_BLURB_16, branch: 2, ceiling: 5, toll_open: 340,  toll_climb: 420,  core_toll: 1, attunement: 9 },
    LatticeSpec { name: lx::L_LATTICE_NODE_17, blurb: lx::L_LATTICE_NODE_BLURB_17, branch: 2, ceiling: 6, toll_open: 180,  toll_climb: 240,  core_toll: 0, attunement: 2 },
    LatticeSpec { name: lx::L_LATTICE_NODE_18, blurb: lx::L_LATTICE_NODE_BLURB_18, branch: 3, ceiling: 6, toll_open: 240,  toll_climb: 300,  core_toll: 0, attunement: 3 },
    LatticeSpec { name: lx::L_LATTICE_NODE_19, blurb: lx::L_LATTICE_NODE_BLURB_19, branch: 3, ceiling: 1, toll_open: 900,  toll_climb: 0,    core_toll: 3, attunement: 11 },
    LatticeSpec { name: lx::L_LATTICE_NODE_20, blurb: lx::L_LATTICE_NODE_BLURB_20, branch: 3, ceiling: 1, toll_open: 700,  toll_climb: 0,    core_toll: 2, attunement: 8 },
    LatticeSpec { name: lx::L_LATTICE_NODE_21, blurb: lx::L_LATTICE_NODE_BLURB_21, branch: 3, ceiling: 1, toll_open: 520,  toll_climb: 0,    core_toll: 1, attunement: 10 },
    LatticeSpec { name: lx::L_LATTICE_NODE_22, blurb: lx::L_LATTICE_NODE_BLURB_22, branch: 3, ceiling: 1, toll_open: 1100, toll_climb: 0,    core_toll: 4, attunement: 16 },
    LatticeSpec { name: lx::L_LATTICE_NODE_23, blurb: lx::L_LATTICE_NODE_BLURB_23, branch: 3, ceiling: 1, toll_open: 800,  toll_climb: 0,    core_toll: 3, attunement: 18 },
];

pub struct ScarabSpec {
    pub name: u16,
    pub blurb: u16,
    pub trait_line: u16,
    pub grade: u32,
    pub ceiling: u32,
    pub feed_open: u32,
    pub feed_climb: u32,
    pub wakes_at_region: u32,
}

pub const CADRE: [ScarabSpec; SCARAB_COUNT] = [
    ScarabSpec { name: lx::L_SCARAB_NAME_0, blurb: lx::L_SCARAB_BLURB_0, trait_line: lx::L_SCARAB_TRAIT_0, grade: 0, ceiling: 20, feed_open: 90,  feed_climb: 70,  wakes_at_region: 0 },
    ScarabSpec { name: lx::L_SCARAB_NAME_1, blurb: lx::L_SCARAB_BLURB_1, trait_line: lx::L_SCARAB_TRAIT_1, grade: 0, ceiling: 20, feed_open: 110, feed_climb: 80,  wakes_at_region: 1 },
    ScarabSpec { name: lx::L_SCARAB_NAME_2, blurb: lx::L_SCARAB_BLURB_2, trait_line: lx::L_SCARAB_TRAIT_2, grade: 1, ceiling: 20, feed_open: 150, feed_climb: 110, wakes_at_region: 2 },
    ScarabSpec { name: lx::L_SCARAB_NAME_3, blurb: lx::L_SCARAB_BLURB_3, trait_line: lx::L_SCARAB_TRAIT_3, grade: 1, ceiling: 20, feed_open: 170, feed_climb: 120, wakes_at_region: 3 },
    ScarabSpec { name: lx::L_SCARAB_NAME_4, blurb: lx::L_SCARAB_BLURB_4, trait_line: lx::L_SCARAB_TRAIT_4, grade: 1, ceiling: 20, feed_open: 190, feed_climb: 130, wakes_at_region: 3 },
    ScarabSpec { name: lx::L_SCARAB_NAME_5, blurb: lx::L_SCARAB_BLURB_5, trait_line: lx::L_SCARAB_TRAIT_5, grade: 2, ceiling: 20, feed_open: 230, feed_climb: 160, wakes_at_region: 4 },
    ScarabSpec { name: lx::L_SCARAB_NAME_6, blurb: lx::L_SCARAB_BLURB_6, trait_line: lx::L_SCARAB_TRAIT_6, grade: 2, ceiling: 20, feed_open: 260, feed_climb: 180, wakes_at_region: 5 },
    ScarabSpec { name: lx::L_SCARAB_NAME_7, blurb: lx::L_SCARAB_BLURB_7, trait_line: lx::L_SCARAB_TRAIT_7, grade: 3, ceiling: 20, feed_open: 320, feed_climb: 220, wakes_at_region: 6 },
];

pub struct RelicSpec {
    pub name: u16,
    pub cluster: u32,
    pub home: u32,
}

pub const RELICS: [RelicSpec; RELIC_COUNT] = [
    RelicSpec { name: lx::L_RELIC_NAME_0,  cluster: 0, home: 0 },
    RelicSpec { name: lx::L_RELIC_NAME_1,  cluster: 0, home: 1 },
    RelicSpec { name: lx::L_RELIC_NAME_2,  cluster: 0, home: 2 },
    RelicSpec { name: lx::L_RELIC_NAME_3,  cluster: 0, home: 3 },
    RelicSpec { name: lx::L_RELIC_NAME_4,  cluster: 1, home: 1 },
    RelicSpec { name: lx::L_RELIC_NAME_5,  cluster: 1, home: 2 },
    RelicSpec { name: lx::L_RELIC_NAME_6,  cluster: 1, home: 4 },
    RelicSpec { name: lx::L_RELIC_NAME_7,  cluster: 1, home: 6 },
    RelicSpec { name: lx::L_RELIC_NAME_8,  cluster: 2, home: 2 },
    RelicSpec { name: lx::L_RELIC_NAME_9,  cluster: 2, home: 3 },
    RelicSpec { name: lx::L_RELIC_NAME_10, cluster: 2, home: 4 },
    RelicSpec { name: lx::L_RELIC_NAME_11, cluster: 2, home: 5 },
    RelicSpec { name: lx::L_RELIC_NAME_12, cluster: 3, home: 3 },
    RelicSpec { name: lx::L_RELIC_NAME_13, cluster: 3, home: 4 },
    RelicSpec { name: lx::L_RELIC_NAME_14, cluster: 3, home: 5 },
    RelicSpec { name: lx::L_RELIC_NAME_15, cluster: 3, home: 6 },
];

pub const RELIC_CLUSTER_NAMES: [u16; RELIC_SETS] = [
    lx::L_RELIC_SET_0,
    lx::L_RELIC_SET_1,
    lx::L_RELIC_SET_2,
    lx::L_RELIC_SET_3,
];

pub const RELIC_CLUSTER_BLURBS: [u16; RELIC_SETS] = [
    lx::L_RELIC_SET_BLURB_0,
    lx::L_RELIC_SET_BLURB_1,
    lx::L_RELIC_SET_BLURB_2,
    lx::L_RELIC_SET_BLURB_3,
];

pub struct RecipeSpec {
    pub name: u16,
    pub blurb: u16,
    pub resin_toll: u32,
    pub shard_toll: u32,
}

pub const RECIPES: [RecipeSpec; RECIPE_COUNT] = [
    RecipeSpec { name: lx::L_RECIPE_NAME_0, blurb: lx::L_RECIPE_BLURB_0, resin_toll: 30,  shard_toll: 120 },
    RecipeSpec { name: lx::L_RECIPE_NAME_1, blurb: lx::L_RECIPE_BLURB_1, resin_toll: 34,  shard_toll: 140 },
    RecipeSpec { name: lx::L_RECIPE_NAME_2, blurb: lx::L_RECIPE_BLURB_2, resin_toll: 22,  shard_toll: 90 },
    RecipeSpec { name: lx::L_RECIPE_NAME_3, blurb: lx::L_RECIPE_BLURB_3, resin_toll: 40,  shard_toll: 160 },
    RecipeSpec { name: lx::L_RECIPE_NAME_4, blurb: lx::L_RECIPE_BLURB_4, resin_toll: 26,  shard_toll: 110 },
    RecipeSpec { name: lx::L_RECIPE_NAME_5, blurb: lx::L_RECIPE_BLURB_5, resin_toll: 44,  shard_toll: 180 },
    RecipeSpec { name: lx::L_RECIPE_NAME_6, blurb: lx::L_RECIPE_BLURB_6, resin_toll: 36,  shard_toll: 150 },
    RecipeSpec { name: lx::L_RECIPE_NAME_7, blurb: lx::L_RECIPE_BLURB_7, resin_toll: 50,  shard_toll: 200 },
];

pub struct OfferSpec {
    pub name: u16,
    pub blurb: u16,
    pub pay_purse: u32,
    pub pay_amount: u32,
    pub get_purse: u32,
    pub get_amount: u32,
}

pub const OFFERS: [OfferSpec; OFFER_COUNT] = [
    OfferSpec { name: lx::L_OFFER_NAME_0, blurb: lx::L_OFFER_BLURB_0, pay_purse: 1, pay_amount: 1,   get_purse: 0, get_amount: 1600 },
    OfferSpec { name: lx::L_OFFER_NAME_1, blurb: lx::L_OFFER_BLURB_1, pay_purse: 0, pay_amount: 700, get_purse: 2, get_amount: 60 },
    OfferSpec { name: lx::L_OFFER_NAME_2, blurb: lx::L_OFFER_BLURB_2, pay_purse: 0, pay_amount: 900, get_purse: 3, get_amount: 2 },
    OfferSpec { name: lx::L_OFFER_NAME_3, blurb: lx::L_OFFER_BLURB_3, pay_purse: 0, pay_amount: 2400, get_purse: 1, get_amount: 1 },
    OfferSpec { name: lx::L_OFFER_NAME_4, blurb: lx::L_OFFER_BLURB_4, pay_purse: 2, pay_amount: 80,  get_purse: 4, get_amount: 1 },
    OfferSpec { name: lx::L_OFFER_NAME_5, blurb: lx::L_OFFER_BLURB_5, pay_purse: 0, pay_amount: 1500, get_purse: 5, get_amount: 1 },
];

pub const BOON_NAMES: [u16; BOON_COUNT] = lx::G_BOON_NAME;
pub const BOON_BLURBS: [u16; BOON_COUNT] = lx::G_BOON_BLURB;
pub const POWER_NAMES: [u16; POWER_COUNT] = lx::G_POWER_NAME;
pub const POWER_BLURBS: [u16; POWER_COUNT] = lx::G_POWER_BLURB;

/// Turns a knack needs to recharge, before modifiers.
pub const POWER_REST: [u32; POWER_COUNT] = [3, 4, 5, 4, 6, 5];

/// Vigour each knack burns when it is unleashed.
pub const POWER_TOLL: [i32; POWER_COUNT] = [1, 2, 2, 2, 1, 2];

pub const BREED_NAMES: [u16; BREED_COUNT] = lx::G_BREED_NAME;
pub const BREED_BLURBS: [u16; BREED_COUNT] = lx::G_BREED_BLURB;
pub const GOAL_LINES: [u16; GOAL_COUNT] = lx::G_GOAL_NAME;
pub const GOAL_HINTS: [u16; GOAL_COUNT] = lx::G_GOAL_HINT;
pub const HAUNT_LINES: [u16; HAUNT_COUNT] = lx::G_HAUNT_NAME;
pub const HAUNT_BLURBS: [u16; HAUNT_COUNT] = lx::G_HAUNT_BLURB;
pub const WARE_LINES: [u16; WARE_COUNT] = lx::G_WARE_NAME;
pub const WARE_BLURBS: [u16; WARE_COUNT] = lx::G_WARE_BLURB;

/// What a mid-run trader charges, in shards carried by the current expedition.
pub const WARE_TOLL: [u64; WARE_COUNT] = [70, 110, 120, 150, 90, 260, 80, 100];

pub struct MedalSpec {
    pub name: u16,
    pub blurb: u16,
    pub probe: u32,
    pub need: u32,
    pub shard_prize: u32,
    pub core_prize: u32,
}

pub const MEDALS: [MedalSpec; MEDAL_COUNT] = [
    MedalSpec { name: lx::L_MEDAL_NAME_0,  blurb: lx::L_MEDAL_BLURB_0,  probe: 1,  need: 1,     shard_prize: 50,   core_prize: 0 },
    MedalSpec { name: lx::L_MEDAL_NAME_1,  blurb: lx::L_MEDAL_BLURB_1,  probe: 21, need: 1,     shard_prize: 120,  core_prize: 0 },
    MedalSpec { name: lx::L_MEDAL_NAME_2,  blurb: lx::L_MEDAL_BLURB_2,  probe: 3,  need: 10,    shard_prize: 150,  core_prize: 0 },
    MedalSpec { name: lx::L_MEDAL_NAME_3,  blurb: lx::L_MEDAL_BLURB_3,  probe: 3,  need: 30,    shard_prize: 600,  core_prize: 1 },
    MedalSpec { name: lx::L_MEDAL_NAME_4,  blurb: lx::L_MEDAL_BLURB_4,  probe: 23, need: 1,     shard_prize: 400,  core_prize: 1 },
    MedalSpec { name: lx::L_MEDAL_NAME_5,  blurb: lx::L_MEDAL_BLURB_5,  probe: 5,  need: 100,   shard_prize: 500,  core_prize: 1 },
    MedalSpec { name: lx::L_MEDAL_NAME_6,  blurb: lx::L_MEDAL_BLURB_6,  probe: 6,  need: 50,    shard_prize: 350,  core_prize: 0 },
    MedalSpec { name: lx::L_MEDAL_NAME_7,  blurb: lx::L_MEDAL_BLURB_7,  probe: 7,  need: 500,   shard_prize: 700,  core_prize: 1 },
    MedalSpec { name: lx::L_MEDAL_NAME_8,  blurb: lx::L_MEDAL_BLURB_8,  probe: 14, need: 1,     shard_prize: 200,  core_prize: 1 },
    MedalSpec { name: lx::L_MEDAL_NAME_9,  blurb: lx::L_MEDAL_BLURB_9,  probe: 14, need: 7,     shard_prize: 2500, core_prize: 6 },
    MedalSpec { name: lx::L_MEDAL_NAME_10, blurb: lx::L_MEDAL_BLURB_10, probe: 16, need: 60,    shard_prize: 900,  core_prize: 2 },
    MedalSpec { name: lx::L_MEDAL_NAME_11, blurb: lx::L_MEDAL_BLURB_11, probe: 16, need: 121,   shard_prize: 3000, core_prize: 8 },
    MedalSpec { name: lx::L_MEDAL_NAME_12, blurb: lx::L_MEDAL_BLURB_12, probe: 17, need: 8,     shard_prize: 1200, core_prize: 3 },
    MedalSpec { name: lx::L_MEDAL_NAME_13, blurb: lx::L_MEDAL_BLURB_13, probe: 18, need: 16,    shard_prize: 2000, core_prize: 5 },
    MedalSpec { name: lx::L_MEDAL_NAME_14, blurb: lx::L_MEDAL_BLURB_14, probe: 12, need: 10,    shard_prize: 250,  core_prize: 0 },
    MedalSpec { name: lx::L_MEDAL_NAME_15, blurb: lx::L_MEDAL_BLURB_15, probe: 12, need: 100,   shard_prize: 2200, core_prize: 5 },
    MedalSpec { name: lx::L_MEDAL_NAME_16, blurb: lx::L_MEDAL_BLURB_16, probe: 0,  need: 30,    shard_prize: 300,  core_prize: 0 },
    MedalSpec { name: lx::L_MEDAL_NAME_17, blurb: lx::L_MEDAL_BLURB_17, probe: 0,  need: 300,   shard_prize: 2600, core_prize: 6 },
    MedalSpec { name: lx::L_MEDAL_NAME_18, blurb: lx::L_MEDAL_BLURB_18, probe: 19, need: 30,    shard_prize: 800,  core_prize: 2 },
    MedalSpec { name: lx::L_MEDAL_NAME_19, blurb: lx::L_MEDAL_BLURB_19, probe: 19, need: 60,    shard_prize: 2800, core_prize: 7 },
    MedalSpec { name: lx::L_MEDAL_NAME_20, blurb: lx::L_MEDAL_BLURB_20, probe: 15, need: 1,     shard_prize: 1500, core_prize: 4 },
    MedalSpec { name: lx::L_MEDAL_NAME_21, blurb: lx::L_MEDAL_BLURB_21, probe: 20, need: 7,     shard_prize: 2000, core_prize: 5 },
    MedalSpec { name: lx::L_MEDAL_NAME_22, blurb: lx::L_MEDAL_BLURB_22, probe: 22, need: 1,     shard_prize: 600,  core_prize: 1 },
    MedalSpec { name: lx::L_MEDAL_NAME_23, blurb: lx::L_MEDAL_BLURB_23, probe: 23, need: 1,     shard_prize: 900,  core_prize: 2 },
];

pub struct EdictShape {
    pub line: u16,
    pub probe: u32,
    pub dawn_need: u32,
    pub moon_need: u32,
}

pub const EDICT_SHAPES_TABLE: [EdictShape; EDICT_SHAPES] = [
    EdictShape { line: lx::L_EDICT_NAME_0,  probe: 1,  dawn_need: 60,   moon_need: 420 },
    EdictShape { line: lx::L_EDICT_NAME_1,  probe: 3,  dawn_need: 8,    moon_need: 18 },
    EdictShape { line: lx::L_EDICT_NAME_2,  probe: 0,  dawn_need: 4,    moon_need: 26 },
    EdictShape { line: lx::L_EDICT_NAME_3,  probe: 21, dawn_need: 1,    moon_need: 6 },
    EdictShape { line: lx::L_EDICT_NAME_4,  probe: 5,  dawn_need: 6,    moon_need: 40 },
    EdictShape { line: lx::L_EDICT_NAME_5,  probe: 7,  dawn_need: 14,   moon_need: 90 },
    EdictShape { line: lx::L_EDICT_NAME_6,  probe: 6,  dawn_need: 5,    moon_need: 32 },
    EdictShape { line: lx::L_EDICT_NAME_7,  probe: 25, dawn_need: 500,  moon_need: 4000 },
    EdictShape { line: lx::L_EDICT_NAME_8,  probe: 24, dawn_need: 1,    moon_need: 7 },
    EdictShape { line: lx::L_EDICT_NAME_9,  probe: 14, dawn_need: 1,    moon_need: 5 },
    EdictShape { line: lx::L_EDICT_NAME_10, probe: 8,  dawn_need: 6,    moon_need: 40 },
    EdictShape { line: lx::L_EDICT_NAME_11, probe: 4,  dawn_need: 1200, moon_need: 5200 },
];

pub struct ChronicleSpec {
    pub line: u16,
    pub probe: u32,
    pub need: u32,
    pub shard_prize: u32,
    pub core_prize: u32,
}

pub const CHRONICLES: [ChronicleSpec; CHRONICLE_COUNT] = [
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_0,  probe: 20, need: 1,     shard_prize: 300,  core_prize: 1 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_1,  probe: 20, need: 2,     shard_prize: 500,  core_prize: 1 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_2,  probe: 20, need: 3,     shard_prize: 800,  core_prize: 2 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_3,  probe: 20, need: 4,     shard_prize: 1200, core_prize: 3 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_4,  probe: 20, need: 5,     shard_prize: 1700, core_prize: 4 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_5,  probe: 20, need: 6,     shard_prize: 2300, core_prize: 5 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_6,  probe: 20, need: 7,     shard_prize: 3000, core_prize: 7 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_7,  probe: 1,  need: 10000, shard_prize: 2500, core_prize: 5 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_8,  probe: 18, need: 16,    shard_prize: 2000, core_prize: 5 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_9,  probe: 24, need: 160,   shard_prize: 2800, core_prize: 6 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_10, probe: 16, need: 121,   shard_prize: 3400, core_prize: 8 },
    ChronicleSpec { line: lx::L_CHRONICLE_NAME_11, probe: 15, need: 1,     shard_prize: 4000, core_prize: 10 },
];

pub const CODEX_TITLES: [u16; CODEX_COUNT] = lx::G_CODEX_ENTRY;
pub const CODEX_BODIES: [u16; CODEX_COUNT] = lx::G_CODEX_BODY;

/// Codex entries 0..7 unlock as features appear, 8..13 one per region, and
/// 14..19 are the grown-up pages: what the priests drank and breathed, what a
/// cracked shell leaves on the floor, and who kept the ledger before you.
/// They are gated deep on purpose, so the first chamber is not the place a
/// player meets them.
pub const CODEX_KEYS: [u32; CODEX_COUNT] =
    [0, 0, 1, 4, 3, 5, 5, 6, 0, 1, 2, 3, 4, 5, 1, 2, 0, 3, 4, 5];

pub const STAT_LINES: [u16; 18] = lx::G_STAT_NAME;
pub const PURSE_LINES: [u16; 4] = lx::G_COIN_NAME;
pub const PURSE_BLURBS: [u16; 4] = lx::G_COIN_BLURB;
pub const TILE_LINES: [u16; TILE_COUNT] = lx::G_TILE_NAME;
pub const TILE_BLURBS: [u16; TILE_COUNT] = lx::G_TILE_BLURB;
pub const BRANCH_LINES: [u16; 4] = lx::G_LATTICE_BRANCH;
pub const BRANCH_BLURBS: [u16; 4] = lx::G_LATTICE_BRANCH_BLURB;
pub const TUTOR_LINES: [u16; 8] = lx::G_TUTOR_STEP;
pub const GREET_LINES: [u16; 4] = lx::G_HOME_GREET;

/// Attunement ladder: light needed to reach each level, index is level - 1.
pub fn attunement_bar(level: u32) -> u64 {
    let step = level.max(1) as u64;
    400 + step * step * 260 + step * 900
}

/// Ascent tier ladder.
pub fn ascent_bar(tier: u32) -> u64 {
    let step = (tier + 1) as u64;
    900 + step * 620 + step * step * 46
}

pub fn ascent_prize(tier: u32) -> (u32, u32, u32, u32) {
    // shards, cores, resin, seals
    let step = tier + 1;
    let shards = 120 + step * 46;
    let cores = if step % 10 == 0 {
        3
    } else if step % 5 == 0 {
        1
    } else {
        0
    };
    let resin = if step % 3 == 0 { 14 + step } else { 0 };
    let seals = if step % 4 == 0 { 1 } else { 0 };
    (shards, cores, resin, seals)
}

pub fn rite_prize(dawn: u32, streak: u32) -> (u32, u32, u32, u32) {
    let bonus = 1 + streak / 7;
    match dawn % RITE_CYCLE as u32 {
        0 => (160 * bonus, 0, 0, 0),
        1 => (0, 0, 22 * bonus, 0),
        2 => (240 * bonus, 0, 0, 0),
        3 => (0, 0, 0, bonus),
        4 => (320 * bonus, 0, 18 * bonus, 0),
        5 => (0, bonus, 0, 0),
        _ => (520 * bonus, bonus, 30 * bonus, bonus),
    }
}
