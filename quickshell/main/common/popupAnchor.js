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
