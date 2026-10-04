.pragma library

// The shape of a page's rows, shared by every control on it: the width of the label
// column (Kirigami's FormLayout aligns the labels in one right-aligned column, and the
// hints sit under the controls, not under the labels), the gap between a label and its
// control, and the lookup a control makes for the page it sits on — up the parents to
// the first item that says it is a page, so that a row needs nothing but its key.
var labelWidth = 220
var spacing = 10

function pageOf(item) {
    let p = item ? item.parent : null
    while (p && p.settingsPage !== true)
        p = p.parent
    return p || null
}
