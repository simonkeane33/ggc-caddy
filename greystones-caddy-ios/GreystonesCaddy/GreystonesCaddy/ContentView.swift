import SwiftUI

struct ContentView: View {
  @EnvironmentObject var state: AppState

  var body: some View {
    HomeView()
  }
}

#Preview {
  ContentView()
    .environmentObject(AppState())
}
