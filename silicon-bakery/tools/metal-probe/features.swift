import Metal
let d = MTLCreateSystemDefaultDevice()!
print("device:", d.name)
for (n, f) in [("apple7", MTLGPUFamily.apple7), ("apple8", .apple8), ("apple9", .apple9), ("metal3", .metal3)] { print("family \(n):", d.supportsFamily(f)) }
print("raytracing:", d.supportsRaytracing, " fn pointers:", d.supportsFunctionPointers)
print("rasterization rate map (1 layer):", d.supportsRasterizationRateMap(layerCount: 1))
print("barycentrics:", d.supportsShaderBarycentricCoordinates)
print("raster order groups:", d.areRasterOrderGroupsSupported)
print("32-bit float filtering:", d.supports32BitFloatFiltering, " 32-bit MSAA:", d.supports32BitMSAA)
print("query texture LOD:", d.supportsQueryTextureLOD, " pull-model interp:", d.supportsPullModelInterpolation)
print("sparse tile 16K:", d.sparseTileSizeInBytes)
let src = """
#include <metal_stdlib>
using namespace metal;
kernel void k(device atomic_ulong *a [[buffer(0)]], uint i [[thread_position_in_grid]]) {
  ulong v = (ulong(i) << 33) | 0x5555;
  atomic_max_explicit(&a[0], v, memory_order_relaxed);
  atomic_min_explicit(&a[1], v, memory_order_relaxed);
}
kernel void k3d(texture3d<float, access::write> t [[texture(0)]], uint3 i [[thread_position_in_grid]]) { t.write(float4(1), i); }
kernel void kms(texture2d_ms<float, access::read> t [[texture(0)]], device float *o [[buffer(0)]], uint2 i [[thread_position_in_grid]]) { o[0] = t.read(i, 0).x; }
"""
do {
  let lib = try d.makeLibrary(source: src, options: nil)
  let p = try d.makeComputePipelineState(function: lib.makeFunction(name: "k")!)
  let b = d.makeBuffer(length: 16, options: .storageModeShared)!
  let ptr = b.contents().bindMemory(to: UInt64.self, capacity: 2); ptr[0] = 0; ptr[1] = UInt64.max
  let q = d.makeCommandQueue()!, cb = q.makeCommandBuffer()!, e = cb.makeComputeCommandEncoder()!
  e.setComputePipelineState(p); e.setBuffer(b, offset: 0, index: 0)
  e.dispatchThreads(MTLSize(width: 1 << 20, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
  e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
  let n: UInt64 = (1 << 20) - 1
  print("64-bit atomic max ok:", ptr[0] == (n << 33 | 0x5555), String(ptr[0], radix: 16), " min ok:", ptr[1] == 0x5555)
} catch { print("64-bit atomics: compile/run failed:", error) }
