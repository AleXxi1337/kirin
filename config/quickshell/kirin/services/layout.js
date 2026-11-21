.pragma library

// Converts a monitor arrangement between two coordinate spaces in which the
// monitors have different sizes: logical pixels (what Hyprland uses) and
// millimetres (what the settings draw, so monitors look as big as they are).
//
// Positions can't just be scaled, as monitors differ in density. Instead the
// arrangement's structure is kept: which monitor sits on which side of which,
// and whether it's aligned to the top/left, bottom/right or centre of it.
// Anything in between is mapped proportionally.
//
// rects: [{ x, y, w, h, W, H }] — position and size in the source space,
//        W/H: size in the target space.
// tolerance: how close (source units) counts as touching/aligned.
// Returns [{ x, y }] in the target space, starting at 0,0.
function relayout(rects, tolerance) {
    const n = rects.length;
    const out = new Array(n);
    if (!n)
        return out;

    // Start from the biggest monitor; it anchors the rest.
    let root = 0;
    for (let i = 1; i < n; i++) {
        if (rects[i].w * rects[i].h > rects[root].w * rects[root].h)
            root = i;
    }
    out[root] = { x: 0, y: 0 };

    // Place the rest one by one, each next to the closest already placed one.
    for (let placed = 1; placed < n; placed++) {
        let best = null;
        for (let p = 0; p < n; p++) {
            if (!out[p])
                continue;
            for (let m = 0; m < n; m++) {
                if (out[m])
                    continue;
                const d = gap(rects[p], rects[m]);
                if (!best || d < best.d)
                    best = { p, m, d };
            }
        }
        out[best.m] = place(rects[best.p], out[best.p], rects[best.m], tolerance);
    }

    const minX = Math.min(...out.map(o => o.x));
    const minY = Math.min(...out.map(o => o.y));
    return out.map(o => ({ x: Math.round(o.x - minX), y: Math.round(o.y - minY) }));
}

function gap(a, b) {
    const dx = Math.max(0, b.x - (a.x + a.w), a.x - (b.x + b.w));
    const dy = Math.max(0, b.y - (a.y + a.h), a.y - (b.y + b.h));
    return Math.hypot(dx, dy);
}

// Position of m in the target space, given its neighbour p (already placed at
// `at`). Sides touch in the target space too.
function place(p, at, m, tolerance) {
    const right = m.x - (p.x + p.w);
    const left = p.x - (m.x + m.w);
    const below = m.y - (p.y + p.h);
    const above = p.y - (m.y + m.h);
    const horizontal = Math.max(right, left);
    const vertical = Math.max(below, above);

    if (horizontal >= -tolerance && horizontal >= vertical) {
        return {
            x: right >= left ? at.x + p.W : at.x - m.W,
            y: align(p.y, p.h, at.y, p.H, m.y, m.h, m.H, tolerance)
        };
    }
    if (vertical >= -tolerance) {
        return {
            x: align(p.x, p.w, at.x, p.W, m.x, m.w, m.W, tolerance),
            y: below >= above ? at.y + p.H : at.y - m.H
        };
    }
    // Overlapping (shouldn't happen): put it on the right.
    return { x: at.x + p.W, y: at.y };
}

// Along the shared side: keep start, end or centre alignment exactly;
// otherwise put m's centre at the same relative spot along p's side
// (a third of the way along stays a third of the way along).
function align(p0, ps, P0, PS, m0, ms, MS, tolerance) {
    if (Math.abs(m0 - p0) <= tolerance)
        return P0;
    if (Math.abs(m0 + ms - (p0 + ps)) <= tolerance)
        return P0 + PS - MS;
    const centre = m0 + ms / 2;
    if (Math.abs(centre - (p0 + ps / 2)) <= tolerance)
        return P0 + (PS - MS) / 2;
    return P0 + (centre - p0) / ps * PS - MS / 2;
}
