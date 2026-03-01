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
    @Published var eyesClosedProgress: CGFloat = 0
    @Published var eyeStatusText: String = ""
    @Published var calibrationProgress: CGFloat = 0

    // ====== 조준 모드 ======
    @Published var isAiming: Bool = false
    @Published var isDotFrozen: Bool = false
    @Published var eyeTapFired: Bool = false
    @Published var tapDotX: CGFloat = 0.5   // 탭 발사 시점 스냅샷
    @Published var tapDotY: CGFloat = 0.5

    // ====== 설정 모드 (입 벌리기) ======
    @Published var isSettingsMode: Bool = false
    @Published var selectedSetting: Int = 0          // 0 = 데드존, 1 = 최대속도

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
    let eyeCloseThreshold: CGFloat = 0.55
    var eyesClosedSince: CFTimeInterval?

    // ====== 고개 좌우 꺾기 → 뒤로/앞으로 ======
    @Published var navProgress: CGFloat = 0       // 0~1 프로그레스
    @Published var navDirection: Int = 0           // -1 = 뒤로, 0 = 없음, 1 = 앞으로
    @Published var headNavBackFired: Bool = false
    @Published var headNavForwardFired: Bool = false
    let navYawThreshold: CGFloat = 10              // 10도 이상 꺾어야 시작
    let navHoldDuration: CFTimeInterval = 2.0
    var yawHoldSince: CFTimeInterval?
    var yawHoldDirection: Int = 0

    // ====== Mouth open state ======
    let mouthOpenThreshold: CGFloat = 0.35
    var mouthOpenSince: CFTimeInterval?
    let mouthToggleDelay: CFTimeInterval = 0.5       // 0.5초 이상 벌려야 토글
    var settingsNeutralPitch: CGFloat = 0             // 설정 모드 진입 시 pitch 기준점
    var settingsNeutralYaw: CGFloat = 0               // 설정 모드 진입 시 yaw 기준점

    // 타이밍 상수
    let aimEntryDuration: CFTimeInterval = 1.0
    let tapConfirmDuration: CFTimeInterval = 1.0
    let calibrateDuration: CFTimeInterval = 3.0
    let graceDelay: CFTimeInterval = 0.5

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

    // ====== 입 벌리기 → 설정 모드 토글 ======
    func processMouthOpen(_ mouthValue: CGFloat) {
        let isOpen = mouthValue > mouthOpenThreshold

        if isOpen {
            if mouthOpenSince == nil { mouthOpenSince = CACurrentMediaTime() }
        } else {
            if let since = mouthOpenSince {
                let duration = CACurrentMediaTime() - since
                if duration >= mouthToggleDelay {
                    DispatchQueue.main.async {
                        if self.isSettingsMode {
                            // 설정 모드 종료
                            self.isSettingsMode = false
                        } else {
                            // 설정 모드 진입: 현재 고개 위치를 기준점으로
                            self.settingsNeutralPitch = self.smoothedPitch - self.neutralPitch
                            self.settingsNeutralYaw = self.smoothedYaw - self.neutralYaw
                            self.isSettingsMode = true
                            self.isAiming = false  // 탭 모드 해제
                        }
                    }
                }
            }
            mouthOpenSince = nil
        }
    }

    // ====== 통합 눈 감기 처리 ======
    func processAiming(leftClosed: Bool, rightClosed: Bool) {
        // 설정 모드 중에는 눈 감기 무시
        if isSettingsMode { return }

        let bothClosed = leftClosed && rightClosed
        let now = CACurrentMediaTime()

        if bothClosed {
            if eyesClosedSince == nil { eyesClosedSince = now }
            let elapsed = now - (eyesClosedSince ?? now)

            let calProgress = elapsed < 1.0 ? 0 : min((elapsed - 1.0) / (calibrateDuration - 1.0), 1.0)
            DispatchQueue.main.async { self.calibrationProgress = calProgress }

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
                DispatchQueue.main.async { self.isDotFrozen = elapsed >= self.graceDelay }
                let tapProgress = elapsed < graceDelay ? 0
                    : min((elapsed - graceDelay) / (tapConfirmDuration - graceDelay), 1.0)
                DispatchQueue.main.async {
                    self.eyesClosedProgress = tapProgress
                    self.eyeStatusText = "탭 실행 중…"
                }
            } else {
                let aimProgress = elapsed < graceDelay ? 0
                    : min((elapsed - graceDelay) / (aimEntryDuration - graceDelay), 1.0)
                DispatchQueue.main.async {
                    self.eyesClosedProgress = aimProgress
                    self.eyeStatusText = "탭 모드 진입 중…"
                }
            }
        } else {
            if let since = eyesClosedSince {
                let elapsed = now - since

                if isAiming {
                    if elapsed >= tapConfirmDuration && elapsed < calibrateDuration {
                        DispatchQueue.main.async {
                            self.tapDotX = self.dotX
                            self.tapDotY = self.dotY
                            self.eyeTapFired = true
                            self.isAiming = false
                        }
                    }
                    DispatchQueue.main.async { self.isDotFrozen = false }
                } else {
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

        let yawRange: CGFloat = 17
        let pitchRange: CGFloat = 15

        if isSettingsMode {
            // 설정 모드: 고개 상하로 값 조절, 좌우로 항목 선택
            let pitchDelta = adjustedPitch - settingsNeutralPitch
            let yawDelta = adjustedYaw - settingsNeutralYaw

            DispatchQueue.main.async {
                // 좌우: 왼쪽 = 데드존(0), 오른쪽 = 최대속도(1)
                if yawDelta < -3 {
                    self.selectedSetting = 0
                } else if yawDelta > 3 {
                    self.selectedSetting = 1
                }

                // 상하: 위로 = 값 증가, 아래로 = 값 감소
                if self.selectedSetting == 0 {
                    let change = pitchDelta / pitchRange * 4.5 // ±15도 → ±4.5
                    self.deadZoneDeg = min(max(Self.defaultDeadZone + change, 1), 10)
                } else {
                    let change = pitchDelta / pitchRange * 1400 // ±15도 → ±1400
                    self.maxSpeedPtPerSec = min(max(Self.defaultMaxSpeed + change, 200), 3000)
                }

                self.pitchDeg = adjustedPitch
                self.yawDeg = adjustedYaw
                self.velocity = 0
            }
        } else if isAiming && !isDotFrozen {
            let rawDotX = 0.5 + (adjustedYaw / yawRange) * 0.5
            let clampedDotX = min(max(rawDotX, 0.05), 0.95)
            smoothedDotX = smoothedDotX + 0.08 * (clampedDotX - smoothedDotX)

            let rawDotY = 0.5 + (adjustedPitch / pitchRange) * 0.5
            let clampedDotY = min(max(rawDotY, 0.05), 0.95)
            smoothedDotY = smoothedDotY + 0.08 * (clampedDotY - smoothedDotY)

            DispatchQueue.main.async {
                self.pitchDeg = adjustedPitch
                self.yawDeg = adjustedYaw
                self.dotX = self.smoothedDotX
                self.dotY = self.smoothedDotY
                self.velocity = 0
            }
        } else if !isAiming {
            let rawDotX = 0.5 + (adjustedYaw / yawRange) * 0.5
            let clampedDotX = min(max(rawDotX, 0.05), 0.95)
            smoothedDotX = smoothedDotX + 0.08 * (clampedDotX - smoothedDotX)

            DispatchQueue.main.async {
                self.pitchDeg = adjustedPitch
                self.yawDeg = adjustedYaw
                self.dotX = self.smoothedDotX
                self.dotY = self.smoothedDotY
                self.velocity = (self.hasFace && self.isScrollEnabled && self.eyesClosedProgress == 0) ? v : 0
            }
        } else {
            // isDotFrozen: 점 고정, velocity 0
            DispatchQueue.main.async {
                self.pitchDeg = adjustedPitch
                self.yawDeg = adjustedYaw
                self.velocity = 0
            }
        }

        // ====== 고개 좌우 꺾기 → 뒤로/앞으로 감지 ======
        // 설정 모드·조준 모드에서는 비활성
        guard !isSettingsMode && !isAiming else {
            yawHoldSince = nil
            yawHoldDirection = 0
            DispatchQueue.main.async { self.navProgress = 0; self.navDirection = 0 }
            return
        }

        let now = CACurrentMediaTime()

        if adjustedYaw < -navYawThreshold {
            // 왼쪽 꺾기 → 뒤로
            if yawHoldDirection != -1 { yawHoldSince = now; yawHoldDirection = -1 }
            let elapsed = now - (yawHoldSince ?? now)
            DispatchQueue.main.async {
                self.navDirection = -1
                self.navProgress = min(CGFloat(elapsed / self.navHoldDuration), 1.0)
            }
            if elapsed >= navHoldDuration {
                DispatchQueue.main.async { self.headNavBackFired = true }
                yawHoldSince = nil; yawHoldDirection = 0
            }
        } else if adjustedYaw > navYawThreshold {
            // 오른쪽 꺾기 → 앞으로
            if yawHoldDirection != 1 { yawHoldSince = now; yawHoldDirection = 1 }
            let elapsed = now - (yawHoldSince ?? now)
            DispatchQueue.main.async {
                self.navDirection = 1
                self.navProgress = min(CGFloat(elapsed / self.navHoldDuration), 1.0)
            }
            if elapsed >= navHoldDuration {
                DispatchQueue.main.async { self.headNavForwardFired = true }
                yawHoldSince = nil; yawHoldDirection = 0
            }
        } else {
            if yawHoldDirection != 0 {
                yawHoldDirection = 0; yawHoldSince = nil
                DispatchQueue.main.async { self.navProgress = 0; self.navDirection = 0 }
            }
        }
    }
}
