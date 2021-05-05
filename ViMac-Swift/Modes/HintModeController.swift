//
//  HintModeController.swift
//  Vimac
//
//  Created by Dexter Leng on 21/3/21.
//  Copyright © 2021 Dexter Leng. All rights reserved.
//

import Cocoa
import RxSwift
import os
import Segment

extension NSEvent {
    static func localEventMonitor(matching: EventTypeMask) -> Observable<NSEvent> {
        Observable.create({ observer in
            let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: matching, handler: { event -> NSEvent? in
                observer.onNext(event)
                // return nil to prevent the event from being dispatched
                // this removes the "doot doot" sound when typing with CMD / CTRL held down
                return nil
            })!

            let cancel = Disposables.create {
                NSEvent.removeMonitor(keyMonitor)
            }
            return cancel
        })
    }
}

enum HintModeInputIntent {
    case rotate
    case exit
    case backspace
    case advance(by: String, action: HintAction)

    case reload
    case multiple
    case center

    case optionModifier
    case shiftModifier
    case commandModifier
    case controlModifier

    case rightClick
    case leftClick
    case singleClick
    case doubleClick
    case tripleClick

    case drag
    case move

    case showHelp

    static func from(event: NSEvent) -> HintModeInputIntent? {
        if event.type != .keyDown { return nil }
        if event.keyCode == kVK_Escape ||
            (event.keyCode == kVK_ANSI_LeftBracket &&
                event.modifierFlags.rawValue & NSEvent.ModifierFlags.control.rawValue == NSEvent.ModifierFlags.control.rawValue) {
            return .exit
        }
        if event.keyCode == kVK_Delete { return .backspace }
        if event.keyCode == kVK_Tab { return .rotate }

        if event.keyCode == kVK_ANSI_R { return .reload }
        if event.keyCode == kVK_ANSI_U { return .multiple }
        if event.keyCode == kVK_ANSI_Grave { return .center }

        if event.keyCode == kVK_ANSI_Z { return .optionModifier }
        if event.keyCode == kVK_ANSI_Quote { return .shiftModifier }
        if event.keyCode == kVK_ANSI_X { return .commandModifier }
        if event.keyCode == kVK_ANSI_Semicolon { return .controlModifier }

        if event.keyCode == kVK_ANSI_Period { return .rightClick }
        if event.keyCode == kVK_ANSI_Comma { return .leftClick }

        if event.keyCode == kVK_ANSI_1 { return .singleClick }
        if event.keyCode == kVK_ANSI_2 { return .doubleClick }
        if event.keyCode == kVK_ANSI_3 { return .tripleClick }

        if event.keyCode == kVK_ANSI_Backslash { return .drag }
        if event.keyCode == kVK_ANSI_Y { return .move }

        if event.keyCode == kVK_ANSI_Slash { return .showHelp }
        
        if let characters = event.charactersIgnoringModifiers {
            let action: HintAction = {
                if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.shift.rawValue == NSEvent.ModifierFlags.shift.rawValue) {
                    return .rightClick
                } else if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.command.rawValue == NSEvent.ModifierFlags.command.rawValue) {
                    return .doubleLeftClick
                } else if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.option.rawValue == NSEvent.ModifierFlags.option.rawValue) {
                    return .move
                } else {
                    return .leftClick
                }
            }()
            return .advance(by: characters, action: action)
        }

        return nil
    }
}

// a view controller that has a single view controller child that can be swapped out.
class ContentViewController: NSViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func loadView() {
        self.view = NSView()
    }

    func setChildViewController(_ vc: NSViewController) {
        assert(self.children.count <= 1)
        removeChildViewController()

        self.addChild(vc)
        vc.view.frame = self.view.frame
        self.view.addSubview(vc.view)
    }

    func removeChildViewController() {
        guard let childVC = self.children.first else { return }
        childVC.view.removeFromSuperview()
        childVC.removeFromParent()
    }
}

struct Hint {
    let element: Element
    let text: String
    func clickPosition(modifiers: ClickModifiers) -> NSPoint {
        // hints are shown at the bottom-left for AXLinks (see HintsViewController#renderHint),
        // so a click is performed there
        if !modifiers.center && element.role == "AXLink" {
            return NSPoint(
                // tiny offset in case clicking on the edge of the element does nothing
                x: element.frame.origin.x + 5,
                y: element.frame.origin.y + element.frame.height - 5
            )
        }
        return GeometryUtils.center(element.frame)
    }
}

enum HintAction: String {
    case leftClick
    case rightClick
    case doubleLeftClick
    case move
}

class HintModeUserInterface {
    let window: Element?
    let windowController: OverlayWindowController
    let contentViewController: ContentViewController
    var hintsViewController: HintsViewController?

    let textSize = UserPreferences.HintMode.TextSizeProperty.readAsFloat()

