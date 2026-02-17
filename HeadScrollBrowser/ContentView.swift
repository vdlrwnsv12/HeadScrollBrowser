import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = FaceTracker()

    @State private var addressBar: String = "https://www.google.com"
    @State private var currentURL: String = "https://www.google.com"
    @State private var canGoBack: Bool = false
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

                    Button("이동") { command = .load(addressBar) }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .opacity(0.5)


                // ✅ (토글됨) 정면설정/고개스크롤/민감도 줄
                if !controlsCollapsed {
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

                        Text("민감도")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(value: $tracker.deadZoneDeg, in: 1...10, step: 0.5)
                            .frame(width: 140)

                        Text("\(tracker.deadZoneDeg, specifier: "%.1f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
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

                    // ✅ 요청: 뒤로 옆에 UI 최소화 버튼
                    Button(controlsCollapsed ? "UI 펼치기" : "UI 최소화") {
                        controlsCollapsed.toggle()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(tracker.isGazeTapEnabled ? "시선탭: ON" : "시선탭: OFF") {
                        tracker.isGazeTapEnabled.toggle()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .opacity(0.5)
            }
            .ignoresSafeArea(edges: .top)
            .statusBarHidden(true)
            .onAppear { tracker.start() }
            .onDisappear { tracker.stop() }
        }
    }
}
