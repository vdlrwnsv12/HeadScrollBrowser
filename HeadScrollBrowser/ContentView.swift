import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = FaceTracker()

    @State private var addressBar: String = "https://www.google.com"
    @State private var currentURL: String = "https://www.google.com"
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var isLoading: Bool = false
    @State private var command: WebCommand? = nil

    @State private var controlsCollapsed: Bool = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                Color.black
                    .frame(height: geo.safeAreaInsets.top)

                // URL 입력 줄
                HStack(spacing: 8) {
                    TextField("URL 입력", text: $addressBar)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
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

                            Button(tracker.isScrollEnabled ? "고개스크롤 ON" : "고개스크롤 OFF") {
                                tracker.setScrollEnabled(!tracker.isScrollEnabled)
                            }
                            .buttonStyle(.bordered)

                            Button(tracker.isScrollInverted ? "상하반전 ON" : "상하반전 OFF") {
                                tracker.isScrollInverted.toggle()
                            }
                            .buttonStyle(.bordered)

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
                .overlay {
                    GeometryReader { webGeo in
                        if tracker.isAiming && tracker.hasFace {
                            // 조준 모드: 왼쪽 눈 감은 상태, 고개로 위치 조절
                            Circle()
                                .fill(.cyan.opacity(0.8))
                                .frame(width: 14, height: 14)
                                .shadow(color: .cyan.opacity(0.6), radius: 4)
                                .position(
                                    x: webGeo.size.width * tracker.dotX,
                                    y: webGeo.size.height * tracker.dotY
                                )
                                .animation(.easeOut(duration: 0.1), value: tracker.dotX)
                                .animation(.easeOut(duration: 0.1), value: tracker.dotY)
                        }
                    }
                }
                .onChange(of: currentURL) { _, newValue in
                    addressBar = newValue
                }
                .onChange(of: tracker.eyeTapFired) { _, fired in
                    if fired {
                        command = .tapAt(tracker.dotX, tracker.dotY)
                        tracker.eyeTapFired = false
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

                    Button("앞으로") { command = .goForward }
                        .disabled(!canGoForward)
                        .buttonStyle(.bordered)

                    Button(controlsCollapsed ? "UI 펼치기" : "UI 최소화") {
                        controlsCollapsed.toggle()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .opacity(0.5)
            }
            .ignoresSafeArea(edges: .top)
            .statusBarHidden(true)
            .overlay {
                if tracker.navProgress > 0 {
                    HStack {
                        if tracker.navDirection == -1 {
                            // 왼쪽: 뒤로
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
                            // 오른쪽: 앞으로
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
                            // 데드존
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

                            // 최대속도
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
            .overlay {
                if tracker.eyesClosedProgress > 0 || tracker.calibrationProgress > 0 {
                    VStack(spacing: 10) {
                        // 정면 설정 프로그레스 (위)
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

                        // 탭 모드 프로그레스 (아래)
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
            .onAppear { tracker.start() }
            .onDisappear { tracker.stop() }
        }
    }
}
