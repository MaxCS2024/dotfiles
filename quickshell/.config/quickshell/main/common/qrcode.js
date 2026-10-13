.pragma library

// A QR encoder, because nothing on this system can make one: `qrencode`
// isn't installed, neither is any Python QR module, and `zbar` (which is)
// only *reads* codes. Rather than add a package dependency to the shell
// for one button, the whole encoder lives here — it is also the only way
// the code can be drawn as vector modules that follow the theme and stay
// crisp at any size, instead of scaling a PNG out of a temp file.
//
// Deliberately partial, sized to its one caller (the Wi-Fi share button
// in network/NetworkPanel.qml):
//   - byte mode only, which is what a `WIFI:` payload needs and what
//     handles a UTF-8 SSID correctly;
//   - error-correction level M, the level phone camera apps expect for
//     Wi-Fi codes;
//   - versions 1-10, i.e. up to 213 bytes. A `WIFI:` string is typically
//     40-80, so v10 is roughly triple the worst realistic case; beyond it
//     encode() returns null rather than emitting a code that won't scan.
// Everything the spec (ISO/IEC 18004) requires *within* that subset is
// here, including all eight masks scored by the four penalty rules — a
// code built with a fixed mask scans badly in poor light and there is no
// way to notice that from looking at it.
//
// Verified end to end rather than by inspection: the rendered code is
// screenshotted and decoded back with `zbarimg`, which is what that
// package is good for.

// ── GF(256), primitive polynomial 0x11d ──────────────
var EXP = new Array(512)
var LOG = new Array(256)
;(function () {
    var x = 1
    for (var i = 0; i < 255; i++) {
        EXP[i] = x
        LOG[x] = i
        x <<= 1
        if (x & 0x100) x ^= 0x11d
    }
    for (var j = 255; j < 512; j++) EXP[j] = EXP[j - 255]
})()

function gfMul(a, b) {
    if (a === 0 || b === 0) return 0
    return EXP[LOG[a] + LOG[b]]
}

// Generator polynomial for `degree` EC codewords, highest power first,
// returned without its leading 1 (which is what the remainder loop wants).
function rsGenerator(degree) {
    var poly = [1]
    for (var i = 0; i < degree; i++) {
        var next = new Array(poly.length + 1)
        for (var k = 0; k < next.length; k++) next[k] = 0
        for (var j = 0; j < poly.length; j++) {
            next[j] ^= poly[j]
            next[j + 1] ^= gfMul(poly[j], EXP[i])
        }
        poly = next
    }
    return poly.slice(1)
}

function rsRemainder(data, ecLen) {
    var gen = rsGenerator(ecLen)
    var res = new Array(ecLen)
    for (var i = 0; i < ecLen; i++) res[i] = 0
    for (var k = 0; k < data.length; k++) {
        var factor = data[k] ^ res.shift()
        res.push(0)
        for (var i2 = 0; i2 < ecLen; i2++) res[i2] ^= gfMul(gen[i2], factor)
    }
    return res
}

// ── Per-version tables, error-correction level M ──────
// [ecCodewordsPerBlock, group1Blocks, group1Data, group2Blocks, group2Data]
var EC_M = {
    1:  [10, 1, 16, 0, 0],
    2:  [16, 1, 28, 0, 0],
    3:  [26, 1, 44, 0, 0],
    4:  [18, 2, 32, 0, 0],
    5:  [24, 2, 43, 0, 0],
    6:  [16, 4, 27, 0, 0],
    7:  [18, 4, 31, 0, 0],
    8:  [22, 2, 38, 2, 39],
    9:  [22, 3, 36, 2, 37],
    10: [26, 4, 43, 1, 44]
}

var ALIGN = {
    1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30],
    6: [6, 34], 7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50]
}

function dataCodewords(version) {
    var t = EC_M[version]
    return t[1] * t[2] + t[3] * t[4]
}

// Mode indicator (4 bits) plus the character count field (8 bits below
// version 10, 16 from it up) is the only overhead byte mode adds.
function byteCapacity(version) {
    return dataCodewords(version) - (version < 10 ? 2 : 3)
}

function pickVersion(byteLen) {
    for (var v = 1; v <= 10; v++) if (byteLen <= byteCapacity(v)) return v
    return -1
}

