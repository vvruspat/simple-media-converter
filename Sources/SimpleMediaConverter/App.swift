import SwiftUI

@main
struct SimpleMediaConverterApp: App {
    var body: some Scene {
        WindowGroup("WAV → MP3") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
