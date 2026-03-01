import SwiftUI

struct SettingsView: View {
  var body: some View {
    List {
      Section {
        NavigationLink("My Bag") { BagSettingsView() }
        NavigationLink("Typical yardages") { ClubBaselinesView() }
      }
    }
    .navigationTitle("Settings")
  }
}
