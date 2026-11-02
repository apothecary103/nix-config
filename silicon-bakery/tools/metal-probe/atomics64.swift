import Metal
let d = MTLCreateSystemDefaultDevice()!
func tryCompile(_ name: String, _ body: String) {
  let src = "#include <metal_stdlib>\nusing namespace metal;\nkernel void k(device atomic_ulong *a [[buffer(0)]], uint i [[thread_position_in_grid]]) { \(body) }"
  do { _ = try d.makeLibrary(source: src, options: nil); print("\(name): compiles") }
  catch { print("\(name): rejected (\(String(describing: error).split(separator: "\n").first { $0.contains("error") } ?? ""))") }
}
tryCompile("64-bit max", "atomic_max_explicit(a, ulong(i), memory_order_relaxed);")
tryCompile("64-bit add", "atomic_fetch_add_explicit(a, ulong(i), memory_order_relaxed);")
tryCompile("64-bit xchg", "atomic_exchange_explicit(a, ulong(i), memory_order_relaxed);")
tryCompile("64-bit cmpxchg", "ulong e = 0; atomic_compare_exchange_weak_explicit(a, &e, ulong(i), memory_order_relaxed, memory_order_relaxed);")
tryCompile("64-bit or", "atomic_fetch_or_explicit(a, ulong(i), memory_order_relaxed);")
// timing: 32 vs 64-bit max, both to 64 slots (contention) and per-thread slots
let src = """
#include <metal_stdlib>
using namespace metal;
kernel void m64(device atomic_ulong *a [[buffer(0)]], constant uint &slots [[buffer(1)]], uint i [[thread_position_in_grid]]) {
  for (uint r = 0; r < 16; r++) atomic_max_explicit(&a[(i + r) % slots], (ulong(i) << 32) | r, memory_order_relaxed); }
kernel void m32(device atomic_uint *a [[buffer(0)]], constant uint &slots [[buffer(1)]], uint i [[thread_position_in_grid]]) {
  for (uint r = 0; r < 16; r++) atomic_fetch_max_explicit(&a[(i + r) % slots], i ^ r, memory_order_relaxed); }
"""
let lib = try! d.makeLibrary(source: src, options: nil)
let q = d.makeCommandQueue()!
let buf = d.makeBuffer(length: 8 << 22, options: .storageModePrivate)!
for slots in [64, 1 << 22] {
  for fn in ["m32", "m64"] {
    let p = try! d.makeComputePipelineState(function: lib.makeFunction(name: fn)!)
    var best = Double.infinity
    for _ in 0..<8 {
      let cb = q.makeCommandBuffer()!, e = cb.makeComputeCommandEncoder()!
      var s = UInt32(slots)
      e.setComputePipelineState(p); e.setBuffer(buf, offset: 0, index: 0); e.setBytes(&s, length: 4, index: 1)
      e.dispatchThreads(MTLSize(width: 1 << 22, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
      e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
      best = min(best, cb.gpuEndTime - cb.gpuStartTime)
    }
    print(String(format: "%@ slots=%-8d %.3f ms  (%.2f G atomics/s)", fn, slots, best * 1e3, Double(16 << 22) / best / 1e9))
  }
}
