import QtQuick

// The enumerations the shared QML reads from PlasmaCore.Types. The numbers follow
// libplasma's Plasma::Types so a value stored in a setting reads the same on both hosts.
QtObject {
    enum Location { Floating, Desktop, FullScreen, TopEdge, BottomEdge, LeftEdge, RightEdge }
    enum BackgroundHints { NoBackground = 0, StandardBackground = 1, TranslucentBackground = 2, ShadowBackground = 4, ConfigurableBackground = 8 }
}
