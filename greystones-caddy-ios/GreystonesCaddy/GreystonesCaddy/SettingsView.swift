import SwiftUI

struct SettingsView: View {
  var body: some View {
    List {
      Section {
        NavigationLink("Round history") { RoundHistoryView() }
          .accessibilityIdentifier("settingsRoundHistoryLink")
        NavigationLink("Stats") { StatsDashboardView() }
          .accessibilityIdentifier("settingsStatsLink")
      }
      Section {
        NavigationLink("My Bag") { BagSettingsView() }
          .accessibilityIdentifier("settingsMyBagLink")
        NavigationLink("Typical yardages") { ClubBaselinesView() }
          .accessibilityIdentifier("settingsYardagesLink")
      }
    }
    .navigationTitle("Settings")
  }
}
