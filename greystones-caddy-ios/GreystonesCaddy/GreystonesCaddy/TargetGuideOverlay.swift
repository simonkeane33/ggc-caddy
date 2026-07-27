import SwiftUI
import Combine
import MapKit
import CoreLocation

/// Where the target is while a drag is in flight.
///
/// `point` is in the guide overlay's local space and drives the crosshair and
/// the guide lines; `coordinate` is the same position on the globe and drives
/// the distance read-outs. Both are published together so a drag frame emits a
/// single change.
struct LiveTarget {
    let point: CGPoint
    let coordinate: CLLocationCoordinate2D
}

/// Shared conduit for the in-flight drag position.
///
/// Hold this in `@State`, **not** `@StateObject`: `@State` keeps the reference
/// alive without subscribing the owning view to `objectWillChange`, so a drag
/// frame re-renders only the views that observe it and leaves the `Map` and its
/// annotations untouched.
///
/// This matters a lot. Driving a drag through the map itself — moving an
/// `Annotation`'s coordinate and rebuilding a `MapPolyline` on every frame —
/// makes the target visibly trail the finger: MapKit animates annotation
/// coordinate changes internally, renders overlays on a separate thread, and
/// re-diffs the whole of `MapContent` each time the parent body runs.
final class TargetDragState: ObservableObject {
    @Published var live: LiveTarget? = nil

    /// Bumped whenever the map camera moves.
    ///
    /// The overlay projects tee, target, and green through the `MapProxy` when
    /// its body runs, so it has to re-run as the camera pans and zooms or the
    /// lines detach from the map underneath. Publishing it here rather than in
    /// parent state means only the overlay re-renders — a `MapPolyline` got this
    /// for free, but at the cost of lagging during a drag.
    @Published var cameraGeneration: Int = 0

    var isDragging: Bool { live != nil }

    func cameraDidChange() {
        cameraGeneration &+= 1
    }
}

/// Guide lines, optional distance rings, and the draggable target crosshair,
/// drawn in SwiftUI screen space on top of a `Map`.
///
/// While dragging, the crosshair position comes straight from the touch point
/// (a subtraction, no reprojection), and the lines are drawn from that same
/// point — so the lines cannot lag the crosshair and neither can lag the finger.
/// The map is not touched at all until the drag ends.
struct TargetGuideOverlay<Accessory: View>: View {
    let proxy: MapProxy
    @ObservedObject var drag: TargetDragState
    let tee: CLLocationCoordinate2D
    let green: CLLocationCoordinate2D
    /// The target as last committed; used whenever no drag is in flight.
    let committedTarget: CLLocationCoordinate2D
    /// Enlarges the crosshair. A drag always enlarges it regardless of this.
    let isZoomed: Bool
    /// Ring radii in yards, drawn only while `isZoomed`. Empty for no rings.
    let ringYardages: [Double]
    /// Accessibility identifier for the crosshair. Must differ per screen —
    /// both screens can be in the hierarchy at once and a shared identifier
    /// makes UI-test queries ambiguous.
    let crosshairIdentifier: String
    let onCommit: (CLLocationCoordinate2D) -> Void
    /// Extra content centred on the crosshair — distance pills and the like.
    /// Drawn above the catch area so its controls stay tappable.
    @ViewBuilder let accessory: (CLLocationCoordinate2D) -> Accessory

    /// Touch catch area around the crosshair. Big enough to grab comfortably,
    /// small enough that the rest of the map stays fully interactive.
    private let catchSize: CGFloat = 160

