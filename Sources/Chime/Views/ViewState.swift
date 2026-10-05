import SwiftUI

/// SwiftUI's `State` property wrapper under another name.
///
/// In the macOS 27 SDK `@State` is a macro whose compiler plugin ships only
/// with Xcode, so views that spell it `@State` do not build with the Command
/// Line Tools alone. This name always resolves to the property wrapper.
typealias ViewState = State
