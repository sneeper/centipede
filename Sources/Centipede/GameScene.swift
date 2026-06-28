import SpriteKit
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Entities

/// One link of a centipede. Centipedes move as a "train": the head obeys the
/// movement rules and every body link follows the path of the link ahead of it.
final class Segment {
    var col: Int
    var row: Int
    var dir: Int   // horizontal heading: +1 right, -1 left
    var vDir: Int  // vertical heading when descending: +1 down, -1 up
    var poisoned = false   // when true, the link dives straight down
    let node: SKShapeNode

    init(col: Int, row: Int, dir: Int, vDir: Int, node: SKShapeNode) {
        self.col = col; self.row = row; self.dir = dir; self.vDir = vDir
        self.node = node
    }
}

/// A mushroom occupies one grid cell and absorbs several hits before clearing.
/// A scorpion can "poison" it, which sends passing centipede links diving.
final class Mushroom {
    var health: Int
    var poisoned = false
    let node: SKShapeNode
    init(health: Int, node: SKShapeNode) {
        self.health = health; self.node = node
    }
}

/// The spider zig-zags through the lower play zone, eating mushrooms it crosses
/// and threatening the shooter. It moves continuously (not grid-locked).
final class Spider {
    let node: SKNode
    var vx: CGFloat
    var vy: CGFloat
    var nextFlip: Double   // seconds until the next random vertical direction flip
    init(node: SKNode, vx: CGFloat, vy: CGFloat, nextFlip: Double) {
        self.node = node; self.vx = vx; self.vy = vy; self.nextFlip = nextFlip
    }
}

/// The flea drops straight down when the player zone runs low on mushrooms,
/// replanting a trail as it falls. It takes two hits — the first speeds it up.
final class Flea {
    let node: SKNode
    var speed: CGFloat
    var health: Int
    var lastDropRow: Int   // so it plants at most one mushroom per row
    init(node: SKNode, speed: CGFloat, health: Int, lastDropRow: Int) {
        self.node = node; self.speed = speed; self.health = health
        self.lastDropRow = lastDropRow
    }
}

/// The scorpion crosses the upper field horizontally, poisoning every mushroom
/// it touches. Centipede links that reach a poisoned mushroom dive at the player.
final class Scorpion {
    let node: SKNode
    var vx: CGFloat
    init(node: SKNode, vx: CGFloat) {
        self.node = node; self.vx = vx
    }
}

// MARK: - Scene

/// Per-wave color scheme. The arcade recolors its sprites each round; we cycle
/// through a few palettes so successive waves look distinct.
struct WavePalette {
    let body: SKColor                          // centipede body
    let head: SKColor                          // centipede head
    let mush: (r: CGFloat, g: CGFloat, b: CGFloat)   // mushroom base (scaled by health)
}

/// Top-level game state. Most of the loop only runs while `.playing` (or the
/// attract-mode `.attractDemo`, which is a real round driven by an AI).
enum GamePhase {
    case attractTitle       // attract: title + "press fire"
    case attractScores      // attract: high score table
    case attractDemo        // attract: AI-driven demo round (no sound, no recording)
    case playing
    case paused             // gameplay frozen behind a pause menu
    case enteringInitials   // qualified for the table; typing initials
    case showingScores      // post-game high score table; click to play again
}

final class GameScene: SKScene {

    // Grid + entities
    private var mushrooms: [[Mushroom?]] = []
    private var chains: [[Segment]] = []          // each chain is one (sub)centipede
    private var bullets: [SKShapeNode] = []

    // Player
    private var player: SKShapeNode!
    private var isFiring = false
    private var fireCooldown: Double = 0

    // Centipede movement timing
    private var stepInterval = GameConfig.centipedeStep
    private var stepAccumulator: Double = 0

    // Spider
    private var spider: Spider?
    private var spiderSpawnTimer: Double = 0

    // Flea
    private var flea: Flea?
    private var fleaCheckTimer: Double = 0

    // Scorpion
    private var scorpion: Scorpion?
    private var scorpionSpawnTimer: Double = 0

    // Bookkeeping
    private var score = 0
    private var level = 1
    private var lives = 3
    private var phase: GamePhase = .playing
    private var lastTime: TimeInterval = 0

    private var scoreLabel: SKLabelNode!
    private var livesNode: SKNode!              // row of shooter-head life icons
    private var cursorHint: SKLabelNode?        // "Esc: free cursor" HUD hint
    private var nextBonusScore = GameConfig.bonusLifeScore
    private var headInjectTimer: Double = 0     // mid-wave lone-head spawn clock

    // Game-over overlay + initials entry
    private var overlay: SKNode?
    private var initialsSlots: [Character] = ["A", "A", "A"]
    private var activeSlot = 0

    // Attract mode
    private var attractTimer: Double = 0   // countdown to the next attract transition
    private var attractColorIndex = 0      // cycles the backdrop color in attract mode

    // Mouse capture
    private var mouseCaptured = false

