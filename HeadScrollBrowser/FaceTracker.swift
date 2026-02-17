import ARKit

final class FaceTracker: HeadTrackerBase, ARSessionDelegate {

    let session = ARSession()

    override func start() {
        let supported = ARFaceTrackingConfiguration.isSupported
        DispatchQueue.main.async { self.isSupported = supported }
        guard supported else { return }
        session.delegate = self
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = true
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    override func stop() {
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

        // ----- 눈 감기 감지 -----
        let blendShapes = face.blendShapes
        let leftBlink = blendShapes[.eyeBlinkLeft].map { CGFloat(truncating: $0) } ?? 0
        let rightBlink = blendShapes[.eyeBlinkRight].map { CGFloat(truncating: $0) } ?? 0

        processAiming(leftClosed: leftBlink > eyeCloseThreshold,
                      rightClosed: rightBlink > eyeCloseThreshold)

        // ----- 입 벌리기 감지 -----
        let jawOpen = blendShapes[.jawOpen].map { CGFloat(truncating: $0) } ?? 0
        processMouthOpen(jawOpen)

        // ----- head pitch -----
        let t = face.transform
        let zAxis = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let forward = -zAxis

        let pitchRad = atan2(forward.y, sqrt(forward.x * forward.x + forward.z * forward.z))
        let rawPitchDeg = CGFloat(pitchRad) * 180.0 / .pi

        // ----- head yaw -----
        let yawRad = atan2(zAxis.x, zAxis.z)
        let rawYawDeg = CGFloat(yawRad) * 180.0 / .pi

        updateHeadPose(rawPitchDeg: rawPitchDeg, rawYawDeg: rawYawDeg)
    }
}
