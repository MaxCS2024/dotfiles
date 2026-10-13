.pragma library

// Whether two answers are the same, compared as JSON. A service whose
// answer a whole tree of rows is bound to publishes only a different one:
// a fresh object every time would tear down and rebuild every row for an
// answer that is almost always last time's.
function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b)
}
