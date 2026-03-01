import SwiftUI
import GreystonesCaddyCore

struct ClubBaselinesView: View {
  @State private var baselines: [ClubID: ClubBaseline] = [:]

  var body: some View {
    List {
      Section {
        Text("Set your typical yardages (carry + total). We’ll use these for recommendations and visuals.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section("Clubs") {
        ForEach(ClubID.allCases) { c in
          NavigationLink {
            BaselineEditView(club: c)
              .onDisappear { load() }
          } label: {
            HStack {
              Text(c.rawValue)
              Spacer()
              if let b = baselines[c], (b.carryYd != nil || b.totalYd != nil) {
                Text("\(b.carryYd ?? 0)/\(b.totalYd ?? 0) yd")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              } else {
                Text("Not set")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    .navigationTitle("Typical yardages")
    .onAppear { load() }
  }

  private func load() {
    let all = (try? GCDB.shared.listBaselines()) ?? []
    baselines = Dictionary(uniqueKeysWithValues: all.map { ($0.club, $0) })
  }
}

private struct BaselineEditView: View {
  let club: ClubID

  @State private var carry: String = ""
  @State private var total: String = ""

  var body: some View {
    Form {
      Section(club.rawValue) {
        TextField("Carry (yd)", text: $carry)
          .keyboardType(.numberPad)
        TextField("Total (yd)", text: $total)
          .keyboardType(.numberPad)
      }

      Section {
        Button("Save") {
          let c = Int(carry.trimmingCharacters(in: .whitespacesAndNewlines))
          let t = Int(total.trimmingCharacters(in: .whitespacesAndNewlines))
          try? GCDB.shared.upsertBaseline(club: club, carryYd: c, totalYd: t)
        }
      }
    }
    .navigationTitle(club.rawValue)
    .onAppear {
      do {
        if let bb = try GCDB.shared.fetchBaseline(club: club) {
          carry = bb.carryYd.map(String.init) ?? ""
          total = bb.totalYd.map(String.init) ?? ""
        }
      } catch {
        // Ignore for MVP.
      }
    }
  }
}
