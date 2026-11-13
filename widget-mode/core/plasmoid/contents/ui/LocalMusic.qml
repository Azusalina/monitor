import QtQuick
import QtMultimedia
Item {
    id: local
    readonly property alias player: playback
    signal playbackError(string message)
    signal ended()
    MediaPlayer {
        id: playback
        objectName: "localMusicPlayer"
        audioOutput: AudioOutput {}
        onErrorOccurred: (error,errorString) => local.playbackError(errorString)
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) local.ended()
    }
}
