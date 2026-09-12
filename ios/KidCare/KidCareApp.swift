import SwiftUI

@main
struct KidCareApp: App {

    init() {
        FirebaseBootstrap.configureForApp()
    }

    var body: some Scene {
        WindowGroup {
            RouterView()
        }
    }
}
