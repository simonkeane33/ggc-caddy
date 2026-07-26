import SwiftUI

struct SettingsView: View {
  var body: some View {
    List {
      Section {
        NavigationLink("Round history") { RoundHistoryView() }
        NavigationLink("Stats") { StatsDashboardView() }
      }
      Section {
        NavigationLink("My Bag") { BagSettingsView() }
        NavigationLink("Typical yardages") { ClubBaselinesView() }
      }
    }
    .navigationTitle("Settings")
  }
}
