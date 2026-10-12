# Watch on My... — v1 (TestFlight 빌드 1.0 (1))

아이폰을 팔 위에 가로질러 올리면 화면이 가린 팔 부분을 가상 손목으로 채우고, 그 위에 시계를 실제 크기(1:1)로 그리는 iOS 앱입니다. 작업지시서 `00_공통컨텍스트`와 `06_v1수정_기존빌드` 기준이며, Linear 프로젝트 **Watch on My...**(MIN-44~47, MIN-246, MIN-247)와 대응합니다.

SwiftUI + Canvas + Vision만 사용합니다. 외부 패키지, 카메라, 네트워크는 쓰지 않습니다.

## 실행

1. `xcodegen generate`로 `WatchOnMy.xcodeproj`를 만들고 Xcode에서 엽니다. 프로젝트 설정은 `project.yml`이 원본입니다.
2. Scheme `WatchOnMy`, 실기는 **Signing & Capabilities → Team**을 지정합니다.
3. Bundle ID `com.sungdotio.watchonmy`, 표시 이름 `Watch on My...`, 버전 1.0 (1). App Store Connect 레코드와 같습니다.

iOS 17 이상, iPhone 세로 전용입니다. 시뮬레이터에서는 계수만 해당 기기 기준이고 Mac 화면에서는 실제 크기가 아닙니다. 사진 배경 분리(Vision)는 시뮬레이터에서 동작하지 않아 실기에서 확인해야 합니다.

## 사용 흐름

1. **온보딩 7단계** (카메라 없음): 원리 설명 → 화면 설정 안내([끄고 왔어요]/[그냥 진행]) → 스케일 확인(미등록 기기만) → 피부톤 프리셋 6종 → 손목 폭 맞추기 → 피부톤 미세조정(색조·채도·밝기, 건너뛰기 가능) → "측정된 손목 폭: 약 OOmm". 재실행 시 다시 묻지 않습니다.
2. **메인**: 화면 좌→우로 지나가는 손목 띠 위에 1:1 시계. 띠 바깥은 순수 검정이고, 버튼은 그 영역에만 있습니다. 화면을 탭하면 버튼이 숨겨집니다.
3. **스펙 편집**: L2L·직경만 필수, 나머지는 "세부 설정". 값이 바뀌면 바로 그려지고, 시트를 내리면 최근 목록에 들어갑니다.
4. **사진으로 보기**: 사진 선택 → 배경 분리(투명 PNG는 건너뜀) → 자동 세우기 + 두 손가락 미세조정 → L2L 입력("L2L이 뭔가요?") → 위·아래 러그 끝에 가로선 → 손목 위 1:1. 스트랩은 사진에서 잰 폭·색으로 파라메트릭으로 그립니다.
5. **최근**: 프리셋 2종(컴팩트 42/47, 롱러그 42/52.5) + 최근 5개(파라메트릭·사진).
6. **설정**: 손목 폭 표시, 손목·피부톤 다시 맞추기, 카드 정확도 확인·스케일 다시 보정.

## 구조

- `Domain/`: 순수 값 타입과 계산. UIKit·SwiftUI를 import하지 않습니다. `PhysicalScale`(mm↔pt 변환은 전부 여기), `WristProfile`, `WatchSpec`·`SpecDraft`, `CaseGeometry`, `PhotoWatch`·`PhotoMath`, `WatchSource`·`RecentList`, `Constants`
- `App/`: 진입점, `AppState`(@Observable), 디버그 전용 아이콘 생성기
- `Features/Rendering/WristCanvas.swift`: 손목 띠·그림자·스트랩·케이스·크라운을 하나의 Canvas에
- `Features/Calibration`, `Onboarding`, `Main`, `SpecInput`, `PhotoImport`, `Settings`
- `Persistence/`: 사진 PNG 저장소(Application Support), 밝기 고정·복원

## 테스트

```sh
xcodebuild -project WatchOnMy.xcodeproj -scheme WatchOnMy \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

Swift Testing, 순수 계산 로직만(00 3절). 29개 테스트(매개변수 케이스 포함 45건): PPI 그룹 값, pt↔mm 왕복, 카드 역산(517.5pt → 0.16541), 미등록 기기 폴백, `trueWidthMM` = mm × 1.083, 피부톤 HSB 경계값, 곡률 음영 표, 슈퍼타원(n=2 원), 형상별 케이스 길이, L2L 40/직경 42 거부, 러그 폭 기본값 짝수, 주축(30° → −30°, 원형 → 회전 없음), mmPerPixel(47/940 = 0.05), 스트랩 폭 클램프(9→12, 30→24, 실패→18), 최근 5개·밀려난 사진 PNG 삭제, 재실행 시 온보딩 생략.

## 디버그 전용 실행 인자 (Release 빌드에는 없음)

- `-reset-state`: 저장 데이터와 사진 초기화
- `-device-identifier iPhone99,9`: 미등록 기기 흐름 확인
- `-export-app-icon <경로>`: 앱 렌더러로 1024px 아이콘 PNG 생성 (`ImageRenderer`, 알파 없음)
- `-debug-import-image <경로>`: 사진 선택기를 건너뛰고 해당 파일로 사진 임포트

## 작업지시서와 다르게 구현한 부분

- **띠 위·아래 2.5mm 페이드의 위치**: 사용자가 맞춘 가장자리를 가운데로 두고 페이드합니다. 페이드 50% 지점이 맞춘 폭입니다.
- **스트랩 시작점**: 러그 끝이 아니라 케이스 아래 러그 사이부터 그립니다. 러그 사이로 피부가 보이지 않게 하기 위해서입니다(사용자 확인).
- **화면 잠금 해제**: 메인뿐 아니라 손목 캔버스가 보이는 모든 화면(온보딩 4~6단계 포함)에서 켭니다. 팔에 올려두고 맞추는 동안 화면이 꺼지지 않게 하려는 것입니다.
- **검정 영역 위 버튼**: 라이트 모드에서도 어두운 외관으로 고정합니다. 검정 바탕에서 읽히게 하기 위해서이고, 시트·설정은 시스템 외관을 따릅니다.
- **v1.1 상수**(핏 판정 밴드, 손목 단면 비율): `Constants`에 넣지 않았습니다. 06 3절 "죽은 코드 금지"에 따른 것입니다.
- **스펙 편집 중 화면**: 시트가 아래 절반을 덮을 때 캔버스를 위로 옮겨 시계가 보이게 합니다. 크기는 그대로입니다.
