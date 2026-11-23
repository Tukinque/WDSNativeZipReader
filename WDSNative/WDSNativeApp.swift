import SwiftUI

@main
struct WDSNativeApp: App {
    @StateObject private var model = LibraryModel()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model) }
    }
}