    init(window: Element?) {
        self.window = window
        self.windowController = OverlayWindowController()
        self.contentViewController = ContentViewController()
        self.windowController.window?.contentViewController = self.contentViewController

        let _frame = frame()
        self.windowController.fitToFrame(_frame)
    }
    
    func frame() -> NSRect {
        guard let window = window else {
            return NSScreen.main!.frame
        }

        let windowFrame = GeometryUtils.convertAXFrameToGlobal(window.frame)

        // expected: When an active window is fullscreen in a non-primary display, NSScreen.main returns the non-primary display
        // actual: it returns the primary display
        // this is a workaround for that edge case
        let fullscreenScreen = NSScreen.screens.first(where: { $0.frame == windowFrame })
        if let fullscreenScreen = fullscreenScreen {
            return fullscreenScreen.frame
        }
        
        // a window can extend outside the screen it belongs to (NSScreen.main)
        // it is visible in other screens if the "Displays have separate spaces" option is disabled
        return windowFrame.union(NSScreen.main!.frame)
    }

    func show() {
        self.windowController.showWindow(nil)
        self.windowController.window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        self.contentViewController.view.removeFromSuperview()
        self.windowController.window?.contentViewController = nil
        self.windowController.close()
    }

    func setHints(hints: [Hint], modifiers: ClickModifiers) {
        self.hintsViewController = HintsViewController(hints: hints, textSize: CGFloat(textSize), typed: "", modifiers: modifiers)
        self.contentViewController.setChildViewController(self.hintsViewController!)
    }

    func updateInput(input: String) {
        guard let hintsViewController = self.hintsViewController else { return }
        hintsViewController.updateTyped(typed: input)
    }

    func rotateHints() {
        guard let hintsViewController = self.hintsViewController else { return }
        hintsViewController.rotateHints()
    }
}

class ClickModifiers {
    var option = false
    var shift = false
    var command = false
    var control = false

    var clicks = 1
    var right = false
    var drag = false
    var move = false

    var multiple = false
    var center = false
}

class HintModeController: ModeController {
    weak var delegate: ModeControllerDelegate?
    private var activated = false

    var modifiers: ClickModifiers

    private let startTime = CFAbsoluteTimeGetCurrent()
    private let disposeBag = DisposeBag()

    let hintCharacters = UserPreferences.HintMode.CustomCharactersProperty.read()
    
    private var ui: HintModeUserInterface?
    private var input: String?
    private var hints: [Hint]?
    
    let app: NSRunningApplication?
    let window: Element?
    
    init(app: NSRunningApplication?, window: Element?) {
        self.app = app
        self.window = window
        self.modifiers = ClickModifiers()
    }

    func activate() {
        if activated { return }
        activated = true
        
        HideCursorGlobally.hide()
        
        self.input = ""
        self.ui = HintModeUserInterface(window: window)
        self.ui!.show()
        
        self.queryHints(
            onSuccess: { [weak self] hints in
                self?.onHintQuerySuccess(hints: hints)
            },
            onError: { [weak self] e in
                self?.deactivate()
            }
        )
    }
    
    func deactivate() {
        if !activated { return }
        guard let ui = ui else { return }

        activated = false
        
        Analytics.shared().track("Hint Mode Deactivated", properties: [
            "Target Application": self.app?.bundleIdentifier as Any
        ])
        
        HideCursorGlobally.unhide()
        
        ui.hide()
        self.ui = nil
        
        self.delegate?.modeDeactivated(controller: self)
    }
    
    func onHintQuerySuccess(hints: [Hint]) {
        guard let ui = ui else { return }
        
        self.hints = hints
        ui.setHints(hints: hints, modifiers: modifiers)
        
        listenForKeyPress(onEvent: { [weak self] event in
            self?.onKeyPress(event: event)
        })
    }
    