    var body: some View {
        GeometryReader { geo in
            // `.position` resolves against this view's local space, so global
            // touch points have to be rebased through the overlay's origin.
            // Positioning with raw global points renders the crosshair offset
            // from the lines by the status/nav bar height.
            let originInGlobal = geo.frame(in: .global).origin
            let teePoint = proxy.convert(tee, to: .local) ?? .zero
            let greenPoint = proxy.convert(green, to: .local) ?? .zero
            let committedPoint = proxy.convert(committedTarget, to: .local) ?? .zero
            let crosshairPoint = drag.live?.point ?? committedPoint
            let activeTarget = drag.live?.coordinate ?? committedTarget

            ZStack {
                LineShape(from: teePoint, to: crosshairPoint)
                    .stroke(.white.opacity(0.8), lineWidth: 2)
                    .allowsHitTesting(false)

                LineShape(from: crosshairPoint, to: greenPoint)
                    .stroke(.white.opacity(0.8), lineWidth: 2)
                    .allowsHitTesting(false)

                if isZoomed {
                    ForEach(ringYardages, id: \.self) { yards in
                        let diameter = ringDiameter(yards: yards, centre: activeTarget)
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                            .frame(width: diameter, height: diameter)
                            .position(crosshairPoint)
                            .allowsHitTesting(false)
                    }
                }

                // Clear catch area behind the crosshair. It consumes the touch so
                // the Map never sees it and cannot pan out from under the target.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: catchSize, height: catchSize)
                    .position(crosshairPoint)
                    .gesture(dragGesture(originInGlobal: originInGlobal))

                TargetCrosshair(isZoomed: isZoomed || drag.isDragging)
                    .frame(width: catchSize, height: catchSize)
                    .position(crosshairPoint)
                    .accessibilityIdentifier(crosshairIdentifier)
                    .allowsHitTesting(false)

                accessory(activeTarget)
                    .position(crosshairPoint)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func dragGesture(originInGlobal: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard let coord = proxy.convert(value.location, from: .global) else { return }
                drag.live = LiveTarget(
                    point: CGPoint(
                        x: value.location.x - originInGlobal.x,
                        y: value.location.y - originInGlobal.y
                    ),
                    coordinate: coord
                )
            }
            .onEnded { value in
                let coord = proxy.convert(value.location, from: .global)
                // Clear the live position before committing so the crosshair
                // hands over to the committed target in the same update.
                drag.live = nil
                if let coord { onCommit(coord) }
            }
    }

    private func ringDiameter(yards: Double, centre: CLLocationCoordinate2D) -> CGFloat {
        guard let edgeCoord = coordinate(eastOf: centre, yards: yards),
              let edgePoint = proxy.convert(edgeCoord, to: .local),
              let centrePoint = proxy.convert(centre, to: .local) else { return 0 }
        return abs(edgePoint.x - centrePoint.x) * 2
    }

    /// A coordinate due east of `centre`, used to measure how many points a
    /// given yardage spans at the current zoom.
    private func coordinate(eastOf centre: CLLocationCoordinate2D, yards: Double) -> CLLocationCoordinate2D? {
        let metres = yards * 0.9144
        let deltaLon = metres / (111320.0 * cos(centre.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: centre.latitude, longitude: centre.longitude + deltaLon)
    }
}

extension TargetGuideOverlay where Accessory == EmptyView {
    init(
        proxy: MapProxy,
        drag: TargetDragState,
        tee: CLLocationCoordinate2D,
        green: CLLocationCoordinate2D,
        committedTarget: CLLocationCoordinate2D,
        isZoomed: Bool,
        ringYardages: [Double],
        crosshairIdentifier: String,
        onCommit: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        self.init(
            proxy: proxy,
            drag: drag,
            tee: tee,
            green: green,
            committedTarget: committedTarget,
            isZoomed: isZoomed,
            ringYardages: ringYardages,
            crosshairIdentifier: crosshairIdentifier,
            onCommit: onCommit,
            accessory: { _ in EmptyView() }
        )
    }
}

/// The on-screen target crosshair.
struct TargetCrosshair: View {
    let isZoomed: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: isZoomed ? 3 : 2)
                .background(Circle().fill(.black.opacity(0.3)))
                .frame(width: isZoomed ? 60 : 44, height: isZoomed ? 60 : 44)
                .shadow(color: .black.opacity(0.6), radius: 4)

            Rectangle().fill(.white).frame(width: isZoomed ? 30 : 20, height: 1)
            Rectangle().fill(.white).frame(width: 1, height: isZoomed ? 30 : 20)
            Circle().fill(.white).frame(width: 4, height: 4)
        }
    }
}

/// A straight line between two points in the enclosing view's coordinate space.
struct LineShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

/// Great-circle distance in yards.
func yardsBetween(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Int {
    let metres = CLLocation(latitude: from.latitude, longitude: from.longitude)
        .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    return Int((metres * 1.0936132983377078).rounded())
}
