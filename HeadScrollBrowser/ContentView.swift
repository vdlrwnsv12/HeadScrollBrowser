import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = FaceTracker()

    @State private var addressBar: String = UserDefaults.standard.string(forKey: "lastURL") ?? "https://www.google.com"
    @State private var currentURL: String = UserDefaults.standard.string(forKey: "lastURL") ?? "https://www.google.com"
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var isLoading: Bool = false
    @State private var command: WebCommand? = nil

    @State private var controlsCollapsed: Bool = false
    @State private var webViewFrame: CGRect = .zero
    @State private var urlBarFrame: CGRect = .zero
    @FocusState private var urlBarFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let root = geo.frame(in: .global)
            let dotGY = root.minY + tracker.dotY * geo.size.height
            let aimActive = tracker.isAiming && tracker.hasFace && !webViewFrame.isEmpty
            let isAimAbove = aimActive && dotGY >= urlBarFrame.maxY && dotGY < webViewFrame.minY
            let isAimBelow = aimActive && dotGY > webViewFrame.maxY
            let cZone: Int = tracker.dotX < 0.33 ? 0 : (tracker.dotX < 0.66 ? 1 : 2)
            let bZone: Int = tracker.dotX < 0.25 ? 0 : (tracker.dotX < 0.5 ? 1 : 2)
            VStack(spacing: 0) {

                Color.black
                    .frame(height: geo.safeAreaInsets.top)

                // URL 입력 줄
                HStack(spacing: 8) {
                    TextField("URL 입력", text: $addressBar)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .focused($urlBarFocused)
                        .onSubmit { command = .load(addressBar) }

                    Button {
                        addressBar = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button { command = .reload } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button("이동") { command = .load(addressBar) }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .opacity(0.5)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { newFrame in
                    urlBarFrame = newFrame
                }

                // 로딩 인디케이터
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                }

                // 정면설정/고개스크롤/민감도 줄
                if !controlsCollapsed {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Button("정면 설정") {
                                tracker.calibrateNeutral()
                            }
                            .buttonStyle(.bordered)
                            .overlay { if isAimAbove && cZone == 0 { aimHighlight } }

                            Button(tracker.isScrollEnabled ? "고개스크롤 ON" : "고개스크롤 OFF") {
                                tracker.setScrollEnabled(!tracker.isScrollEnabled)
                            }
                            .buttonStyle(.bordered)
                            .overlay { if isAimAbove && cZone == 1 { aimHighlight } }

                            Button(tracker.isScrollInverted ? "상하반전 ON" : "상하반전 OFF") {
                                tracker.isScrollInverted.toggle()
                            }
                            .buttonStyle(.bordered)
                            .overlay { if isAimAbove && cZone == 2 { aimHighlight } }

                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Text("데드존")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Slider(value: $tracker.deadZoneDeg, in: 1...10, step: 0.5)

                            Text("\(tracker.deadZoneDeg, specifier: "%.1f")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .trailing)
                        }

                        HStack(spacing: 8) {
                            Text("최대속도")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Slider(value: $tracker.maxSpeedPtPerSec, in: 200...3000, step: 100)

                            Text("\(Int(tracker.maxSpeedPtPerSec))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .opacity(0.5)
                }

                // WebView
                SimpleWebView(
                    initialURL: currentURL,
                    command: $command,
                    currentURL: $currentURL,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading,
                    tracker: tracker
                )
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { newFrame in
                    webViewFrame = newFrame
                }
                .onChange(of: currentURL) { _, newValue in
                    addressBar = newValue
                    UserDefaults.standard.set(newValue, forKey: "lastURL")
                }
                .onChange(of: tracker.eyeTapFired) { _, fired in
                    if fired {
                        // 좌표계를 global로 통일 (webViewFrame도 global)
                        let root = geo.frame(in: .global)
                        let pt = CGPoint(
                            x: root.minX + tracker.tapDotX * geo.size.width,
                            y: root.minY + tracker.tapDotY * geo.size.height
                        )

                        defer { tracker.eyeTapFired = false }
                        guard !webViewFrame.isEmpty else { return }

                        // 1) WebView 탭
                        if webViewFrame.contains(pt) {
                            let relX = (pt.x - webViewFrame.minX) / webViewFrame.width
                            let relY = (pt.y - webViewFrame.minY) / webViewFrame.height

                            let clampedX = min(max(relX, 0.0), 1.0)
                            let clampedY = min(max(relY, 0.0), 1.0)

                            command = .tapAt(clampedX, clampedY)
                            return
                        }

                        // 2) WebView 위 영역: 컨트롤 스트립 (URL바 제외)
                        if pt.y >= urlBarFrame.maxY && pt.y < webViewFrame.minY {
                            if !controlsCollapsed {
                                // 화면 3등분으로 버튼 3개 판단
                                if pt.x < root.minX + geo.size.width * 0.33 {
                                    tracker.calibrateNeutral()
                                } else if pt.x < root.minX + geo.size.width * 0.66 {
                                    tracker.setScrollEnabled(!tracker.isScrollEnabled)
                                } else {
                                    tracker.isScrollInverted.toggle()
                                }
                            } else {
                                urlBarFocused = true
                            }
                            return
                        }

                        // 3) WebView 아래 영역: 하단바
                        if pt.y > webViewFrame.maxY {
                            if pt.x < root.minX + geo.size.width * 0.25 {
                                if canGoBack { command = .goBack }
                            } else if pt.x < root.minX + geo.size.width * 0.5 {
                                if canGoForward { command = .goForward }
                            } else {
                                controlsCollapsed.toggle()
                            }
                            return
                        }
                    }
                }
                .onChange(of: tracker.headNavBackFired) { _, fired in
                    if fired {
                        command = .goBack
                        tracker.headNavBackFired = false
                    }
                }
                .onChange(of: tracker.headNavForwardFired) { _, fired in
                    if fired {
                        command = .goForward
                        tracker.headNavForwardFired = false
                    }
                }

                // 하단바
                HStack {
                    Button("뒤로") { command = .goBack }
                        .disabled(!canGoBack)
                        .buttonStyle(.bordered)
                        .overlay { if isAimBelow && bZone == 0 { aimHighlight } }

                    Button("앞으로") { command = .goForward }
                        .disabled(!canGoForward)
                        .buttonStyle(.bordered)
                        .overlay { if isAimBelow && bZone == 1 { aimHighlight } }

                    Button(controlsCollapsed ? "UI 펼치기" : "UI 최소화") {
                        controlsCollapsed.toggle()
                    }
                    .buttonStyle(.bordered)
                    .overlay { if isAimBelow && bZone == 2 { aimHighlight } }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .opacity(0.5)
            }
            .ignoresSafeArea(edges: .top)
            .statusBarHidden(true)

            // 네비게이션 진행도 오버레이
            .overlay {
                if tracker.navProgress > 0 {
                    HStack {
                        if tracker.navDirection == -1 {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.title2.bold())
                                Text("뒤로")
                                    .font(.headline)
                                ProgressView(value: tracker.navProgress)
                                    .progressViewStyle(.linear)
                                    .tint(.white)
                                    .frame(width: 80)
                            }
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                            Spacer()
                        } else {
                            Spacer()
                            HStack(spacing: 8) {
                                ProgressView(value: tracker.navProgress)
                                    .progressViewStyle(.linear)
                                    .tint(.white)
                                    .frame(width: 80)
                                Text("앞으로")
                                    .font(.headline)
                                Image(systemName: "chevron.right")
                                    .font(.title2.bold())
                            }
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: tracker.navProgress)
                }
            }

            // 설정 모드 오버레이
            .overlay {
                if tracker.isSettingsMode {
                    VStack(spacing: 16) {
                        Text("설정 모드")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("고개 좌우: 항목 선택 · 상하: 값 조절\n입 다물면 종료")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 20) {
                            VStack(spacing: 6) {
                                Text("데드존")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                Text("\(tracker.deadZoneDeg, specifier: "%.1f")°")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(tracker.selectedSetting == 0 ? .cyan.opacity(0.5) : .white.opacity(0.15))
                            )

                            VStack(spacing: 6) {
                                Text("최대속도")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                Text("\(Int(tracker.maxSpeedPtPerSec))")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(tracker.selectedSetting == 1 ? .orange.opacity(0.5) : .white.opacity(0.15))
                            )
                        }
                    }
                    .padding(24)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: tracker.isSettingsMode)
                    .animation(.easeOut(duration: 0.1), value: tracker.selectedSetting)
                }
            }

            // 지원 안될 때
            .overlay {
                if !tracker.isSupported {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text("이 기기는 얼굴 추적을 지원하지 않습니다")
                            .font(.headline)
                        Text("고개 스크롤 기능을 사용하려면\nTrueDepth 카메라가 탑재된 기기가 필요합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(32)
                }
            }

            // 눈 감기/정면설정 프로그레스
            .overlay {
                if tracker.eyesClosedProgress > 0 || tracker.calibrationProgress > 0 {
                    VStack(spacing: 10) {
                        if tracker.calibrationProgress > 0 {
                            VStack(spacing: 8) {
                                ProgressView(value: tracker.calibrationProgress)
                                    .progressViewStyle(.linear)
                                    .tint(.green)
                                    .frame(width: 160)
                                Text("정면 설정 중…")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                            }
                            .padding(12)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        }

                        if tracker.eyesClosedProgress > 0 {
                            VStack(spacing: 8) {
                                ProgressView(value: tracker.eyesClosedProgress)
                                    .progressViewStyle(.linear)
                                    .tint(tracker.isAiming ? .orange : .cyan)
                                    .frame(width: 160)
                                Text(tracker.eyeStatusText)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                            }
                            .padding(12)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: tracker.eyesClosedProgress)
                    .animation(.easeInOut(duration: 0.2), value: tracker.calibrationProgress)
                }
            }

            // 조준 모드 점
            .overlay {
                if tracker.isAiming && tracker.hasFace {
                    Circle()
                        .fill(.cyan.opacity(0.8))
                        .frame(width: 14, height: 14)
                        .shadow(color: .cyan.opacity(0.6), radius: 4)
                        .position(
                            x: geo.size.width * tracker.dotX,
                            y: geo.size.height * tracker.dotY
                        )
                        .animation(.easeOut(duration: 0.1), value: tracker.dotX)
                        .animation(.easeOut(duration: 0.1), value: tracker.dotY)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { tracker.start() }
            .onDisappear { tracker.stop() }
        }
    }

    private var aimHighlight: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.cyan, lineWidth: 2)
            .shadow(color: .cyan.opacity(0.7), radius: 6)
    }
}

