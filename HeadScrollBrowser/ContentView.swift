import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = FaceTracker()

    @State private var addressBar: String = "https://www.google.com"
    @State private var currentURL: String = "https://www.google.com"
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var isLoading: Bool = false
    @State private var command: WebCommand? = nil

    // ✅ 컨트롤(정면설정/고개스크롤/민감도) 줄 숨김 상태
    @State private var controlsCollapsed: Bool = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // ✅ 검은 베젤(상단 상태바 영역)
                Color.black
                    .frame(height: geo.safeAreaInsets.top)

                // ✅ (항상 보임) URL 입력 줄
                HStack(spacing: 8) {
                    TextField("URL 입력", text: $addressBar)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { command = .load(addressBar) }

                    // ✅ X 버튼: 입력한 주소 싹 지우고 빈칸으로
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

                // ✅ (토글됨) 정면설정/고개스크롤/민감도 줄
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

                // ✅ 남는 공간은 전부 WebView가 먹음
                SimpleWebView(
                    initialURL: currentURL,
                    command: $command,
                    currentURL: $currentURL,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading,
                    tracker: tracker
                )
                .onChange(of: currentURL) { _, newValue in
                // 필요하면 async로 감싸도 됨
                    addressBar = newValue
                }

                // ✅ 하단바: 뒤로 + UI 최소화 + 시선탭
                HStack {
                    Button("뒤로") { command = .goBack }
                        .disabled(!canGoBack)
                        .buttonStyle(.bordered)

                    Button("앞으로") { command = .goForward }
                        .disabled(!canGoForward)
                        .buttonStyle(.bordered)

                    // ✅ 요청: 뒤로 옆에 UI 최소화 버튼
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
            .onAppear { tracker.start() }
            .onDisappear { tracker.stop() }
        }
    }
}
