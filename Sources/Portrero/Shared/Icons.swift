import AppKit
import SwiftUI

/// A browser's icon; for profiles, the profile avatar with the browser badged in the corner
/// (the way Chrome's own profile picker presents them).
struct BrowserIcon: View {
    let browser: Browser
    var size: CGFloat = 32

    var body: some View {
        if let avatar = browser.avatar {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatar(avatar: avatar, size: size * 0.86)
                    .frame(width: size, height: size, alignment: .topLeading)
                Image(nsImage: browser.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
            }
            .frame(width: size, height: size)
        } else {
            Image(nsImage: browser.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        }
    }
}

struct ProfileAvatar: View {
    let avatar: Browser.Avatar
    let size: CGFloat

    var body: some View {
        Group {
            if let image = avatar.image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                ZStack {
                    Color(nsColor: avatar.color).brightness(0.08)
                    Text(avatar.initial)
                        .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
    }
}

struct AppIcon: View {
    let image: NSImage
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Small icons for menus. SwiftUI menus draw images at their natural size, so they must be pre-sized.
@MainActor
enum MenuIcons {
    private static var cache: [String: NSImage] = [:]

    static func browser(_ browser: Browser) -> NSImage {
        cached("browser:\(browser.id)") {
            let renderer = ImageRenderer(content: BrowserIcon(browser: browser, size: 16))
            renderer.scale = 2
            return renderer.nsImage
        }
    }

    static func app(_ app: AppInfo) -> NSImage {
        cached("app:\(app.id)") { resized(app.icon) }
    }

    static func resized(_ image: NSImage, to size: CGFloat = 16) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }

    private static func cached(_ key: String, make: () -> NSImage?) -> NSImage {
        if let image = cache[key] { return image }
        let image = make() ?? NSImage()
        cache[key] = image
        return image
    }
}
