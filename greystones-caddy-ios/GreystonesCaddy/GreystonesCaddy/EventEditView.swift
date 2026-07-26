import SwiftUI
import CoreLocation
import GreystonesCaddyCore

struct EventEditView: View {
  let event: HoleEvent

  @Environment(\.dismiss) private var dismiss
  @StateObject private var loc = LocationProvider()

  @State private var selectedClub: ClubID = .iron7
  @State private var shotType: ShotType = .full
  @State private var penaltyStrokes: Int = 1
  @State private var message: String? = nil

  var body: some View {
    Form {
      Section("Event") {
        HStack {
          Text("Type")
          Spacer()
          Text(event.kind == .shot ? "Shot" : "Penalty")
            .foregroundStyle(.secondary)
        }
        HStack {
          Text("Time")
          Spacer()
          Text(event.ts, style: .time)
            .foregroundStyle(.secondary)
        }
      }

      if event.kind == .shot {
        Section("Club") {
          Picker("Club", selection: $selectedClub) {
            ForEach(ClubID.allCases) { c in
              Text(c.rawValue).tag(c)
            }
          }
        }

        Section("Position") {
          Button("Recapture position") {
            recapturePosition()
          }
        }

        if selectedClub != .putter {
          Section("Shot type") {
            Picker("Type", selection: $shotType) {
              ForEach([ShotType.full, .threeQuarter, .half, .chip], id: \.self) { st in
                Text(st.label).tag(st)
              }
            }
            .pickerStyle(.segmented)
          }
        }
      } else {
        Section("Penalty") {
          Stepper("Strokes: \(penaltyStrokes)", value: $penaltyStrokes, in: 1...4)
        }
      }

      Section {
        Button("Save") { save() }
          .frame(maxWidth: .infinity, alignment: .center)
      }

      if let message {
        Section {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Edit")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      selectedClub = event.club
      shotType = event.shotType
      penaltyStrokes = event.penaltyStrokes ?? 1
    }
  }

  private func recapturePosition() {
    guard let l = loc.lastLocation else {
      message = "Waiting for GPS…"
      return
    }
    let alt: Double? = (l.altitude >= 0) ? l.altitude : nil
    do {
      try GCDB.shared.updateShotPosition(id: event.id, lat: l.coordinate.latitude, lng: l.coordinate.longitude, alt: alt)
      message = "Position updated"
    } catch {
      message = "Failed to update position: \(error.localizedDescription)"
    }
  }

  private func save() {
    do {
      if event.kind == .shot {
        try GCDB.shared.updateShotClub(id: event.id, club: selectedClub)
        if selectedClub != .putter {
          try GCDB.shared.updateShotType(id: event.id, shotType: shotType)
        }
      } else {
        try GCDB.shared.updatePenalty(id: event.id, strokes: penaltyStrokes)
      }
      dismiss()
    } catch {
      message = "Save failed: \(error.localizedDescription)"
    }
  }
}
