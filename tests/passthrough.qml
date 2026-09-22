// Click-through stand: does plasmashell's applet wrapper hand the mouse over when disabled?
//
// What it checks. On the desktop every applet sits inside an ItemContainer — the C++ half of
// plasmashell's AppletContainer — which accepts the left button itself before the applet sees
// it, so an applet cannot let clicks through from the inside; only the right button passes.
// The widgets get through by disabling that container while clicks pass through (a Binding on
// root.parent.enabled): a disabled item and its whole subtree are never mouse targets in Qt.
// This file rebuilds the real chain, desktop MouseArea <- AppletsLayout <- ItemContainer <-
// applet content, out of the compiled classes of the installed
// org.kde.plasma.private.containmentlayoutmanager module — the very ones plasmashell runs,
// not a copy — and checks that: the left button is swallowed and the right one passes;
// Locked (immutability=2) and Manual still swallow; container.enabled=false passes both
// buttons to the desktop and to an applet beneath; re-enabling restores capture; no
// press-and-hold edit mode starts while disabled.
//
// How to run: ./install.sh --check-passthrough, or by hand from the repo root
//   QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/passthrough.qml
// /usr/bin/qmltestrunner is the Qt 5 runner and cannot read a Qt 6 qmldir. Without
// QT_FORCE_STDERR_LOGGING Qt logs to journald when stderr is not a terminal, so a pipe sees
// nothing.
//
// The stand tests Plasma's behaviour, not ours: the trick lives or dies with ItemContainer and
// Qt's event delivery, so re-run it after every Plasma or Qt upgrade. Last verified 2026-09-22
// against plasma-workspace 6.7.5 and Qt 6.11.2: 10 of 10 passed.

import QtQuick
import QtTest
import org.kde.plasma.private.containmentlayoutmanager as CLM

Item {
    id: scene
    width: 600; height: 600

    // What lies under the applets on the real desktop: the folder view / containment mouse areas.
    MouseArea {
        id: desktop
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property int nLeft: 0
        property int nRight: 0
        onPressed: mouse => { if (mouse.button === Qt.LeftButton) nLeft++; else nRight++ }
    }

    CLM.AppletsLayout {
        id: layout
        anchors.fill: parent
        editModeCondition: CLM.AppletsLayout.AfterPressAndHold

        // "under": an ordinary applet with a counting MouseArea, at 100..300
        CLM.ItemContainer {
            id: under
            x: 100; y: 100; width: 200; height: 200
            editModeCondition: CLM.ItemContainer.AfterPressAndHold
            contentItem: Item {
                MouseArea { id: underArea; anchors.fill: parent; property int nLeft: 0; onPressed: nLeft++ }
            }
        }

        // "over": one of our widgets with clicks set to pass through — its content takes no input
        // (the representation's enabled: !cfg.clickThrough) — at 200..400, overlapping "under"
        CLM.ItemContainer {
            id: over
            x: 200; y: 200; width: 200; height: 200
            editModeCondition: CLM.ItemContainer.AfterPressAndHold
            contentItem: Item {
                MouseArea { id: overArea; anchors.fill: parent; enabled: false; property int nLeft: 0; onPressed: nLeft++ }
            }
        }
    }

    // Right button: the desktop builds its context menu after a geometric lookup — it asks
    // every applet item contains(pos) (ContainmentItem::mousePressEvent) and never looks at
    // enabled. A containment mask is what makes contains() say no. It is set through a
    // Binding by name: the property carries QtQuick revision 2.11, and a type from another
    // module (PlasmoidItem, this container) cannot name it declaratively.
    CLM.ItemContainer {
        id: masked
        x: 420; y: 420; width: 100; height: 100
        editModeCondition: CLM.ItemContainer.AfterPressAndHold
        contentItem: Item {}
        property bool maskOn: false
        Binding { target: masked; property: "containmentMask"; value: masked.maskOn ? noHit : null }
        Item { id: noHit; width: 0; height: 0; visible: false }
    }

    TestCase {
        name: "LeftButtonThroughItemContainer"
        when: windowShown

        function reset() {
            desktop.nLeft = 0; desktop.nRight = 0; underArea.nLeft = 0; overArea.nLeft = 0
            over.enabled = true
            over.editModeCondition = CLM.ItemContainer.AfterPressAndHold
            over.editMode = false
        }
        // Click spots: (350,350) is over "over" only; (250,250) is where the two overlap;
        // (150,150) is over "under" only.

        function test_01_today_left_swallowed_right_passes() {
            reset()
            mouseClick(scene, 350, 350, Qt.LeftButton)
            compare(desktop.nLeft, 0, "today: the container swallows the left button")
            compare(overArea.nLeft, 0)
            mouseClick(scene, 350, 350, Qt.RightButton)
            compare(desktop.nRight, 1, "today: the right button reaches the desktop")
        }
        function test_02_locked_still_swallows() {
            reset(); over.editModeCondition = CLM.ItemContainer.Locked
            mouseClick(scene, 350, 350, Qt.LeftButton)
            compare(desktop.nLeft, 0, "Locked (immutability=2): left still swallowed")
        }
        function test_03_manual_still_swallows() {
            reset(); over.editModeCondition = CLM.ItemContainer.Manual
            mouseClick(scene, 350, 350, Qt.LeftButton)
            console.info("RESULT manual: desktop.nLeft=" + desktop.nLeft)
            compare(desktop.nLeft, 0, "Manual: left still swallowed (event pre-accepted by Qt)")
        }
        function test_04_disabled_container_passes_both_buttons() {
            reset(); over.enabled = false
            mouseClick(scene, 350, 350, Qt.LeftButton)
            compare(desktop.nLeft, 1, "container.enabled=false: left reaches the desktop")
            mouseClick(scene, 350, 350, Qt.RightButton)
            compare(desktop.nRight, 1, "container.enabled=false: right reaches the desktop")
            compare(overArea.nLeft, 0)
        }
        function test_05_disabled_container_passes_to_the_widget_beneath() {
            reset(); over.enabled = false
            mouseClick(scene, 250, 250, Qt.LeftButton)
            compare(underArea.nLeft, 1, "the click lands in the applet beneath")
            compare(desktop.nLeft, 0)
        }
        function test_06_under_only_spot_unaffected() {
            reset(); over.enabled = false
            mouseClick(scene, 150, 150, Qt.LeftButton)
            compare(underArea.nLeft, 1)
        }
        function test_07_reenable_swallows_again() {
            reset(); over.enabled = false; over.enabled = true
            mouseClick(scene, 350, 350, Qt.LeftButton)
            compare(desktop.nLeft, 0, "re-enabled (edit mode): the container takes the left button again")
        }
        function test_09_containment_mask_set_by_name_makes_contains_say_no() {
            masked.maskOn = false
            compare(masked.contains(Qt.point(50, 50)), true, "no mask: the point is inside")
            masked.maskOn = true
            compare(masked.contains(Qt.point(50, 50)), false, "empty mask: contains() says no")
            compare(masked.contains(Qt.point(1, 1)), false)
            masked.maskOn = false
            compare(masked.contains(Qt.point(50, 50)), true, "mask removed: inside again")
        }
        function test_08_disabled_no_press_and_hold_edit_mode() {
            reset(); over.enabled = false
            mousePress(scene, 350, 350, Qt.LeftButton)
            wait(1200)
            mouseRelease(scene, 350, 350, Qt.LeftButton)
            compare(over.editMode, false, "no press-and-hold edit mode while disabled")
            compare(desktop.nLeft, 1)
        }
    }
}
