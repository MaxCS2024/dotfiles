pragma Singleton
import Quickshell
import "../config"

// The Conf menu's own scale — a notch above the rest of the shell's —
// and the numbers every surface Conf opens has to match.
//
// Kept out of config/Theme.qml for the same reason theme/SlabStyle.qml
// is: Theme's sizes are the bar's and every other panel's too. Only
// these surfaces wanted to grow (user request 2026-09-19), and bumping
// Theme would have taken the whole shell with them. (config/ was also
// shared with quickshell/old at the time, which made the split doubly
// necessary; that config went away 2026-09-20 and the first reason
// stands on its own.)
//
// It lived on menu/ConfMenu.qml as four local properties until
// keybinds/KeybindsPanel.qml needed the same ones, which is the point a
// local constant becomes two copies that drift. Both read it now, so
// "make the Conf text bigger" is one edit here rather than a hunt
// through every file Conf can open.
//
// Sizes derive from Theme where Theme has one that fits, so a shell-wide
// change still carries; fontIcon does not, because Theme's scale has no
// step between fontLarge (15) and fontHuge (32) and a glyph wants to sit
// just above the words beside it.
Singleton {
    id: root

    // A row of the Conf list, and of any list Conf opens. 40px held a
    // 13px label comfortably; 15px needs the extra four.
    readonly property int rowHeight: 44

    readonly property int fontRow: Theme.fontLarge     // labels, filter, the chevron
    readonly property int fontKeys: Theme.fontMedium   // a key chord, always mono
    readonly property int fontHint: Theme.fontNormal   // the dim note beside a row
    readonly property int fontIcon: 17                 // the glyph column
}
