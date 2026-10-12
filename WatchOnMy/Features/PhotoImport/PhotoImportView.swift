import PhotosUI
import SwiftUI

/// 사진 선택 → 누끼 → 자동 세우기 → L2L 입력 → 가로선 두 개 → 렌더링 (06 6-1, MIN-247 최소판)
struct PhotoImportView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case pick, upright, lugToLug, lines
    }

    @State private var step: Step = .pick
    @State private var pickerItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var cutout: PhotoProcessor.Cutout?
    @State private var manualRotation = 0.0
    @State private var uprightImage: CGImage?
    @State private var lugToLugText = ""
    @State private var lines: (top: Double, bottom: Double) = (0, 0)

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .pick: pickStep
                case .upright: uprightStep
                case .lugToLug: lugToLugStep
                case .lines: linesStep
                }
                if isWorking {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView(step == .pick ? "배경을 분리하는 중…" : "처리하는 중…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            load(item)
        }
        #if DEBUG
        .task {
            // 시뮬레이터 검증용: -debug-import-image <경로> 로 사진 선택 단계를 건너뛴다
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-debug-import-image"), arguments.indices.contains(index + 1),
               let data = FileManager.default.contents(atPath: arguments[index + 1]) {
                process(data)
            }
        }
        #endif
    }

    private var title: String {
        switch step {
        case .pick: "사진으로 보기"
        case .upright: "똑바로 세우기"
        case .lugToLug: "러그 투 러그 입력"
        case .lines: "러그 끝 맞추기"
        }
    }

    // MARK: 1~2. 사진 선택과 누끼

    private var pickStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("갖고 싶은 시계의 상품 사진을 고르세요.")
                    .font(.title3.weight(.semibold))
                Label("시계를 정면에서 찍은 사진이어야 정확합니다. 비스듬한 사진은 실제보다 작게 그려집니다.", systemImage: "camera.viewfinder")
                Label("배경이 투명한 PNG는 그대로 씁니다. 그 외에는 기기 안에서 배경을 분리합니다.", systemImage: "scissors")
                Label("원본 사진은 저장하지 않고, 잘라낸 시계 부분만 이 기기 안에 보관합니다. 공유·전송하지 않습니다.", systemImage: "lock")
                if let errorMessage {
                    NoticeBanner(symbol: "exclamationmark.triangle.fill", title: errorMessage, tint: .red)
                        .accessibilityIdentifier("photo.error")
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(errorMessage == nil ? "사진 고르기" : "다른 사진 고르기")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("photo.pick")
            }
            .font(.subheadline)
            .padding(24)
        }
    }

    private func load(_ item: PhotosPickerItem) {
        errorMessage = nil
        isWorking = true
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                errorMessage = PhotoImportError.unreadable.errorDescription
                isWorking = false
                pickerItem = nil
                return
            }
            process(data)
        }
    }

    private func process(_ data: Data) {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try PhotoProcessor.prepare(data: data) }.value
                cutout = result
                manualRotation = 0
                step = .upright
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? PhotoImportError.failed.errorDescription
            }
            isWorking = false
            pickerItem = nil
        }
    }

    // MARK: 3. 자동 세우기 + 수동 미세조정

    @GestureState private var gestureRotation = Angle.zero

    private var uprightStep: some View {
        VStack(spacing: 14) {
            if let cutout {
                ZStack {
                    Color(white: 0.12)
                    Image(decorative: cutout.image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(28)
                        .rotationEffect(.degrees(cutout.autoRotationDegrees + manualRotation) + gestureRotation)
                    // 세로 기준선
                    Rectangle()
                        .fill(Color.yellow.opacity(0.8))
                        .frame(width: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    RotateGesture()
                        .updating($gestureRotation) { value, state, _ in state = value.rotation }
                        .onEnded { value in manualRotation += value.rotation.degrees }
                )
                .padding(.horizontal, 16)

                Text(cutout.autoRotationDegrees == 0
                     ? "거의 원형이라 자동으로 돌리지 않았어요."
                     : "자동으로 \(abs(cutout.autoRotationDegrees).mmText)° 돌려 세웠어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("시계의 12시–6시 축이 노란 세로선과 나란하도록 두 손가락으로 돌려 맞추세요. (현재 \((cutout.autoRotationDegrees + manualRotation).mmText)°)")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                HStack(spacing: 10) {
                    Button("자동값으로") { manualRotation = 0 }
                        .buttonStyle(.bordered)
                    Button {
                        bakeRotation(cutout)
                    } label: {
                        Text("다음").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("photo.uprightNext")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
    }

    private func bakeRotation(_ cutout: PhotoProcessor.Cutout) {
        let degrees = cutout.autoRotationDegrees + manualRotation
        isWorking = true
        Task {
            let image = await Task.detached(priority: .userInitiated) { PhotoProcessor.rotated(cutout.image, degrees: degrees) }.value
            uprightImage = image
            let extent = PhotoProcessor.alphaMask(of: image).verticalExtent
            lines = (Double(extent?.lowerBound ?? 0), Double(extent?.upperBound ?? image.height))
            isWorking = false
            step = .lugToLug
        }
    }

    // MARK: 4. L2L 입력

    @State private var showsLugToLugHelp = false

    private var lugToLugValue: Double? {
        SpecDraft.parse(lugToLugText).flatMap { Constants.photoLugToLugRangeMM.contains($0) ? $0 : nil }
    }

    private var lugToLugStep: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Text("러그 투 러그")
                    Spacer()
                    TextField("30~60", text: $lugToLugText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70)
                        .accessibilityIdentifier("photo.l2l")
                    Text("mm").foregroundStyle(.secondary)
                    Stepper("러그 투 러그", value: Binding(
                        get: { SpecDraft.parse(lugToLugText) ?? WatchSpec.defaultLugToLugMM },
                        set: { lugToLugText = min(max($0, 30), 60).mmText }
                    ), in: Constants.photoLugToLugRangeMM, step: 0.5)
                    .labelsHidden()
                }
                DisclosureGroup("L2L이 뭔가요?", isExpanded: $showsLugToLugHelp) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• 위쪽 러그 끝에서 아래쪽 러그 끝까지의 직선 거리입니다. 케이스 직경과 다른 값이에요.")
                        Text("• 상품 상세 스펙에 \"Lug to lug\", \"러그 투 러그\", \"L2L\"로 표기됩니다.")
                        Text("• 스펙에 없으면 제조사 공식 사이트나 리뷰 글에서 확인하세요.")
                        Text("• 직경만 아는 경우 지금은 사진으로 보기를 쓸 수 없습니다. 스펙 편집에서 직경과 비슷한 실루엣으로 확인해 보세요.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            } footer: {
                if !lugToLugText.isEmpty, lugToLugValue == nil {
                    Text("L2L은 30~60mm 범위로 입력하세요.").foregroundStyle(.red)
                }
            }
            Section {
                Button("다음") { step = .lines }
                    .disabled(lugToLugValue == nil)
                    .accessibilityIdentifier("photo.l2lNext")
            }
        }
    }

    // MARK: 5. 가로선 두 개

    private var linesStep: some View {
        VStack(spacing: 12) {
            if let image = uprightImage, let lugToLug = lugToLugValue {
                Text("위·아래 러그 끝에 선을 맞추세요. 사진은 두 손가락으로 확대할 수 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                LugLineEditor(image: image, top: $lines.top, bottom: $lines.bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 12)
                Text("L2L \(lugToLug.mmText)mm · 선 간격 \(Int(abs(lines.bottom - lines.top).rounded()))px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("이전") { step = .lugToLug }
                        .buttonStyle(.bordered)
                    Button {
                        finish(image: image, lugToLug: lugToLug)
                    } label: {
                        Text("손목에 올려보기").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(abs(lines.bottom - lines.top) < 20)
                    .accessibilityIdentifier("photo.finish")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
    }

    private func finish(image: CGImage, lugToLug: Double) {
        let top = lines.top
        let bottom = lines.bottom
        isWorking = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try PhotoProcessor.finish(image: image, topLineY: top, bottomLineY: bottom, lugToLugMM: lugToLug)
                }.value
                try appState.addPhotoWatch(
                    pngData: result.pngData,
                    lugToLugMM: lugToLug,
                    mmPerPixel: result.mmPerPixel,
                    strapWidthMM: result.strapWidthMM,
                    strapColor: result.strapColor
                )
                isWorking = false
                dismiss()
            } catch {
                isWorking = false
                errorMessage = (error as? LocalizedError)?.errorDescription
                step = .pick
            }
        }
    }
}

/// 화면 전폭을 가로지르는 수평선 2개를 위아래로만 끈다. 선 위치는 사진 픽셀 좌표로 들고 있어 확대해도 유지된다.
/// 스케일을 정하는 이 단계까지만 사진 확대를 허용한다 (00 절대 원칙 1의 예외)
struct LugLineEditor: View {
    let image: CGImage
    @Binding var top: Double
    @Binding var bottom: Double

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var zoomStart: CGFloat?
    @State private var panStart: CGSize?
    @State private var lineStart: Double?

    var body: some View {
        GeometryReader { proxy in
            let imageSize = CGSize(width: image.width, height: image.height)
            let fit = min(proxy.size.width / imageSize.width, (proxy.size.height - 40) / imageSize.height)
            let s = fit * zoom
            let origin = CGPoint(
                x: proxy.size.width / 2 + pan.width - imageSize.width * s / 2,
                y: proxy.size.height / 2 + pan.height - imageSize.height * s / 2
            )
            ZStack(alignment: .topLeading) {
                Color(white: 0.12)
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: imageSize.width * s, height: imageSize.height * s)
                    .offset(x: origin.x, y: origin.y)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .simultaneousGesture(zoomGesture)
                line(y: $top, label: "위 러그 끝", originY: origin.y, scale: s, width: proxy.size.width, imageHeight: imageSize.height)
                line(y: $bottom, label: "아래 러그 끝", originY: origin.y, scale: s, width: proxy.size.width, imageHeight: imageSize.height)
            }
        }
    }

    private func line(y: Binding<Double>, label: String, originY: CGFloat, scale: CGFloat, width: CGFloat, imageHeight: CGFloat) -> some View {
        let screenY = originY + CGFloat(y.wrappedValue) * scale
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.yellow)
                .frame(height: 1.5)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.yellow, in: Capsule())
                .offset(x: 8, y: label.hasPrefix("위") ? -12 : 12)
        }
        .frame(width: width, height: 44)
        .contentShape(Rectangle())
        .offset(y: screenY - 22)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let start = lineStart ?? y.wrappedValue
                    if lineStart == nil { lineStart = start }
                    y.wrappedValue = min(max(start + Double(value.translation.height / scale), 0), Double(imageHeight))
                }
                .onEnded { _ in lineStart = nil }
        )
        .accessibilityLabel(label)
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = panStart ?? pan
                if panStart == nil { panStart = start }
                pan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
            }
            .onEnded { _ in panStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? zoom
                if zoomStart == nil { zoomStart = start }
                zoom = min(max(start * value.magnification, 1), 8)
            }
            .onEnded { _ in zoomStart = nil }
    }
}
