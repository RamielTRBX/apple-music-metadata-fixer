import SwiftUI

struct AppleMusicMetadataFixerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

@main
enum Main {
    static func main() {
        AppleMusicMetadataFixerApp.main()
    }
}
