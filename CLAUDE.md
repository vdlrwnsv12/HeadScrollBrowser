# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 빌드 & 실행

Xcode 전용 iOS 프로젝트 (SPM/CocoaPods 미사용). Xcode에서 빌드 및 실행:

```bash
xcodebuild -project HeadScrollBrowser.xcodeproj -scheme HeadScrollBrowser -destination 'platform=iOS,name=<device>' build
```

- **배포 타겟**: iOS 18.6+
- **실물 기기 필수** — TrueDepth 카메라(ARFaceTrackingConfiguration)가 필요하므로 시뮬레이터에서는 동작하지 않음.
- 카메라 사용 설명(NSCameraUsageDescription)은 별도 Info.plist가 아닌 Xcode 프로젝트 빌드 설정에 포함되어 있음.

## 아키텍처

ARKit 얼굴 추적을 활용하여 고개 움직임과 시선으로 조작하는 SwiftUI iOS 웹 브라우저 앱.

### 핵심 파일 (모두 `HeadScrollBrowser/` 내)

- **FaceTracker.swift** — `ARSession` + `ARFaceTrackingConfiguration`을 감싸는 `ObservableObject`. `ARFaceAnchor.transform`에서 머리 pitch를 추출하여 스크롤 속도를 계산하고, `lookAtPoint`를 화면 좌표로 투영하여 시선 탭을 구현. 데드존 + 클램핑 선형 매핑(pitch→velocity), 지수 평활(pitch/시선 모두), 일정 반경 내 시선이 머무르면 `gazeTapPulse`를 발생시키는 dwell 타이머 포함.

- **SimpleWebView.swift** — `WKWebView`를 감싸는 `UIViewRepresentable`. `Coordinator` 내 `CADisplayLink`가 매 프레임 `FaceTracker.velocity`를 읽어 `scrollView.setContentOffset`으로 스크롤 적용. 시선 탭은 정규화된 시선 좌표에 JavaScript 마우스 이벤트를 주입하여 실행. `WKNavigationDelegate`를 통해 `canGoBack`, `currentURL` 등 네비게이션 상태를 동기화. `WebCommand` 열거형(`.load`/`.goBack`)을 `@Binding`으로 받아 명령적 네비게이션 수행.

- **ContentView.swift** — 메인 UI: URL 입력바, 컨트롤 스트립(정면 설정, 고개스크롤 토글, 민감도 슬라이더), 하단바(뒤로, UI 최소화, 시선탭 토글). 컨트롤 영역은 접어서 웹 콘텐츠 영역을 최대화할 수 있음.

### 핵심 데이터 흐름

`FaceTracker` (ARSession delegate) → `velocity`, `gazePoint`, `gazeTapPulse` 퍼블리시 → `SimpleWebView.Coordinator`가 `CADisplayLink` tick에서 이를 읽어 → `WKWebView`에 스크롤 오프셋 적용 / JS 탭 실행.

## 언어

UI 문자열은 한국어. 코드 주석은 한국어와 영어 혼용.
