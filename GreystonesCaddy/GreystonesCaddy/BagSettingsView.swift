import SwiftUI
import GreystonesCaddyCore

struct BagSettingsView: View {
  @EnvironmentObject var state: AppState

  @State private var selected: Set<ClubID> = []
  @State private var order: [ClubID] = []

  var body: some View {
    List {
      Section("Your bag") {
        Text("Pick the clubs you actually carry. This is a one-off setting.")
          .font(.footnote)
          .foregroundStyle(.secondary)

        if order.isEmpty {
          Text("No clubs selected yet")
            .foregroundStyle(.secondary)
        } else {
          ForEach(order) { c in
            HStack {
              Text(c.rawValue)
              Spacer()
              Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
            }
          }
          .onMove { from, to in
            order.move(fromOffsets: from, toOffset: to)
          }

          Button("Save bag") {
            try? GCDB.shared.setBagClubs(order)
            state.reloadBagFromDB()
          }
        }
      }

      Section("All clubs") {
        ForEach(ClubID.allCases) { c in
          Toggle(c.rawValue, isOn: Binding(
            get: { selected.contains(c) },
            set: { on in
              if on {
                selected.insert(c)
                if !order.contains(c) { order.append(c) }
              } else {
                selected.remove(c)
                order.removeAll(where: { $0 == c })
              }
            }
          ))
        }
      }
    }
    .navigationTitle("My Bag")
    .toolbar {
      EditButton()
    }
    .onAppear {
      let current = (try? GCDB.shared.fetchBagClubs()) ?? []
      if current.isEmpty {
        order = Club.defaultFavourites
      } else {
        order = current
      }
      selected = Set(order)
    }
  }
}
