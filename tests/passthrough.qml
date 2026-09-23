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
// Tests 10 and up cover the partial mask (decision 11): a containmentMask on the wrapper that is
// only the buttons' rectangle keeps the wrapper enabled, and Qt's target search
// (QQuickDeliveryAgentPrivate::eventTargets) then skips the wrapper where its contains() says no
// but still visits its children, so a MouseArea inside the rectangle works and everything
// outside goes through — provided nothing else in the applet accepts the mouse (test_10).
//
// How to run: ./install.sh --check-passthrough, or by hand from the repo root
//   QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/passthrough.qml
// /usr/bin/qmltestrunner is the Qt 5 runner and cannot read a Qt 6 qmldir. Without
// QT_FORCE_STDERR_LOGGING Qt logs to journald when stderr is not a terminal, so a pipe sees
// nothing.
//
// The stand tests Plasma's behaviour, not ours: the trick lives or dies with ItemContainer and
// Qt's event delivery, so re-run it after every Plasma or Qt upgrade. Last verified 2026-09-23
// against plasma-workspace 6.7.5 and Qt 6.11.2: 19 of 19 passed.

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

        // "beneath": a plain applet with a hovering MouseArea at 400..600 x 100..300 — what the
        // partly masked one below covers with its lower half
        CLM.ItemContainer {
            id: beneath
            x: 400; y: 100; width: 200; height: 200
            editModeCondition: CLM.ItemContainer.AfterPressAndHold
            contentItem: Item {
                MouseArea { id: beneathArea; anchors.fill: parent; hoverEnabled: true; property int nLeft: 0; onPressed: nLeft++ }
            }
        }

        // "row": the player's case — text with a 120x24 row of buttons at the bottom, at
        // 380..580 x 10..210. The buttons are 40..160 x 176..200 in the container's own
        // coordinates. A containmentMask of that rectangle is meant to make the wrapper take the
        // mouse there and nowhere else, with the whole subtree left enabled. It is set by name,
        // as the widgets must do on their wrapper (root.parent) and on the PlasmoidItem.
        CLM.ItemContainer {
            id: row
            x: 380; y: 10; width: 200; height: 200
            editModeCondition: CLM.ItemContainer.AfterPressAndHold
            contentItem: Item {
                Text { id: rowText; anchors.fill: parent; text: "artist - title" }
                MouseArea { id: buttons; x: 40; y: 176; width: 120; height: 24; hoverEnabled: true; property int nLeft: 0; onPressed: nLeft++ }
                // the buttons' rectangle as a child of the content item — test_16
                Item { id: rowMaskInContent; x: 40; y: 176; width: 120; height: 24; visible: false }
            }
            property Item mask: null
            Binding { target: row; property: "containmentMask"; value: row.mask }
        }
    }

    // The buttons' rectangle again, as a child of the scene: 40..160 x 176..200 means nothing in
    // scene coordinates — Qt reads only the mask's x/y and takes them as the masked item's own
    // (test_16). Invisible: contains() does not look at visibility.
    Item { id: rowMaskInScene; x: 40; y: 176; width: 120; height: 24; visible: false }

    // Can an ItemContainer name containmentMask declaratively? A PlasmoidItem cannot (GOTCHAS);
    // test_17 records what this type does.
    CLM.ItemContainer {
        id: declared
        x: 540; y: 540; width: 50; height: 50
        editModeCondition: CLM.ItemContainer.AfterPressAndHold
        contentItem: Item {}
        containmentMask: declMask
        Item { id: declMask; x: 0; y: 0; width: 25; height: 50; visible: false }
    }

    // Right button: the desktop builds its context menu after a geometric lookup — it asks
    // every applet item contains(pos) (ContainmentItem::mousePressEvent) and never looks at
    // enabled. A containment mask is what makes contains() say no. It is set through a
    // Binding by name, as the widgets must: the property carries QtQuick revision 2.11 and
    // PlasmoidItem cannot name it declaratively (GOTCHAS) — this container can, test_17.
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

        // --- The partial mask, tests 10 and up. Spots: (480,198) is inside the buttons' rect and
        // over "beneath"; (480,150) is outside the rect, on the text, over "beneath"; (480,60) is
        // outside the rect, on the text, over the desktop only. resetRow() also undoes what a
        // release in edit mode does to the container: ItemContainer::mouseReleaseEvent calls
        // AppletsLayout::positionItem, and the grid manager then stacks the container before a
        // sibling to its right or below (GridLayoutManager::assignSpaceImpl, "Reorder items tab
        // order") — on the stand "row" ends up under "beneath", whose MouseArea then takes
        // everything. Re-parenting appends it last, on top again; the geometry is restored too.
        function resetRow() {
            desktop.nLeft = 0; desktop.nRight = 0; beneathArea.nLeft = 0; buttons.nLeft = 0
            row.editMode = false
            row.parent = null; row.parent = layout
            row.x = 380; row.y = 10; row.width = 200; row.height = 200; row.leftPadding = 0
            row.mask = rowMaskInScene
            rowText.textFormat = Text.PlainText   // why: test_10
            mouseMove(scene, 1, 1)
        }

        function test_10_a_default_Text_outside_the_mask_arms_edit_mode() {
            // A Text built with the default textFormat keeps the constructor's
            // acceptedMouseButtons = LeftButton (qquicktext.cpp: init(); only setTextFormat()
            // lowers it to NoButton), so it is a pointer target, and the wrapper's
            // childMouseEventFilter runs for it: the press-and-hold timer starts. The press itself
            // goes on to the desktop, and so does the release — to the desktop's grabber, never
            // through the filter. Nothing stops the timer, and a plain click on the text puts the
            // wrapper into edit mode 800 ms later. Without a mask the wrapper is a target too,
            // takes the grab and stops the timer in its own mouseReleaseEvent; outside the mask it
            // is not. So under a partial mask no text may accept the mouse: textFormat:
            // Text.PlainText does it (enabled: false would too — test_04 for a whole subtree).
            desktop.nLeft = 0; row.mask = rowMaskInScene; row.editMode = false
            mouseClick(scene, 480, 60, Qt.LeftButton)
            compare(desktop.nLeft, 1, "the press passes the text and reaches the desktop")
            compare(row.editMode, false)
            wait(1200)
            compare(row.editMode, true, "...and the timer armed by the filter enters edit mode")
            // Back to a clean state: setEditMode() sent the wrapper a press of its own and made
            // it the grabber; a click ends that with its mouseReleaseEvent (m_mouseDown = false),
            // and only then can editMode be cleared without re-arming the timer.
            mouseClick(scene, 430, 198, Qt.LeftButton)
            resetRow()
            mouseClick(scene, 480, 60, Qt.LeftButton)
            wait(1200)
            compare(row.editMode, false, "PlainText: not a target, no filter, no timer")
            compare(desktop.nLeft, 1)
        }
        function test_11_partial_mask_left_inside_to_the_buttons_outside_through() {
            resetRow()
            mouseClick(scene, 480, 198, Qt.LeftButton)
            compare(buttons.nLeft, 1, "inside the rect: the buttons take the left button")
            compare(desktop.nLeft, 0); compare(beneathArea.nLeft, 0)
            mouseClick(scene, 480, 150, Qt.LeftButton)
            compare(beneathArea.nLeft, 1, "outside the rect: the click lands in the applet beneath")
            compare(buttons.nLeft, 1); compare(desktop.nLeft, 0)
            mouseClick(scene, 480, 60, Qt.LeftButton)
            compare(desktop.nLeft, 1, "outside the rect, nothing beneath: the desktop")
            compare(row.enabled, true, "the container stays enabled throughout")
            compare(row.contentItem.enabled, true); compare(buttons.enabled, true)
            compare(row.editMode, false)
        }
        function test_12_partial_mask_right_button_reaches_the_desktop_either_side() {
            // The wrapper and the buttons accept Left only, so the right button passes as in
            // test_01. On the real desktop ContainmentItem::mousePressEvent then asks every
            // PlasmoidItem contains(pos), and finds this applet for its menu only where the
            // PlasmoidItem's own containmentMask says yes — the same rectangle, set by name on
            // the PlasmoidItem. That half has no stand-in here (GOTCHAS, "The right button needs
            // one thing more").
            resetRow()
            mouseClick(scene, 480, 198, Qt.RightButton)
            compare(desktop.nRight, 1, "inside the rect: the right button reaches the desktop")
            mouseClick(scene, 480, 150, Qt.RightButton)
            compare(desktop.nRight, 2, "outside: the desktop too")
        }
        function test_13_partial_mask_hover_goes_beneath_outside_the_rect() {
            // Hover delivery (deliverHoverEventRecursive) walks into every visible child whatever
            // the parent's contains() or enabled say; it is the hovering item's own geometry that
            // decides. So a hoverEnabled area covering the whole applet would take hover
            // everywhere — the buttons' area, 120x24, takes it only over itself.
            resetRow()
            mouseMove(scene, 480, 150)
            compare(beneathArea.containsMouse, true, "outside the rect: the applet beneath is hovered")
            compare(buttons.containsMouse, false)
            mouseMove(scene, 480, 198)
            compare(buttons.containsMouse, true, "inside the rect: the buttons are hovered")
            compare(beneathArea.containsMouse, false, "...and the applet beneath is not")
            mouseMove(scene, 480, 60)
            compare(buttons.containsMouse, false); compare(beneathArea.containsMouse, false)
        }
        function test_14_partial_mask_press_and_hold_inside_enters_edit_mode_outside_does_not() {
            resetRow()
            mousePress(scene, 480, 198, Qt.LeftButton)
            wait(1200)
            mouseRelease(scene, 480, 198, Qt.LeftButton)
            compare(row.editMode, true, "inside the rect: the wrapper's filter arms press-and-hold, as for any applet today")
            compare(buttons.nLeft, 1)
            resetRow()
            mousePress(scene, 480, 60, Qt.LeftButton)
            wait(1200)
            mouseRelease(scene, 480, 60, Qt.LeftButton)
            compare(row.editMode, false, "outside: the wrapper is not a target and filters nothing")
            compare(desktop.nLeft, 1)
        }
        function test_15_partial_mask_back_to_null_restores_full_capture() {
            resetRow(); row.mask = null
            mouseClick(scene, 480, 150, Qt.LeftButton)
            compare(desktop.nLeft, 0, "no mask: the wrapper takes the left button everywhere again")
            compare(beneathArea.nLeft, 0); compare(buttons.nLeft, 0)
            mouseClick(scene, 480, 198, Qt.LeftButton)
            compare(buttons.nLeft, 1, "...and the buttons still work: the filter lets the press on to the child")
            compare(row.editMode, false)
        }
        function clicksWithMask(m, which) {
            row.mask = m
            desktop.nLeft = 0; buttons.nLeft = 0; beneathArea.nLeft = 0
            mouseClick(scene, 430, 198, Qt.LeftButton)   // x=50 in the container: inside the mask, left of the buttons
            compare(desktop.nLeft, 0, which + ": inside the mask, outside the buttons — the wrapper takes it")
            compare(buttons.nLeft, 0); compare(beneathArea.nLeft, 0)
            mouseClick(scene, 550, 198, Qt.LeftButton)   // x=170: outside the mask, on the buttons
            compare(buttons.nLeft, 1, which + ": outside the mask, on the buttons — the child is still a target")
            compare(desktop.nLeft, 0)
        }
        function test_16_mask_xy_are_the_containers_coordinates_whatever_its_parent() {
            // QQuickItem::contains(): quickMask->contains(point - quickMask->position()) — the
            // point is in the masked item's coordinates, only the mask's x/y are subtracted, and
            // its parent is never consulted (qquickitem.cpp, 6.11.2). Shown with a padding of 20:
            // the content item and the buttons move to 60..180, both masks stay at 40..160. The
            // mask gates the wrapper, not its subtree: the buttons are hit by their own geometry.
            resetRow(); row.leftPadding = 20
            compare(row.contentItem.x, 20)
            clicksWithMask(rowMaskInScene, "scene child")
            clicksWithMask(rowMaskInContent, "content child")
            row.leftPadding = 0
        }
        function test_17_declarative_mask_on_an_ItemContainer_and_nothing_clips() {
            compare(declared.contains(Qt.point(10, 10)), true, "containmentMask: named declaratively loads on an ItemContainer")
            compare(declared.contains(Qt.point(40, 10)), false)
            // eventTargets() stops at an item only if it clips and the point is outside its bounds
            compare(row.clip, false); compare(row.contentItem.clip, false); compare(layout.clip, false)
        }
    }
}
