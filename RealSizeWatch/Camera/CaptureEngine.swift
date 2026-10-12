import AVFoundation
import SwiftUI
import UIKit

enum CameraAccess {
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

/// AVCaptureSession 구성과 실행을 전용 큐에서 처리한다. 영상은 저장하거나 전송하지 않는다.
final class CaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let device: AVCaptureDevice
    private let preset: AVCaptureSession.Preset
    private let queue: DispatchQueue
    private var isConfigured = false
    /// 캡처 큐에서 호출된다. 시작 전에 설정한다.
    var frameHandler: ((CVPixelBuffer) -> Void)?

    init(device: AVCaptureDevice, preset: AVCaptureSession.Preset, label: String) {
        self.device = device
        self.preset = preset
        self.queue = DispatchQueue(label: "RealSizeWatch.capture.\(label)")
        super.init()
    }

    func start(configure: @escaping (AVCaptureDevice) -> Void, completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            if !isConfigured {
                isConfigured = configureSession()
            }
            guard isConfigured else {
                completion(false)
                return
            }
            configure(device)
            if !session.isRunning {
                session.startRunning()
            }
            completion(session.isRunning)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func withDevice(_ work: @escaping (AVCaptureDevice) -> Void) {
        queue.async { [self] in
            guard session.isRunning else { return }
            work(device)
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return false }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let frameHandler, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameHandler(buffer)
    }
}

enum CameraTuning {
    /// 카메라 AWB가 조명색을 지워버리지 않도록 화이트밸런스를 D65로 잠근다 (MIN-45)
    static func lockWhiteBalanceToD65(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isWhiteBalanceModeSupported(.locked) {
                let gains = device.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: 6500, tint: 0))
                device.setWhiteBalanceModeLocked(with: clamped(gains, limit: device.maxWhiteBalanceGain), completionHandler: nil)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
        } catch {}
    }

    static func useAutomaticMetering(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        } catch {}
    }

    /// 자동 노출·AWB가 정한 값에서 장면의 노출(EV100)과 광원 색온도를 읽는다
    static func ambientReading(from device: AVCaptureDevice) -> AmbientReading? {
        let seconds = CMTimeGetSeconds(device.exposureDuration)
        let iso = Double(device.iso)
        let aperture = Double(device.lensAperture)
        guard seconds > 0, iso > 0, aperture > 0 else { return nil }
        let gains = clamped(device.deviceWhiteBalanceGains, limit: device.maxWhiteBalanceGain)
        let values = device.temperatureAndTintValues(for: gains)
        return AmbientReading(
            temperatureK: Double(values.temperature),
            ev100: ev100(aperture: aperture, seconds: seconds, iso: iso)
        )
    }

    /// EV100 = log2(N²/t) − log2(ISO/100)
    static func ev100(aperture: Double, seconds: Double, iso: Double) -> Double {
        log2(aperture * aperture / seconds) - log2(iso / 100)
    }

    static func clamped(_ gains: AVCaptureDevice.WhiteBalanceGains, limit: Float) -> AVCaptureDevice.WhiteBalanceGains {
        var result = gains
        result.redGain = min(max(result.redGain, 1), limit)
        result.greenGain = min(max(result.greenGain, 1), limit)
        result.blueGain = min(max(result.blueGain, 1), limit)
        return result
    }
}

enum PixelSampler {
    /// BGRA 프레임 가운데 정사각 영역의 평균색 (sRGB)
    static func averageCenter(of buffer: CVPixelBuffer, fraction: Double = 0.25) -> RGB? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let side = max(1, Int(Double(min(width, height)) * fraction))
        let x0 = (width - side) / 2
        let y0 = (height - side) / 2
        let step = max(1, side / 48)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        var y = y0
        while y < y0 + side {
            let row = pixels + y * bytesPerRow
            var x = x0
            while x < x0 + side {
                let pixel = row + x * 4
                b += Double(pixel[0])
                g += Double(pixel[1])
                r += Double(pixel[2])
                count += 1
                x += step
            }
            y += step
        }
        guard count > 0 else { return nil }
        return RGB(r / count / 255, g / count / 255, b / count / 255)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
