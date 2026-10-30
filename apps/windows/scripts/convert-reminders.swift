// Development tool (macOS only): converts the Mac app's HEVC-with-alpha reminder videos
// into VP9-with-alpha WebM that Chromium/Electron on Windows can play transparently.
// Frames are decoded by AVFoundation (which understands HEVC alpha) and piped to ffmpeg.
// Usage: swift scripts/convert-reminders.swift <input.mov> <output.webm>
import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else { FileHandle.standardError.write("usage: convert-reminders <in.mov> <out.webm>\n".data(using: .utf8)!); exit(2) }
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
let asset = AVURLAsset(url: input)
let semaphore = DispatchSemaphore(value: 0)
var tracks: [AVAssetTrack] = []
var audioTracks: [AVAssetTrack] = []
Task {
    tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
    audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
    semaphore.signal()
}
semaphore.wait()
guard let track = tracks.first else { print("no video track"); exit(1) }
var size = CGSize.zero, fps: Float = 0
let s2 = DispatchSemaphore(value: 0)
Task { size = (try? await track.load(.naturalSize)) ?? .zero; fps = (try? await track.load(.nominalFrameRate)) ?? 24; s2.signal() }
s2.wait()
let width = Int(size.width), height = Int(size.height)
let reader = try AVAssetReader(asset: asset)
let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
out.alwaysCopiesSampleData = false
reader.add(out)
guard reader.startReading() else { print("cannot read: \(String(describing: reader.error))"); exit(1) }

let ffmpeg = Process()
ffmpeg.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
var ff = ["-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "\(width)x\(height)", "-r", String(format: "%.3f", fps), "-i", "pipe:0"]
if !audioTracks.isEmpty { ff += ["-i", input.path, "-map", "0:v", "-map", "1:a", "-c:a", "libopus", "-b:a", "96k"] }
ff += ["-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-b:v", "0", "-crf", "34", "-row-mt", "1", "-auto-alt-ref", "0", "-shortest", output.path]
ffmpeg.arguments = ff
let pipe = Pipe(); ffmpeg.standardInput = pipe
try ffmpeg.run()
var frames = 0, alphaSeen = false
while let sample = out.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    var frame = Data(capacity: width * height * 4)
    for y in 0..<height { frame.append(base + y * rowBytes, count: width * 4) }
    if !alphaSeen { for i in stride(from: 3, to: frame.count, by: 4 * 97) where frame[i] < 250 { alphaSeen = true; break } }
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    try pipe.fileHandleForWriting.write(contentsOf: frame)
    frames += 1
}
try pipe.fileHandleForWriting.close()
ffmpeg.waitUntilExit()
print("\(input.lastPathComponent): \(frames) frames \(width)x\(height) @\(fps) alpha=\(alphaSeen) exit=\(ffmpeg.terminationStatus)")
exit(ffmpeg.terminationStatus == 0 && reader.status == .completed ? 0 : 1)