    private func onKeyPress(event: NSEvent) {
        guard let intent = HintModeInputIntent.from(event: event) else { return }

        switch intent {
        case .exit:
            modifiers.multiple = false
            self.deactivate()
        case .rotate:
            guard let ui = ui else { return }
            Analytics.shared().track("Hint Mode Rotated Hints", properties: [
                "Target Application": self.app?.bundleIdentifier as Any
            ])
            ui.rotateHints()

        case .multiple:
            modifiers.multiple = !modifiers.multiple
            os_log("[Hint Mode] Multiple Modifier %@", String(modifiers.multiple))

        case .reload:
            self.deactivate()
            let delegate = NSApplication.shared.delegate as! AppDelegate
            delegate.modeCoordinator.setHintMode(mechanism: "Reload", modifiers: modifiers)
            os_log("[Hint Mode] Reload")

        case .center:
            self.deactivate()
            modifiers.center = !modifiers.center
            let delegate = NSApplication.shared.delegate as! AppDelegate
            delegate.modeCoordinator.setHintMode(mechanism: "Center", modifiers: modifiers)
            os_log("[Hint Mode] Center")

        case .optionModifier:
            modifiers.option = !modifiers.option
            os_log("[Hint Mode] Option Modifier %@", String(modifiers.option))
        case .shiftModifier:
            modifiers.shift = !modifiers.shift
            os_log("[Hint Mode] Shift Modifier %@", String(modifiers.shift))
        case .commandModifier:
            modifiers.command = !modifiers.command
            os_log("[Hint Mode] Command Modifier %@", String(modifiers.command))
        case .controlModifier:
            modifiers.control = !modifiers.control
            os_log("[Hint Mode] Control Modifier %@", String(modifiers.control))

        case .rightClick:
            modifiers.right = true
            modifiers.move = false
            os_log("[Hint Mode] Right Click %@", String(modifiers.right))
        case .leftClick:
            modifiers.right = false
            modifiers.move = false
            os_log("[Hint Mode] Left Click %@", String(!modifiers.right))
        case .singleClick:
            modifiers.clicks = 1
            os_log("[Hint Mode] Single Click")
        case .doubleClick:
            modifiers.clicks = 2
            os_log("[Hint Mode] Double Click")
        case .tripleClick:
            modifiers.clicks = 3
            os_log("[Hint Mode] Triple Click")

        case .drag:
            modifiers.drag = !modifiers.drag
            os_log("[Hint Mode] Drag %@", String(modifiers.drag))

        case .move:
            modifiers.move = !modifiers.move
            os_log("[Hint Mode] Move %@", String(modifiers.move))

        case .showHelp:
            os_log("[Hint Mode] Show Help")

        case .backspace:
            guard let ui = ui,
                  let _ = input else { return }
            _ = self.input!.popLast()
            ui.updateInput(input: self.input!)
        case .advance(let by, let action):
            guard let ui = ui,
                  let input = input,
                  let hints = hints else { return }
            
            let newInput = input + by
            self.input = newInput

            let hintsWithInputAsPrefix = hints.filter { $0.text.starts(with: newInput.uppercased()) }

            if hintsWithInputAsPrefix.count == 0 {
                Analytics.shared().track("Hint Mode Deadend", properties: [
                    "Target Application": app?.bundleIdentifier as Any
                ])
                self.deactivate()
                return
            }

            let matchingHint = hintsWithInputAsPrefix.first(where: { $0.text == newInput.uppercased() })

            if let matchingHint = matchingHint {
                Analytics.shared().track("Hint Mode Action Performed", properties: [
                    "Target Application": app?.bundleIdentifier as Any,
                    "Hint Action": action.rawValue
                ])
                
                self.deactivate()
                performHintAction(matchingHint, action: action)

                if modifiers.multiple {
                    let delegate = NSApplication.shared.delegate as! AppDelegate
                    delegate.modeCoordinator.setHintMode(mechanism: "Multiple", modifiers: modifiers)
                }
                return
            }

            ui.updateInput(input: newInput)
        }
    }
    
    private func queryHints(onSuccess: @escaping ([Hint]) -> Void, onError: @escaping (Error) -> Void) {
        HintModeQueryService.init(app: app, window: window, hintCharacters: hintCharacters).perform()
            .toArray()
            .observeOn(MainScheduler.instance)
            .do(onSuccess: { _ in self.logQueryTime() })
            .do(onError: { e in self.logError(e) })
            .subscribe(
                onSuccess: { onSuccess($0) },
                onError: { onError($0) }
            )
            .disposed(by: disposeBag)
    }

    private func listenForKeyPress(onEvent: @escaping (NSEvent) -> Void) {
        NSEvent.localEventMonitor(matching: .keyDown)
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { event in
                onEvent(event)
            })
            .disposed(by: disposeBag)
    }
    
    private func performHintAction(_ hint: Hint, action: HintAction) {
        let clickPosition = hint.clickPosition(modifiers: modifiers)

        Utils.moveMouse(position: clickPosition)

        switch action {
        case .leftClick:
            Utils.leftClickMouse(position: clickPosition)
        case .rightClick:
            Utils.rightClickMouse(position: clickPosition)
        case .doubleLeftClick:
            Utils.doubleLeftClickMouse(position: clickPosition)
        case .move:
            Utils.moveMouse(position: clickPosition)
        }
    }
    
    private func logQueryTime() {
        let timeElapsed = CFAbsoluteTimeGetCurrent() - self.startTime
        os_log("[Hint mode] query time: %@", log: Log.accessibility, String(describing: timeElapsed))
    }

    private func logError(_ e: Error) {
        os_log("[Hint mode] query error: %@", log: Log.accessibility, String(describing: e))
    }
}
