

<img width="800" height="520" alt="mercury" src="https://github.com/user-attachments/assets/a7fcb2cb-d1a6-417c-a031-f39286a92193" />


# MercuryShader

A real-time liquid-metal shader for iOS and macOS built with Metal and SwiftUI.
It simulates a flowing mercury surface using fractional Brownian motion (fBm) noise,
fake surface normals, Fresnel reflection, environment mapping, and specular highlights
— all running at 60 fps on the GPU with no geometry buffers.

---

## How it works

### 1. fBm Noise

Fractional Brownian motion is built by summing six octaves of smooth value noise.
Each octave doubles the frequency (lacunarity = 2.0) and halves the amplitude
(gain = 0.5), producing detail at multiple scales that resembles a turbulent fluid.

### 2. UV Distortion

The screen UV coordinates are warped by two nested fBm evaluations offset in both
space and time. The result is a constantly shifting, organic distortion that makes
the surface appear to flow and ripple without any vertex animation.

### 3. Fake Surface Normals

A surface normal is reconstructed analytically from the fBm height field using
central finite differences: sample the height at `uv`, `uv + (ε, 0)`, and
`uv + (0, ε)`, then form a tangent-space normal from the gradient.
No normal map texture is needed.

### 4. Fresnel Reflection

A Schlick approximation computes how much of the environment is reflected based on
the viewing angle: `pow(1 - dot(viewDir, normal), 3)`. Grazing angles reflect
strongly; straight-on angles reveal the base silver colour.

### 5. Environment Map + Specular

The reflection direction is projected to UV space and used to sample a 2D
environment texture. A Blinn–Phong specular term (`pow(dot(R, V), 64)`) adds a
sharp highlight. The final pixel is:

```
color = mix(baseColor, envColor, fresnel) + specular
```

---

## Build instructions

**Requirements**
- Xcode 15 or later
- iOS 17+ device or simulator / macOS 14+ (Sonoma)

**Steps**

1. Open `MercuryShader.xcodeproj` in Xcode.
2. Select the `MercuryShader` scheme.
3. Choose an iOS simulator or connected device.
4. Press **⌘R** to build and run.

No third-party dependencies. No CocoaPods or SPM packages required.

---

## What to swap out: replacing the placeholder environment map

The renderer (`Renderer.swift`) loads a 2×2 white `MTLTexture` as a stand-in
environment map. To replace it with a real `.hdr` (or `.png`) panorama:

1. **Add the image to your project.** Drag the file into Xcode and tick
   *Copy items if needed*. For HDR panoramas, a `.hdr` equirectangular image
   works well at 1024×512 or 2048×1024.

2. **Load it at runtime.** In `Renderer.init`, replace `buildPlaceholderEnvMap()`
   with an `MTKTextureLoader` call:

   ```swift
   import MetalKit

   private func loadEnvMap(device: MTLDevice) {
       let loader = MTKTextureLoader(device: device)
       guard let url = Bundle.main.url(forResource: "env", withExtension: "hdr") else { return }
       let opts: [MTKTextureLoader.Option: Any] = [
           .textureUsage: MTLTextureUsage.shaderRead.rawValue,
           .textureStorageMode: MTLStorageMode.private.rawValue,
           .generateMipmaps: true,
       ]
       envMapTexture = try? loader.newTexture(URL: url, options: opts)
   }
   ```

3. **Use an equirectangular projection in the shader.** In `Mercury.metal`,
   convert the reflection vector to spherical UV coordinates instead of the
   simple planar projection currently used:

   ```metal
   float phi   = atan2(R.z, R.x);          // [-π, π]
   float theta = asin(clamp(R.y, -1.0, 1.0)); // [-π/2, π/2]
   float2 envUV = float2(phi / (2.0 * M_PI_F) + 0.5,
                         theta / M_PI_F + 0.5);
   ```

   This maps the full sphere of reflections onto the equirectangular panorama.
