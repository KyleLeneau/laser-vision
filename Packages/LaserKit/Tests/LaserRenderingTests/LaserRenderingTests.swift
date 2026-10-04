import CoreGraphics
import Foundation
import ImageIO
import LaserShaderTypes
import Testing
import UniformTypeIdentifiers
@testable import LaserRendering
import ShowModel
import simd

@Suite struct ShaderLayoutTests {
    // Swift imports these from the same C header Metal compiles, so these sizes are what the
    // GPU sees. They guard against accidental changes that would bloat per-frame uploads.
    @Test func structSizes() {
        #expect(MemoryLayout<LaserPatternUniforms>.stride == 80)
        #expect(MemoryLayout<LaserSegment>.stride == 48)
        #expect(MemoryLayout<LaserBeamVertex>.stride == 32)
        #expect(MemoryLayout<LaserBeamVertex>.offset(of: \.uv) == 16)
        #expect(MemoryLayout<LaserFrameUniforms>.stride < 4_096, "must fit setBytes")
    }
}

@Suite struct PatternBudgetTests {
    @Test(arguments: PatternKind.allCases)
    func staysWithinBudget(kind: PatternKind) {
        for density in [0.0, 0.5, 1.0] {
            for symmetry in [1, 3, 8, 64] {
                let settings = PatternSettings(kind: kind, parameters: PatternParameters(density: density, symmetry: symmetry))
                let layout = PatternBudget.layout(for: settings)
                #expect(layout.segmentCount > 0)
                #expect(layout.segmentCount <= PatternBudget.maxSegmentsPerSlot)
                #expect(layout.elementCount >= 1)
            }
        }
    }

    @Test func colorLinearization() throws {
        #expect(LaserColor(red: 1, green: 1, blue: 1).linear == SIMD3(1, 1, 1))
        #expect(LaserColor(red: 0, green: 0, blue: 0).linear == SIMD3(0, 0, 0))
        let mid = LaserColor(red: 0.5, green: 0.5, blue: 0.5).linear.x
        #expect(abs(mid - 0.214) < 0.001)
    }
}

/// Renders every pattern through the real GPU kernels. Requires the Metal library, so it runs
/// under `xcodebuild test` (SwiftPM's command line does not compile .metal files).
@Suite(.serialized) @MainActor struct KeyVisualTests {
    static let outputDirectory = FileManager.default.temporaryDirectory.appending(path: "LaserKeyVisuals")

    @Test(arguments: PatternKind.allCases)
    func rendersPattern(kind: PatternKind) throws {
        let renderer: KeyVisualRenderer
        do {
            renderer = try KeyVisualRenderer()
        } catch LaserRenderingError.missingShaderLibrary {
            withKnownIssue("Metal library unavailable under `swift test`; run via xcodebuild") { throw CancellationError() }
            return
        }

        let show = ShowDefinition(
            id: kind.rawValue,
            title: kind.rawValue,
            artist: "Test",
            audio: AudioReference(location: .bundled, fileName: "none.m4a"),
            tempo: Tempo(bpm: 120),
            palette: ColorPalette(colors: [LaserColor(hex: "#00F0FF")!, LaserColor(hex: "#FF2A9D")!]),
            signature: PatternSettings(kind: kind, parameters: PatternParameters(scale: 0.8, density: 0.6, symmetry: 5)),
            cues: [Cue(startBar: 0, pattern: PatternSettings(kind: kind))]
        )
        let image = try renderer.render(show: show, imageSize: 256)
        #expect(image.width == 256)

        // Lasers must add clearly visible light over the dark sky.
        let brightPixels = try countBrightPixels(in: image, threshold: 120)
        #expect(brightPixels > 40, "only \(brightPixels) bright pixels")

        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        try writePNG(image, to: Self.outputDirectory.appending(path: "\(kind.rawValue).png"))
    }

    private func countBrightPixels(in image: CGImage, threshold: UInt8) throws -> Int {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: pixels.count, by: 4).count { index in
            max(pixels[index], pixels[index + 1], pixels[index + 2]) > threshold
        }
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

@Suite struct DomeProjectionTests {
    private func isClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool { simd_distance(a, b) < 1e-5 }

    @Test func diskAxesMatchShaderConvention() {
        #expect(isClose(DomeProjection.direction(forDisk: [0, 0]), [0, 1, 0]), "center is the zenith")
        #expect(isClose(DomeProjection.direction(forDisk: [0, 1]), [0, 0, -1]), "+y is the front horizon")
        #expect(isClose(DomeProjection.direction(forDisk: [1, 0]), [1, 0, 0]), "+x is the right horizon")
    }

    @Test func frontOfDomeSamplesTopOfImage() {
        // RealityKit's v runs up the image; the shader puts the dome's front on the top row.
        #expect(DomeProjection.textureCoordinate(forDisk: [0, 1]) == SIMD2(0.5, 1))
        #expect(DomeProjection.textureCoordinate(forDisk: [1, 0]) == SIMD2(1, 0.5))
    }
}
