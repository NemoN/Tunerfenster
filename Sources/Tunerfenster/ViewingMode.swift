enum ViewingMode: String, Codable, CaseIterable, Identifiable {
    case mosaic
    case tv
    var id: String { rawValue }
    var title: String { L10n.text(self == .mosaic ? "mosaicMode" : "tvMode") }
}

struct ViewingState: Codable, Equatable {
    var mode: ViewingMode = .mosaic
    var tunerID: String?
}
