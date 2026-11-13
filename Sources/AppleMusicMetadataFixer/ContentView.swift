import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.pink)
                    .frame(width: 48, height: 48)
                    .background(.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Music 音乐信息订正")
                        .font(.system(size: 23, weight: .semibold))
                    Text("自动检查新增歌曲，并联网核对日文名称")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(model.status)
                    .font(.headline)
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text("新增 \(model.checkedCount) 首")
                    Text("修正 \(model.changedCount) 首")
                    if model.skippedCount > 0 {
                        Text("未确认 \(model.skippedCount) 首")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            GroupBox("本次更改") {
                if model.changes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: model.isRunning ? "hourglass" : "checkmark.circle")
                            .font(.system(size: 25))
                            .foregroundStyle(
                                model.isRunning
                                    ? Color.secondary
                                    : Color.green
                            )
                        Text(model.isRunning ? "正在处理…" : "本次没有名称修改")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 82)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            ForEach(model.changes) { change in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(
                                        change.oldTitle == change.newTitle
                                            ? change.newTitle
                                            : "\(change.oldTitle)  →  \(change.newTitle)"
                                    )
                                        .font(.callout.weight(.medium))
                                    if change.oldAlbum != change.newAlbum {
                                        Text("\(change.oldAlbum)  →  \(change.newAlbum)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if change.oldArtist != change.newArtist {
                                        Text("\(change.oldArtist)  →  \(change.newArtist)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(minHeight: 82, maxHeight: 130)
                }
            }

            GroupBox("需要处理") {
                if model.attentionTracks.isEmpty {
                    Text(model.isRunning ? "正在匹配…" : "没有需要处理的项目")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            ForEach(model.attentionTracks) { track in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.name)
                                        .font(.callout.weight(.medium))
                                    Text("\(track.artist) · \(track.album)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(minHeight: 44, maxHeight: 84)
                }
            }

            GroupBox("已经正确／非日文作品") {
                if model.likelyCorrectTracks.isEmpty {
                    Text(model.isRunning ? "正在判断…" : "没有需要保留说明的歌曲")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(model.likelyCorrectTracks) { track in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.name)
                                        .font(.callout)
                                    Text("\(track.artist) · \(track.album)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 34, maxHeight: 70)
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Button("撤销上次修改") {
                    Task { await model.undoLastRun() }
                }
                .disabled(model.isRunning || !model.canUndo)

                Spacer()

                Button("再次检查") {
                    Task { await model.run() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning)
            }
        }
        .padding(24)
        .frame(width: 620, height: 700)
        .task {
            await model.startIfNeeded()
        }
    }
}
