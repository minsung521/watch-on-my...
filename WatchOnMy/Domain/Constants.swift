import Foundation

/// 공통 상수 (작업지시서 00 7절). 실기 확인 후 조정할 값은 모두 여기에 둔다.
enum Constants {
    // 신용카드 ISO/IEC 7810 ID-1. 화면 폭보다 길어 세로로 세워 맞추므로 긴 변(85.60)이 화면 세로축이다.
    static let cardWidthMM = 85.60
    static let cardHeightMM = 53.98
    static let cardCornerRadiusMM = 3.18

    // 시야각 오프셋 보정 (00 6절). 손목 측정값에만 곱한다. 시계에는 절대 곱하지 않는다.
    static let wristDepthCorrection = 1.083

    // 손목 캔버스 표시 중 고정 밝기
    static let canvasBrightness = 0.85

    // 손목 띠 경계 페이드
    static let bandEdgeFadeMM = 0.8    // 띠 위·아래 가장자리 (맞춘 폭의 경계를 중심으로). 2.5mm는 실루엣이 뭉개져 보여 줄임
    static let screenSideFadeMM = 10.0 // 화면 좌·우 끝 (실기 확인 후 조정)

    /// 손목 곡률 음영: 띠 높이 대비 위치 → 밝기 배율 (02 3-2)
    static let bandShading: [(location: Double, brightness: Double)] = [
        (0.0, 0.80), (0.2, 0.94), (0.5, 1.00), (0.8, 0.94), (1.0, 0.80),
    ]

    // 손목 맞추기
    static let initialMatchedWidthMM = 52.6   // 맞추기 전 띠의 시작 폭 (실제 약 57mm 손목)
    static let matchedWidthRangeMM: ClosedRange<Double> = 35...80
    static let matchedWidthStepMM = 0.5

    // 파라메트릭 시계 (02 4~5절)
    static let lugOuterStartAngleDegrees = 35.0
    static let lugTipTaper = 0.85
    static let lugTipRadiusMM = 1.0
    static let minimumLugThicknessMM = 1.6
    static let crownWidthMM = 2.0
    static let crownHeightMM = 4.0
    static let strapEndTaper = 0.82
    static let strapEdgeShading = 0.72
    static let strapEndFadeMM = 3.0
    static let shadowBlurMM = 2.0
    static let shadowOpacity = 0.25

    // 최근 목록
    static let recentLimit = 5

    // 사진 임포트 (06 6절)
    static let photoLugToLugRangeMM: ClosedRange<Double> = 30...60
    static let strapWidthRangeMM: ClosedRange<Double> = 12...24
    static let fallbackStrapWidthMM = 18.0
    static let strapSampleOffsetsMM = [2.0, 2.5, 3.0]
    static let uprightAxisRatioThreshold = 1.15
}
