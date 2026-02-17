import Foundation
import ARKit
import Combine
import simd

final class FaceTracker: NSObject, ObservableObject, ARSessionDelegate {

    // ====== Head scroll ======
    @Published var pitchDeg: CGFloat = 0
    @Published var hasFace: Bool = false
    @Published var velocity: CGFloat = 0
    @Published var isScrollEnabled: Bool = true

    // ====== ARKit 지원 여부 ======
    @Published var isSupported: Bool = true

    let session = ARSession()

    private var neutralPitch: CGFloat = 0
    private var smoothedPitch: CGFloat = 0
    private let alpha: CGFloat = 0.2

    @Published var deadZoneDeg: CGFloat = 3.5
    var maxAngleDeg: CGFloat = 12
    @Published var maxSpeedPtPerSec: CGFloat = 1200

    func calibrateNeutral() {
        neutralPitch = smoothedPitch
        smoothedPitch = neutralPitch
        DispatchQueue.main.async {
            self.pitchDeg = 0
            self.velocity = 0
        }
    }

    func setScrollEnabled(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.isScrollEnabled = enabled
            if !enabled { self.velocity = 0 }
        }
    }

    func start() {
        let supported = ARFaceTrackingConfiguration.isSupported
        DispatchQueue.main.async { self.isSupported = supported }
        guard supported else { return }
        session.delegate = self
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = true
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
        DispatchQueue.main.async {
            self.hasFace = false
            self.pitchDeg = 0
            self.velocity = 0
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else {
            DispatchQueue.main.async {
                self.hasFace = false
                self.pitchDeg = 0
                self.velocity = 0
            }
            return
        }
        DispatchQueue.main.async { self.hasFace = true }

        // ----- head pitch -----
        let t = face.transform
        let zAxis = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let forward = -zAxis

        let pitchRad = atan2(forward.y, sqrt(forward.x * forward.x + forward.z * forward.z))
        let rawDeg = CGFloat(pitchRad) * 180.0 / .pi

        smoothedPitch = smoothedPitch + alpha * (rawDeg - smoothedPitch)
        let adjustedPitch = smoothedPitch - neutralPitch
        let v = mapPitchToVelocity(pitch: adjustedPitch)

        DispatchQueue.main.async {
            self.pitchDeg = adjustedPitch
            self.velocity = (self.hasFace && self.isScrollEnabled) ? v : 0
        }
    }

    private func mapPitchToVelocity(pitch: CGFloat) -> CGFloat {
        let absP = abs(pitch)
        if absP < deadZoneDeg { return 0 }
        let clamped = min(absP, maxAngleDeg)
        let norm = (clamped - deadZoneDeg) / max(1, (maxAngleDeg - deadZoneDeg))
        let curve = norm  // 민감도 높임
        let sign: CGFloat = pitch > 0 ? -1 : 1
        return sign * curve * maxSpeedPtPerSec
    }
}
