.pragma library

// Anchor rect for a popup that hangs below anchorItem, horizontally
// centered on it and clamped to stay within hostWindow's width. Shared
// by bar/DropdownPanel.qml and common/Tooltip.qml so this geometry only
// exists once — a fixed y (hostWindow's own height + gap)
// assumes the anchor item lives inside hostWindow itself, which holds
// for every current and planned caller (all bar items).
function rectBelow(anchorItem, hostWindow, popupWidth, edgeMargin, gap) {
    if (!anchorItem || !hostWindow) return Qt.rect(0, 0, 1, 1)

    const pos = anchorItem.mapToItem(hostWindow.contentItem,
                                      anchorItem.width / 2, anchorItem.height)

    let x = pos.x - popupWidth / 2
    const maxX = hostWindow.width - popupWidth - edgeMargin
    const minX = edgeMargin
    x = Math.max(minX, Math.min(x, maxX))

    const y = hostWindow.implicitHeight + gap
    return Qt.rect(x, y, 1, 1)
}

// Where anchorItem's middle sits across hostWindow, as a fraction of its
// width: what a card on its own layer-shell surface centres itself on,
// since it cannot see the bar's geometry (see Panels.clockAnchor). Null
// until the window has a width; callers add their fallback with `??`,
// which only reads it when it is needed — a fallback passed in would be
// read every time, and a caller whose fallback is the very Panels value
// it binds this to would be a binding loop. The clock, the media pill and
// the earbuds button each had a copy of this.
//
// Meant to be called from a binding. The item's x and width and the
// window's width are read although only mapToItem's answer is used:
// mapToItem is a function call, not a tracked dependency, so without
// naming the geometry the binding would be evaluated once and never
// again, and a module moved to another row would open its card wherever
// it was at startup (bar/Clock.qml found that the hard way). Reads made
// in here count as the calling binding's own.
function centreFraction(anchorItem, hostWindow) {
    if (!anchorItem || !hostWindow || hostWindow.width <= 0) return null
    void (anchorItem.x + anchorItem.width + hostWindow.width)
    return anchorItem.mapToItem(hostWindow.contentItem, anchorItem.width / 2, 0).x / hostWindow.width
}
