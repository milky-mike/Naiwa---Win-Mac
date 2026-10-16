import AppKit
import AVFoundation
import QuartzCore
import Foundation

// Naiwa Desktop Pet for macOS — v4.0 native-quality laugh frames and original audio.
// An AppKit floating panel with a transparent background. No third-party dependencies.

final class PetWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    var isHovered = false

    private let sprite = NSImageView(frame: .zero)
    private var hoverArea: NSTrackingArea?
    private var mouseDownGlobal = NSPoint.zero
    private var windowOriginOnDown = NSPoint.zero
    private var didDrag = false
    private var pendingSingleClick: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        sprite.frame = bounds
        sprite.autoresizingMask = [.width, .height]
        sprite.imageAlignment = .alignBottom
        sprite.imageScaling = .scaleProportionallyUpOrDown
        sprite.wantsLayer = true
        sprite.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(sprite)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    // Forward all interactions to this view, not the NSImageView child.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        if let area = hoverArea { removeTrackingArea(area) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        hoverArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        if let area = hoverArea { addTrackingArea(area) }
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHoverEnter?()
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHoverExit?()
    }
    override func mouseDown(with event: NSEvent) {
        mouseDownGlobal = NSEvent.mouseLocation
        windowOriginOnDown = window?.frame.origin ?? .zero
        didDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let deltaX = NSEvent.mouseLocation.x - mouseDownGlobal.x
        let deltaY = NSEvent.mouseLocation.y - mouseDownGlobal.y
        if hypot(deltaX, deltaY) > 4 { didDrag = true }
        if didDrag {
            window.setFrameOrigin(NSPoint(x: windowOriginOnDown.x + deltaX,
                                          y: windowOriginOnDown.y + deltaY))
        }
    }
    override func mouseUp(with event: NSEvent) {
        if didDrag { return }
        if event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            onDoubleClick?()
        } else {
            // A short delay separates single-clicks from double-clicks.
            pendingSingleClick?.cancel()
            let job = DispatchWorkItem { [weak self] in self?.onSingleClick?() }
            pendingSingleClick = job
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.33, execute: job)
        }
    }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(event) }

    func show(_ image: NSImage?, fade: Bool = true) {
        guard let image = image else { return }
        if fade, sprite.image != nil, let layer = sprite.layer {
            let t = CATransition()
            t.type = .fade
            t.duration = 0.45
            t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(t, forKey: "naiwaFade")
        } else {
            // Never overlay the previous still onto a 30fps video frame.
            // A lingering 0.45-second CATransition looked like a veil/obstruction.
            sprite.layer?.removeAnimation(forKey: "naiwaFade")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.image = image
        CATransaction.commit()
    }
    func floatOffset(_ y: CGFloat) {
        var rect = bounds
        rect.origin.y = y
        sprite.frame = rect
    }
}

final class PetController: NSObject, NSApplicationDelegate {
    private enum Mode { case idle, hover, clicked, laughing }
    private enum BellyBehavior: String { case toggle, auto }
    private var mode: Mode = .idle
    private var panel: PetWindow!
    private var pet: PetView!
    private var statusItem: NSStatusItem!
    private var cycleTimer: Timer?
    private var nextCycleAt: TimeInterval = 0
    private var actuallyHovered = false
    private var bellyTimer: Timer?
    private var animationTimer: Timer?
    private var audio: AVAudioPlayer?
    private var hoverPose = 1
    private var bellyExpanded = false
    private var bellyBehavior: BellyBehavior = .toggle
    private var bellySteps: [Int] = []
    private var bellyStepIndex = 0
    // This records the ACTUAL still displayed; rapid repeated clicks start
    // from the current frame rather than jumping to a hard-coded endpoint.
    private var bellyFrameIndex = 3
    // Last intentional single click. After 10 seconds without another click,
    // automatically return to pose 1 and restart the four-pose cycle.
    private var lastBellyClickAt: TimeInterval?
    private let bellyInactivitySeconds: TimeInterval = 10.0
    private var returnToClickedAfterLaugh = false
    private var animationStartedAt: TimeInterval = 0
    private let frameRate: Double = 30
    private let videoDuration: Double = 14.767664
    private let frameCount = 443
    private var cachedImages: [String: NSImage] = [:]
    private let frameCache = NSCache<NSNumber, NSImage>()
    // Aspect ratio shared by the 960×1107 stills and native 720×830 video.
    private let originalSize = NSSize(width: 320, height: 369)
    private var sizeMultiplier: CGFloat = 0.65
    private var volume: Float = 0.75
    private var muted = false
    private var repeatCount = 3
    private var hoverTick: Int = 0

