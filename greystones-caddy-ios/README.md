# Greystones Caddy (iOS)

Phone-only shot tracker + digital scorecard for **Greystones Golf Club**.

## Stack
- SwiftUI
- SQLite via **GRDB** (Swift Package Manager)

## Repo layout (this folder)
- `CourseData/greystones_course.json` - hole metadata (par, SI, distances, flyover links)
- `GreystonesCaddyCore/` - Swift Package (models + storage + course loader)

## First-time setup (Xcode)
1. **Create the iOS app project**
   - Xcode → *File → New → Project…* → **iOS → App**
   - Product Name: `GreystonesCaddy`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Save it inside this folder: `greystones-caddy-ios/` (so git captures everything)

2. **Add the local Swift Package**
   - In Xcode: File → Add Package Dependencies… → **Add Local…**
   - Select `GreystonesCaddyCore/`

3. **Add GRDB**
   - In Xcode: File → Add Package Dependencies…
   - URL: `https://github.com/groue/GRDB.swift`

4. **Info.plist location permission**
   Add:
   - `NSLocationWhenInUseUsageDescription` = "We use your location to log shot positions during a round."

5. **Run on device**
   - Connect iPhone
   - Select your device target
   - Run (you may need to set a Development Team for signing)

## Data
All distances in the course JSON are **metres**. UI can toggle metres/yards.

## Next
Once the Xcode app shell exists, we’ll wire in:
- Load course JSON
- Round start (tees + units)
- Live hole screen: select club → log shot (GPS)
- SQLite persistence (rounds + shots)
