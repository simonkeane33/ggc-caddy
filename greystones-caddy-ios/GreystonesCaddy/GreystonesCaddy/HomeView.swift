import SwiftUI
import GreystonesCaddyCore

struct HomeView: View {
  @EnvironmentObject var state: AppState

  var body: some View {
    NavigationStack {
      ZStack {
        // Full-screen hero background
        Image("HomeHero")
          .resizable()
          .scaledToFill()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .ignoresSafeArea()
          .clipped()

        // Gradient overlay for legibility
        LinearGradient(
          colors: [.clear, .black.opacity(0.5), .black.opacity(0.85)],
          startPoint: .top,
          endPoint: .bottom
        )
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
    } else {
      NavigationLink {
        RoundSetupView()
      } label: {
        ctaButton(label: "Start round", icon: "plus.circle.fill")
      }
      .buttonStyle(.plain)
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