    private var resDir: URL {
        return Bundle.main.resourceURL!
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = UserDefaults.standard
        let savedSize = prefs.double(forKey: "naiwa.size")
        if savedSize >= 0.55 && savedSize <= 1.5 { sizeMultiplier = CGFloat(savedSize) }
        if prefs.object(forKey: "naiwa.volume") != nil { volume = Float(prefs.double(forKey: "naiwa.volume")) }
        muted = prefs.bool(forKey: "naiwa.muted")
        if let saved = prefs.string(forKey: "naiwa.bellyBehavior"),
           let behavior = BellyBehavior(rawValue: saved) { bellyBehavior = behavior }
        let savedRepeats = prefs.integer(forKey: "naiwa.repeats")
        if [1, 3, 5].contains(savedRepeats) { repeatCount = savedRepeats }
        frameCache.countLimit = 24
        createPanel()
        createStatusMenu()
        showStill(1, fade: false)
        panel.orderFrontRegardless()
        nextCycleAt = ProcessInfo.processInfo.systemUptime + 10.0
        cycleTimer = Timer(timeInterval: 0.08, target: self,
                           selector: #selector(cycleTick), userInfo: nil, repeats: true)
        if let timer = cycleTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func createPanel() {
        let sz = NSSize(width: originalSize.width * sizeMultiplier,
                        height: originalSize.height * sizeMultiplier)
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = NSPoint(x: area.maxX - sz.width - 36, y: area.minY + 38)
        panel = PetWindow(contentRect: NSRect(origin: origin, size: sz),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true

        pet = PetView(frame: NSRect(origin: .zero, size: sz))
        panel.contentView = pet
        pet.onHoverEnter = { [weak self] in self?.refreshHoverState() }
        pet.onHoverExit = { [weak self] in self?.refreshHoverState() }
        pet.onSingleClick = { [weak self] in self?.singleClick() }
        pet.onDoubleClick = { [weak self] in self?.startLaughing() }
        pet.onContextMenu = { [weak self] event in self?.popMenu(with: event) }
    }

    private func stillImage(_ name: String) -> NSImage? {
        if let i = cachedImages[name] { return i }
        guard let image = NSImage(contentsOf: resDir.appendingPathComponent("Stills/\(name).png")) else { return nil }
        cachedImages[name] = image
        return image
    }
    private func showStill(_ number: Int, fade: Bool = true) {
        pet.show(stillImage("pose_\(number)"), fade: fade)
    }
    // A clock which starts as soon as the app launches: pose transitions work even
    // if mouseEntered/Exited events are missed by a borderless nonactivating NSPanel.
    // The transitions are based on system uptime, never reset by tiny hover jitters.
    private func refreshHoverState() {
        // Do not touch nextCycleAt here. Frame changes and floating can cause
        // enter/exit events that otherwise make a 10-second timer never fire.
        let inside = panel.frame.contains(NSEvent.mouseLocation)
        actuallyHovered = inside
        pet.isHovered = inside
    }
    @objc private func cycleTick() {
        let now = ProcessInfo.processInfo.systemUptime
        refreshHoverState()
        if mode == .laughing { return }
        if mode == .clicked {
            // Holding a belly size must be persistent *between* clicks, but
            // after 10s of inactivity go to the FIRST pose (not the next one).
            // This clock is independent of the regular four-pose cycle.
            if let last = lastBellyClickAt, now - last >= bellyInactivitySeconds {
                resumePoseCycle()
            } else {
                pet.floatOffset(0)
                return
            }
        }
        mode = actuallyHovered ? .hover : .idle
        if now >= nextCycleAt {
            // Advance by elapsed wall-clock intervals, even if the main runloop
            // was briefly occupied (e.g., playback or an open menu).
            let advances = max(1, Int((now - nextCycleAt) / 10.0) + 1)
            hoverPose = ((hoverPose - 1 + advances) % 4) + 1
            showStill(hoverPose)
            nextCycleAt += Double(advances) * 10.0
        }
        if actuallyHovered {
            hoverTick += 1
            let offset = sin(Double(hoverTick) * 0.095) * 1.25
            pet.floatOffset(CGFloat(offset))
        } else {
            pet.floatOffset(0)
        }
    }
    private func invalidateHoverTimers() {
        // Cancel only movement. The independent 10-second clock keeps running.
        pet.floatOffset(0)
    }
    private func resumePoseCycle(advance: Bool = false) {
        if mode == .laughing { stopLaughing(restore: false) }
        bellyTimer?.invalidate(); bellyTimer = nil
        bellyExpanded = false
        bellyFrameIndex = 3
        lastBellyClickAt = nil
        bellySteps.removeAll()
        returnToClickedAfterLaugh = false
        mode = actuallyHovered ? .hover : .idle
        hoverPose = advance ? (hoverPose % 4 + 1) : 1
        showStill(hoverPose)
        nextCycleAt = ProcessInfo.processInfo.systemUptime + 10.0
    }
    @objc private func menuNextPose() { resumePoseCycle(advance: true) }
    @objc private func menuResumePoseCycle() { resumePoseCycle() }

    private func singleClick() {
        if mode == .laughing { stopLaughing(restore: false) }
        invalidateHoverTimers()
        bellyTimer?.invalidate(); bellyTimer = nil
        // On the first click, enter the fifth pose with its ORIGINAL-sized belly.
        // On subsequent clicks, continue exactly where the prior animation ended.
        if mode != .clicked {
            bellyFrameIndex = 3
            bellyExpanded = false
            pet.show(stillImage("belly_03") ?? stillImage("pose_5"), fade: true)
        }
        mode = .clicked
        lastBellyClickAt = ProcessInfo.processInfo.systemUptime
        if bellyBehavior == .auto {
            // One click performs a complete pulse and settles back to the
            // ORIGINAL pose_5 belly. All frames come from unchanged assets.
            let ascend = bellyFrameIndex < 8
                ? Array((bellyFrameIndex + 1)...8) : []
            let descend = Array(stride(from: 7, through: 3, by: -1))
            // Hold the fully expanded frame for ~0.15 seconds, matching Windows.
            bellySteps = ascend + [8, 8] + descend
            bellyExpanded = false
        } else {
            bellyExpanded.toggle()
            let target = bellyExpanded ? 8 : 3
            if bellyFrameIndex == target { return }
            let step = target > bellyFrameIndex ? 1 : -1
            bellySteps = Array(stride(from: bellyFrameIndex + step, through: target, by: step))
        }
        bellyStepIndex = 0
        bellyTimer = Timer(timeInterval: 0.075, target: self,
                           selector: #selector(stepBelly), userInfo: nil, repeats: true)
        if let t = bellyTimer { RunLoop.main.add(t, forMode: .common) }
    }
    @objc private func stepBelly() {
        guard bellyStepIndex < bellySteps.count else {
            bellyTimer?.invalidate(); bellyTimer = nil
            return
        }
        let step = bellySteps[bellyStepIndex]
        if let image = stillImage(String(format: "belly_%02d", step)) {
            pet.show(image, fade: false)
        }
        bellyFrameIndex = step
        bellyStepIndex += 1
        // The last frame is deliberately persistent; there is no auto-reverse.
        if bellyStepIndex == bellySteps.count {
            bellyTimer?.invalidate(); bellyTimer = nil
        }
    }

    private func frameImage(_ idx: Int) -> NSImage? {
        let key = NSNumber(value: idx)
        if let i = frameCache.object(forKey: key) { return i }
        let fileName = String(format: "LaughFrames/frame_%03d.png", idx)
        guard let image = NSImage(contentsOf: resDir.appendingPathComponent(fileName)) else { return nil }
        frameCache.setObject(image, forKey: key)
        return image
    }
    private func startLaughing() {
        // Double-click plays 3 complete iterations by default (~44.3 seconds), original soundtrack repeated in sync.
        // Afterwards restore exactly the belly size selected with single-click.
        if mode != .laughing { returnToClickedAfterLaugh = (mode == .clicked) }
        invalidateHoverTimers()
        bellyTimer?.invalidate(); bellyTimer = nil
        stopLaughing(restore: false)
        mode = .laughing
        if let url = Bundle.main.url(forResource: "laugh_original_audio", withExtension: "m4a") {
            do {
                audio = try AVAudioPlayer(contentsOf: url)
                audio?.numberOfLoops = repeatCount - 1
                audio?.volume = muted ? 0 : volume
                audio?.prepareToPlay()
                audio?.play()
            } catch {
                NSLog("Naiwa could not play the source audio: %@", String(describing: error))
            }
        }
        animationStartedAt = ProcessInfo.processInfo.systemUptime
        pet.show(frameImage(0), fade: false)
        animationTimer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(laughTick), userInfo: nil, repeats: true)
        if let t = animationTimer { RunLoop.main.add(t, forMode: .common) }
    }
    @objc private func laughTick() {
        guard mode == .laughing else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - animationStartedAt
        if elapsed >= videoDuration * Double(repeatCount) {
            stopLaughing()
            return
        }
        let local = elapsed.truncatingRemainder(dividingBy: videoDuration)
        let idx = min(frameCount - 1, max(0, Int(local * frameRate)))
        pet.show(frameImage(idx), fade: false)
    }
    private func stopLaughing(restore: Bool = true) {
        animationTimer?.invalidate(); animationTimer = nil
        audio?.stop(); audio = nil
        if restore {
            if returnToClickedAfterLaugh {
                mode = .clicked
                // Pause the inactivity countdown during a laugh; a new full
                // 10-second timeout starts when playback finishes.
                lastBellyClickAt = ProcessInfo.processInfo.systemUptime
                // In auto mode the belly finishes relaxed, even if a double
                // click interrupted the pulse halfway through.
                if bellyBehavior == .auto { bellyFrameIndex = 3; bellyExpanded = false }
                let stillName = String(format: "belly_%02d", bellyFrameIndex)
                pet.show(stillImage(stillName) ?? stillImage("pose_5"), fade: true)
            } else {
                mode = actuallyHovered ? .hover : .idle
                lastBellyClickAt = nil
                hoverPose = 1
                nextCycleAt = ProcessInfo.processInfo.systemUptime + 10.0
                showStill(hoverPose)
            }
        }
    }

    // Status-bar icon and right-click menu provide controls without obscuring the pet.
    private func createStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐸 奶娃"
        statusItem.menu = makeMenu()
    }
    private func menuItem(_ title: String, _ selector: Selector, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }
    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "奶娃桌宠")
        menu.addItem(menuItem("捧腹大笑（带原声）", #selector(menuLaugh)))
        menu.addItem(menuItem("停止动画", #selector(menuStop)))
        menu.addItem(menuItem("立即回到托腮姿势（自动轮换）", #selector(menuResumePoseCycle)))
        menu.addItem(menuItem("立刻切换下一姿势（测试）", #selector(menuNextPose)))
        menu.addItem(NSMenuItem.separator())
        let behaviorMenu = NSMenu()
        for (label, tag, behavior) in [
            ("交替变大 / 变小（默认）", 0, BellyBehavior.toggle),
            ("单击自动变大再缩回", 1, BellyBehavior.auto)
        ] {
            let item = menuItem(label, #selector(menuBellyBehavior(_:)), tag: tag)
            item.state = (bellyBehavior == behavior) ? .on : .off
            behaviorMenu.addItem(item)
        }
        let behaviorItem = NSMenuItem(title: "肚子点击模式", action: nil, keyEquivalent: "")
        behaviorItem.submenu = behaviorMenu
        menu.addItem(behaviorItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(muted ? "🔇 取消静音" : "🔊 静音", #selector(menuMute)))
        let volumeMenu = NSMenu()
        for vol in [25, 50, 75, 100] {
            let item = menuItem("\(vol)%", #selector(menuVolume(_:)), tag: vol)
            if abs(volume * 100 - Float(vol)) < 1 { item.state = .on }
            volumeMenu.addItem(item)
        }
        let volItem = NSMenuItem(title: "音量", action: nil, keyEquivalent: "")
        volItem.submenu = volumeMenu; menu.addItem(volItem)

        let loopMenu = NSMenu()
        for n in [1, 3, 5] {
            let item = menuItem("\(n) 遍（约 \(Int(Double(n) * videoDuration)) 秒）", #selector(menuLoops(_:)), tag: n)
            if repeatCount == n { item.state = .on }
            loopMenu.addItem(item)
        }
        let loopItem = NSMenuItem(title: "双击播放时长", action: nil, keyEquivalent: "")
        loopItem.submenu = loopMenu; menu.addItem(loopItem)

        let sizeMenu = NSMenu()
        for p in [50, 65, 75, 100, 125, 150] {
            let item = menuItem("\(p)%", #selector(menuSize(_:)), tag: p)
            if abs(sizeMultiplier * 100 - CGFloat(p)) < 1 { item.state = .on }
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "桌宠大小", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu; menu.addItem(sizeItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("退出奶娃", #selector(menuQuit)))
        return menu
    }
    private func refreshStatusMenu() { statusItem.menu = makeMenu() }
    private func popMenu(with event: NSEvent) {
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: pet)
    }
    @objc private func menuLaugh() { startLaughing() }
    @objc private func menuStop() { if mode == .laughing { stopLaughing() } }
    @objc private func menuBellyBehavior(_ item: NSMenuItem) {
        bellyBehavior = item.tag == 1 ? .auto : .toggle
        UserDefaults.standard.set(bellyBehavior.rawValue, forKey: "naiwa.bellyBehavior")
        // A mode switch clears a partially played belly pulse so the next
        // click always starts from the same predictable default posture.
        if mode == .clicked { resumePoseCycle() }
        refreshStatusMenu()
    }
    @objc private func menuMute() {
        muted.toggle(); UserDefaults.standard.set(muted, forKey: "naiwa.muted")
        audio?.volume = muted ? 0 : volume
        refreshStatusMenu()
    }
    @objc private func menuVolume(_ item: NSMenuItem) {
        volume = Float(item.tag) / 100.0
        UserDefaults.standard.set(Double(volume), forKey: "naiwa.volume")
        if !muted { audio?.volume = volume }
        refreshStatusMenu()
    }
    @objc private func menuLoops(_ item: NSMenuItem) {
        repeatCount = item.tag
        UserDefaults.standard.set(repeatCount, forKey: "naiwa.repeats")
        refreshStatusMenu()
    }
    @objc private func menuSize(_ item: NSMenuItem) {
        sizeMultiplier = CGFloat(item.tag) / 100
        UserDefaults.standard.set(Double(sizeMultiplier), forKey: "naiwa.size")
        let newSize = NSSize(width: originalSize.width * sizeMultiplier,
                             height: originalSize.height * sizeMultiplier)
        var bounds = panel.frame
        bounds.size = newSize
        panel.setFrame(bounds, display: true, animate: true)
        refreshStatusMenu()
    }
    @objc private func menuQuit() {
        stopLaughing(restore: false)
        NSApp.terminate(nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        cycleTimer?.invalidate(); cycleTimer = nil
        invalidateHoverTimers(); bellyTimer?.invalidate(); stopLaughing(restore: false)
    }
}

let application = NSApplication.shared
let controller = PetController()
application.setActivationPolicy(.accessory) // menu-bar app: no persistent Dock icon
application.delegate = controller
application.run()
