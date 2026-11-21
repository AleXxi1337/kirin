import QtQuick
import qs.services

// NumberAnimation with Material 3 motion tokens (after Hyprstack's Anim).
// Pick a `type`; spatial types overshoot a little, effects types don't.
NumberAnimation {
    enum Type {
        StandardSmall = 0,
        Standard,
        StandardLarge,
        StandardExtraLarge,
        EmphasizedSmall,
        Emphasized,
        EmphasizedLarge,
        EmphasizedExtraLarge,
        FastSpatial,
        DefaultSpatial,
        SlowSpatial,
        FastEffects,
        DefaultEffects,
        SlowEffects
    }

    property int type: Anim.DefaultSpatial

    readonly property var spec: {
        const d = Theme.anim.durations;
        const c = Theme.anim.curves;
        switch (type) {
        case Anim.FastSpatial:
            return [d.expressiveFastSpatial, c.expressiveFastSpatial];
        case Anim.DefaultSpatial:
            return [d.expressiveDefaultSpatial, c.expressiveDefaultSpatial];
        case Anim.SlowSpatial:
            return [d.expressiveSlowSpatial, c.expressiveSlowSpatial];
        case Anim.FastEffects:
            return [d.expressiveFastEffects, c.expressiveFastEffects];
        case Anim.DefaultEffects:
            return [d.expressiveDefaultEffects, c.expressiveDefaultEffects];
        case Anim.SlowEffects:
            return [d.expressiveSlowEffects, c.expressiveSlowEffects];
        }
        // Standard and emphasized: small, normal, large, extra large.
        const durations = [d.small, d.normal, d.large, d.extraLarge];
        return [durations[type % 4], type >= Anim.EmphasizedSmall ? c.emphasized : c.standard];
    }

    duration: spec[0]
    easing.type: Easing.BezierSpline
    easing.bezierCurve: spec[1]
}
