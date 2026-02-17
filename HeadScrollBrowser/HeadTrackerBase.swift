import Foundation
import Combine
import QuartzCore

class HeadTrackerBase: NSObject, ObservableObject {

    // ====== Head scroll ======
    @Published var pitchDeg: CGFloat = 0
    @Published var yawDeg: CGFloat = 0
    @Published var dotX: CGFloat = 0.5       // 0~1 정규화된 좌우 위치 (0.5 = 중앙)
    @Published var dotY: CGFloat = 0.5       // 0~1 정규화된 상하 위치 (0.5 = 중앙)
    @Published var hasFace: Bool = false
    @Published var velocity: CGFloat = 0

    @Published var isScrollEnabled: Bool {
        didSet { UserDefaults.standard.set(isScrollEnabled, forKey: "isScrollEnabled") }
    }
    @Published var isScrollInverted: Bool {
        didSet { UserDefaults.standard.set(isScrollInverted, forKey: "isScrollInverted") }
    }

    // ====== 지원 여부 ======
    @Published var isSupported: Bool = true

    // ====== 눈 감기 상태 ======
    @Published var eyesClosedProgress: CGFloat = 0   // 탭 모드 진입 / 탭 실행 프로그레스
    @Published var eyeStatusText: String = ""        // 프로그레스 바 레이블
    @Published var calibrationProgress: CGFloat = 0  // 정면 설정 프로그레스 (별도 표시)

    // ====== 조준 모드 ======
    @Published var isAiming: Bool = false
    @Published var isDotFrozen: Bool = false          // 조준 중 눈 감으면 점 고정
    @Published var eyeTapFired: Bool = false

    @Published var deadZoneDeg: CGFloat {
        didSet { UserDefaults.standard.set(deadZoneDeg, forKey: "deadZoneDeg") }
    }
    var maxAngleDeg: CGFloat = 12
    @Published var maxSpeedPtPerSec: CGFloat {
        didSet { UserDefaults.standard.set(maxSpeedPtPerSec, forKey: "maxSpeedPtPerSec") }
    }

    // ====== Smoothing state ======
    var neutralPitch: CGFloat = 0
    var neutralYaw: CGFloat = 0
    var smoothedPitch: CGFloat = 0
    var smoothedYaw: CGFloat = 0
    var smoothedDotX: CGFloat = 0.5
    var smoothedDotY: CGFloat = 0.5
    let alpha: CGFloat = 0.2

    // ====== Eye close state ======
    let eyeCloseThreshold: CGFloat = 0.65
    var eyesClosedSince: CFTimeInterval?

    // 타이밍 상수
    let aimEntryDuration: CFTimeInterval = 1.0     // 스크롤 중 1초 눈감기 → 탭 모드
    let tapConfirmDuration: CFTimeInterval = 1.0   // 조준 중 1초 눈감기 → 탭
    let calibrateDuration: CFTimeInterval = 3.0    // 3초 눈감기 → 정면 설정
    let graceDelay: CFTimeInterval = 0.5           // 프로그레스 시작 전 유예

    static let defaultDeadZone: CGFloat = 3.5
    static let defaultMaxSpeed: CGFloat = 1200

    override init() {
        let ud = UserDefaults.standard
        self.isScrollEnabled = ud.object(forKey: "isScrollEnabled") as? Bool ?? true
        self.deadZoneDeg = ud.object(forKey: "deadZoneDeg") as? CGFloat ?? Self.defaultDeadZone
        self.maxSpeedPtPerSec = ud.object(forKey: "maxSpeedPtPerSec") as? CGFloat ?? Self.defaultMaxSpeed
        self.isScrollInverted = ud.object(forKey: "isScrollInverted") as? Bool ?? false
        super.init()
    }

    func calibrateNeutral() {
        neutralPitch = smoothedPitch
        neutralYaw = smoothedYaw
        smoothedDotX = 0.5
        smoothedDotY = 0.5
        DispatchQueue.main.async {
            self.pitchDeg = 0
            self.yawDeg = 0
            self.dotX = 0.5
            self.dotY = 0.5
            self.velocity = 0
        }
    }

