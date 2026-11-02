// mt-probe: record what macOS makes of finger motion on the built-in trackpad.
//
// Opens a window. While it runs, every multitouch frame (raw finger positions,
// from the private MultitouchSupport framework the trackpad driver feeds) and
// every pointer and scroll event the window receives (the deltas WindowServer
// delivers after acceleration) is written, one JSON object per line, to the
// file given on the command line. tools/mt-probe/analyse.py turns a recording
// into the transfer functions and compares them with a Silicon Bakery profile.
//
//   ./build && ./mt-probe recording.jsonl     # then move, scroll, close window
//   ./mt-probe --selftest                     # load the framework, list devices
//
// Nothing is sent anywhere, no settings are changed, and no permission prompt
// is needed: the window only sees events aimed at it.

import AppKit
import Foundation

// MultitouchSupport's frame callback hands over an array of these. The layout
// is the one community tools (OpenMultitouchSupport and its predecessors) have
// used since 10.5; --selftest and the analysis check it looks sane.
struct MTPoint { var x: Float; var y: Float }
struct MTVector { var position: MTPoint; var velocity: MTPoint }
struct MTTouch {
  var frame: Int32
  var timestamp: Double
  var pathIndex: Int32
  var state: Int32
  var fingerID: Int32
  var handID: Int32
  var normalized: MTVector
  var zTotal: Float
  var force: Float  // grams (record 0x1a)
  var angle: Float
  var majorAxis: Float
  var minorAxis: Float
  var millimetres: MTVector
  var field14: Int16  // record 0x1c
  var pad: Int16
  var field15: Float  // record 0x18, scaled (tilt)
  var zDensity: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTFrameCallback = @convention(c) (
  MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

struct Multitouch {
  let createList: @convention(c) () -> Unmanaged<CFMutableArray>
  let register: @convention(c) (MTDeviceRef, MTFrameCallback) -> Void
  let start: @convention(c) (MTDeviceRef, Int32) -> Void
  let stop: @convention(c) (MTDeviceRef) -> Void
  let isBuiltIn: @convention(c) (MTDeviceRef) -> Bool

  init?() {
    guard
      let handle = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    else { return nil }
    func sym<T>(_ name: String, _: T.Type) -> T? {
      guard let p = dlsym(handle, name) else { return nil }
      return unsafeBitCast(p, to: T.self)
    }
    guard
      let createList = sym("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFMutableArray>).self),
      let register = sym(
        "MTRegisterContactFrameCallback", (@convention(c) (MTDeviceRef, MTFrameCallback) -> Void).self),
      let start = sym("MTDeviceStart", (@convention(c) (MTDeviceRef, Int32) -> Void).self),
      let stop = sym("MTDeviceStop", (@convention(c) (MTDeviceRef) -> Void).self),
      let isBuiltIn = sym("MTDeviceIsBuiltIn", (@convention(c) (MTDeviceRef) -> Bool).self)
    else { return nil }
    self.createList = createList
    self.register = register
    self.start = start
    self.stop = stop
    self.isBuiltIn = isBuiltIn
  }

  func devices() -> [MTDeviceRef] {
    let list = createList().takeRetainedValue() as NSArray
    return list.map { Unmanaged<AnyObject>.passUnretained($0 as AnyObject).toOpaque() }
  }
}

// One writer for both threads (multitouch frames arrive off the main thread).
final class Recorder {
  private let handle: FileHandle
  private let lock = NSLock()
  init(path: String) throws {
    FileManager.default.createFile(atPath: path, contents: nil)
    guard let h = FileHandle(forWritingAtPath: path) else {
      throw NSError(domain: "mt-probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot write \(path)"])
    }
    handle = h
  }
  func write(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
    lock.lock()
    handle.write(data)
    handle.write(Data([0x0a]))
    lock.unlock()
  }
  func close() {
    lock.lock()
    try? handle.close()
    lock.unlock()
  }
}

var recorder: Recorder?

let frameCallback: MTFrameCallback = { _, data, count, timestamp, frame in
  guard let recorder = recorder else { return 0 }
  var touches: [[String: Any]] = []
  if let data = data, count > 0 {
    let buffer = data.bindMemory(to: MTTouch.self, capacity: Int(count))
    for i in 0..<Int(count) {
      let t = buffer[i]
      touches.append([
        "id": t.pathIndex, "state": t.state, "finger": t.fingerID, "hand": t.handID,
        "x": t.normalized.position.x, "y": t.normalized.position.y,
        "vx": t.normalized.velocity.x, "vy": t.normalized.velocity.y,
        "mmx": t.millimetres.position.x, "mmy": t.millimetres.position.y,
        "major": t.majorAxis, "minor": t.minorAxis, "angle": t.angle,
        "z": t.zTotal, "density": t.zDensity, "force": t.force,
        "f14": t.field14, "f15": t.field15,
      ])
    }
  }
  recorder.write(["kind": "frame", "t": timestamp, "frame": frame, "touches": touches])
  return 0
}

final class ProbeView: NSView {
  override var acceptsFirstResponder: Bool { true }
  override func updateTrackingAreas() {
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
  }
  private func pointer(_ e: NSEvent, _ kind: String) {
    recorder?.write([
      "kind": kind, "t": e.timestamp, "dx": e.deltaX, "dy": e.deltaY,
      "x": NSEvent.mouseLocation.x, "y": NSEvent.mouseLocation.y,
    ])
  }
  override func mouseMoved(with e: NSEvent) { pointer(e, "move") }
  override func mouseDragged(with e: NSEvent) { pointer(e, "drag") }
  private func button(_ e: NSEvent, _ kind: String) {
    recorder?.write(["kind": kind, "t": e.timestamp, "button": e.buttonNumber, "clicks": e.clickCount])
  }
  // When keys go down and up, for typing-related palm rejection; never which.
  override func keyDown(with e: NSEvent) {
    if !e.isARepeat { recorder?.write(["kind": "key", "t": e.timestamp, "down": true]) }
  }
  override func keyUp(with e: NSEvent) { recorder?.write(["kind": "key", "t": e.timestamp, "down": false]) }
  override func mouseDown(with e: NSEvent) { button(e, "down") }
  override func mouseUp(with e: NSEvent) { button(e, "up") }
  override func rightMouseDown(with e: NSEvent) { button(e, "down") }
  override func rightMouseUp(with e: NSEvent) { button(e, "up") }
  override func scrollWheel(with e: NSEvent) {
    recorder?.write([
      "kind": "scroll", "t": e.timestamp, "dx": e.scrollingDeltaX, "dy": e.scrollingDeltaY,
      "precise": e.hasPreciseScrollingDeltas, "phase": e.phase.rawValue,
      "momentum": e.momentumPhase.rawValue, "inverted": e.isDirectionInvertedFromDevice,
    ])
  }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
    let text = """
      mt-probe is recording.

      1. Pointer: with one finger, move the cursor around inside this window,
         slowly, then at a normal pace, then quickly, for about 30 seconds.
      2. Scroll: with two fingers, scroll up and down, slowly and then faster,
         lifting your fingers between strokes, for about 30 seconds.
      3. Three-finger drag (if it is on): drag across the window with three
         fingers a few times, lifting them at the end of each drag.
      4. Palms: type in this window for a minute as you normally would (the
         text is not recorded, only when keys go down), with your hands
         resting on the trackpad as they do; then move the pointer with one
         finger while the other hand rests, and rest a thumb on the pad.
      5. Close the window.
      """
    (text as NSString).draw(
      at: NSPoint(x: 24, y: 24),
      withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor])
  }
  override var isFlipped: Bool { true }
}

