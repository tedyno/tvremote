import SwiftUI

/// A button that mirrors the web client's tap / long-press / press-and-hold
/// behaviour:
/// - tap mode: fires `action` on release if the finger didn't move far (a swipe
///   that starts on the button is ignored) and no long-press fired.
/// - long press: if `onLongPress` is set, fires after `longPressDuration` and
///   suppresses the tap (used to toggle favorites).
/// - hold mode (`holdable`): fires `holdBegin` on touch down and `holdEnd` on
///   release, so the TV ramps its own key repeat.
struct PressableButton<Content: View>: View {
    var holdable = false
    var longPressDuration: Double = 0.5
    var action: () -> Void = {}
    var holdBegin: () -> Void = {}
    var holdEnd: () -> Void = {}
    var onLongPress: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @State private var pressing = false
    @State private var holding = false
    @State private var moved = false
    @State private var didLong = false
    @State private var longPressTask: Task<Void, Never>?

    private let moveTolerance: CGFloat = 14

    var body: some View {
        content()
            .scaleEffect(pressing ? 0.93 : 1)
            .brightness(pressing ? 0.06 : 0)
            .animation(.easeOut(duration: 0.1), value: pressing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressing {
                            pressing = true
                            moved = false
                            didLong = false
                            if holdable {
                                holding = true
                                holdBegin()
                            }
                            startLongPressIfNeeded()
                        }
                        if abs(value.translation.width) > moveTolerance
                            || abs(value.translation.height) > moveTolerance {
                            moved = true
                            cancelLongPress()
                            if !holdable { pressing = false }
                        }
                    }
                    .onEnded { _ in
                        pressing = false
                        cancelLongPress()
                        if holdable {
                            if holding { holding = false; holdEnd() }
                        } else if !moved && !didLong {
                            action()
                        }
                    }
            )
    }

    private func startLongPressIfNeeded() {
        guard let onLongPress else { return }
        longPressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(longPressDuration * 1_000_000_000))
            guard !Task.isCancelled, pressing, !moved else { return }
            didLong = true
            Haptics.light()
            onLongPress()
        }
    }

    private func cancelLongPress() {
        longPressTask?.cancel()
        longPressTask = nil
    }
}
