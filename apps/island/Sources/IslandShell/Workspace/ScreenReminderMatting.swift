import AVFoundation
import CoreImage
import Vision

/// Offline cutout. Only a successfully decoded alpha movie becomes a reminder.
/// Source videos and all frames stay on this Mac.
enum ScreenReminderMatting {
    static func convert(_ source: URL, to output: URL) async throws {
        let worker = Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: source)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw WorkError.message("视频没有画面。") }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let displayed = CGRect(origin: .zero, size: size).applying(transform)
            let scale = min(1, 720 / max(displayed.width, displayed.height))
            let width = max(2, Int(abs(displayed.width) * scale) / 2 * 2)
            let height = max(2, Int(abs(displayed.height) * scale) / 2 * 2)
            let extent = CGRect(x: 0, y: 0, width: width, height: height)
            let reader = try AVAssetReader(asset: asset)
            let read = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            read.alwaysCopiesSampleData = false; reader.add(read)
            let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
            let write = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha, AVVideoWidthKey: width, AVVideoHeightKey: height])
            write.expectsMediaDataInRealTime = false
            guard writer.canAdd(write) else { throw WorkError.message("这台 Mac 暂不支持透明视频编码。") }
            writer.add(write)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: write, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
            var audioRead: AVAssetReaderTrackOutput?
            var audioWrite: AVAssetWriterInput?
            if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                let a = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
                let b = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 44100, AVEncoderBitRateKey: 128000])
                if reader.canAdd(a) && writer.canAdd(b) { reader.add(a); writer.add(b); audioRead = a; audioWrite = b }
            }
            guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? WorkError.message("视频处理未能开始。") }
            writer.startSession(atSourceTime: .zero)
            let context = CIContext(options: [.cacheIntermediates: false])
            let object = VNGenerateForegroundInstanceMaskRequest()
            let audioTask = Task.detached {
                if let audioRead, let audioWrite {
                    while let sample = audioRead.copyNextSampleBuffer() {
                        try Task.checkCancellation()
                        while !audioWrite.isReadyForMoreMediaData {
                            guard writer.status == .writing else { throw writer.error ?? WorkError.message("音频编码中断。") }
                            try await Task.sleep(for: .milliseconds(5))
                        }
                        guard audioWrite.append(sample) else { throw writer.error ?? WorkError.message("音频保存失败。") }
                    }
                    audioWrite.markAsFinished()
                }
            }
            var last = -Double.infinity
            var frames = 0
            var visibleFrames = 0
            do {
                while let sample = read.copyNextSampleBuffer() {
                    try Task.checkCancellation()
                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    guard time.seconds - last >= 1.0 / 15 - 0.001, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                    while !write.isReadyForMoreMediaData {
                        guard writer.status == .writing else { throw writer.error ?? WorkError.message("透明视频编码中断。") }
                        try await Task.sleep(for: .milliseconds(5))
                    }
                    try autoreleasepool {
                        let transformed = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
                        let normalized = transformed.transformed(by: .init(translationX: -transformed.extent.minX, y: -transformed.extent.minY)).transformed(by: .init(scaleX: scale, y: scale)).cropped(to: extent)
                        guard let cg = context.createCGImage(normalized, from: extent) else { throw WorkError.message("无法处理视频帧。") }
                        let handler = VNImageRequestHandler(cgImage: cg)
                        try handler.perform([object])
                        let mask: CIImage
                        if let result = object.results?.first, !result.allInstances.isEmpty {
                            mask = CIImage(cvPixelBuffer: try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler))
                            visibleFrames += 1
                        } else { mask = CIImage(color: .black).cropped(to: extent) }
                        let scaledMask = mask.transformed(by: .init(scaleX: extent.width / mask.extent.width, y: extent.height / mask.extent.height)).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.65]).cropped(to: extent)
                        let clear = CIImage(color: .clear).cropped(to: extent)
                        let cutout = normalized.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: scaledMask])
                        guard let pool = adaptor.pixelBufferPool else { throw WorkError.message("透明帧缓冲不可用。") }
                        var target: CVPixelBuffer?
                        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &target) == kCVReturnSuccess, let target else { throw WorkError.message("视频处理内存不足。") }
                        CVBufferSetAttachment(target, kCVImageBufferAlphaChannelModeKey, kCVImageBufferAlphaChannelMode_PremultipliedAlpha, .shouldPropagate)
                        context.render(cutout, to: target, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())
                        guard adaptor.append(target, withPresentationTime: time) else { throw writer.error ?? WorkError.message("无法保存透明帧。") }
                        frames += 1; last = time.seconds
                    }
                }
                write.markAsFinished()
                try await audioTask.value
                guard frames > 0, visibleFrames > 0, reader.status != .failed else { throw reader.error ?? WorkError.message("未找到可分离的主体。请选择主体清楚的视频。") }
                await writer.finishWriting()
                guard writer.status == .completed else { throw writer.error ?? WorkError.message("透明视频保存失败。") }
            } catch { audioTask.cancel(); reader.cancelReading(); writer.cancelWriting(); throw error }
        }
        try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}
