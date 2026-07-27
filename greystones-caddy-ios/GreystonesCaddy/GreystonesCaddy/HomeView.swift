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

            // Scrim for the controls in the lower third only. Evenly spaced
            // stops previously put 50% black across the middle of the frame,
            // dimming the whole photograph; holding it clear to just under
            // halfway keeps the hero bright while still backing the buttons.
            LinearGradient(
              stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.45),
                .init(color: .black.opacity(0.45), location: 0.78),
                .init(color: .black.opacity(0.7), location: 1.0)
              ],
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

        // CTA row in lower third
        VStack {
          Spacer()
          primaryActions
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }

        // Overflow menu — top-right. Replaces the settings cog; History and
        // Stats moved in here so the lower third is a single row of primary
        // actions rather than three stacked rows of competing buttons.
        VStack {
          HStack {
            Spacer()
            Menu {
              NavigationLink {
                RoundHistoryView()
              } label: {
                Label("Round history", systemImage: "clock.arrow.circlepath")
              }
              .accessibilityIdentifier("historyLink")

              NavigationLink {
                StatsDashboardView()
              } label: {
                Label("Stats", systemImage: "chart.bar.fill")
              }
              .accessibilityIdentifier("statsLink")

              Divider()

              NavigationLink {
                SettingsView()
              } label: {
                Label("Settings", systemImage: "gear")
              }
              .accessibilityIdentifier("settingsButton")
            } label: {
              Image(systemName: "line.3.horizontal")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("homeMenuButton")
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

  /// The two primary actions, side by side and equally weighted. With a round
  /// in progress both are shown; otherwise "Start round" takes the full width.
  @ViewBuilder
  private var primaryActions: some View {
    if state.activeRoundId != nil {
      HStack(spacing: 12) {
        NavigationLink {
          ResumeRoundView(roundId: state.activeRoundId!)
        } label: {
          ctaButton(label: "Resume", icon: "play.circle.fill", style: .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("resumeRoundButton")

        NavigationLink {
          RoundSetupView()
        } label: {
          ctaButton(label: "New round", icon: "plus.circle.fill")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("startNewRoundButton")
      }
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

  private enum CTAStyle { case primary, secondary }

  /// Equal-width so a pair sits as a balanced row; single-line and scalable so
  /// the longer label doesn't wrap at half width. Both styles share the same
  /// metrics so the two sit level regardless of which is filled.
  private func ctaButton(label: String, icon: String, style: CTAStyle = .primary) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.title3)
      Text(label)
        .font(.headline)
        .fontWeight(.semibold)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
    .background {
      switch style {
      case .primary:
        RoundedRectangle(cornerRadius: 14).fill(Color.accentColor)
      case .secondary:
        // Tinted rather than fully transparent: over a photograph a plain
        // outline leaves white text sitting on whatever happens to be behind it.
        RoundedRectangle(cornerRadius: 14)
          .fill(.black.opacity(0.35))
          .overlay(
            RoundedRectangle(cornerRadius: 14)
              .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
          )
      }
    }
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
