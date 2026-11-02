//
//  CompatViews.swift  —  视图 / API backport
//

import SwiftUI
import UIKit

// MARK: - AsyncImage (iOS 15+)

public struct MinisAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhaseCompat) -> Content
    @StateObject private var loader = _ImageLoader()

    public init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhaseCompat) -> Content) {
        self.url = url
        self.content = content
    }

    public init(url: URL?, scale: CGFloat = 1) where Content == AnyView {
        self.url = url
        self.content = { phase in
            AnyView(
                Group {
                    if let img = phase.image {
                        img.resizable().scaledToFit()
                    } else if phase.error != nil {
                        Color.clear
                    } else {
                        ProgressView()
                    }
                }
            )
        }
    }

    public var body: some View {
        content(loader.phase)
            .onAppear { loader.load(url) }
            .onChange(of: url) { _ in loader.load(url) }
    }
}

public enum AsyncImagePhaseCompat {
    case empty, success(Image), failure(Error)
    public var image: Image? { if case .success(let i) = self { return i }; return nil }
    public var error: Error? { if case .failure(let e) = self { return e }; return nil }
}

final class _ImageLoader: ObservableObject {
    @Published var phase: AsyncImagePhaseCompat = .empty
    private var task: URLSessionDataTask?
    private var current: URL?

    func load(_ url: URL?) {
        guard let url else { phase = .empty; return }
        if current == url, case .success = phase { return }
        current = url
        task?.cancel()
        phase = .empty
        task = URLSession.shared.dataTask(with: url) { data, _, err in
            DispatchQueue.main.async {
                if let d = data, let ui = UIImage(data: d) {
                    self.phase = .success(Image(uiImage: ui))
                } else {
                    self.phase = .failure(err ?? URLError(.badServerResponse))
                }
            }
        }
        task?.resume()
    }
}

// MARK: - ContentUnavailableView (iOS 17+)

public struct MinisContentUnavailableView: View {
    let title: String
    let systemImage: String?
    let description: String?

    public init(_ title: String, systemImage: String? = nil, description: String? = nil) {
        self.title = title; self.systemImage = systemImage; self.description = description
    }

    public init(_ title: String, systemImage: String, description: Text) {
        self.init(title, systemImage: systemImage, description: description.stringBody)
    }

    public var body: some View {
        VStack(spacing: 10) {
            if let s = systemImage {
                Image(systemName: s).font(.system(size: 44)).foregroundColor(.secondary)
            }
            Text(title).font(.headline)
            if let d = description {
                Text(d).font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension Text {
    var stringBody: String {
        // Text 无法反查内容，调用点必须传字符串；这里给空串兜底
        ""
    }
}

// MARK: - ShareLink (iOS 16+)

public struct MinisShareLink<Label: View>: View {
    let items: [Any]
    let label: Label

    public init(items: [Any], @ViewBuilder label: () -> Label) {
        self.items = items; self.label = label()
    }

    public init(item: URL, @ViewBuilder label: () -> Label) {
        self.items = [item]; self.label = label()
    }

    public init(_ title: String, item: URL) where Label == Text {
        self.items = [item]; self.label = Text(title)
    }

    public var body: some View {
        Button { _present(items) } label: { label }
    }

    private func _present(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        av.popoverPresentationController?.sourceView = root.view
        var top = root
        while let p = top.presentedViewController { top = p }
        top.present(av, animated: true)
    }
}

// MARK: - Text.bold() (iOS 16+)

public extension Text {
    func bold() -> Text { self.fontWeight(.bold) }
}

// MARK: - .task (iOS 15+)

public extension View {
    @inlinable
    func task(priority: TaskPriority = .userInitiated, _ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(_MinisTaskModifier(priority: priority, action: action))
    }
}

struct _MinisTaskModifier: ViewModifier {
    let priority: TaskPriority
    let action: @Sendable () async -> Void
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if task == nil {
                    task = Task(priority: priority) { await action() }
                }
            }
            .onDisappear { task?.cancel(); task = nil }
    }
}

// MARK: - .refreshable (iOS 15+)

public extension View {
    @inlinable
    func refreshable(action: @escaping @Sendable () async -> Void) -> some View { self }
}

// MARK: - swipeActions (iOS 15+)

public extension View {
    @inlinable
    func swipeActions<T: View>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true,
                               @ViewBuilder content: () -> T) -> some View { self }
}

// MARK: - searchable (iOS 15+)

public extension View {
    @inlinable
    func searchable(text: Binding<String>, placement: SearchFieldPlacementCompat = .automatic,
                    prompt: String? = nil) -> some View { self }
}

public enum SearchFieldPlacementCompat: Hashable { case automatic, navigationBarDrawer }

// MARK: - confirmationDialog (iOS 15+)

public extension View {
    func confirmationDialog<A: View>(_ title: String, isPresented: Binding<Bool>,
                                     titleVisibility: VisibilityCompat = .automatic,
                                     @ViewBuilder actions: () -> A) -> some View {
        actionSheet(isPresented: isPresented) {
            ActionSheet(title: Text(title), buttons: [.cancel()])
        }
    }
}

// MARK: - alert(…, isPresented:) (iOS 15+)

public extension View {
    func alert<A: View>(_ title: String, isPresented: Binding<Bool>,
                        @ViewBuilder actions: () -> A) -> some View {
        self.alert(isPresented: isPresented) {
            Alert(title: Text(title), dismissButton: .default(Text("好")))
        }
    }

    func alert<A: View, M: View>(_ title: String, isPresented: Binding<Bool>,
                                 @ViewBuilder actions: () -> A,
                                 @ViewBuilder message: () -> M) -> some View {
        self.alert(title, isPresented: isPresented, actions: actions)
    }
}

// MARK: - Task.sleep(for:) (iOS 16+)

public extension Task where Success == Never, Failure == Never {
    static func sleep(for duration: DurationCompat) async throws {
        try await Task.sleep(nanoseconds: duration.nanoseconds)
    }
}

public struct DurationCompat {
    let nanoseconds: UInt64
    public static func seconds(_ v: Double) -> DurationCompat { .init(nanoseconds: UInt64(v * 1_000_000_000)) }
    public static func milliseconds(_ v: Int) -> DurationCompat { .init(nanoseconds: UInt64(v) * 1_000_000) }
}

// MARK: - formatted() (iOS 15+)

public extension Date {
    func formattedCompat(_ style: DateFormatter.Style = .medium) -> String {
        let f = DateFormatter()
        f.dateStyle = style
        f.timeStyle = .short
        return f.string(from: self)
    }
}