    // Visuals
    private let gameCamera = SKCameraNode()    // used only for screen-shake
    private let wavePalettes: [WavePalette] = [
        WavePalette(body: SKColor(red: 0.5, green: 0.9, blue: 0.4, alpha: 1),
                    head: SKColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1),
                    mush: (0.7, 0.45, 0.95)),
        WavePalette(body: SKColor(red: 0.3, green: 0.85, blue: 1.0, alpha: 1),
                    head: SKColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1),
                    mush: (0.3, 0.8, 0.7)),
        WavePalette(body: SKColor(red: 1.0, green: 0.5, blue: 0.8, alpha: 1),
                    head: SKColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
                    mush: (0.45, 0.6, 1.0)),
        WavePalette(body: SKColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 1),
                    head: SKColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1),
                    mush: (0.6, 0.9, 0.35)),
    ]
    private var wavePalette: WavePalette {
        wavePalettes[((level - 1) % wavePalettes.count + wavePalettes.count) % wavePalettes.count]
    }

    /// A small soft dot reused as the particle image for explosions.
    private var sparkTexture: SKTexture!

    // MARK: Setup

    override func didMove(to view: SKView) {
        backgroundColor = .black
        sparkTexture = makeSparkTexture()
        _ = SoundEngine.shared      // warm up the audio engine

        #if os(macOS)
        // Release / re-grab the cursor automatically as the app loses/gains focus.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        // Keep the cursor hint in sync with full-screen state.
        NotificationCenter.default.addObserver(
            self, selector: #selector(fullScreenChanged),
            name: NSWindow.didEnterFullScreenNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(fullScreenChanged),
            name: NSWindow.didExitFullScreenNotification, object: nil)
        // The shooter is driven by relative mouse motion, so we need moved events.
        view.window?.acceptsMouseMovedEvents = true
        #endif

        enterAttractTitle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildNewGame() {
        removeAllChildren()
        overlay = nil
        initialsSlots = ["A", "A", "A"]
        activeSlot = 0
        bullets.removeAll()
        chains.removeAll()
        phase = .playing
        score = 0
        level = 1
        lives = 3
        nextBonusScore = GameConfig.bonusLifeScore
        backgroundColor = backgroundForLevel(level)
        stepInterval = GameConfig.centipedeStep
        spider = nil
        resetSpiderTimer()
        flea = nil
        fleaCheckTimer = 3     // don't drop a flea instantly on a fresh board
        scorpion = nil
        resetScorpionTimer()

        buildEmptyMushroomGrid()
        addBackdropGrid()
        installCamera()
        scatterMushrooms()
        buildPlayer()
        buildHUD()
        spawnWave()
    }

    private func buildEmptyMushroomGrid() {
        mushrooms = Array(
            repeating: Array(repeating: nil, count: GameConfig.cols),
            count: GameConfig.rows
        )
    }

    private func scatterMushrooms() {
        // Keep the very top row (centipede spawn) and the player zone clear-ish.
        let topClear = 1
        let bottomClear = GameConfig.rows - GameConfig.playerRows
        var placed = 0
        var attempts = 0
        while placed < GameConfig.mushroomCount && attempts < 1000 {
            attempts += 1
            let row = Int.random(in: topClear..<bottomClear)
            let col = Int.random(in: 0..<GameConfig.cols)
            if mushrooms[row][col] == nil {
                addMushroom(col: col, row: row)
                placed += 1
            }
        }
    }

    private func buildPlayer() {
        let w = GameConfig.cell * 0.7
        let h = GameConfig.cell * 0.8
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: h / 2))
        path.addLine(to: CGPoint(x: -w / 2, y: -h / 2))
        path.addLine(to: CGPoint(x: w / 2, y: -h / 2))
        path.closeSubpath()

        let node = SKShapeNode(path: path)
        node.fillColor = SKColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1)
        node.strokeColor = SKColor(red: 0.6, green: 1.0, blue: 0.6, alpha: 1)
        node.glowWidth = 3
        node.position = point(col: GameConfig.cols / 2, row: GameConfig.rows - 2)
        node.zPosition = 10
        addChild(node)
        player = node
    }

    private func buildHUD() {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontSize = 18
        label.fontColor = .white
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: 12, y: size.height - 10)
        label.zPosition = 100
        addChild(label)
        scoreLabel = label

        let lives = SKNode()
        lives.position = CGPoint(x: 16, y: size.height - 40)
        lives.zPosition = 100
        addChild(lives)
        livesNode = lives

        #if os(macOS)
        let hint = SKLabelNode(fontNamed: "Menlo")
        hint.text = "Esc: free cursor"
        hint.fontSize = 11
        hint.fontColor = SKColor(white: 0.5, alpha: 1)
        hint.horizontalAlignmentMode = .right
        hint.verticalAlignmentMode = .top
        hint.position = CGPoint(x: size.width - 12, y: size.height - 12)
        hint.zPosition = 100
        addChild(hint)
        cursorHint = hint
        updateCursorHintVisibility()
        #endif

        #if os(iOS)
        // A visible Pause button (top-right) — the obvious in-app exit on touch.
        let pauseButton = makeButton("PAUSE", name: "pause",
                                     at: CGPoint(x: size.width - 54, y: size.height - 30),
                                     width: 84, fontSize: 15)
        pauseButton.zPosition = 100
        addChild(pauseButton)
        #endif

        updateHUD()
    }

    /// The cursor hint only makes sense when the cursor is actually captured AND
    /// there's somewhere for it to go — i.e. not in full screen (and not during
    /// the demo, where the cursor is already free).
    private var isFullScreen: Bool {
        #if os(macOS)
        view?.window?.styleMask.contains(.fullScreen) ?? false
        #else
        false
        #endif
    }

    private func updateCursorHintVisibility() {
        cursorHint?.isHidden = !(mouseCaptured && !isFullScreen)
    }

    private func updateHUD() {
        guard let scoreLabel else { return }
        scoreLabel.text = "SCORE \(score)    LEVEL \(level)"
        refreshLivesDisplay()
    }

    /// Show one little shooter icon per *spare* life (the arcade hides these in
    /// the attract demo).
    private func refreshLivesDisplay() {
        guard let livesNode else { return }
        livesNode.removeAllChildren()
        livesNode.isHidden = (phase == .attractDemo)
        let reserves = max(0, lives - 1)
        for i in 0..<reserves {
            let icon = makeShooterIcon()
            icon.position = CGPoint(x: CGFloat(i) * 20 + 8, y: 0)
            livesNode.addChild(icon)
        }
    }

    private func makeShooterIcon() -> SKShapeNode {
        let w = GameConfig.cell * 0.5
        let h = GameConfig.cell * 0.6
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: h / 2))
        path.addLine(to: CGPoint(x: -w / 2, y: -h / 2))
        path.addLine(to: CGPoint(x: w / 2, y: -h / 2))
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor = SKColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1)
        node.strokeColor = .green
        return node
    }

    /// Spawn the wave for the current `level`. The arcade keeps the total segment
    /// count constant (12) but, each wave, shortens the main centipede by one and
    /// adds another lone single-segment "head" centipede — so later waves are a
    /// swarm of fast independent heads rather than one long train.
    private func spawnWave() {
        let total = GameConfig.centipedeWaveTotal
        let mainLength = max(1, total - (level - 1))
        let extraHeads = total - mainLength
        spawnCentipede(length: mainLength)
        for _ in 0..<extraHeads { spawnLoneHead() }
        headInjectTimer = headInjectInterval()
    }

    private func headInjectInterval() -> Double {
        Double.random(in: GameConfig.headInjectMin...GameConfig.headInjectMax)
    }

    /// Once the centipede has worked its way down into the player's area, the
    /// arcade keeps feeding in lone "head" centipedes to pressure you into
    /// finishing the wave. We top back up toward the wave total while any segment
    /// is in the bottom zone.
    private func updateHeadInjection(_ dt: Double) {
        let segmentCount = chains.reduce(0) { $0 + $1.count }
        guard segmentCount > 0, segmentCount < GameConfig.centipedeWaveTotal else { return }
        let bottomRow = GameConfig.rows - GameConfig.playerRows
        let reachedBottom = chains.contains { $0.contains { $0.row >= bottomRow } }
        guard reachedBottom else { return }
        headInjectTimer -= dt
        if headInjectTimer <= 0 {
            spawnLoneHead()
            headInjectTimer = headInjectInterval()
        }
    }

    /// A single-segment centipede entering at the top in a random column/heading.
    private func spawnLoneHead() {
        let col = Int.random(in: 0..<GameConfig.cols)
        let dir = Bool.random() ? 1 : -1
        let node = makeSegmentNode(isHead: true)
        node.position = point(col: col, row: 0)
        addChild(node)
        chains.append([Segment(col: col, row: 0, dir: dir, vDir: 1, node: node)])
    }

    private func spawnCentipede(length: Int) {
        // Head enters top-left heading right; body trails behind to the left.
        var chain: [Segment] = []
        let startRow = 0
        for i in 0..<length {
            let col = length - 1 - i      // head (i==0) is rightmost
            let isHead = (i == 0)
            let node = makeSegmentNode(isHead: isHead)
            node.position = point(col: col, row: startRow)
            addChild(node)
            chain.append(Segment(col: col, row: startRow, dir: 1, vDir: 1, node: node))
        }
        chains.append(chain)
    }

    private func makeSegmentNode(isHead: Bool) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: GameConfig.cell * 0.42)
        let color = isHead ? wavePalette.head : wavePalette.body
        node.fillColor = color
        node.strokeColor = color
        node.lineWidth = 1
        node.glowWidth = 3               // neon halo
        node.zPosition = 5
        return node
    }

    // MARK: Coordinate helpers

    /// Convert a grid cell to a scene point. Row 0 is the TOP row.
    private func point(col: Int, row: Int) -> CGPoint {
        let x = (CGFloat(col) + 0.5) * GameConfig.cell
        let y = size.height - (CGFloat(row) + 0.5) * GameConfig.cell
        return CGPoint(x: x, y: y)
    }

    private func cell(of p: CGPoint) -> (col: Int, row: Int) {
        let col = Int(p.x / GameConfig.cell)
        let row = Int((size.height - p.y) / GameConfig.cell)
        return (col, row)
    }

    private func inGrid(col: Int, row: Int) -> Bool {
        col >= 0 && col < GameConfig.cols && row >= 0 && row < GameConfig.rows
    }

    // MARK: Mushrooms

    private func addMushroom(col: Int, row: Int, health: Int = GameConfig.mushroomHealth) {
        guard inGrid(col: col, row: row), mushrooms[row][col] == nil else { return }
        let s = GameConfig.cell * 0.72
        let node = SKShapeNode(rectOf: CGSize(width: s, height: s), cornerRadius: 5)
        node.position = point(col: col, row: row)
        node.strokeColor = .clear
        node.zPosition = 1
        addChild(node)
        let m = Mushroom(health: health, node: node)
        m.node.fillColor = mushroomColor(for: health)
        mushrooms[row][col] = m
    }

    private func mushroomColor(for health: Int, poisoned: Bool = false) -> SKColor {
        // Brighter when healthier; poisoned mushrooms glow a sickly red. The base
        // hue follows the current wave palette.
        let t = CGFloat(health) / CGFloat(GameConfig.mushroomHealth)
        if poisoned {
            return SKColor(red: 0.6 * t + 0.4, green: 0.1 * t, blue: 0.1 * t, alpha: 1)
        }
        let k = 0.4 + 0.6 * t
        let m = wavePalette.mush
        return SKColor(red: m.r * k, green: m.g * k, blue: m.b * k, alpha: 1)
    }

    private func poisonMushroom(col: Int, row: Int) {
        guard inGrid(col: col, row: row), let m = mushrooms[row][col], !m.poisoned else { return }
        m.poisoned = true
        m.node.fillColor = mushroomColor(for: m.health, poisoned: true)
    }

    private func damageMushroom(col: Int, row: Int) {
        guard let m = mushrooms[row][col] else { return }
        m.health -= 1
        if m.health <= 0 {
            let pos = m.node.position
            m.node.removeFromParent()
            mushrooms[row][col] = nil
            addScore(1)
            spawnExplosion(at: pos,
                           color: SKColor(red: 0.7, green: 0.4, blue: 0.9, alpha: 1),
                           count: 12, speed: 90)
        } else {
            m.node.fillColor = mushroomColor(for: m.health, poisoned: m.poisoned)
        }
        sfx(.mushroom)
    }

    // MARK: Game loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : currentTime - lastTime
        lastTime = currentTime

        handleTimedTransitions(dt)

        // Gameplay logic runs for a real round and for the AI demo.
        guard phase == .playing || phase == .attractDemo else { return }

        #if os(iOS)
        if phase == .playing { isFiring = true }   // touch control auto-fires
        #endif

        updatePlayer(dt)
        updateFiring(dt)
        updateBullets(dt)
        updateSpider(dt)
        updateFlea(dt)
        updateScorpion(dt)
        updateHeadInjection(dt)

        stepAccumulator += dt
        if stepAccumulator >= stepInterval {
            stepAccumulator = 0
            stepCentipede()
        }

        resolveBulletHits()
        checkPlayerCollision()
        checkWaveCleared()
    }

    private func updatePlayer(_ dt: Double) {
        // During a real round the shooter is driven by captured mouse deltas
        // (see mouseMoved / mouseDragged). The demo is driven by the AI.
        if phase == .attractDemo { updateDemoPlayer(dt) }
    }

    /// Move the shooter by a relative delta, clamped to the bottom play zone.
    private func movePlayer(dx: CGFloat, dy: CGFloat) {
        guard player != nil else { return }
        let half = GameConfig.cell * 0.4
        let minX = half
        let maxX = size.width - half
        let minY = GameConfig.cell * 0.5
        let maxY = CGFloat(GameConfig.playerRows) * GameConfig.cell
        player.position.x = min(max(player.position.x + dx, minX), maxX)
        player.position.y = min(max(player.position.y - dy, minY), maxY)  // screen y is flipped
    }

    private func updateFiring(_ dt: Double) {
        fireCooldown -= dt
        if isFiring && fireCooldown <= 0 {
            fire()
            fireCooldown = GameConfig.fireInterval
        }
    }

    private func fire() {
        let bullet = SKShapeNode(rectOf: CGSize(width: 3, height: 12), cornerRadius: 1)
        bullet.fillColor = .yellow
        bullet.strokeColor = .yellow
        bullet.glowWidth = 3
        bullet.zPosition = 4
        bullet.position = CGPoint(x: player.position.x, y: player.position.y + GameConfig.cell * 0.5)
        addChild(bullet)
        bullets.append(bullet)
        sfx(.fire)
    }

    private func updateBullets(_ dt: Double) {
        let dy = GameConfig.bulletSpeed * CGFloat(dt)
        var survivors: [SKShapeNode] = []
        for b in bullets {
            b.position.y += dy
            if b.position.y > size.height {
                b.removeFromParent()
            } else {
                survivors.append(b)
            }
        }
        bullets = survivors
    }

    /// Advance every centipede chain by one cell using classic rules:
    /// move horizontally; if blocked by a wall or a mushroom, drop a row and
    /// reverse direction. Body links follow the head's trail.
    private func stepCentipede() {
        for c in chains.indices {
            let chain = chains[c]   // class refs — we mutate elements in place
            guard !chain.isEmpty else { continue }

            // Snapshot prior state so body links can follow.
            let prior = chain.map { ($0.col, $0.row, $0.dir, $0.vDir, $0.poisoned) }

            // Move the head.
            let head = chain[0]

            // A head sitting on a poisoned mushroom catches the poison.
            if let m = mushrooms[head.row][head.col], m.poisoned {
                head.poisoned = true
            }

            if head.poisoned {
                // Plunge straight down toward the player, ignoring mushrooms.
                head.row += 1
                if head.row >= GameConfig.rows - 1 {
                    head.row = GameConfig.rows - 1
                    head.poisoned = false   // recover at the bottom...
                    head.vDir = -1          // ...and climb back up
                }
            } else {
                let nextCol = head.col + head.dir
                let blocked = nextCol < 0 || nextCol >= GameConfig.cols
                    || (inGrid(col: nextCol, row: head.row) && mushrooms[head.row][nextCol] != nil)

                if blocked {
                    head.dir *= -1
                    head.row += head.vDir
                    if head.row >= GameConfig.rows - 1 { head.row = GameConfig.rows - 1; head.vDir = -1 }
                    if head.row <= 1 { head.row = 1; head.vDir = 1 }
                } else {
                    head.col = nextCol
                }
            }

            // Body follows the link ahead of it (poison propagates down the trail).
            for i in 1..<chain.count {
                let p = prior[i - 1]
                chain[i].col = p.0
                chain[i].row = p.1
                chain[i].dir = p.2
                chain[i].vDir = p.3
                chain[i].poisoned = p.4
            }

            // Push positions to the sprites.
            for seg in chain {
                seg.node.position = point(col: seg.col, row: seg.row)
            }
        }
    }

    // MARK: Spider

    private func resetSpiderTimer() {
        spiderSpawnTimer = Double.random(in: GameConfig.spiderMinSpawn...GameConfig.spiderMaxSpawn)
    }

    /// The vertical band the spider is allowed to roam: the player zone plus a
    /// little headroom above it.
    private var spiderBand: (min: CGFloat, max: CGFloat) {
        (GameConfig.cell * 0.6, CGFloat(GameConfig.playerRows + 1) * GameConfig.cell)
    }

    private func updateSpider(_ dt: Double) {
        guard let s = spider else {
            // None on screen — count down to the next appearance.
            spiderSpawnTimer -= dt
            if spiderSpawnTimer <= 0 { spawnSpider() }
            return
        }

        s.node.position.x += s.vx * CGFloat(dt)
        s.node.position.y += s.vy * CGFloat(dt)

        // Bounce off the top/bottom of its band.
        let band = spiderBand
        if s.node.position.y < band.min { s.node.position.y = band.min; s.vy = abs(s.vy) }
        if s.node.position.y > band.max { s.node.position.y = band.max; s.vy = -abs(s.vy) }

        // Occasionally flip vertical direction for that erratic skitter.
        s.nextFlip -= dt
        if s.nextFlip <= 0 {
            s.vy = -s.vy
            s.nextFlip = Double.random(in: 0.2...0.6)
        }

        // Eat any mushroom it crosses.
        let (col, row) = cell(of: s.node.position)
        if inGrid(col: col, row: row), let m = mushrooms[row][col] {
            m.node.removeFromParent()
            mushrooms[row][col] = nil
            sfx(.mushroom)
        }

        // Despawn once it leaves the far side.
        if s.node.position.x < -GameConfig.cell || s.node.position.x > size.width + GameConfig.cell {
            s.node.removeFromParent()
            spider = nil
            resetSpiderTimer()
        }
    }

    private func spawnSpider() {
        let fromLeft = Bool.random()
        let band = spiderBand
        let node = makeSpiderNode()
        node.position = CGPoint(
            x: fromLeft ? -GameConfig.cell * 0.5 : size.width + GameConfig.cell * 0.5,
            y: CGFloat.random(in: band.min...band.max)
        )
        addChild(node)

        let vx = (fromLeft ? 1 : -1) * GameConfig.spiderSpeedX
        let vy = (Bool.random() ? 1 : -1) * GameConfig.spiderSpeedY
        spider = Spider(node: node, vx: vx, vy: vy, nextFlip: Double.random(in: 0.2...0.6))
    }

    /// Shooting the spider scores by proximity, classic-style: closer = more.
    private func killSpider() {
        guard let s = spider else { return }
        let pos = s.node.position
        let dy = abs(pos.y - player.position.y)
        let points = dy < GameConfig.cell * 1.5 ? 900 : (dy < GameConfig.cell * 3 ? 600 : 300)
        addScore(points)
        showFloatingScore(points, at: pos)
        sfx(.explosion)
        spawnExplosion(at: pos, color: SKColor(red: 1.0, green: 0.2, blue: 0.8, alpha: 1),
                       count: 30, speed: 160)
        s.node.removeFromParent()
        spider = nil
        resetSpiderTimer()
    }

    private func makeSpiderNode() -> SKNode {
        let container = SKNode()
        container.zPosition = 8
        let color = SKColor(red: 1.0, green: 0.2, blue: 0.8, alpha: 1)
        let bodyR = GameConfig.cell * 0.36

        let body = SKShapeNode(circleOfRadius: bodyR)
        body.fillColor = color
        body.strokeColor = color
        body.lineWidth = 1
        body.glowWidth = 3
        container.addChild(body)

        let legs = SKShapeNode()
        let path = CGMutablePath()
        let legLen = GameConfig.cell * 0.55
        for i in 0..<4 {
            let yOff = (CGFloat(i) - 1.5) * (bodyR * 0.6)
            path.move(to: CGPoint(x: -bodyR * 0.6, y: yOff * 0.4))
            path.addLine(to: CGPoint(x: -legLen, y: yOff))
            path.move(to: CGPoint(x: bodyR * 0.6, y: yOff * 0.4))
            path.addLine(to: CGPoint(x: legLen, y: yOff))
        }
        legs.path = path
        legs.strokeColor = color
        legs.lineWidth = 2
        legs.glowWidth = 1.5
        wiggleLegs(legs)
        container.addChild(legs)

        return container
    }

    private func showFloatingScore(_ amount: Int, at position: CGPoint) {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "\(amount)"
        label.fontSize = 16
        label.fontColor = .white
        label.position = position
        label.zPosition = 50
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 30, duration: 0.6), .fadeOut(withDuration: 0.6)]),
            .removeFromParent()
        ]))
    }

    // MARK: Flea

    /// Count mushrooms currently inside the player's zone (bottom rows).
    private func playerZoneMushroomCount() -> Int {
        var count = 0
        let top = GameConfig.rows - GameConfig.playerRows
        for r in top..<GameConfig.rows {
            for c in 0..<GameConfig.cols where mushrooms[r][c] != nil {
                count += 1
            }
        }
        return count
    }

    private func updateFlea(_ dt: Double) {
        guard let f = flea else {
            // No flea — periodically check whether the player zone is too bare.
            fleaCheckTimer -= dt
            if fleaCheckTimer <= 0 {
                fleaCheckTimer = 1.0
                if playerZoneMushroomCount() < GameConfig.fleaMushroomThreshold {
                    spawnFlea()
                }
            }
            return
        }

        f.node.position.y -= f.speed * CGFloat(dt)

        // Plant a trail of mushrooms, at most one per row it enters.
        let (col, row) = cell(of: f.node.position)
        if row != f.lastDropRow {
            f.lastDropRow = row
            if inGrid(col: col, row: row), mushrooms[row][col] == nil,
               row >= 1, row < GameConfig.rows - 1,
               Double.random(in: 0...1) < GameConfig.fleaPlantChance {
                addMushroom(col: col, row: row)
            }
        }

        // Gone once it falls off the bottom.
        if f.node.position.y < -GameConfig.cell * 0.5 {
            f.node.removeFromParent()
            flea = nil
            fleaCheckTimer = 2.0
        }
    }

    private func spawnFlea() {
        let col = Int.random(in: 0..<GameConfig.cols)
        let node = makeFleaNode()
        node.position = CGPoint(x: point(col: col, row: 0).x, y: size.height + GameConfig.cell * 0.5)
        addChild(node)
        flea = Flea(node: node, speed: GameConfig.fleaSpeed, health: 2, lastDropRow: -1)
    }

    /// First hit just speeds the flea up; the second destroys it (200 points).
    private func hitFlea() {
        guard let f = flea else { return }
        f.health -= 1
        if f.health <= 0 {
            let pos = f.node.position
            addScore(200)
            showFloatingScore(200, at: pos)
            sfx(.explosion)
            spawnExplosion(at: pos, color: SKColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1),
                           count: 24, speed: 140)
            f.node.removeFromParent()
            flea = nil
            fleaCheckTimer = 2.0
        } else {
            f.speed *= 1.8
            sfx(.mushroom)
        }
    }

    private func makeFleaNode() -> SKNode {
        let container = SKNode()
        container.zPosition = 8
        let color = SKColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1)

        // A small vertical body (taller than wide) so it reads as a falling bug.
        let body = SKShapeNode(ellipseOf: CGSize(width: GameConfig.cell * 0.5,
                                                 height: GameConfig.cell * 0.78))
        body.fillColor = color
        body.strokeColor = color
        body.lineWidth = 1
        body.glowWidth = 3
        container.addChild(body)

        // A couple of little legs sticking out the sides.
        let legs = SKShapeNode()
        let path = CGMutablePath()
        let legLen = GameConfig.cell * 0.42
        for i in 0..<2 {
            let yOff = (CGFloat(i) - 0.5) * GameConfig.cell * 0.3
            path.move(to: CGPoint(x: -GameConfig.cell * 0.2, y: yOff))
            path.addLine(to: CGPoint(x: -legLen, y: yOff - GameConfig.cell * 0.12))
            path.move(to: CGPoint(x: GameConfig.cell * 0.2, y: yOff))
            path.addLine(to: CGPoint(x: legLen, y: yOff - GameConfig.cell * 0.12))
        }
        legs.path = path
        legs.strokeColor = color
        legs.lineWidth = 2
        legs.glowWidth = 1.5
        wiggleLegs(legs)
        container.addChild(legs)

        return container
    }

    // MARK: Scorpion

    private func resetScorpionTimer() {
        scorpionSpawnTimer = Double.random(in: GameConfig.scorpionMinSpawn...GameConfig.scorpionMaxSpawn)
    }

    private func updateScorpion(_ dt: Double) {
        guard let sc = scorpion else {
            // Scorpions only appear from a certain level onward.
            guard level >= GameConfig.scorpionMinLevel else { return }
            scorpionSpawnTimer -= dt
            if scorpionSpawnTimer <= 0 { spawnScorpion() }
            return
        }

        sc.node.position.x += sc.vx * CGFloat(dt)

        // Poison any mushroom it crosses.
        let (col, row) = cell(of: sc.node.position)
        poisonMushroom(col: col, row: row)

        // Despawn once it leaves the far side.
        if sc.node.position.x < -GameConfig.cell || sc.node.position.x > size.width + GameConfig.cell {
            sc.node.removeFromParent()
            scorpion = nil
            resetScorpionTimer()
        }
    }

    private func spawnScorpion() {
        let fromLeft = Bool.random()
        // Travels across the upper field, above the player zone.
        let topRow = 1
        let bottomRow = max(topRow, GameConfig.rows - GameConfig.playerRows - 2)
        let row = Int.random(in: topRow...bottomRow)

        let node = makeScorpionNode()
        node.position = CGPoint(
            x: fromLeft ? -GameConfig.cell * 0.5 : size.width + GameConfig.cell * 0.5,
            y: point(col: 0, row: row).y
        )
        addChild(node)
        scorpion = Scorpion(node: node, vx: (fromLeft ? 1 : -1) * GameConfig.scorpionSpeed)
    }

    /// Shooting the scorpion is worth a flat 1000 points.
    private func killScorpion() {
        guard let sc = scorpion else { return }
        let pos = sc.node.position
        addScore(1000)
        showFloatingScore(1000, at: pos)
        sfx(.explosion)
        spawnExplosion(at: pos, color: SKColor(red: 0.2, green: 0.85, blue: 0.9, alpha: 1),
                       count: 30, speed: 160)
        screenShake(intensity: 8, duration: 0.25)
        sc.node.removeFromParent()
        scorpion = nil
        resetScorpionTimer()
    }

    private func makeScorpionNode() -> SKNode {
        let container = SKNode()
        container.zPosition = 8
        let color = SKColor(red: 0.2, green: 0.85, blue: 0.9, alpha: 1)
        let c = GameConfig.cell

        let body = SKShapeNode(ellipseOf: CGSize(width: c * 0.95, height: c * 0.45))
        body.fillColor = color
        body.strokeColor = color
        body.lineWidth = 1
        body.glowWidth = 3
        container.addChild(body)

        let legs = SKShapeNode()
        let path = CGMutablePath()
        let legLen = c * 0.38
        for i in 0..<3 {
            let xOff = (CGFloat(i) - 1) * c * 0.28
            path.move(to: CGPoint(x: xOff, y: -c * 0.1)); path.addLine(to: CGPoint(x: xOff - c * 0.1, y: -legLen))
            path.move(to: CGPoint(x: xOff, y:  c * 0.1)); path.addLine(to: CGPoint(x: xOff - c * 0.1, y:  legLen))
        }
        legs.path = path
        legs.strokeColor = color
        legs.lineWidth = 2
        legs.glowWidth = 1.5
        wiggleLegs(legs)
        container.addChild(legs)

        let tail = SKShapeNode(circleOfRadius: c * 0.12)
        tail.fillColor = color
        tail.strokeColor = color
        tail.lineWidth = 1
        tail.glowWidth = 2
        tail.position = CGPoint(x: c * 0.5, y: c * 0.18)
        container.addChild(tail)

        return container
    }

    // MARK: Collisions

    private func resolveBulletHits() {
        var remainingBullets: [SKShapeNode] = []

        bulletLoop: for b in bullets {
            // 1) Segment hit?
            for c in chains.indices {
                for s in chains[c].indices {
                    let seg = chains[c][s]
                    if distance(b.position, seg.node.position) < GameConfig.cell * 0.5 {
                        let pos = seg.node.position
                        let isHead = (s == 0)            // index 0 of a chain is its head
                        b.removeFromParent()
                        destroySegment(chainIndex: c, segIndex: s)
                        addScore(isHead ? 100 : 10)      // arcade: head 100, body 10
                        sfx(.explosion)
                        spawnExplosion(at: pos, color: SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1))
                        continue bulletLoop
                    }
                }
            }
            // 2) Spider hit?
            if let s = spider, distance(b.position, s.node.position) < GameConfig.cell * 0.6 {
                b.removeFromParent()
                killSpider()
                continue bulletLoop
            }
            // 3) Flea hit?
            if let f = flea, distance(b.position, f.node.position) < GameConfig.cell * 0.6 {
                b.removeFromParent()
                hitFlea()
                continue bulletLoop
            }
            // 4) Scorpion hit?
            if let sc = scorpion, distance(b.position, sc.node.position) < GameConfig.cell * 0.6 {
                b.removeFromParent()
                killScorpion()
                continue bulletLoop
            }
            // 5) Mushroom hit?
            let (col, row) = cell(of: b.position)
            if inGrid(col: col, row: row), mushrooms[row][col] != nil {
                b.removeFromParent()
                damageMushroom(col: col, row: row)
                continue bulletLoop
            }
            remainingBullets.append(b)
        }

        bullets = remainingBullets
    }

    /// Shooting a link drops a mushroom in its place and splits the chain in two.
    private func destroySegment(chainIndex: Int, segIndex: Int) {
        let chain = chains[chainIndex]
        let seg = chain[segIndex]
        seg.node.removeFromParent()
        addMushroom(col: seg.col, row: seg.row)

        let before = Array(chain[0..<segIndex])
        let after = Array(chain[(segIndex + 1)...])

        chains.remove(at: chainIndex)
        // Re-promote heads: the link behind the gap becomes a new head.
        if !after.isEmpty {
            recolorHead(of: after)
            chains.insert(after, at: chainIndex)
        }
        if !before.isEmpty {
            chains.insert(before, at: chainIndex)
        }
    }

    private func recolorHead(of chain: [Segment]) {
        guard let head = chain.first else { return }
        head.node.fillColor = wavePalette.head
        head.node.strokeColor = wavePalette.head
    }

    /// Recolor all live mushrooms and centipede links to the current wave palette
    /// (the arcade flips every sprite's color at the start of each round).
    private func applyWavePalette() {
        for chain in chains {
            for (i, seg) in chain.enumerated() {
                let color = (i == 0) ? wavePalette.head : wavePalette.body
                seg.node.fillColor = color
                seg.node.strokeColor = color
            }
        }
        for r in 0..<GameConfig.rows {
            for c in 0..<GameConfig.cols {
                guard let m = mushrooms[r][c] else { continue }
                m.node.fillColor = mushroomColor(for: m.health, poisoned: m.poisoned)
            }
        }
    }

    private func checkPlayerCollision() {
        for chain in chains {
            for seg in chain {
                if distance(seg.node.position, player.position) < GameConfig.cell * 0.6 {
                    loseLife()
                    return
                }
            }
        }
        if let s = spider, distance(s.node.position, player.position) < GameConfig.cell * 0.6 {
            loseLife()
            return
        }
        if let f = flea, distance(f.node.position, player.position) < GameConfig.cell * 0.6 {
            loseLife()
        }
    }

    private func checkWaveCleared() {
        let segmentsLeft = chains.reduce(0) { $0 + $1.count }
        if segmentsLeft == 0 {
            level += 1
            stepInterval = max(0.06, stepInterval - 0.015)   // speed up each wave
            backgroundColor = backgroundForLevel(level)       // screen changes color
            applyWavePalette()                                // recolor surviving mushrooms
            updateHUD()
            sfx(.wave)
            spawnWave()
        }
    }

    // MARK: State changes

    private func addScore(_ points: Int) {
        score += points
        while score >= nextBonusScore {        // bonus life every bonusLifeScore points
            lives += 1
            nextBonusScore += GameConfig.bonusLifeScore
            awardBonusLife()
        }
        updateHUD()
    }

    private func awardBonusLife() {
        sfx(.wave)
        guard phase == .playing else { return }   // no flourish during the silent demo
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "EXTRA LIFE!"
        label.fontSize = 26
        label.fontColor = SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.zPosition = 60
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 40, duration: 1.0), .fadeOut(withDuration: 1.0)]),
            .removeFromParent()
        ]))
    }

    private func loseLife() {
        lives -= 1
        updateHUD()
        sfx(.death)
        spawnExplosion(at: player.position,
                       color: SKColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1),
                       count: 40, speed: 190)
        screenShake(intensity: 16, duration: 0.4)
        // The spider doesn't survive the player's demise either.
        spider?.node.removeFromParent()
        spider = nil
        resetSpiderTimer()
        flea?.node.removeFromParent()
        flea = nil
        fleaCheckTimer = 2.0
        scorpion?.node.removeFromParent()
        scorpion = nil
        resetScorpionTimer()
        if lives <= 0 {
            endGame()
            return
        }
        // Clear remaining centipede and respawn the wave for the next life.
        for chain in chains { for seg in chain { seg.node.removeFromParent() } }
        chains.removeAll()
        for b in bullets { b.removeFromParent() }
        bullets.removeAll()
        regenerateMushrooms()      // arcade: damaged mushrooms are restored on death
        spawnWave()
    }

    /// Restore every partially-shot mushroom to full health (the original does
    /// this each time the player loses a life). Poison state is preserved.
    private func regenerateMushrooms() {
        for r in 0..<GameConfig.rows {
            for c in 0..<GameConfig.cols {
                guard let m = mushrooms[r][c], m.health < GameConfig.mushroomHealth else { continue }
                m.health = GameConfig.mushroomHealth
                m.node.fillColor = mushroomColor(for: m.health, poisoned: m.poisoned)
            }
        }
    }

    private func endGame() {
        isFiring = false
        releaseMouse()
        // A demo round just bounces back to the attract loop — nothing recorded.
        if phase == .attractDemo {
            enterAttractTitle()
            return
        }
        if HighScores.shared.qualifies(score) {
            phase = .enteringInitials
            initialsSlots = ["A", "A", "A"]
            activeSlot = 0
            showInitialsEntry()
        } else {
            phase = .showingScores
            showHighScoreTable(highlightIndex: nil)
        }
    }

    // MARK: Game-over overlay

    private func overlayLabel(_ text: String, size: CGFloat, color: SKColor, y: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: self.size.width / 2, y: y)
        label.zPosition = 151
        return label
    }

    /// A fresh dimmed-backdrop overlay container, attached to the scene.
    private func makeOverlayContainer() -> SKNode {
        overlay?.removeFromParent()
        let node = SKNode()
        node.zPosition = 150

        let backdrop = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        backdrop.fillColor = SKColor(white: 0, alpha: 0.78)
        backdrop.strokeColor = .clear
        backdrop.zPosition = 150
        node.addChild(backdrop)

        overlay = node
        addChild(node)
        return node
    }

    /// Overlay container plus the "GAME OVER" + score header shared by the
    /// post-game initials-entry and high-score screens.
    private func makeGameOverOverlay() -> SKNode {
        let node = makeOverlayContainer()
        node.addChild(overlayLabel("GAME OVER", size: 46,
                                   color: SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1),
                                   y: size.height - 130))
        node.addChild(overlayLabel("SCORE  \(score)", size: 30, color: .white, y: size.height - 190))
        return node
    }

    /// Render the high score rows into `node`, starting at `topY`.
    private func addHighScoreRows(to node: SKNode, highlightIndex: Int?, topY: CGFloat) {
        let entries = HighScores.shared.entries
        if entries.isEmpty {
            node.addChild(overlayLabel("(no scores yet)", size: 18, color: .white, y: topY))
            return
        }
        var y = topY
        let lineHeight: CGFloat = 30
        for (i, e) in entries.enumerated() {
            let text = String(format: "%2d.  %@   %7d", i + 1, e.initials, e.score)
            let color: SKColor = (i == highlightIndex)
                ? SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)
                : .white
            node.addChild(overlayLabel(text, size: 20, color: color, y: y))
            y -= lineHeight
        }
    }

    /// A tappable button (rounded rect + glyph). The rect carries the `name`
    /// used for hit-testing.
    private func makeButton(_ glyph: String, name: String, at p: CGPoint, width: CGFloat = 50, fontSize: CGFloat = 24) -> SKNode {
        let bg = SKShapeNode(rectOf: CGSize(width: width, height: 44), cornerRadius: 8)
        bg.fillColor = SKColor(white: 1, alpha: 0.10)
        bg.strokeColor = SKColor(white: 1, alpha: 0.3)
        bg.position = p
        bg.zPosition = 152
        bg.name = name
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = glyph
        label.fontSize = fontSize
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        bg.addChild(label)
        return bg
    }

    private func showInitialsEntry() {
        let node = makeGameOverOverlay()
        node.addChild(overlayLabel("NEW HIGH SCORE!", size: 24,
                                   color: SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1),
                                   y: size.height - 245))
        node.addChild(overlayLabel("ENTER YOUR INITIALS", size: 18, color: .white,
                                   y: size.height / 2 + 90))

        let cy = size.height / 2 + 5
        for i in 0..<3 {
            let x = size.width / 2 + CGFloat(i - 1) * 72
            node.addChild(makeButton("▲", name: "up\(i)", at: CGPoint(x: x, y: cy + 58)))
            node.addChild(makeButton("▼", name: "down\(i)", at: CGPoint(x: x, y: cy - 58)))
            let letter = overlayLabel(String(initialsSlots[i]), size: 52,
                                      color: i == activeSlot ? SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1) : .white,
                                      y: cy)
            letter.position.x = x
            node.addChild(letter)
        }
        node.addChild(makeButton("OK", name: "ok", at: CGPoint(x: size.width / 2, y: cy - 130), width: 90))

        #if os(macOS)
        let help = "Tap ▲ ▼ or type · OK / Return to confirm"
        #else
        let help = "Tap ▲ ▼ to set each letter · OK to confirm"
        #endif
        node.addChild(overlayLabel(help, size: 13, color: SKColor(white: 0.7, alpha: 1), y: 70))
    }

    private func showHighScoreTable(highlightIndex: Int?) {
        let node = makeGameOverOverlay()
        node.addChild(overlayLabel("HIGH SCORES", size: 24,
                                   color: SKColor(red: 0.3, green: 0.9, blue: 1, alpha: 1),
                                   y: size.height - 250))
        addHighScoreRows(to: node, highlightIndex: highlightIndex, topY: size.height - 295)
        node.addChild(overlayLabel("Click or press Space to play again",
                                   size: 16, color: SKColor(white: 0.7, alpha: 1), y: 60))
        // After a while with no input, drift back into the attract loop.
        attractTimer = 12
    }

    private func commitInitials() {
        let index = HighScores.shared.add(initials: String(initialsSlots), score: score)
        phase = .showingScores
        showHighScoreTable(highlightIndex: index)
    }

    // MARK: Attract mode

    /// Play a sound effect only during a real round — the attract demo is silent.
    private func sfx(_ sound: Sound) {
        if phase == .playing { SoundEngine.shared.play(sound) }
    }

    /// Per-level backdrop tint. Kept dark so sprites stay readable.
    private func backgroundForLevel(_ level: Int) -> SKColor {
        let palette: [SKColor] = [
            SKColor(white: 0, alpha: 1),
            SKColor(red: 0.05, green: 0.05, blue: 0.16, alpha: 1),
            SKColor(red: 0.04, green: 0.13, blue: 0.08, alpha: 1),
            SKColor(red: 0.13, green: 0.04, blue: 0.13, alpha: 1),
            SKColor(red: 0.12, green: 0.09, blue: 0.02, alpha: 1),
            SKColor(red: 0.02, green: 0.11, blue: 0.13, alpha: 1),
        ]
        return palette[((level - 1) % palette.count + palette.count) % palette.count]
    }

    /// Advance attract / post-game screens that auto-cycle after a delay.
    private func handleTimedTransitions(_ dt: Double) {
        switch phase {
        case .attractTitle, .attractScores, .attractDemo, .showingScores:
            attractTimer -= dt
            if attractTimer <= 0 { advanceAttract() }
        default:
            break
        }
    }

    private func advanceAttract() {
        switch phase {
        case .attractTitle:  enterAttractScores()
        case .attractScores: enterAttractDemo()
        default:             enterAttractTitle()   // demo or post-game timeout
        }
    }

    /// Clear the board and lay down a fresh mushroom field as a quiet backdrop
    /// for the title / high-score attract screens. Cycles the background color.
    private func setupAttractBackdrop() {
        removeAllChildren()
        overlay = nil
        attractColorIndex += 1
        backgroundColor = backgroundForLevel(attractColorIndex)
        buildEmptyMushroomGrid()
        addBackdropGrid()
        installCamera()
        scatterMushrooms()
    }

    private func pulsingPrompt(_ text: String, y: CGFloat) -> SKLabelNode {
        let label = overlayLabel(text, size: 22, color: SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1), y: y)
        label.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.25, duration: 0.6),
            .fadeAlpha(to: 1.0, duration: 0.6)
        ])))
        return label
    }

    private func enterAttractTitle() {
        phase = .attractTitle
        attractTimer = 7
        releaseMouse()
        setupAttractBackdrop()
        let node = makeOverlayContainer()
        node.addChild(overlayLabel("CENTIPEDE", size: 64,
                                   color: SKColor(red: 0.5, green: 1, blue: 0.4, alpha: 1),
                                   y: size.height - 180))
        node.addChild(overlayLabel("a SpriteKit tribute", size: 16,
                                   color: SKColor(white: 0.7, alpha: 1), y: size.height - 225))
        node.addChild(pulsingPrompt("PRESS FIRE TO PLAY", y: size.height / 2 - 20))
        node.addChild(overlayLabel("Move: mouse      Fire: click / space",
                                   size: 14, color: SKColor(white: 0.7, alpha: 1), y: size.height / 2 - 70))
        node.addChild(overlayLabel("© 2026", size: 12, color: SKColor(white: 0.55, alpha: 1), y: 60))
    }

    private func enterAttractScores() {
        phase = .attractScores
        attractTimer = 7
        setupAttractBackdrop()
        let node = makeOverlayContainer()
        node.addChild(overlayLabel("HIGH SCORES", size: 30,
                                   color: SKColor(red: 0.3, green: 0.9, blue: 1, alpha: 1),
                                   y: size.height - 150))
        addHighScoreRows(to: node, highlightIndex: nil, topY: size.height - 210)
        node.addChild(overlayLabel("Earn a top-10 spot to enter your initials",
                                   size: 13, color: SKColor(white: 0.7, alpha: 1), y: 110))
        node.addChild(pulsingPrompt("PRESS FIRE TO PLAY", y: 65))
    }

    private func enterAttractDemo() {
        buildNewGame()              // full real board + HUD...
        phase = .attractDemo        // ...but flagged as a silent, unrecorded demo
        attractTimer = 22           // cap the demo length
        updateHUD()                 // refresh to hide the lives count
        let hint = pulsingPrompt("PRESS FIRE TO PLAY", y: 30)
        hint.fontSize = 16
        hint.zPosition = 130
        addChild(hint)              // floats above the board (not in an overlay)
    }

    /// Simple demo AI: glide under the lowest enemy and auto-fire, dodging
    /// anything that gets too close.
    private func updateDemoPlayer(_ dt: Double) {
        isFiring = true
        player.position.y = point(col: 0, row: GameConfig.rows - 2).y

        var targetX = player.position.x
        var lowestY = CGFloat.greatestFiniteMagnitude
        var dodgeX: CGFloat?

        func evaluate(_ pos: CGPoint) {
            if pos.y < lowestY { lowestY = pos.y; targetX = pos.x }
            if distance(pos, player.position) < GameConfig.cell * 2.4 {
                dodgeX = player.position.x + (pos.x >= player.position.x ? -1 : 1) * GameConfig.cell * 3
            }
        }

        for chain in chains { for seg in chain { evaluate(seg.node.position) } }
        if let s = spider { evaluate(s.node.position) }
        if let f = flea { evaluate(f.node.position) }
        if let sc = scorpion { evaluate(sc.node.position) }

        let goalX = dodgeX ?? targetX
        let maxStep = CGFloat(340) * CGFloat(dt)
        let dx = goalX - player.position.x
        player.position.x += max(-maxStep, min(maxStep, dx))

        let half = GameConfig.cell * 0.4
        player.position.x = min(max(player.position.x, half), size.width - half)
    }

    /// Leave attract mode and start a real round.
    private func startGame() {
        buildNewGame()
        captureMouse()
    }

    // MARK: Mouse capture

    /// Lock the system cursor in place so it can't accidentally slide out of the
    /// window mid-game. The shooter is then driven by relative mouse motion —
    /// which also matches the original's trackball feel.
    private func captureMouse() {
        #if os(macOS)
        guard !mouseCaptured else { return }
        CGAssociateMouseAndMouseCursorPosition(0)   // decouple cursor from the mouse
        NSCursor.hide()
        mouseCaptured = true
        updateCursorHintVisibility()
        #endif
    }

    private func releaseMouse() {
        #if os(macOS)
        guard mouseCaptured else { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        mouseCaptured = false
        updateCursorHintVisibility()
        #endif
    }

    #if os(macOS)
    @objc private func appResignedActive() {
        releaseMouse()   // hand the cursor back when the user switches away
    }

    @objc private func appBecameActive() {
        if phase == .playing { captureMouse() }
    }

    @objc private func fullScreenChanged() {
        updateCursorHintVisibility()
    }
    #endif

    // MARK: Input (shared)

    /// A primary tap (mouse click on macOS, touch on iOS) on the non-gameplay
    /// screens. Returns true if it was consumed by UI.
    @discardableResult
    private func handlePrimaryTap(at p: CGPoint) -> Bool {
        switch phase {
        case .attractTitle, .attractScores, .attractDemo, .showingScores:
            startGame()
            return true
        case .enteringInitials:
            handleInitialsTap(at: p)
            return true
        case .paused:
            handlePauseTap(at: p)
            return true
        case .playing:
            return false
        }
    }

    /// First named node (or its parent) under a point — used for button hit-tests.
    private func hitName(at p: CGPoint) -> String? {
        for node in nodes(at: p) {
            if let n = node.name ?? node.parent?.name { return n }
        }
        return nil
    }

    // MARK: Pause

    private func pauseGame() {
        guard phase == .playing else { return }
        phase = .paused
        isFiring = false
        showPauseOverlay()
    }

    private func resumeGame() {
        guard phase == .paused else { return }
        overlay?.removeFromParent()
        overlay = nil
        phase = .playing
    }

    private func handlePauseTap(at p: CGPoint) {
        switch hitName(at: p) {
        case "resume": resumeGame()
        case "quit":   enterAttractTitle()   // back to the title screen
        default:       break
        }
    }

    private func showPauseOverlay() {
        let node = makeOverlayContainer()
        node.addChild(overlayLabel("PAUSED", size: 44, color: .white, y: size.height / 2 + 80))
        node.addChild(makeButton("RESUME", name: "resume",
                                  at: CGPoint(x: size.width / 2, y: size.height / 2), width: 220, fontSize: 22))
        node.addChild(makeButton("QUIT", name: "quit",
                                  at: CGPoint(x: size.width / 2, y: size.height / 2 - 70), width: 220, fontSize: 22))
    }

    /// Hit-test the initials selector (▲ / ▼ / OK buttons) at a point.
    private func handleInitialsTap(at p: CGPoint) {
        for node in nodes(at: p) {
            guard let name = node.name ?? node.parent?.name else { continue }
            if name == "ok" { commitInitials(); return }
            if name.hasPrefix("up"), let i = Int(name.dropFirst(2)) { cycleSlot(i, by: 1); return }
            if name.hasPrefix("down"), let i = Int(name.dropFirst(4)) { cycleSlot(i, by: -1); return }
        }
    }

    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private func cycleSlot(_ i: Int, by delta: Int) {
        guard i >= 0, i < 3 else { return }
        activeSlot = i
        let idx = alphabet.firstIndex(of: initialsSlots[i]) ?? 0
        initialsSlots[i] = alphabet[((idx + delta) % 26 + 26) % 26]
        showInitialsEntry()
    }

    #if os(macOS)
    // MARK: Input (macOS — mouse + keyboard)

    override func mouseDown(with event: NSEvent) {
        switch phase {
        case .playing:
            if mouseCaptured {
                isFiring = true
                fireCooldown = 0       // fire immediately on click
            } else {
                captureMouse()         // click back in to re-grab the cursor (no shot)
            }
        default:
            handlePrimaryTap(at: event.location(in: self))
        }
    }

    override func mouseUp(with event: NSEvent) {
        isFiring = false
    }

    override func mouseMoved(with event: NSEvent) {
        applyMouseDelta(event)
    }

    override func mouseDragged(with event: NSEvent) {
        applyMouseDelta(event)
    }

    private func applyMouseDelta(_ event: NSEvent) {
        guard phase == .playing, mouseCaptured else { return }
        movePlayer(dx: event.deltaX, dy: event.deltaY)
    }

    override func keyDown(with event: NSEvent) {
        if phase == .enteringInitials {
            handleInitialsKey(event)
            return
        }
        switch event.keyCode {
        case 49:               // space
            if phase == .playing { isFiring = true; fireCooldown = 0 }
            else { startGame() }
        case 15:               // 'r'
            startGame()
        case 53:               // escape — free / re-grab the cursor during play
            if phase == .playing {
                if mouseCaptured { releaseMouse() } else { captureMouse() }
            }
        default:
            break
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { isFiring = false }   // space
    }

    private func handleInitialsKey(_ event: NSEvent) {
        switch event.keyCode {
        case 36, 76: commitInitials()                                   // return / enter
        case 123: activeSlot = max(0, activeSlot - 1); showInitialsEntry()   // ←
        case 124: activeSlot = min(2, activeSlot + 1); showInitialsEntry()   // →
        case 126: cycleSlot(activeSlot, by: 1)                          // ↑
        case 125: cycleSlot(activeSlot, by: -1)                         // ↓
        default:
            if let ch = event.charactersIgnoringModifiers?.first, ch.isLetter {
                initialsSlots[activeSlot] = Character(ch.uppercased())
                if activeSlot < 2 { activeSlot += 1 }
                showInitialsEntry()
            }
        }
    }
    #endif

    #if os(iOS)
    // MARK: Input (iOS — touch)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if handlePrimaryTap(at: p) { return }
        if hitName(at: p) == "pause" { pauseGame(); return }
        moveGunToTouch(p)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .playing, let t = touches.first else { return }
        moveGunToTouch(t.location(in: self))
    }

    /// Place the shooter at the finger's x, lifted above the fingertip so the
    /// finger doesn't cover it, clamped to the bottom play zone.
    private func moveGunToTouch(_ p: CGPoint) {
        guard player != nil else { return }
        let half = GameConfig.cell * 0.4
        let minY = GameConfig.cell * 0.5
        let maxY = CGFloat(GameConfig.playerRows) * GameConfig.cell
        let x = min(max(p.x, half), size.width - half)
        let y = min(max(p.y + GameConfig.cell * 2.5, minY), maxY)
        player.position = CGPoint(x: x, y: y)
    }
    #endif

    // MARK: Effects

    /// Give a node a gentle continuous rock, so bug legs look like they scuttle.
    private func wiggleLegs(_ node: SKNode) {
        node.run(.repeatForever(.sequence([
            .rotate(toAngle: 0.14, duration: 0.12),
            .rotate(toAngle: -0.14, duration: 0.12)
        ])))
    }

    /// A faint grid behind the action that reinforces the cell structure.
    private func addBackdropGrid() {
        let grid = SKShapeNode()
        let path = CGMutablePath()
        for c in 0...GameConfig.cols {
            let x = CGFloat(c) * GameConfig.cell
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
        }
        for r in 0...GameConfig.rows {
            let y = CGFloat(r) * GameConfig.cell
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
        }
        grid.path = path
        grid.strokeColor = SKColor(white: 1, alpha: 0.05)
        grid.lineWidth = 1
        grid.zPosition = -10
        addChild(grid)
    }

    /// Keep a camera installed (centered) so we can shake it. removeAllChildren()
    /// detaches it, so re-add and recenter whenever we rebuild the scene.
    private func installCamera() {
        if gameCamera.parent == nil { addChild(gameCamera) }
        gameCamera.position = CGPoint(x: size.width / 2, y: size.height / 2)
        camera = gameCamera
    }

    /// Quick screen shake by jittering the camera back to center.
    private func screenShake(intensity: CGFloat, duration: Double = 0.3) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let steps = 6
        var actions: [SKAction] = []
        let stepTime = duration / Double(steps + 1)
        for i in 0..<steps {
            let decay = 1 - CGFloat(i) / CGFloat(steps)
            let dx = CGFloat.random(in: -intensity...intensity) * decay
            let dy = CGFloat.random(in: -intensity...intensity) * decay
            actions.append(.move(to: CGPoint(x: center.x + dx, y: center.y + dy), duration: stepTime))
        }
        actions.append(.move(to: center, duration: stepTime))
        gameCamera.run(.sequence(actions), withKey: "shake")
    }

    /// Build a small white dot texture in code (no image assets) to use as the
    /// particle for explosions. Drawn via Core Graphics so it works on both
    /// macOS (AppKit) and iOS (UIKit).
    private func makeSparkTexture() -> SKTexture {
        let d = 8
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: d, height: d, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return SKTexture()
        }
        ctx.setFillColor(SKColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
        guard let image = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: image)
    }

    /// Fire off a one-shot particle burst that emits `count` sparks then removes
    /// itself. Configured entirely in code (no .sks particle file needed).
    private func spawnExplosion(at position: CGPoint,
                                color: SKColor,
                                count: Int = 22,
                                speed: CGFloat = 130) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = sparkTexture
        emitter.numParticlesToEmit = count
        emitter.particleBirthRate = 1800            // emit the burst fast, then stop
        emitter.particleLifetime = 0.45
        emitter.particleLifetimeRange = 0.2
        emitter.position = position
        emitter.zPosition = 6
        emitter.particlePositionRange = CGVector(dx: 4, dy: 4)
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2        // radiate in all directions
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.6
        emitter.particleScale = 0.5
        emitter.particleScaleRange = 0.25
        emitter.particleScaleSpeed = -0.8
        emitter.particleAlpha = 1
        emitter.particleAlphaSpeed = -2.2
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: 0.9), .removeFromParent()]))
    }

    // MARK: Util

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
