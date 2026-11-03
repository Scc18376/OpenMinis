#!/usr/bin/env python3
"""Source backports for the original Minis app; no binary version relabeling."""
from pathlib import Path
import re
root = Path('src/ios')
for p in root.rglob('*.swift'):
    if 'MinisTests' in p.parts or 'Compat' in p.parts:
        continue
    s = p.read_text()
    s = s.replace('@Environment(\\.dismiss)', '@MinisDismiss')
    s = s.replace('.reconfigureItems(', '.minisReconfigureItems(')
    s = re.sub(r'(?m)^(\s*)(\w+)\.wantsPriorityOverSystemBehavior = true$',
               r'\1if #available(iOS 15.0, *) { \2.wantsPriorityOverSystemBehavior = true }', s)
    s = s.replace('.foregroundStyle(.primary.opacity(', '.foregroundStyle(Color.primary.opacity(')
    s = s.replace('.toolbar(.visible, for: .navigationBar)', '.minisNavigationBarVisible()')
    if s != p.read_text():
        p.write_text(s)
p = root / 'Shared/AppLocalization.swift'
s = p.read_text().replace('_ key: String.LocalizationValue,', '_ key: String,')
s = s.replace('String(localized: key, bundle: AppBundle.current, comment: comment)',
              'AppBundle.current.localizedString(forKey: key, value: nil, table: nil)')
s = s.replace('String(localized: String.LocalizationValue(plain), bundle: bundle, comment: comment)',
              'bundle.localizedString(forKey: plain, value: nil, table: nil)')
s = s.replace('func AppLocalized(resource: LocalizedStringResource)',
              '@available(iOS 16.0, *)\nfunc AppLocalized(resource: LocalizedStringResource)')
p.write_text(s)
p = root / 'Agent/MessageList/CollectionViewMessageListV3/Search/ChatSearchHighlights.swift'
s = p.read_text()
old = 'Text(SearchHighlightText.attributed(text, searchOffset: searchOffset, state: state, dimmed: dimmed))'
assert old in s
s = s.replace(old, '''if #available(iOS 15.0, *) {
                    Text(SearchHighlightText.attributed(text, searchOffset: searchOffset, state: state, dimmed: dimmed))
                } else {
                    SearchHighlightText.legacy(text, searchOffset: searchOffset, state: state, dimmed: dimmed)
                }''')
s = s.replace('    static func attributed(', '    @available(iOS 15.0, *)\n    static func attributed(')
pos = s.index('    @available(iOS 15.0, *)\n    static func attributed(')
s = s[:pos] + '''    static func legacy(_ text: String, searchOffset: Int, state: ChatSearchUnitHighlight,
                       dimmed: Bool) -> Text {
        let start = text.index(text.startIndex, offsetBy: min(max(searchOffset, 0), text.count))
        let searchable = String(text[start...])
        let ranges = ChatSearchMatcher.ranges(of: state.query, in: searchable, limit: state.drawLimit)
        var out = Text(String(text[..<start]))
        var cursor = searchable.startIndex
        for (ordinal, r) in ranges.enumerated() {
            out = out + Text(String(searchable[cursor..<r.lowerBound]))
            out = out + Text(String(searchable[r])).bold()
                .foregroundColor(ordinal == state.current ? .orange : .yellow)
            cursor = r.upperBound
        }
        return out + Text(String(searchable[cursor...]))
    }

''' + s[pos:]
p.write_text(s)
p = root / 'Compat/CompatCore.swift'
s = p.read_text()
assert 'public struct MinisDismiss' not in s
s += '''
// iOS 14 presentation and diffable-data-source backports.
@propertyWrapper
public struct MinisDismiss: DynamicProperty {
    @Environment(\\.presentationMode) private var mode
    public init() {}
    public var wrappedValue: () -> Void { { mode.wrappedValue.dismiss() } }
}
public extension NSDiffableDataSourceSnapshot {
    mutating func minisReconfigureItems(_ items: [ItemIdentifierType]) {
        if #available(iOS 15.0, *) { reconfigureItems(items) }
        else { reloadItems(items) }
    }
}
public extension View {
    @ViewBuilder func minisNavigationBarVisible() -> some View {
        if #available(iOS 16.0, *) { self.toolbar(.visible, for: .navigationBar) }
        else { self.navigationBarHidden(false) }
    }
}
'''
p.write_text(s)
print('Applied original-app iOS 14 presentation, search, localization and terminal backports')

# The upstream binary requires iOS 15.6. Keep all other app features, but
# exclude the optional automatic voice-segmentation engine from this build.
p = root / 'Providers/Voice/VoiceActivityDetector.swift'
s = p.read_text().replace('import RealTimeCutVADLibrary\n', '')
a = s.index('final class VoiceActivityDetector: NSObject {')
b = s.index('// MARK: - Microphone permission')
s = s[:a] + '''final class VoiceActivityDetector: NSObject {
    weak var delegate: VoiceActivityDelegate?
    let isRunning = false
    let isCapturing = false
    let isSpeaking = false
    var maxSegmentSeconds: Double = 60
    var runningDuration: TimeInterval { 0 }
    var hasRawFallbackAudio: Bool { false }
    var currentSessionId: String? { nil }
    func start() throws {
        throw NSError(domain: "MinisLegacyVoice", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Automatic voice segmentation is unavailable in this iOS 14 build. Please use text input."])
    }
    func stop() {}
    func flush() {}
    @discardableResult func flushRawFallback() -> Bool { false }
}

''' + s[b:]
p.write_text(s)
p = root / 'Minis.xcodeproj/project.pbxproj'
s = p.read_text()
s, n = re.subn(r'(?m)^\t{4}(?:891443CAA4679D09A6D32AE4 /\* RealTimeCutVADLibrary in Frameworks \*/|C42120806C66A2C804F89620 /\* RealTimeCutVADLibrary \*/),\n', '', s)
assert n == 2, f'Expected two VAD product links, found {n}'
p.write_text(s)
print('Excluded iOS 15.6-only voice segmentation binary; text chat and sandbox unchanged')
