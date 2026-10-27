import QtQuick

// Windows-style history graph: gridded box, filled area for `values`, and
// an optional dashed line for `values2` (e.g. disk write / network send).
// Newest sample on the right; `capacity` samples span the full width.
// maxValue > 0 fixes the scale (e.g. 1 for percentages); 0 auto-scales to
// a 1-2-5 ceiling of the data (at least minScale) — read it via scaleMax.
Item {
    id: g

    required property var theme
    property var    values:   []
    property var    values2:  []
    property color  color:    theme.primary
    property real   maxValue: 1
    property real   minScale: 1
    property int    capacity: 60
    property bool   grid:     true
    property real   lineWidth: 1.5

    readonly property real scaleMax: maxValue > 0 ? maxValue
                                   : _nice(Math.max(minScale, _peak(values), _peak(values2)))

    function _peak(a) { let m = 0; for (const v of (a || [])) if (v > m) m = v; return m }
    function _nice(v) {
        const e = Math.pow(10, Math.floor(Math.log10(v)))
        const f = v / e
        return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * e
    }

    onValuesChanged:   canvas.requestPaint()
    onValues2Changed:  canvas.requestPaint()
    onColorChanged:    canvas.requestPaint()
    onScaleMaxChanged: canvas.requestPaint()
    onWidthChanged:    canvas.requestPaint()
    onHeightChanged:   canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height
            const c = g.color
            const rgba = a => "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                                     + Math.round(c.b * 255) + "," + a + ")"
            ctx.fillStyle = rgba(0.04)
            ctx.fillRect(0, 0, w, h)

            if (g.grid) {
                ctx.strokeStyle = rgba(0.13)
                ctx.lineWidth = 1
                ctx.beginPath()
                for (let i = 1; i < 10; i++) {
                    const y = Math.round(h * i / 10) + 0.5
                    ctx.moveTo(0, y); ctx.lineTo(w, y)
                }
                for (let i = 1; i < 20; i++) {
                    const x = Math.round(w * i / 20) + 0.5
                    ctx.moveTo(x, 0); ctx.lineTo(x, h)
                }
                ctx.stroke()
            }

            const step = w / Math.max(1, g.capacity - 1)
            const ys = v => h - Math.max(0, Math.min(1, v / g.scaleMax)) * (h - 1)
            const trace = a => {
                const n = a.length
                for (let i = 0; i < n; i++) {
                    const x = w - (n - 1 - i) * step
                    if (i === 0) ctx.moveTo(x, ys(a[i]))
                    else         ctx.lineTo(x, ys(a[i]))
                }
            }

            const a = g.values || []
            if (a.length > 1) {
                ctx.beginPath()
                trace(a)
                ctx.lineTo(w, h)
                ctx.lineTo(w - (a.length - 1) * step, h)
                ctx.closePath()
                ctx.fillStyle = rgba(0.2)
                ctx.fill()
                ctx.beginPath()
                trace(a)
                ctx.strokeStyle = rgba(1)
                ctx.lineWidth = g.lineWidth
                ctx.stroke()
            }
            const b = g.values2 || []
            if (b.length > 1) {
                ctx.beginPath()
                trace(b)
                ctx.setLineDash([4, 3])
                ctx.strokeStyle = rgba(0.9)
                ctx.lineWidth = g.lineWidth
                ctx.stroke()
                ctx.setLineDash([])
            }

            ctx.strokeStyle = rgba(0.6)
            ctx.lineWidth = 1
            ctx.strokeRect(0.5, 0.5, w - 1, h - 1)
        }
    }
}
