import SwiftUI
import GreystonesCaddyCore

struct HomeView: View {
  @EnvironmentObject var state: AppState

  var body: some View {
    NavigationStack {
      ZStack {
        // Full-screen hero background, isolated in its own ignoring-safe-area subtree.
        // Mixing ignoresSafeArea() content directly alongside non-ignoring Spacer()-based
        // siblings (the overlays below) in one ZStack causes SwiftUI/UINavigationController
        // to render an opaque bar over the safe-area strip regardless of ignoresSafeArea on
        // the individual children. Isolating the full-bleed content in its own subtree here
        // avoids that; the overlays below keep their original, unmodified layout.
        GeometryReader { geo in
          ZStack {
            Image("HomeHero")
              .resizable()
              .scaledToFill()
              .frame(width: geo.size.width, height: geo.size.height)
              .clipped()

            LinearGradient(
              colors: [.clear, .black.opacity(0.5), .black.opacity(0.85)],
              startPoint: .top,
              endPoint: .bottom
            )
          }
        }
        .ignoresSafeArea()

        // Logo in top third
        VStack {
          Image("ClubLogo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 180)
            .padding(.top, 60)
          Spacer()
        }

        // CTA stack in lower third
        VStack {
          Spacer()
          VStack(spacing: 20) {
            primaryCTA
            if state.activeRoundId != nil {
              secondaryCTA
            }
            hubLinks
          }
          .padding(.bottom, 56)
        }

        // Settings overlay — top-right, white
        VStack {
          HStack {
            Spacer()
            NavigationLink {
              SettingsView()
            } label: {
              Image(systemName: "gear")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("settingsButton")
            .padding(.trailing, 16)
            .padding(.top, 8)
          }
          Spacer()
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.hidden, for: .navigationBar)
    }
  }

  @ViewBuilder
  private var primaryCTA: some View {
    if state.activeRoundId != nil {
      NavigationLink {
        ResumeRoundView(roundId: state.activeRoundId!)
      } label: {
        ctaButton(label: "Resume round", icon: "play.circle.fill")
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("resumeRoundButton")
    } else {
      NavigationLink {
        RoundSetupView()
      } label: {
        ctaButton(label: "Start round", icon: "plus.circle.fill")
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("startRoundButton")
    }
  }

  private var secondaryCTA: some View {
    NavigationLink {
      RoundSetupView()
    } label: {
      Text("Start new round")
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.white.opacity(0.5), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("startNewRoundButton")
  }

  private func ctaButton(label: String, icon: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .font(.title2)
      Text(label)
        .font(.headline)
        .fontWeight(.semibold)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 32)
    .padding(.vertical, 18)
    .background(Color.accentColor)
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  /// Secondary hub links: round history and stats. The pre-cinematic Home exposed
  /// these as a toolbar icon and a recent-rounds list; the rebuild dropped both from
  /// the home surface and buried them in Settings. Restoring them here keeps Home as
  /// the navigation hub the v1 round-flow docs describe (Home -> Round history).
  private var hubLinks: some View {
    HStack(spacing: 16) {
      NavigationLink {
        RoundHistoryView()
      } label: {
        hubLink(label: "History", icon: "clock.arrow.circlepath")
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("historyLink")

      NavigationLink {
        StatsDashboardView()
      } label: {
        hubLink(label: "Stats", icon: "chart.bar.fill")
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("statsLink")
    }
    .padding(.top, 4)
  }

  private func hubLink(label: String, icon: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.footnote)
      Text(label)
        .font(.subheadline)
        .fontWeight(.medium)
    }
    .foregroundStyle(.white.opacity(0.9))
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
    .overlay(
      Capsule()
        .strokeBorder(.white.opacity(0.4), lineWidth: 1)
    )
  }
}

/// Wrapper that sets activeRoundId before showing MainGameView for resuming in-progress rounds.
struct ResumeRoundView: View {
  @EnvironmentObject var state: AppState
  let roundId: Int64

  var body: some View {
    MainGameView()
      .onAppear { state.activeRoundId = roundId }
  }
}
