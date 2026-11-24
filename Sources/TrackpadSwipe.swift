import Foundation

struct TrackpadContact {
    let id: Int32
    let x: Float
    let y: Float
}

struct ThreeFingerSwipe {
    private var start: (contacts: [TrackpadContact], time: Double)?
    private var qualifies = false
    private var ignoreUntilLift = false

    mutating func update(_ contacts: [TrackpadContact], time: Double) -> Bool {
        if contacts.count > 3 {
            ignoreUntilLift = true
        }
        if contacts.count < 3 {
            let recognized = qualifies && !ignoreUntilLift
            let finishing = start != nil
            start = nil
            qualifies = false
            ignoreUntilLift = !contacts.isEmpty && (ignoreUntilLift || finishing)
            return recognized
        }
        guard !ignoreUntilLift else { return false }
        guard let start else {
            self.start = (contacts, time)
            return false
        }

        let duration = time - start.time
        guard duration <= 0.9 else {
            qualifies = false
            ignoreUntilLift = true
            return false
        }
        guard duration >= 0.055 else { return false }

        var up: Float = 0
        for contact in contacts {
            guard let initial = start.contacts.first(where: { $0.id == contact.id }) else {
                qualifies = false
                ignoreUntilLift = true
                return false
            }
            let vertical = contact.y - initial.y
            guard vertical >= 0.065, abs(contact.x - initial.x) <= vertical * 0.7 else {
                qualifies = false
                return false
            }
            up += vertical
        }
        qualifies = up >= 0.36
        return false
    }
}

final class TrackpadSwipe {
    static let shared = TrackpadSwipe()

    private typealias FrameCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32
    ) -> Void
    private typealias CreateDevice = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias DeviceAction = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias StartDevice = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    private typealias ReleaseDevice = @convention(c) (UnsafeMutableRawPointer) -> Void
    private typealias SetCallback = @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void

    private struct MultitouchAPI {
        let create: CreateDevice
        let start: StartDevice
        let stop: DeviceAction
        let release: ReleaseDevice
        let register: SetCallback
        let unregister: SetCallback
    }

    private lazy var api: MultitouchAPI? = {
        let framework = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let library = dlopen(framework, RTLD_NOW | RTLD_LOCAL) else { return nil }
        func load<T>(_ name: String) -> T? {
            dlsym(library, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let create: CreateDevice = load("MTDeviceCreateDefault"),
              let start: StartDevice = load("MTDeviceStart"),
              let stop: DeviceAction = load("MTDeviceStop"),
              let release: ReleaseDevice = load("MTDeviceRelease"),
              let register: SetCallback = load("MTRegisterContactFrameCallback"),
              let unregister: SetCallback = load("MTUnregisterContactFrameCallback") else {
            dlclose(library)
            return nil
        }
        return MultitouchAPI(create: create, start: start, stop: stop, release: release,
                             register: register, unregister: unregister)
    }()

    private static let callback: FrameCallback = { _, data, count, time, _ in
        shared.receive(data, count: Int(count), time: time)
    }

    private let lock = NSLock()
    private var device: UnsafeMutableRawPointer?
    private var handler: (() -> Void)?
    private var generation = 0
    private var recognizer = ThreeFingerSwipe()

    private init() {}

    func start(onSwipe: @escaping () -> Void) -> Bool {
        if device != nil { return true }
        guard let api, let device = api.create() else { return false }
        self.device = device
        lock.withLock {
            handler = onSwipe
            recognizer = ThreeFingerSwipe()
            generation += 1
        }
        api.register(device, Self.callback)
        guard api.start(device, 0) == 0 else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        guard let device, let api else { return }
        self.device = nil
        lock.withLock {
            handler = nil
            generation += 1
        }
        api.unregister(device, Self.callback)
        _ = api.stop(device)
        api.release(device)
    }

    private func receive(_ data: UnsafeRawPointer?, count: Int, time: Double) {
        guard (0...16).contains(count), count == 0 || data != nil else { return }
        var contacts: [TrackpadContact] = []
        if let data {
            // The 64-bit MTTouch record is 96 bytes. Read only its ID, state and
            // normalized coordinates. See OpenMTInternal.h in OpenMultitouchSupport.
            for index in 0..<count {
                let record = data.advanced(by: index * 96)
                let state = record.load(fromByteOffset: 20, as: Int32.self)
                guard state == 3 || state == 4 else { continue }
                let id = record.load(fromByteOffset: 16, as: Int32.self)
                let x = record.load(fromByteOffset: 32, as: Float.self)
                let y = record.load(fromByteOffset: 36, as: Float.self)
                contacts.append(TrackpadContact(id: id, x: x, y: y))
            }
        }
        let swipeGeneration: Int? = lock.withLock {
            guard handler != nil, recognizer.update(contacts, time: time) else { return nil }
            return generation
        }
        guard let swipeGeneration else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let handler = self.lock.withLock { self.generation == swipeGeneration ? self.handler : nil }
            handler?()
        }
    }
}
