import SpriteKit

/// Picks the carved artwork for everything the board and the outland show.
/// Keeping the choice here means the scenes themselves never hold a name or
/// an index: they ask for a tile kind and get a texture back.
/// Which way the hero is turned. Four sides, because there is art for four.
enum Face {
    case near
    case away
    case left
    case right
}

enum Relief {
    private static var cut: [Int: SKTexture] = [:]

    static func grain(_ prop: Int) -> SKTexture? {
        if let known = cut[prop] { return known }
        guard let art = Vault.prop(prop) else { return nil }
        let fresh = SKTexture(image: art)
        fresh.filteringMode = .linear
        cut[prop] = fresh
        return fresh
    }

    /// A seat-stable pick inside one art group, so neighbouring stones differ
    /// but never flicker between frames.
    private static func pick(_ group: [Int], _ seat: Int, _ salt: Int) -> Int {
        guard !group.isEmpty else { return 0 }
        var churn = UInt32(truncatingIfNeeded: seat * 2654435761 + salt * 40503)
        churn ^= churn >> 13
        return group[Int(churn % UInt32(group.count))]
    }

    // --- the chamber -------------------------------------------------------

    /// A pillar or a heap of fallen temple, by which of the four looks the core
    /// rolled for it.
    static func pillar(_ look: Int) -> SKTexture? {
        let roll = [
            Canvas.aColumns[0],
            Canvas.aRuins[0],
            Canvas.aStoneObjects[0],
            Canvas.aColumns[3],
        ]
        return grain(roll[look % roll.count])
    }

    /// The way out, lit once the chamber is quiet.
    static func doorway() -> SKTexture? {
        grain(Canvas.bTempleDoors[0])
    }

    /// Anything loose on the floor: coins, the crystals that mend and refill,
    /// the urn nobody mentions, and a chest.
    static func moteProp(_ kind: UInt8) -> Int {
        switch kind {
        case Pickup.heart: return Canvas.bVices[0]
        case Pickup.focus: return Canvas.bVices[1]
        case Pickup.relic: return Canvas.aCeremonialVessels[3]
        case Pickup.chest: return Canvas.aTreasureChests[0]
        default: return Canvas.aAncientRelics[0]
        }
    }

    static func mote(_ kind: UInt8) -> SKTexture? {
        grain(moteProp(kind))
    }

    /// Loose dressing for the floor: sand, scrub, a dropped vessel. Nothing
    /// here is ever stood on or fought, it only stops the floor looking swept.
    static func litter(_ look: Int) -> SKTexture? {
        let roll = [
            Canvas.aSandEffects[0],
            Canvas.aDesertPlants[0],
            Canvas.aSandEffects[1],
            Canvas.bVegetation[0],
            Canvas.aStoneObjects[1],
            Canvas.bVices[2],
            Canvas.bVices[3],
        ]
        return grain(roll[look % roll.count])
    }

    /// What is left of whoever came down here first. Scattered across the
    /// floor of every chamber, and the reason the temple reads as a place
    /// people died in rather than a museum.
    static func remains(_ look: Int) -> SKTexture? {
        let roll = [
            Canvas.bRemains[0],
            Canvas.bRemains[1],
            Canvas.bRemains[2],
            Canvas.bRemains[3],
        ]
        return grain(roll[look % roll.count])
    }

    /// Blood that dried here long before the hero arrived: a pool, a spray,
    /// a drag mark. Laid flat into the floor at the start of a chamber.
    static func scarlet(_ look: Int) -> SKTexture? {
        grain(Canvas.bGore[look % 4])
    }

    /// Art for the floor guide, in the order the core lists it: the three
    /// things that drop, the urn, the chest, cover, and the way out.
    static func guideProp(_ entry: Int) -> Int {
        switch entry {
        case 1: return moteProp(Pickup.heart)
        case 2: return moteProp(Pickup.focus)
        case 3: return moteProp(Pickup.relic)
        case 4: return moteProp(Pickup.chest)
        case 5: return Canvas.aColumns[0]
        case 6: return Canvas.bTempleDoors[0]
        default: return moteProp(Pickup.coin)
        }
    }

    /// The Keeper, drawn from four sides. Which one is used follows the way
    /// she is running, so the sprite turns instead of being flipped.
    static func keeper(_ facing: Face) -> SKTexture? {
        switch facing {
        case .near: return grain(Canvas.bKeeper[0])
        case .away: return grain(Canvas.bKeeper[1])
        case .left: return grain(Canvas.bKeeper[2])
        case .right: return grain(Canvas.bKeeper[3])
        }
    }

    /// The old hero art, kept for the halls where a portrait is wanted and a
    /// direction means nothing.
    static var shelled: SKTexture? { grain(Canvas.bKeeper[0]) }

    static func huskProp(_ breed: UInt8) -> Int {
        switch breed {
        case Breed.jackal: return Canvas.aGodStatues[0]
        case Breed.spitter: return Canvas.aGodStatues[2]
        case Breed.hopper: return Canvas.bScarabSupport[0]
        case Breed.warden: return Canvas.aSarcophagi[2]
        case Breed.brooder: return Canvas.bScarabSupport[2]
        case Breed.sentinel: return Canvas.bTempleMechanisms[0]
        case Breed.revenant: return Canvas.aGodStatues[1]
        default: return Canvas.aSarcophagi[0]
        }
    }

    static func husk(_ breed: UInt8) -> SKTexture? {
        grain(huskProp(breed))
    }

    // --- the outland -------------------------------------------------------

    /// The landmark that marks one region on the desert map.
    static func waymark(_ region: Int) -> SKTexture? {
        let roll = [
            Canvas.aTempleDoors[3],
            Canvas.aOasisAssets[1],
            Canvas.aRuins[0],
            Canvas.aLargePyramids[0],
            Canvas.bSolarDevices[1],
            Canvas.bTempleMechanisms[0],
            Canvas.aAncientMechanisms[0],
        ]
        return grain(roll[region % roll.count])
    }

    static var dustPuff: SKTexture? { grain(Canvas.aSandEffects[1]) }

    // --- the jar -----------------------------------------------------------

    /// The tankard of temple beer, which is both a knack's face in the HUD and
    /// the thing she lifts on screen when she drinks it.
    static var brew: SKTexture? { grain(Canvas.bBeer[0]) }

    /// The same art for UIKit, where there are no textures.
    static var brewArt: UIImage? { Vault.prop(Canvas.bBeer[0]) }
}
