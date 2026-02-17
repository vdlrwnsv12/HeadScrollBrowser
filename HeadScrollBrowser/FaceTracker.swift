import Foundation
import ARKit
import Combine
import simd
import CoreGraphics
import UIKit

final class FaceTracker: NSObject, ObservableObject, ARSessionDelegate {

    // ====== Head scroll ======
    @Published var pitchDeg: CGFloat = 0
    @Published var hasFace: Bool = false
    @Published var velocity: CGFloat = 0
    @Published var isScrollEnabled: Bool = true

    // ✅ Gaze tap enable/disable
    @Published var isGazeTapEnabled: Bool = true

    // ====== ARKit 지원 여부 ======
    @Published var isSupported: Bool = true

    // ====== Gaze tracking (커서/탭) ======
    @Published var gazeValid: Bool = false
    @Published var gazePoint: CGPoint = .zero
    @Published var gazeTapPulse: Int = 0
    @Published var gazeTapNorm: CGPoint = .zero

    let session = ARSession()

    private var neutralPitch: CGFloat = 0
    private var smoothedPitch: CGFloat = 0
    private let alpha: CGFloat = 0.2

    var deadZoneDeg: CGFloat = 3.5
    var maxAngleDeg: CGFloat = 12
    var maxSpeedPtPerSec: CGFloat = 1200

    // gaze smoothing/dwell
    private var smoothedGaze: CGPoint = .zero
    private let gazeAlpha: CGFloat = 0.25
    var dwellSeconds: CFTimeInterval = 1.0
    var dwellRadiusPt: CGFloat = 28
    private var dwellStart: CFTimeInterval? = nil
    private var dwellAnchorPoint: CGPoint = .zero
    private var dwellFired: Bool = false

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
            self.gazeValid = false
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else {
            DispatchQueue.main.async {
                self.hasFace = false
                self.pitchDeg = 0
                self.velocity = 0
                self.gazeValid = false
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

        // ----- gaze (lookAtPoint 기반 추천) -----
        guard let frame = session.currentFrame else { return }
        let viewport = UIScreen.main.bounds.size
        let orientation = currentInterfaceOrientation()

        let look = face.lookAtPoint
        let lookWorld4 = simd_mul(face.transform, simd_float4(look.x, look.y, look.z, 1.0))
        let lookWorld = simd_float3(lookWorld4.x, lookWorld4.y, lookWorld4.z)

        let proj = frame.camera.projectPoint(lookWorld, orientation: orientation, viewportSize: viewport)

        var gaze = CGPoint(x: CGFloat(proj.x), y: CGFloat(proj.y))
        // 좌우가 반대로 느껴지면 아래 1줄 켜기
        gaze.x = viewport.width - gaze.x

        gaze.x = min(max(0, gaze.x), viewport.width)
        gaze.y = min(max(0, gaze.y), viewport.height)

        smoothedGaze.x = smoothedGaze.x + gazeAlpha * (gaze.x - smoothedGaze.x)
        smoothedGaze.y = smoothedGaze.y + gazeAlpha * (gaze.y - smoothedGaze.y)

        DispatchQueue.main.async {
            self.gazeValid = true
            self.gazePoint = self.smoothedGaze
        }

        // dwell -> tap pulse (실제 탭 실행은 WebView에서 isGazeTapEnabled 체크)
        let now = CACurrentMediaTime()
        let d = hypot(smoothedGaze.x - dwellAnchorPoint.x, smoothedGaze.y - dwellAnchorPoint.y)

        if dwellStart == nil || d > dwellRadiusPt {
            dwellStart = now
            dwellAnchorPoint = smoothedGaze
            dwellFired = false
        } else if !dwellFired, let start = dwellStart, (now - start) >= dwellSeconds {
            dwellFired = true
            let nx = smoothedGaze.x / max(1, viewport.width)
            let ny = smoothedGaze.y / max(1, viewport.height)
            DispatchQueue.main.async {
                self.gazeTapNorm = CGPoint(x: nx, y: ny)
                self.gazeTapPulse += 1
            }
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

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if Thread.isMainThread {
            return (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .portrait
        } else {
            var result: UIInterfaceOrientation = .portrait
            DispatchQueue.main.sync {
                result = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .portrait
            }
            return result
        }
    }
}
