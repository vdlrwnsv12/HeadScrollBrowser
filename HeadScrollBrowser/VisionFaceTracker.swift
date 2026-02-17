// macOS 지원 비활성화 — 주석 해제 요청 시까지 유지
/*
#if os(macOS)
import AVFoundation
import Vision

final class VisionFaceTracker: HeadTrackerBase, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.headscroll.face-tracking")

    // Eye Aspect Ratio: 눈 높이/너비 비율이 이 값 이하면 "감은 것"
    private let earClosedThreshold: CGFloat = 0.2

    override func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupCapture()
                } else {
                    DispatchQueue.main.async { self.isSupported = false }
                }
            }
        default:
            DispatchQueue.main.async { self.isSupported = false }
        }
    }

    private func setupCapture() {
        // macOS: position .unspecified → 기본 카메라 (FaceTime 등)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
            DispatchQueue.main.async { self.isSupported = false }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .medium

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }

            captureSession.commitConfiguration()
            captureSession.startRunning()
        } catch {
            DispatchQueue.main.async { self.isSupported = false }
        }
    }

    override func stop() {
        captureSession.stopRunning()
        DispatchQueue.main.async {
            self.hasFace = false
            self.pitchDeg = 0
            self.velocity = 0
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        try? handler.perform([request])

        guard let face = request.results?.first else {
            DispatchQueue.main.async {
                self.hasFace = false
                self.pitchDeg = 0
                self.velocity = 0
            }
            return
        }

        DispatchQueue.main.async { self.hasFace = true }

        // ----- 고개 pitch/yaw -----
        let pitchRad = face.pitch?.doubleValue ?? 0
        let yawRad = face.yaw?.doubleValue ?? 0
        let rawPitchDeg = CGFloat(pitchRad) * 180.0 / .pi
        // 웹캠 미러링 고려: yaw 부호 반전
        let rawYawDeg = -CGFloat(yawRad) * 180.0 / .pi

        // ----- 눈 감기 감지 (Eye Aspect Ratio) -----
        var leftClosed = false
        var rightClosed = false
        if let landmarks = face.landmarks {
            let leftEAR = eyeAspectRatio(landmarks.leftEye)
            let rightEAR = eyeAspectRatio(landmarks.rightEye)
            leftClosed = leftEAR < earClosedThreshold
            rightClosed = rightEAR < earClosedThreshold
        }

        DispatchQueue.main.async {
            self.processAiming(leftClosed: leftClosed, rightClosed: rightClosed)
            self.updateHeadPose(rawPitchDeg: rawPitchDeg, rawYawDeg: rawYawDeg)
        }
    }

    // Eye Aspect Ratio: 눈 랜드마크의 높이/너비 비율
    private nonisolated func eyeAspectRatio(_ eye: VNFaceLandmarkRegion2D?) -> CGFloat {
        guard let eye = eye, eye.pointCount >= 4 else { return 1.0 }
        let points = eye.pointsInImage(imageSize: CGSize(width: 1, height: 1))
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)
        guard width > 0 else { return 1.0 }
        return height / width
    }
}
#endif
*/
