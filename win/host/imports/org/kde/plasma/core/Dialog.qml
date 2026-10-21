import QtQuick

// PlasmaCore.Dialog for a bare Qt host: a frameless, transparent, always-on-top tool
// window whose size is its `mainItem`'s and whose place is next to `visualParent` — under
// Wayland only the shell can place a window by an item, on Windows the window places
// itself with the item's global position. `type` Notification keeps the keyboard where
// it was (the window does not accept focus), anything else takes it when shown;
// `hideOnWindowDeactivate` closes it when the focus goes elsewhere.
Window {
    id: dialog

    enum Type { Normal, Dock, DialogWindow, PopupMenu, Tooltip, Notification, OnScreenDisplay, CriticalNotification, AppletPopup }
    enum BackgroundHints { NoBackground = 0, StandardBackground = 1, SolidBackground = 2 }

    property Item mainItem: null
    property Item visualParent: null
    property int type: Dialog.Normal
    property int location: 0            // Types.Location
    property int backgroundHints: Dialog.StandardBackground
    property bool hideOnWindowDeactivate: false
    property bool outputOnly: false

    visible: false
    color: "transparent"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
           | (type === Dialog.Notification || type === Dialog.Tooltip || type === Dialog.OnScreenDisplay
              ? Qt.WindowDoesNotAcceptFocus : 0)

    width: mainItem ? Math.max(1, Math.ceil(mainItem.width)) : 1
    height: mainItem ? Math.max(1, Math.ceil(mainItem.height)) : 1

    // The sheet is reparented into the window, as libplasma does.
    onMainItemChanged: if (mainItem) { mainItem.parent = dialog.contentItem; mainItem.x = 0; mainItem.y = 0 }

    function place() {
        const vp = visualParent
        if (!vp || !vp.Window.window) return
        const g = vp.mapToGlobal(0, 0)
        const w = width, h = height
        let x, y
        switch (location) {
        case 3:     // TopEdge: the dialog's top at the anchor's bottom, centred on it
            x = g.x + (vp.width - w) / 2
            y = g.y + vp.height
            break
        case 4:     // BottomEdge: above the anchor
            x = g.x + (vp.width - w) / 2
            y = g.y - h
            break
        case 5:     // LeftEdge: to the right of the anchor
            x = g.x + vp.width
            y = g.y
            break
        case 6:     // RightEdge: to the left
            x = g.x - w
            y = g.y
            break
        default:    // Floating: beside the anchor, to the right, top-aligned
            x = g.x + vp.width + 4
            y = g.y
        }
        // Kept on the anchor's screen.
        const s = vp.Window.window.screen
        if (s) {
            x = Math.min(Math.max(s.virtualX, x), s.virtualX + s.width - w)
            y = Math.min(Math.max(s.virtualY, y), s.virtualY + s.height - h)
        }
        dialog.x = Math.round(x)
        dialog.y = Math.round(y)
    }

    onVisibleChanged: {
        if (visible) {
            place()
            if (!(flags & Qt.WindowDoesNotAcceptFocus)) requestActivate()
        }
    }
    onWidthChanged: if (visible) place()
    onHeightChanged: if (visible) place()
    onVisualParentChanged: if (visible) place()
    onActiveChanged: if (!active && visible && hideOnWindowDeactivate) visible = false
}