final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let mt: Multitouch
  let devices: [MTDeviceRef]
  var window: NSWindow!
  init(mt: Multitouch, devices: [MTDeviceRef]) {
    self.mt = mt
    self.devices = devices
  }
  func applicationDidFinishLaunching(_ n: Notification) {
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    window = NSWindow(
      contentRect: screen.insetBy(dx: screen.width * 0.08, dy: screen.height * 0.08),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "mt-probe"
    window.contentView = ProbeView()
    window.acceptsMouseMovedEvents = true
    window.delegate = self
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(window.contentView)
    NSApp.activate(ignoringOtherApps: true)
    for d in devices {
      mt.register(d, frameCallback)
      mt.start(d, 0)
    }
  }
  func windowWillClose(_ n: Notification) {
    for d in devices { mt.stop(d) }
    recorder?.close()
    NSApp.terminate(nil)
  }
}

func ioregInt(_ cls: String, _ key: String) -> Int? {
  let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(cls))
  guard service != 0 else { return nil }
  defer { IOObjectRelease(service) }
  let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
    .takeRetainedValue()
  return (value as? NSNumber)?.intValue
}

func modelName() -> String {
  var size = 0
  sysctlbyname("hw.model", nil, &size, nil, 0)
  var buffer = [CChar](repeating: 0, count: size)
  sysctlbyname("hw.model", &buffer, &size, nil, 0)
  return String(cString: buffer)
}

let args = CommandLine.arguments
guard let mt = Multitouch() else {
  FileHandle.standardError.write("mt-probe: MultitouchSupport could not be loaded\n".data(using: .utf8)!)
  exit(1)
}
// MTDeviceIsBuiltIn answers false for the internal trackpad on some
// releases; with no device claiming to be built in, take them all (a MacBook
// without an external trackpad has just the one).
let builtIn: [MTDeviceRef] = {
  let all = mt.devices()
  let flagged = all.filter { mt.isBuiltIn($0) }
  return flagged.isEmpty ? all : flagged
}()

if args.count == 2 && args[1] == "--selftest" {
  print("MultitouchSupport loaded; \(mt.devices().count) device(s), recording \(builtIn.count)")
  print("MTTouch is \(MemoryLayout<MTTouch>.size) bytes (stride \(MemoryLayout<MTTouch>.stride))")
  if let w = ioregInt("AppleMultitouchDevice", "Sensor Surface Width"),
    let h = ioregInt("AppleMultitouchDevice", "Sensor Surface Height")
  {
    print("sensor surface \(Double(w) / 100) x \(Double(h) / 100) mm")
  }
  exit(builtIn.isEmpty ? 1 : 0)
}

guard args.count == 2 else {
  FileHandle.standardError.write("usage: mt-probe <recording.jsonl> | --selftest\n".data(using: .utf8)!)
  exit(2)
}
guard !builtIn.isEmpty else {
  FileHandle.standardError.write("mt-probe: no built-in trackpad\n".data(using: .utf8)!)
  exit(1)
}

do {
  recorder = try Recorder(path: args[1])
} catch {
  FileHandle.standardError.write("mt-probe: \(error.localizedDescription)\n".data(using: .utf8)!)
  exit(1)
}
recorder?.write([
  "kind": "header", "model": modelName(),
  "sensorWidth": ioregInt("AppleMultitouchDevice", "Sensor Surface Width") ?? 0,
  "sensorHeight": ioregInt("AppleMultitouchDevice", "Sensor Surface Height") ?? 0,
  "backingScale": NSScreen.main?.backingScaleFactor ?? 0,
  "screenPoints": [NSScreen.main?.frame.width ?? 0, NSScreen.main?.frame.height ?? 0],
  "uptime": ProcessInfo.processInfo.systemUptime,
])

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate(mt: mt, devices: builtIn)
app.delegate = delegate
app.run()
