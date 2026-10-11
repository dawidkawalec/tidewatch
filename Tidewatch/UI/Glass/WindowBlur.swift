import AppKit
import Darwin

/// The window server's blur behind a window, with a radius of our choosing: the same call iTerm and
/// Terminal use for blurred transparent windows. It blurs only behind the window's visible pixels,
/// so the glass shapes get a light blur and the transparent canvas around them stays clear (the
/// owner's call, 2026-10-11: Liquid Glass and the system materials blur too much to read
/// anything behind them, and their radius cannot be set). Looked up at run time: if a macOS
/// update removes it, the glass simply has no blur.
enum WindowBlur {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetBlurRadius = @convention(c) (Int32, Int32, Int32) -> Int32

    @discardableResult
    static func set(_ radius: Int, on window: NSWindow) -> Bool {
        guard window.windowNumber > 0,
              let connectionSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSDefaultConnectionForThread"),
              let blurSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetWindowBackgroundBlurRadius") else {
            return false
        }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        let setRadius = unsafeBitCast(blurSymbol, to: SetBlurRadius.self)
        return setRadius(connection, Int32(window.windowNumber), Int32(radius)) == 0
    }
}
