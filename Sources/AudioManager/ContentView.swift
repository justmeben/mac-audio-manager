import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DevicesView()
                .tabItem { Label("Devices", systemImage: "headphones") }
            MixerView()
                .tabItem { Label("App Mixer", systemImage: "slider.horizontal.3") }
        }
        .padding(.top, 4)
    }
}
