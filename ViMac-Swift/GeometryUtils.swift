//
//  GeometryUtils.swift
//  Vimac
//
//  Created by Dexter Leng on 20/2/21.
//  Copyright © 2021 Dexter Leng. All rights reserved.
//

import Cocoa

class GeometryUtils {
    static func center(_ frame: NSRect) -> NSPoint {
        NSPoint(
            x: frame.origin.x + (frame.size.width / 2),
            y: frame.origin.y + (frame.size.height / 2)
        )
    }
    
    static func corner(_ frame: NSRect, top: Bool, right: Bool, offset: CGFloat) -> NSPoint {
        var x = CGFloat(0)
        var y = CGFloat(0)
        
        var xOffset = CGFloat(0)
        var yOffset = CGFloat(0)
        
        if offset < frame.width {
            xOffset = offset
        }
        else {
            xOffset = CGFloat(0)
        }
        
        if offset < frame.height {
            yOffset = offset
        }
        else {
            yOffset = CGFloat(0)
        }
        
        if right {
            x = frame.maxX - xOffset
        }
        else {
            x = frame.origin.x + xOffset
        }
        
        if top {
            y = frame.maxY - yOffset
        }
        else {
            y = frame.origin.y + yOffset
        }
        
        return NSPoint(x: x, y: y)
    }
    
    static func convertGlobalFrame(_ globalFrame: NSRect, relativeTo: NSPoint) -> NSRect {
        let menuBarScreen = NSScreen.screens.first!
        let screenFrame = GeometryUtils.screensFrame() // menuBarScreen.frame

        let origin = changeOrigin(globalFrame.origin, fromOrigin: screenFrame.origin, toOrigin: relativeTo)
        return NSRect(origin: origin, size: globalFrame.size)
    }

    static func convertAXFrameToGlobal(_ axFrame: NSRect) -> NSRect {

        // uninvert the y-axis
        let topLeftRelativeToTopLeftMenuBar: NSPoint = NSPoint(
            x: axFrame.origin.x,
            y: -axFrame.origin.y
        )

        let menuBarScreen = NSScreen.screens.first!
        let menuBarScreenFrame = menuBarScreen.frame

        let screensFrame = GeometryUtils.screensFrame() // menuBarScreen.frame
        
        let topLeftMenuBarPosition = NSPoint(x: menuBarScreenFrame.origin.x, y: menuBarScreenFrame.origin.y + menuBarScreenFrame.height)
        let topLeftRelativeToGlobalOrigin = changeOrigin(topLeftRelativeToTopLeftMenuBar,
                                                         fromOrigin: topLeftMenuBarPosition,
                                                         toOrigin: screensFrame.origin)

        let bottomLeftRelativeToGlobalOrigin = NSPoint(
            x: topLeftRelativeToGlobalOrigin.x,
            y: topLeftRelativeToGlobalOrigin.y - axFrame.height
        )
        
        return NSRect(origin: bottomLeftRelativeToGlobalOrigin, size: axFrame.size)
    }
    
    static func changeOrigin(_ point: NSPoint, fromOrigin: NSPoint, toOrigin: NSPoint) -> NSPoint {
        let deltaX = toOrigin.x - fromOrigin.x
        let deltaY = toOrigin.y - fromOrigin.y
        let x = point.x - deltaX
        let y = point.y - deltaY
        return NSPoint(x: x, y: y)
    }

    static func screensFrame() -> NSRect {
        var screensFrame = NSRect()
        for screen in NSScreen.screens {
            screensFrame = screensFrame.union(screen.frame)
        }
        return screensFrame
    }
}
