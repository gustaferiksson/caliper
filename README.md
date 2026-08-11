# Caliper

Measure real-world distances on an image. A native macOS SwiftUI proof of concept.

Preview, but with a ruler.

## Use

```sh
./run.sh
```

1. Drop an image on the window, or press ⌘O.
2. In **Calibrate** mode, drag a line across a dimension you know.
3. Type that dimension and its unit in the sidebar.
4. Switch to **Measure** and drag more lines. Each one shows its length.

Hold ⇧ while dragging to lock a line to 90° — dead horizontal or dead vertical.

Measurements are stored in image coordinates. Change the reference length or the
unit at any time and every label recalculates.

## Scope

Proof of concept: images only, straight-line distances only. No zoom, no areas,
no PDF, no export, nothing saved to disk.
