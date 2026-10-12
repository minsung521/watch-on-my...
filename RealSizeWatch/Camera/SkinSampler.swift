import AVFoundation
import Observation

/// 폰을 팔에 올리기 전에 후면 카메라로 팔 피부를 직접 비춰 색을 샘플링한다.
/// 주변광에서 색을 역산하는 것보다 정확한 1차 소스다 (MIN-45).
@Observable
final class SkinSampler {
    enum Status: Equatable {
        case idle, starting, running, unavailable, denied, failed
    }

    private(set) var status: Status = .idle
    private(set) var liveColor: RGB?
    @ObservationIgnored private var engine: CaptureEngine?

    var session: AVCaptureSession? { engine?.session }

    @MainActor
    func start() {
        guard status == .idle || status == .failed else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            status = .unavailable
            return
        }
        status = .starting
        Task { @MainActor in
            guard await CameraAccess.request() else {
                status = .denied
                return
            }
            let engine = self.engine ?? makeEngine(device: device)
            self.engine = engine
            engine.start(configure: CameraTuning.lockWhiteBalanceToD65) { running in
                DispatchQueue.main.async { [weak self] in
                    self?.status = running ? .running : .failed
                }
            }
        }
    }

    @MainActor
    func stop() {
        engine?.stop()
        if status == .running || status == .starting {
            status = .idle
        }
    }

    private func makeEngine(device: AVCaptureDevice) -> CaptureEngine {
        let engine = CaptureEngine(device: device, preset: .high, label: "skin")
        var frame = 0
        engine.frameHandler = { [weak self] buffer in
            frame += 1
            guard frame % 6 == 0, let rgb = PixelSampler.averageCenter(of: buffer) else { return }
            DispatchQueue.main.async {
                self?.liveColor = rgb
            }
        }
        return engine
    }
}

/// 폰을 팔에 올린 뒤에는 후면 카메라가 가려지므로 전면 카메라(천장광)로 조명 변화를 추적한다 (MIN-45).
/// 손목 캘리브레이션 화면과 착용 화면이 함께 쓰므로 참조 횟수로 켜고 끈다.
/// 상태는 메인 스레드에서만 바꾼다(타이머도 메인 런루프). 캡처 큐에서는 장치 값만 읽는다.
@Observable
final class AmbientLightMonitor: @unchecked Sendable {
    enum Availability: Equatable {
        case unknown, available, unavailable, denied
    }

    static let shared = AmbientLightMonitor()

    private(set) var reading: AmbientReading?
    private(set) var availability: Availability = .unknown
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var engine: CaptureEngine?
    @ObservationIgnored private var timer: Timer?

    @MainActor
    func acquire() {
        users += 1
        if users == 1 { start() }
    }

    @MainActor
    func release() {
        guard users > 0 else { return }
        users -= 1
        if users == 0 { stop() }
    }

    @MainActor
    private func start() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            availability = .unavailable
            return
        }
        Task { @MainActor in
            guard await CameraAccess.request() else {
                availability = .denied
                return
            }
            guard users > 0 else { return }
            let engine = self.engine ?? CaptureEngine(device: device, preset: .low, label: "ambient")
            self.engine = engine
            engine.start(configure: CameraTuning.useAutomaticMetering) { running in
                DispatchQueue.main.async { [weak self] in
                    self?.availability = running ? .available : .unavailable
                }
            }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.poll()
            }
        }
    }

    @MainActor
    private func stop() {
        timer?.invalidate()
        timer = nil
        engine?.stop()
    }

    private func poll() {
        engine?.withDevice { device in
            let reading = CameraTuning.ambientReading(from: device)
            DispatchQueue.main.async { [weak self] in
                self?.ingest(reading)
            }
        }
    }

    private func ingest(_ new: AmbientReading?) {
        guard let new else { return }
        guard let old = reading else {
            reading = new
            return
        }
        let smoothing = 0.35
        reading = AmbientReading(
            temperatureK: old.temperatureK + (new.temperatureK - old.temperatureK) * smoothing,
            ev100: old.ev100 + (new.ev100 - old.ev100) * smoothing
        )
    }
}
