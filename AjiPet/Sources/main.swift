import AppKit

enum Mood { case walking, sitting, sleeping, happy }

final class PetView: NSView {
    weak var owner: PetController?
    var frames: [NSImage] = []
    var dragStart = NSPoint.zero
    var originStart = NSPoint.zero
    var dragged = false

    override func draw(_ dirtyRect: NSRect) {
        guard let pet = owner, frames.count == 4 else { return }
        let index: Int
        switch pet.mood {
        case .walking: index = Int(pet.elapsed * 5) % 2
        case .sleeping: index = 3
        default: index = 2
        }
        let bounce = pet.mood == .walking ? abs(sin(pet.elapsed * 10)) * 3 : sin(pet.elapsed * 2) * 1.2
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        if pet.direction < 0 && pet.mood == .walking {
            transform.translateX(by: bounds.width, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
        }
        transform.concat()
        frames[index].draw(in: NSRect(x: 10, y: 4 + bounce, width: bounds.width - 20, height: bounds.height - 44), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        if pet.mood == .happy || pet.mood == .sleeping {
            let label = pet.mood == .happy ? "♥" : "z Z"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: pet.mood == .happy ? NSColor.systemPink : NSColor.secondaryLabelColor]
            label.draw(at: NSPoint(x: bounds.midX - 14, y: bounds.height - 34), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        originStart = window?.frame.origin ?? .zero
        dragged = false
        owner?.isDragging = true
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if hypot(point.x - dragStart.x, point.y - dragStart.y) > 3 { dragged = true }
        window?.setFrameOrigin(NSPoint(x: originStart.x + point.x - dragStart.x, y: originStart.y + point.y - dragStart.y))
    }
    override func mouseUp(with event: NSEvent) {
        owner?.isDragging = false
        owner?.keepOnScreen()
        if !dragged { owner?.react() }
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = owner?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class PetController: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var petView: PetView!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var mood = Mood.sitting
    var direction: CGFloat = 1
    var elapsed = 0.0
    var remaining = 4.0
    var isDragging = false
    var paused = false
    var lastTick = ProcessInfo.processInfo.systemUptime

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch brings the existing pet forward instead of duplicating it.
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: "local.aji.desktop-pet")
        if peers.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 194), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        petView = PetView(frame: NSRect(origin: .zero, size: panel.frame.size))
        petView.owner = self
        guard let url = Bundle.main.url(forResource: "pet-sheet", withExtension: "png"),
              let source = NSImage(contentsOf: url),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let alert = NSAlert(); alert.messageText = "강아지 이미지를 불러오지 못했어요."; alert.runModal(); NSApp.terminate(nil); return
        }
        for index in 0..<4 {
            let rect = CGRect(x: (index % 2) * cg.width / 2, y: (index / 2) * cg.height / 2, width: cg.width / 2, height: cg.height / 2)
            guard let frame = cg.cropping(to: rect) else { NSApp.terminate(nil); return }
            petView.frames.append(NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height)))
        }
        panel.contentView = petView
        resetPosition()
        panel.orderFrontRegardless()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Aji Pet")
        statusItem.menu = makeMenu()
        let tick = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let report = "frames=\(self.petView.frames.count) visible=\(self.panel.isVisible) timer=\(self.timer?.isValid == true)\n"
                try? report.write(toFile: "/private/tmp/aji-pet-smoke.txt", atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
    }

    func update() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        guard !isDragging, panel.isVisible else { return }
        elapsed += dt
        if !paused {
            remaining -= dt
            if remaining <= 0 {
                switch mood {
                case .walking: mood = Bool.random() ? .sitting : .sleeping; remaining = Double.random(in: 5...12)
                default: mood = .walking; direction = Bool.random() ? 1 : -1; remaining = Double.random(in: 7...15)
                }
            }
            if mood == .walking {
                var origin = panel.frame.origin
                origin.x += direction * CGFloat(dt) * 32
                let frame = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
                let maxX = max(frame.minX, frame.maxX - panel.frame.width)
                if origin.x < frame.minX { origin.x = frame.minX; direction = 1 }
                if origin.x > maxX { origin.x = maxX; direction = -1 }
                panel.setFrameOrigin(origin)
            }
        }
        petView.needsDisplay = true
    }
    func keepOnScreen() {
        let frame = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let p = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: min(max(p.x, frame.minX), max(frame.minX, frame.maxX - panel.frame.width)), y: min(max(p.y, frame.minY), max(frame.minY, frame.maxY - panel.frame.height))))
    }
    @objc func screenChanged() { keepOnScreen() }
    @objc func react() { mood = .happy; remaining = 3; petView.needsDisplay = true }
    @objc func sleepPet() { mood = .sleeping; remaining = 25 }
    @objc func walkPet() { paused = false; mood = .walking; remaining = 15; refreshMenu() }
    @objc func togglePause() { paused.toggle(); if paused { mood = .sitting }; refreshMenu() }
    @objc func toggleVisible() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }; refreshMenu() }
    @objc func resetPosition() {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 8))
    }
    @objc func resizePet(_ sender: NSMenuItem) {
        let width = CGFloat(sender.tag)
        panel.setContentSize(NSSize(width: width, height: width + 14))
        petView.frame = NSRect(origin: .zero, size: panel.frame.size)
        keepOnScreen()
    }
    @objc func quit() { NSApp.terminate(nil) }
    func refreshMenu() { statusItem.menu = makeMenu() }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Aji Pet · 나의 작은 친구", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        menu.addItem(.separator())
        func add(_ text: String, _ action: Selector) { let item = NSMenuItem(title: text, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
        add("쓰다듬기 ♡", #selector(react))
        add("산책하기", #selector(walkPet))
        add("낮잠 자기", #selector(sleepPet))
        add(paused ? "움직임 재개" : "움직임 일시정지", #selector(togglePause))
        let sizeItem = NSMenuItem(title: "크기", action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for (label, width) in [("작게", 130), ("보통", 180), ("크게", 240)] { let item = NSMenuItem(title: label, action: #selector(resizePet(_:)), keyEquivalent: ""); item.tag = width; item.target = self; sizes.addItem(item) }
        sizeItem.submenu = sizes; menu.addItem(sizeItem)
        add("화면 아래로 데려오기", #selector(resetPosition))
        add(panel?.isVisible == true ? "숨기기" : "다시 보기", #selector(toggleVisible))
        menu.addItem(.separator())
        add("종료", #selector(quit))
        return menu
    }
}

let app = NSApplication.shared
let delegate = PetController()
app.delegate = delegate
app.run()
