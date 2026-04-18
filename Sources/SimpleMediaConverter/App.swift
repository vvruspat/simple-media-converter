import SwiftUI

@main
struct SimpleMediaConverterApp: App {
    var body: some Scene {
        WindowGroup("Simple media converter") {
            ContentView()
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
