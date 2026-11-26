import SwiftUI
import SwiftData

struct ItemCard: View {
    let item: LibraryItem
    var isSelected = false
    var showsDetails = true
    var fixedSize: CGFloat? = nil
    var coverAspectRatio: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let fixedSize {
                    coverContent
                        .frame(width: fixedSize, height: fixedSize / coverAspectRatio)
                } else {
                    Color.clear
                        .aspectRatio(coverAspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            coverContent
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }

            if showsDetails {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    PlatformBadge(source: item.sourceEnum)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coverContent: some View {
        ZStack(alignment: .topLeading) {
            MediaThumbnail(item: item)

            if isSelected {
                ZStack {
                    Color.accentColor.opacity(0.28)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
            }

            if item.kindEnum == .dynamic {
                Label("LIVE", systemImage: "livephoto")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            }

            if item.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.35), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
            }

            if item.needsRetry {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(6)
                    .background(.black.opacity(0.35), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(8)
            }

            TypeBadge(item: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(8)
        }
    }

    static func typeBadgeText(for item: LibraryItem) -> String {
        switch item.kindEnum {
        case .video:
            if let duration = item.duration, duration > 0 {
                return "视频 · \(durationText(duration))"
            }
            return "视频"
        case .image:
            return "图片"
        case .imageText:
            return "图文 · \(item.sourceImageURLStrings.count)张"
        case .dynamic:
            return "动态图片 · \(item.sourceImageURLStrings.count)张"
        case .audio:
            return "音频"
        }
    }

    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let rest = total % 60
        return String(format: "%d:%02d", minutes, rest)
    }
}

struct TypeBadge: View {
    let item: LibraryItem

    var body: some View {
        Text(ItemCard.typeBadgeText(for: item))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.6), in: Capsule())
    }
}

struct PlatformBadge: View {
    let source: MediaSource

    var body: some View {
        Label(source.displayName, systemImage: source.icon)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct TrashCard: View {
    @Environment(\.modelContext) private var modelContext
    let item: LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if let date = item.trashedAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("恢复") {
                    LibraryRepository.shared.restore(item: item, in: modelContext)
                }
                .buttonStyle(.bordered)
                Button("彻底删除", role: .destructive) {
                    try? LibraryRepository.shared.deletePermanently(item: item, in: modelContext)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StatTile: View {
    let value: String
    let title: String
    let icon: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.semibold))
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct RecentItemCard: View {
    let item: LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    ZStack(alignment: .bottomTrailing) {
                        MediaThumbnail(item: item)
                        TypeBadge(item: item)
                            .padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(item.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                PlatformBadge(source: item.sourceEnum)
                Spacer(minLength: 0)
                if item.kindEnum == .video, let duration = item.duration, duration > 0 {
                    Text(ItemCard.durationText(duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 150, alignment: .leading)
    }
}

struct MediaThumbnail: View {
    let item: LibraryItem
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: item.kindEnum == .video ? "play.rectangle" : "photo.stack")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: "\(item.id.uuidString)-\(item.updatedAt.timeIntervalSince1970)") {
            image = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> UIImage? {
        if let cover = item.coverFile, cover.existsOnDisk,
           let thumbnail = ThumbnailCache.image(for: cover.fileURL) {
            return thumbnail
        }
        if let imageFile = item.imageFiles.first(where: { $0.existsOnDisk }),
           let thumbnail = ThumbnailCache.image(for: imageFile.fileURL) {
            return thumbnail
        }
        if let video = item.videoFile, video.existsOnDisk {
            return await VideoThumbnailCache.image(for: video.fileURL)
        }
        return nil
    }
}
