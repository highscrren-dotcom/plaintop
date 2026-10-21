import QtQuick

// Mpris.PlaybackStatus.Playing and its kin, as the player view reads them; the numbers
// are kmpris's and the service's (win/PROTOCOL.md, /player).
QtObject {
    enum Status { Unknown, Stopped, Paused, Playing }
}