    func setScrollEnabled(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.isScrollEnabled = enabled
            if !enabled { self.velocity = 0 }
        }
    }

    func start() { /* Override in subclass */ }
    func stop() { /* Override in subclass */ }

    func mapPitchToVelocity(pitch: CGFloat) -> CGFloat {
        let absP = abs(pitch)
        if absP < deadZoneDeg { return 0 }
        let clamped = min(absP, maxAngleDeg)
        let norm = (clamped - deadZoneDeg) / max(1, (maxAngleDeg - deadZoneDeg))
        let curve = norm
        let sign: CGFloat = pitch > 0 ? -1 : 1
        let invert: CGFloat = isScrollInverted ? -1 : 1
        return sign * invert * curve * maxSpeedPtPerSec
    }

    // ====== 통합 눈 감기 처리 ======
    // 스크롤 중: 2초 눈감고 뜨면 → 탭 모드 진입
    // 탭 모드:  1초 눈감고 뜨면 → 탭 실행, 스크롤 복귀
    // 언제든:   3초 이상 눈감기 → 정면 설정
    func processAiming(leftClosed: Bool, rightClosed: Bool) {
        let bothClosed = leftClosed && rightClosed
        let now = CACurrentMediaTime()

        if bothClosed {
            // ── 눈 감는 중 ──
            if eyesClosedSince == nil { eyesClosedSince = now }
            let elapsed = now - (eyesClosedSince ?? now)

            // 정면 설정 프로그레스 (항상 표시)
            let calProgress = elapsed < 1.0 ? 0 : min((elapsed - 1.0) / (calibrateDuration - 1.0), 1.0)
            DispatchQueue.main.async { self.calibrationProgress = calProgress }

            // 3초 이상 → 정면 설정 (어떤 모드에서든)
            if elapsed >= calibrateDuration {
                calibrateNeutral()
                eyesClosedSince = nil
                DispatchQueue.main.async {
                    self.isAiming = false
                    self.isDotFrozen = false
                    self.eyesClosedProgress = 0
                    self.eyeStatusText = ""
                    self.calibrationProgress = 0
                }
                return
            }

            if isAiming {
                // 조준 중 눈 감기 → 유예 후 점 고정 + 탭 프로그레스
                DispatchQueue.main.async { self.isDotFrozen = elapsed >= self.graceDelay }
                let tapProgress = elapsed < graceDelay ? 0
                    : min((elapsed - graceDelay) / (tapConfirmDuration - graceDelay), 1.0)
                DispatchQueue.main.async {
                    self.eyesClosedProgress = tapProgress
                    self.eyeStatusText = "탭 실행 중…"
                }
            } else {
                // 스크롤 중 눈 감기 → 탭 모드 진입 프로그레스
                let aimProgress = elapsed < graceDelay ? 0
                    : min((elapsed - graceDelay) / (aimEntryDuration - graceDelay), 1.0)
                DispatchQueue.main.async {
                    self.eyesClosedProgress = aimProgress
                    self.eyeStatusText = "탭 모드 진입 중…"
                }
            }
        } else {
            // ── 눈 뜸 ──
            if let since = eyesClosedSince {
                let elapsed = now - since

                if isAiming {
                    // 조준 중이었고: 1초 이상 감았다 뜨면 → 탭!
                    if elapsed >= tapConfirmDuration && elapsed < calibrateDuration {
                        DispatchQueue.main.async {
                            self.eyeTapFired = true
                            self.isAiming = false
                        }
                    }
                    // 1초 미만 → 점 고정 해제, 계속 조준
                    DispatchQueue.main.async { self.isDotFrozen = false }
                } else {
                    // 스크롤 중이었고: 2초 이상 감았다 뜨면 → 탭 모드 진입
                    if elapsed >= aimEntryDuration && elapsed < calibrateDuration {
                        DispatchQueue.main.async { self.isAiming = true }
                    }
                }
            }
            eyesClosedSince = nil
            DispatchQueue.main.async {
                self.eyesClosedProgress = 0
                self.eyeStatusText = ""
                self.calibrationProgress = 0
            }
        }
    }

    // ====== 고개 방향 업데이트 ======
    func updateHeadPose(rawPitchDeg: CGFloat, rawYawDeg: CGFloat) {
        smoothedPitch = smoothedPitch + alpha * (rawPitchDeg - smoothedPitch)
        let adjustedPitch = smoothedPitch - neutralPitch

        smoothedYaw = smoothedYaw + alpha * (rawYawDeg - smoothedYaw)
        let adjustedYaw = smoothedYaw - neutralYaw

        let v = mapPitchToVelocity(pitch: adjustedPitch)

        // 조준 모드: X,Y 반전 매핑 (점 고정 중엔 업데이트 안 함)
        let yawRange: CGFloat = 15
        let pitchRange: CGFloat = 15

        if isAiming && !isDotFrozen {
            // 반전: 고개 위 → 점 아래 (좌우는 그대로)
            let rawDotX = 0.5 + (adjustedYaw / yawRange) * 0.5
            let clampedDotX = min(max(rawDotX, 0.05), 0.95)
            smoothedDotX = smoothedDotX + 0.08 * (clampedDotX - smoothedDotX)

            let rawDotY = 0.5 + (adjustedPitch / pitchRange) * 0.5
            let clampedDotY = min(max(rawDotY, 0.05), 0.95)
            smoothedDotY = smoothedDotY + 0.08 * (clampedDotY - smoothedDotY)
        } else if !isAiming {
            // 스크롤 모드: 기존 방향으로 dotX만 업데이트
            let rawDotX = 0.5 + (adjustedYaw / yawRange) * 0.5
            let clampedDotX = min(max(rawDotX, 0.05), 0.95)
            smoothedDotX = smoothedDotX + 0.08 * (clampedDotX - smoothedDotX)
        }
        // isDotFrozen일 때는 smoothedDotX/Y 업데이트 안 함 → 점 고정

        DispatchQueue.main.async {
            self.pitchDeg = adjustedPitch
            self.yawDeg = adjustedYaw
            self.dotX = self.smoothedDotX
            self.dotY = self.smoothedDotY

            if self.isAiming {
                self.velocity = 0
            } else {
                self.velocity = (self.hasFace && self.isScrollEnabled && self.eyesClosedProgress == 0) ? v : 0
            }
        }
    }
}
