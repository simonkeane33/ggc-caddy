//
//  GreystonesCaddyApp.swift
//  GreystonesCaddy
//
//  Created by Albie on 20/02/2026.
//

import SwiftUI

@main
struct GreystonesCaddyApp: App {
  @StateObject private var state = AppState()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(state)
    }
  }
}
