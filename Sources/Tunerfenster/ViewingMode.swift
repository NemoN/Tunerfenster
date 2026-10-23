enum ViewingMode: String, Codable, CaseIterable, Identifiable {
    case mosaic
    case tv
    case recordings
    var id: String { rawValue }
    var title: String { L10n.text(rawValue + "Mode") }
    var symbol: String {
        switch self {
        case .mosaic: return "square.grid.2x2"
        case .tv: return "tv"
        case .recordings: return "rectangle.stack.badge.play"
        }
    }
}

struct ViewingState: Codable, Equatable {
    var mode: ViewingMode = .mosaic
    var tunerID: String?
}