// ── Payload helpers ──────────────────────────────────
function utf8(str) {
    var out = []
    for (var i = 0; i < str.length; i++) {
        var c = str.charCodeAt(i)
        if (c < 0x80) out.push(c)
        else if (c < 0x800) {
            out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f))
        } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
            // Surrogate pair — one code point, four bytes.
            var lo = str.charCodeAt(++i)
            var cp = 0x10000 + ((c - 0xd800) << 10) + (lo - 0xdc00)
            out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f),
                     0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f))
        } else {
            out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f))
        }
    }
    return out
}

// The five characters the WIFI: grammar reserves. Escaping is not
// cosmetic — an SSID or password containing a `;` splits the payload into
// the wrong fields and the phone joins the wrong network, or nothing.
function escapeField(value) {
    return String(value).replace(/([\;,:"])/g, "\\$1")
}

// `WIFI:T:<auth>;S:<ssid>;P:<psk>;;` — the de-facto format Android and
// iOS both read. `security` is passed through from `nmcli device wifi
// show-password`, which says "WPA", "WPA2", "WPA3", "WEP" or nothing.
function wifiPayload(ssid, security, password) {
    var sec = String(security || "")
    var auth = (sec === "" || /^(none|nopass)$/i.test(sec)) ? "nopass"
             : /wep/i.test(sec) ? "WEP" : "WPA"
    var out = "WIFI:T:" + auth + ";S:" + escapeField(ssid) + ";"
    if (auth !== "nopass") out += "P:" + escapeField(password) + ";"
    return out + ";"
}

// ── Encode ───────────────────────────────────────────
// Returns { size, modules } where modules is a flat row-major array of
// 0/1, or null if the text is too long for version 10.
function encode(text) {
    var bytes = utf8(text)
    var version = pickVersion(bytes.length)
    if (version < 0) return null

    var t = EC_M[version]
    var ecLen = t[0], nb1 = t[1], d1 = t[2], nb2 = t[3], d2 = t[4]
    var totalData = dataCodewords(version)

    // Bit stream: mode, length, payload, terminator, pad to a byte, then
    // the alternating 0xec/0x11 filler the spec names.
    var bits = []
    function push(value, len) {
        for (var i = len - 1; i >= 0; i--) bits.push((value >> i) & 1)
    }
    push(0x4, 4)
    push(bytes.length, version < 10 ? 8 : 16)
    for (var i = 0; i < bytes.length; i++) push(bytes[i], 8)

    var capacityBits = totalData * 8
    push(0, Math.min(4, capacityBits - bits.length))
    push(0, (8 - bits.length % 8) % 8)
    for (var pad = 0xec; bits.length < capacityBits; pad ^= 0xec ^ 0x11) push(pad, 8)

    var dataCw = []
    for (var b = 0; b < bits.length; b += 8) {
        var v = 0
        for (var k = 0; k < 8; k++) v = (v << 1) | bits[b + k]
        dataCw.push(v)
    }

    // Split into blocks, compute each block's EC, then interleave both —
    // the spec interleaves so that a burst of damage is spread across
    // blocks rather than destroying one of them outright.
    var blocks = [], ecBlocks = [], p = 0
    for (var bi = 0; bi < nb1 + nb2; bi++) {
        var len = bi < nb1 ? d1 : d2
        var blk = dataCw.slice(p, p + len)
        p += len
        blocks.push(blk)
        ecBlocks.push(rsRemainder(blk, ecLen))
    }

    var codewords = []
    var maxData = Math.max(d1, d2)
    for (var c = 0; c < maxData; c++)
        for (var bj = 0; bj < blocks.length; bj++)
            if (c < blocks[bj].length) codewords.push(blocks[bj][c])
    for (var e = 0; e < ecLen; e++)
        for (var bk = 0; bk < ecBlocks.length; bk++)
            codewords.push(ecBlocks[bk][e])

    var size = version * 4 + 17
    var mod = [], fn = []
    for (var r = 0; r < size; r++) {
        mod.push(new Array(size))
        fn.push(new Array(size))
        for (var cc = 0; cc < size; cc++) { mod[r][cc] = 0; fn[r][cc] = false }
    }

    function set(r, c, val) {
        if (r < 0 || r >= size || c < 0 || c >= size) return
        mod[r][c] = val
        fn[r][c] = true
    }

    // Finder + its separator ring in one pass: the ring distance from the
    // centre is 0,1,3 dark and 2,4 light.
    function finder(r0, c0) {
        for (var dr = -1; dr <= 7; dr++)
            for (var dc = -1; dc <= 7; dc++) {
                var d = Math.max(Math.abs(dr - 3), Math.abs(dc - 3))
                set(r0 + dr, c0 + dc, (d === 2 || d === 4) ? 0 : 1)
            }
    }
    finder(0, 0)
    finder(0, size - 7)
    finder(size - 7, 0)

    for (var ti = 0; ti < size; ti++) {
        if (!fn[6][ti]) set(6, ti, ti % 2 === 0 ? 1 : 0)
        if (!fn[ti][6]) set(ti, 6, ti % 2 === 0 ? 1 : 0)
    }

    var pos = ALIGN[version]
    var nAlign = pos.length
    for (var ai = 0; ai < nAlign; ai++)
        for (var aj = 0; aj < nAlign; aj++) {
            var ar = pos[ai], ac = pos[aj]
            // Only the three corners are skipped, because only they are
            // already covered by a finder. This has to be an index test,
            // NOT "is this module already a function module" — from
            // version 7 up, the middle alignment patterns legitimately sit
            // across the timing row and column, so the looser test drops
            // them and every code from v7 on silently fails to scan while
            // still looking correct.
            if ((ai === 0 && aj === 0)
                || (ai === 0 && aj === nAlign - 1)
                || (ai === nAlign - 1 && aj === 0)) continue
            for (var mr = -2; mr <= 2; mr++)
                for (var mc = -2; mc <= 2; mc++)
                    set(ar + mr, ac + mc, Math.max(Math.abs(mr), Math.abs(mc)) === 1 ? 0 : 1)
        }

    // Reserve the format areas (written for real once the mask is known)
    // and the always-dark module.
    drawFormat(0)
    set(size - 8, 8, 1)

    if (version >= 7) {
        // BCH(18,6) over the version number, generator 0x1f25.
        var rem = version
        for (var vi = 0; vi < 12; vi++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25)
        var vbits = (version << 12) | (rem & 0xfff)
        for (var vb = 0; vb < 18; vb++) {
            var bit = (vbits >> vb) & 1
            set(size - 11 + vb % 3, Math.floor(vb / 3), bit)
            set(Math.floor(vb / 3), size - 11 + vb % 3, bit)
        }
    }

    function drawFormat(mask) {
        // 5 data bits (EC level M = 0b00, then the mask) through BCH(15,5)
        // with generator 0x537, masked with 0x5412 so an all-zero format
        // never reads as a valid one.
        var data = (0x0 << 3) | mask
        var rem2 = data
        for (var fi = 0; fi < 10; fi++) rem2 = (rem2 << 1) ^ ((rem2 >>> 9) * 0x537)
        var fbits = ((data << 10) | (rem2 & 0x3ff)) ^ 0x5412

        // Note the order: set() here takes (row, column). Most published
        // listings of this layout are written (x, y), and transcribing
        // them straight across transposes both copies — which still
        // produces a code that *looks* entirely plausible, finder
        // patterns and all, and simply never scans.
        for (var i2 = 0; i2 <= 5; i2++) set(i2, 8, (fbits >> i2) & 1)
        set(7, 8, (fbits >> 6) & 1)
        set(8, 8, (fbits >> 7) & 1)
        set(8, 7, (fbits >> 8) & 1)
        for (var i3 = 9; i3 < 15; i3++) set(8, 14 - i3, (fbits >> i3) & 1)

        for (var i4 = 0; i4 < 8; i4++) set(8, size - 1 - i4, (fbits >> i4) & 1)
        for (var i5 = 8; i5 < 15; i5++) set(size - 15 + i5, 8, (fbits >> i5) & 1)
    }

    // Zigzag fill, two columns at a time from the bottom right, skipping
    // the vertical timing column entirely.
    var bitIdx = 0
    for (var right = size - 1; right >= 1; right -= 2) {
        if (right === 6) right = 5
        for (var vert = 0; vert < size; vert++)
            for (var j2 = 0; j2 < 2; j2++) {
                var col = right - j2
                var upward = ((right + 1) & 2) === 0
                var row = upward ? size - 1 - vert : vert
                if (!fn[row][col] && bitIdx < codewords.length * 8) {
                    mod[row][col] = (codewords[bitIdx >>> 3] >>> (7 - (bitIdx & 7))) & 1
                    bitIdx++
                }
            }
    }

    function maskBit(m, r, c) {
        switch (m) {
        case 0: return (r + c) % 2 === 0
        case 1: return r % 2 === 0
        case 2: return c % 3 === 0
        case 3: return (r + c) % 3 === 0
        case 4: return (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0
        case 5: return (r * c) % 2 + (r * c) % 3 === 0
        case 6: return ((r * c) % 2 + (r * c) % 3) % 2 === 0
        default: return ((r + c) % 2 + (r * c) % 3) % 2 === 0
        }
    }

    function applyMask(m) {
        for (var r2 = 0; r2 < size; r2++)
            for (var c2 = 0; c2 < size; c2++)
                if (!fn[r2][c2] && maskBit(m, r2, c2)) mod[r2][c2] ^= 1
    }

    // The four penalty rules. Lower is better; the spec picks the mask
    // that minimises the total.
    function penalty() {
        var score = 0, r3, c3, run, i6

        // Rule 1 — runs of five or more of one colour, rows then columns.
        for (r3 = 0; r3 < size; r3++) {
            run = 1
            for (c3 = 1; c3 < size; c3++) {
                if (mod[r3][c3] === mod[r3][c3 - 1]) { run++; if (run === 5) score += 3; else if (run > 5) score++ }
                else run = 1
            }
        }
        for (c3 = 0; c3 < size; c3++) {
            run = 1
            for (r3 = 1; r3 < size; r3++) {
                if (mod[r3][c3] === mod[r3 - 1][c3]) { run++; if (run === 5) score += 3; else if (run > 5) score++ }
                else run = 1
            }
        }

        // Rule 2 — every 2x2 block of one colour.
        for (r3 = 0; r3 < size - 1; r3++)
            for (c3 = 0; c3 < size - 1; c3++) {
                var v2 = mod[r3][c3]
                if (v2 === mod[r3][c3 + 1] && v2 === mod[r3 + 1][c3] && v2 === mod[r3 + 1][c3 + 1]) score += 3
            }

        // Rule 3 — the finder-lookalike 1:1:3:1:1 sequence with four
        // light modules on either side, in rows and columns.
        var pa = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
        var pb = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
        function matches(get, start) {
            var okA = true, okB = true
            for (i6 = 0; i6 < 11; i6++) {
                var g = get(start + i6)
                if (g !== pa[i6]) okA = false
                if (g !== pb[i6]) okB = false
            }
            return (okA ? 1 : 0) + (okB ? 1 : 0)
        }
        for (r3 = 0; r3 < size; r3++)
            for (c3 = 0; c3 + 11 <= size; c3++)
                score += 40 * matches(function (k) { return mod[r3][k] }, c3)
        for (c3 = 0; c3 < size; c3++)
            for (r3 = 0; r3 + 11 <= size; r3++)
                score += 40 * matches(function (k) { return mod[k][c3] }, r3)

        // Rule 4 — how far the dark/light balance strays from 50%.
        var dark = 0
        for (r3 = 0; r3 < size; r3++)
            for (c3 = 0; c3 < size; c3++) if (mod[r3][c3]) dark++
        var pct = dark * 100 / (size * size)
        score += 10 * Math.floor(Math.abs(pct - 50) / 5)

        return score
    }

    var bestMask = 0, bestScore = Infinity
    for (var m2 = 0; m2 < 8; m2++) {
        applyMask(m2)
        drawFormat(m2)
        var s2 = penalty()
        if (s2 < bestScore) { bestScore = s2; bestMask = m2 }
        applyMask(m2)   // XOR is its own inverse — undo before the next try
    }
    applyMask(bestMask)
    drawFormat(bestMask)

    var flat = []
    for (var fr = 0; fr < size; fr++)
        for (var fc = 0; fc < size; fc++) flat.push(mod[fr][fc])

    return { size: size, version: version, mask: bestMask, modules: flat }
}
