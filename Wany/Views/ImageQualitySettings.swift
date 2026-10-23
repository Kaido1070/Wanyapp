import SwiftUI

struct ImageQualityChoices: View {
    let selected: ImageQuality
    let select: (ImageQuality) -> Void
    var body: some View {
        ForEach(ImageQuality.allCases) { quality in
            Button { select(quality) } label: {
                HStack(spacing:12) {
                    VStack(alignment:.leading,spacing:5) {
                        Text(quality.label).font(RanyTypography.font(.body))
                        Text(quality.detail).font(RanyTypography.font(.caption)).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    if selected == quality { Image(systemName:"checkmark").foregroundStyle(Theme.accent) }
                }.frame(minHeight:44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.primary)
                .accessibilityIdentifier("reader.quality."+quality.rawValue)
        }
    }
}

#if DEBUG
struct ImageQualityFixture: View {
    @State private var quality: ImageQuality = .balanced
    var body: some View {
        VStack(spacing:24) {
            ImageQualityChoices(selected:quality,select:{ quality=$0 })
            Text(quality.rawValue).accessibilityIdentifier("fixture.quality")
            Spacer()
        }.padding(20).background(Theme.background.ignoresSafeArea())
            .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark).tint(Theme.accent)
    }
}
#endif
