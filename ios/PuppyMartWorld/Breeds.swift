import UIKit

func hex(_ v: UInt32) -> UIColor {
    UIColor(red: CGFloat((v >> 16) & 255) / 255,
            green: CGFloat((v >> 8) & 255) / 255,
            blue: CGFloat(v & 255) / 255, alpha: 1)
}

/// rarity: 0 common, 1 rare, 2 epic
struct Breed {
    let name: String
    let body: UIColor
    let patch: UIColor
    let rarity: Int
    let pointyEars: Bool
}

let breeds: [Breed] = [
    Breed(name: "Labrador",  body: hex(0xE2B866), patch: hex(0xC99B45), rarity: 0, pointyEars: false),
    Breed(name: "Beagle",    body: hex(0xC98A4B), patch: hex(0xFFFFFF), rarity: 0, pointyEars: false),
    Breed(name: "Corgi",     body: hex(0xE59A4A), patch: hex(0xFFF3E0), rarity: 0, pointyEars: true),
    Breed(name: "Kelpie",    body: hex(0x3A2B25), patch: hex(0xB8743A), rarity: 1, pointyEars: true),
    Breed(name: "Dalmatian", body: hex(0xF6F6F2), patch: hex(0x222222), rarity: 1, pointyEars: false),
    Breed(name: "Husky",     body: hex(0x8D98A6), patch: hex(0xFFFFFF), rarity: 1, pointyEars: true),
    Breed(name: "Poodle",    body: hex(0xF2D7E6), patch: hex(0xFFFFFF), rarity: 2, pointyEars: false),
    Breed(name: "Samoyed",   body: hex(0xFFFFFF), patch: hex(0xF1ECE4), rarity: 2, pointyEars: true),
]

let rarityNames = ["Common", "Rare", "Epic"]
let rarityCoins = [10, 25, 60]
/// width of the green catch zone (fraction of the bar)
let rarityZone: [Double] = [0.30, 0.22, 0.15]
/// how fast the marker sweeps (bar lengths per second)
let raritySpeed: [Double] = [0.9, 1.3, 1.8]

/// Deterministic random numbers so the island looks the same every launch.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
