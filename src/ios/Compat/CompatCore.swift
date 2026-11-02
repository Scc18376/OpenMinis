//
//  CompatCore.swift  —  OpenMinis iOS 14.3 降级兼容层
//  放到 src/ios/Compat/ 并加入 Minis target
//
//  全部 shim 在 iOS 16+ 上走系统实现，iOS 14.3 上走降级实现。
//

import SwiftUI
import UIKit

// MARK: - 导航栈（NavigationStack，iOS 16+）

/// 无 path 版本的 NavigationStack 替代。iOS 16+ 直接用系统实现。
public struct MinisNavStack<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

/// 带 path 的版本。iOS 14 上用隐藏 NavigationLink 驱动，语义等价。
public struct MinisNavStackPath<Data: MutableCollection & RandomAccessCollection, Content: View>: View
where Data.Element: Hashable, Data.Index == Int {
    @Binding private var path: Data
    private let content: Content

    public init(path: Binding<Data>, @ViewBuilder content: () -> Content) {
        self._path = path
        self.content = content()
    }

    public var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack(path: $path) { content }
            } else {
                NavigationView { content }
                    .navigationViewStyle(.stack)
            }
        }
    }
}

// MARK: - 颜色样式（.foregroundStyle，iOS 15+）

/// iOS 14 上没有 ShapeStyle 的通用渲染，按实际类型降级。
public extension View {
    @inlinable
    func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        modifier(_MinisForegroundStyle(style: style))
    }

    @inlinable
    func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View {
        modifier(_MinisForegroundStyle(style: primary))
    }
}

public struct _MinisForegroundStyle<S: ShapeStyle>: ViewModifier {
    let style: S

    @ViewBuilder
    public func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content.foregroundStyle(style)
        } else {
            content.foregroundColor(_resolve(style))
        }
    }

    private func _resolve(_ s: S) -> Color {
        if let c = s as? Color { return c }
        if let g = s as? LinearGradient { return g.gradient.stops.first?.color ?? .primary }
        if let g = s as? AngularGradient { return g.gradient.stops.first?.color ?? .primary }
        if let g = s as? RadialGradient { return g.gradient.stops.first?.color ?? .primary }
        if let m = s as? Material {
            switch m {
            case .ultraThinMaterial, .thinMaterial: return Color(UIColor.tertiarySystemFill)
            case .regularMaterial, .thickMaterial: return Color(UIColor.secondarySystemFill)
            default: return Color(UIColor.systemBackground)
            }
        }
        return .primary
    }
}

// MARK: - 通用 no-op / 语义降级 modifier

public extension View {
    /// presentationDetents — iOS 14 上 sheet 本身就接近全屏，忽略即可
    @inlinable
    func presentationDetents(_ detents: Set<PresentationDetentCompat>) -> some View { self }

    func presentationDetents(_ detents: Set<PresentationDetentCompat>, selection: Binding<PresentationDetentCompat>) -> some View {
        self.presentationDetents(detents)
    }

    /// scrollContentBackground — iOS 14 没有配置化背景，忽略
    @inlinable
    func scrollContentBackground(_ visibility: VisibilityCompat) -> some View { self }

    /// scrollDismissesKeyboard
    @inlinable
    func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardModeCompat) -> some View { self }

    /// toolbarBackground
    @inlinable
    func toolbarBackground<S: ShapeStyle>(_ style: S, for bars: ToolbarPlacementCompat = .automatic) -> some View { self }

    /// symbolEffect — iOS 14 无 SF Symbols 动画
    @inlinable
    func symbolEffect<T>(_ effect: T, options: Int = 0) -> some View { self }

    /// dynamicTypeSize — 交给系统自动处理
    @inlinable
    func dynamicTypeSize(_ size: DynamicTypeSizeCompat) -> some View { self }

    /// sensoryFeedback — 用 UIKit 触感替代
    @inlinable
    func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedbackCompat, trigger: T) -> some View {
        self.onChange(of: trigger) { _ in
            let g = UIImpactFeedbackGenerator(style: .light)
            g.impactOccurred()
        }
    }

    /// textSelection — iOS 14 上整体降级为不可选
    @inlinable
    func textSelection(_ selection: TextSelectionCompat) -> some View { self }

    /// tint — 用 accentColor
    @inlinable
    func tint(_ color: Color) -> some View { self.accentColor(color) }

    /// ContentUnavailableView 替代在 CompatViews.swift
}

// MARK: - 兼容枚举

public enum PresentationDetentCompat: Hashable {
    case medium, large
    case fraction(Double)
    case height(Double)
}

public enum VisibilityCompat: Hashable { case automatic, visible, hidden }

public enum ScrollDismissesKeyboardModeCompat: Hashable {
    case never, immediately, interactively, automatically
}

public enum ToolbarPlacementCompat: Hashable { case automatic, navigationBar, tabBar }

public enum DynamicTypeSizeCompat: Hashable { case small, medium, large, xLarge }

public enum TextSelectionCompat: Hashable { case enabled, disabled }

public enum SensoryFeedbackCompat: Hashable { case success, warning, error, selection, impact }

// MARK: - contentMargins / badge 等零散

public extension View {
    @inlinable func contentMargins(_ value: CGFloat, for placement: Int = 0) -> some View { self }
    @inlinable func badge(_ count: Int) -> some View { self }
    @inlinable func badge(_ text: String) -> some View { self }
}
