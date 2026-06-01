import Metal
import MetalKit

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var envMapTexture: MTLTexture?
    private var time: Float = 0

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        super.init()
        buildPipeline()
        buildPlaceholderEnvMap()
    }

    private func buildPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to load default Metal library.")
            return
        }
        let vertexFn   = library.makeFunction(name: "vertexShader")
        let fragmentFn = library.makeFunction(name: "fragmentShader")

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)
    }

    private func buildPlaceholderEnvMap() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false)
        guard let tex = device.makeTexture(descriptor: desc) else { return }
        // 4 white pixels (RGBA)
        let white: [UInt8] = Array(repeating: 0xFF, count: 2 * 2 * 4)
        white.withUnsafeBytes { ptr in
            tex.replace(
                region: MTLRegionMake2D(0, 0, 2, 2),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: 2 * 4)
        }
        envMapTexture = tex
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        time += 1.0 / 60.0

        guard
            let pipeline  = pipelineState,
            let drawable  = view.currentDrawable,
            let rpd        = view.currentRenderPassDescriptor,
            let cmdBuffer  = commandQueue.makeCommandBuffer(),
            let encoder    = cmdBuffer.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        var uniforms = Uniforms(
            time: time,
            resolution: SIMD2<Float>(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            )
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(envMapTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }
}
