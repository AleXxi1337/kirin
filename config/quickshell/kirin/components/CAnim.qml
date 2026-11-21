import QtQuick
import qs.services

// ColorAnimation with the Material 3 "slow effects" motion tokens. While
// the scheme changes it's instant: the colours already animate in Theme,
// and chasing them would lag behind everything else.
ColorAnimation {
    duration: Theme.shifting ? 0 : Theme.anim.durations.expressiveSlowEffects
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.anim.curves.expressiveSlowEffects
}
