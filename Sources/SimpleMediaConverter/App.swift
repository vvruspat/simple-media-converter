import SwiftUI

@main
struct SimpleMediaConverterApp: App {
    var body: some Scene {
        WindowGroup("WAV → MP3  v2") {
            ContentView()
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
