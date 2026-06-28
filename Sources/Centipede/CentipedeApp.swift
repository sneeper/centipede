import SwiftUI
import SpriteKit
#if os(macOS)
import AppKit
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
    // On iOS, size the field to the device's safe area so it fills the screen
    // (and the HUD clears the Dynamic Island / home indicator).
    @State private var scene: GameScene?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()       // fill the notch / home-indicator insets
            GeometryReader { geo in
                Group {
                    if let scene {
                        SpriteView(scene: scene)
                    }
                }
                .onAppear {
                    if scene == nil { scene = GameScene.makeFilling(viewSize: geo.size) }
                }
            }
        }
    }
    #endif
}
