import CoreGraphics

/// Central place for tunable game constants. Centipede is a grid-based game:
/// the whole playfield is a lattice of square cells. Mushrooms occupy whole
/// cells and the centipede walks one cell per movement "tick".
enum GameConfig {
    /// Size of one grid cell, in points.
    static let cell: CGFloat = 24

    /// Playfield dimensions, in cells.
    static let cols = 25
    static let rows = 30

    /// How many rows at the bottom the player's shooter is allowed to roam.
    static let playerRows = 6

    /// Window size derived from the grid.
    static var width: CGFloat { CGFloat(cols) * cell }   // 600
    static var height: CGFloat { CGFloat(rows) * cell }  // 720

    // Gameplay tuning.
    static let bulletSpeed: CGFloat = 700      // points per second
    static let fireInterval: Double = 0.16     // seconds between shots while firing
    static let centipedeStep: Double = 0.16    // seconds per centipede move tick
    static let centipedeWaveTotal = 12         // total segments per wave (arcade: 12)
    static let bonusLifeScore = 12_000         // award an extra life every N points
    static let headInjectMin: Double = 3       // min seconds between mid-wave lone heads
    static let headInjectMax: Double = 6       // max seconds between mid-wave lone heads
    static let mushroomCount = 40              // mushrooms sprinkled at start
    static let mushroomHealth = 4              // hits to clear a mushroom

    // Spider.
    static let spiderSpeedX: CGFloat = 130     // horizontal drift, points/second
    static let spiderSpeedY: CGFloat = 175     // vertical bounce, points/second
    static let spiderMinSpawn: Double = 5      // seconds between spiders (min)
    static let spiderMaxSpawn: Double = 9      // seconds between spiders (max)

    // Flea.
    static let fleaSpeed: CGFloat = 220        // downward speed, points/second
    static let fleaMushroomThreshold = 5       // spawn when player zone has fewer than this
    static let fleaPlantChance = 0.55          // chance to plant a mushroom per row passed

    // Scorpion.
    static let scorpionSpeed: CGFloat = 110    // horizontal speed, points/second
    static let scorpionMinSpawn: Double = 8    // seconds between scorpions (min)
    static let scorpionMaxSpawn: Double = 14   // seconds between scorpions (max)
    static let scorpionMinLevel = 2            // first level a scorpion can appear
}
