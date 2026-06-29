import SwiftUI
import SpriteKit
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// The whole app: a single SwiftUI entry point shared by macOS and iOS that
/// hosts the SpriteKit `GameScene` in a `SpriteView`. The scene keeps its fixed
/// 600×720 coordinate space and `.aspectFit` scales it to whatever screen it's on.
@main
struct CentipedeApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        #endif
    }
}

struct GameView: View {
    #if os(macOS)
    // Fixed 600×720 window on the Mac.
    @State private var scene: GameScene = {
        let scene = GameScene(size: CGSize(width: GameConfig.width, height: GameConfig.height))
        scene.scaleMode = .aspectFit
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene)
            .frame(width: GameConfig.width, height: GameConfig.height)
            .ignoresSafeArea()
    }
    #else
    // On iOS, size the field to the full screen aspect so it fills the display
    // (HUD sits in the corners, clear of the centered Dynamic Island).
    @State private var scene: GameScene = GameScene.makeFilling(viewSize: UIScreen.main.bounds.size)

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }
    #endif
}
