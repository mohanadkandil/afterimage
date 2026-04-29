import SwiftUI

struct FilmstripView: View {
  @Bindable var model: MemoryModel
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 8) {
          ForEach(model.moments) { moment in
            Button {
              model.select(moment.id)
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                Group {
                  if let image = model.image(moment) {
                    Image(nsImage: image).resizable().scaledToFit()
                  } else {
                    Color.clear
                  }
                }
                .frame(width: 108, height: 62).background(Style.faint).clipShape(
                  RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 5).strokeBorder(
                    model.selected == moment.id ? Style.mint : .clear, lineWidth: 1.5))
                HStack(spacing: 5) {
                  AppLogo(model: model, bundle: moment.bundle, size: 12)
                  Text(moment.app).lineLimit(1)
                  Spacer(minLength: 0)
                  Text(moment.date, format: .dateTime.hour().minute()).monospacedDigit()
                }.font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 108)
              }.padding(2)
            }.task(id: moment.id) { await model.loadImage(moment) }.buttonStyle(.plain).id(
              moment.id
            ).help("\(moment.app) · \(moment.title)")
              .accessibilityLabel(
                "\(moment.app), \(moment.date.formatted(date: .abbreviated, time: .standard))")
          }
        }.padding(.horizontal, 22)
      }.frame(height: 88).onChange(of: model.selected) { _, id in
        if let id { proxy.scrollTo(id, anchor: .center) }
      }
    }

  }
}
