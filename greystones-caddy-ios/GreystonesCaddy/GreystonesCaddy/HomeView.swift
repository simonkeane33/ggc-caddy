import SwiftUI
import GreystonesCaddyCore

struct HomeView: View {
  @EnvironmentObject var state: AppState

  @State private var rounds: [RoundSummary] = []

  var body: some View {
    NavigationStack {
      List {
        if state.activeRoundId != nil {
          Section {
            NavigationLink("Resume active round") {
              MainGameView()
            }
          }
        }

        Section {
          NavigationLink("Start new round") {
            RoundSetupView()
          }
          NavigationLink("Course insights") {
            CourseInsightsView(course: state.course)
          }
          NavigationLink("Course intelligence") {
            CourseIntelligenceView(course: state.course)
          }
        }

        if !rounds.isEmpty {
          Section("Recent rounds") {
            ForEach(rounds) { r in
              NavigationLink {
                RoundDetailView(round: r)
              } label: {
                VStack(alignment: .leading, spacing: 3) {
                  Text(r.startedAt, style: .date)
                    .font(.headline)
                  Text("\(r.tee.rawValue.capitalized) • \(r.distanceUnit == .yards ? "Yards" : "Metres")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                  if let ended = r.endedAt {
                    Text("Ended \(ended, style: .time)")
                      .font(.footnote)
                      .foregroundStyle(.secondary)
                  } else {
                    Text("In progress")
                      .font(.footnote)
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
          }
        }
      }
      .navigationTitle("Greystones Caddy")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink {
            StatsDashboardView()
          } label: {
            Image(systemName: "chart.bar.fill")
          }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink {
            SettingsView()
          } label: {
            Image(systemName: "gear")
          }
        }
      }
      .onAppear { refresh() }
    }
  }

  private func refresh() {
    rounds = (try? GCDB.shared.listRounds(limit: 20)) ?? []
  }
}
