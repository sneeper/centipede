import AppKit
import SpriteKit

/// Bootstraps a plain AppKit application by hand (no storyboard / no Xcode
/// project needed) and drops an SKView running the game into a window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var skView: SKView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        let size = NSSize(width: GameConfig.width, height: GameConfig.height)

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Centipede"
        window.isReleasedWhenClosed = false        // we hold the only strong ref
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior.insert(.fullScreenPrimary)   // allow ⌘F full screen
        window.contentAspectRatio = size           // keep 5:6 when resizing manually
        window.center()

        skView = SKView(frame: NSRect(origin: .zero, size: size))
        skView.ignoresSiblingOrder = true
        // Flip these on while developing if you want perf stats:
        // skView.showsFPS = true
        // skView.showsNodeCount = true
        window.contentView = skView

        let scene = GameScene(size: size)
        // Keep the fixed 600x720 coordinate space and scale it uniformly to fill
        // the view (letterboxed). This is what makes full screen "just bigger".
        scene.scaleMode = .aspectFit
        skView.presentScene(scene)

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(skView)          // so key events reach the scene
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A minimal main menu so the standard ⌘Q quit shortcut is wired up.
    /// (A hand-built SwiftPM app has no menu bar unless we make one.)
    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Centipede",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu

        // View menu: full-screen toggle (⌘F). toggleFullScreen: travels up the
        // responder chain to the key window, which supports it via fullScreenPrimary.
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        let fullScreen = NSMenuItem(
            title: "Toggle Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(fullScreen)
        viewMenuItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// Manual app entry point. (A SwiftPM executable needs us to wire up the
// NSApplication ourselves since there's no Info.plist / main storyboard.)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
