import Metal
let d = MTLCreateSystemDefaultDevice()!
let lib = try! d.makeLibrary(source: """
#include <metal_stdlib>
using namespace metal;
kernel void add(device float *a [[buffer(0)]], uint i [[thread_position_in_grid]]) { a[i] += 1.0f; }
""", options: nil)
let p = try! d.makeComputePipelineState(function: lib.makeFunction(name: "add")!)
let q = d.makeCommandQueue()!
let buf = d.makeBuffer(length: 4096 * 4, options: .storageModePrivate)!
for (label, type) in [("serial (each depends on the last)", MTLDispatchType.serial), ("concurrent (no barriers)", .concurrent)] {
  for n in [4096] {
    var best = Double.infinity
    for _ in 0..<5 {
      let cb = q.makeCommandBuffer()!, e = cb.makeComputeCommandEncoder(dispatchType: type)!
      e.setComputePipelineState(p); e.setBuffer(buf, offset: 0, index: 0)
      for _ in 0..<n { e.dispatchThreads(MTLSize(width: 4096, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1)) }
      e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
      best = min(best, cb.gpuEndTime - cb.gpuStartTime)
    }
    print(String(format: "%@: %d dispatches of 4096 threads, %.2f us each", label, n, best / Double(n) * 1e6))
  }
}
