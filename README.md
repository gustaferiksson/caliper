# Caliper

Measure real-world distances on images and PDFs. A native macOS SwiftUI proof of concept.

Preview, but with a ruler.

## Use

```sh
./run.sh
```

1. Drop images or PDFs on the window, or press ⌘O. A PDF adds one page per page.
2. Drag on the image to draw a measurement. There is only one mode.
3. In the inspector, mark any measurement as the reference and type its real length.
   Every other measurement then reads in that unit.

## Keys and gestures

| | |
|---|---|
| ⇧ drag | lock the line to 90° |
| drag an endpoint | move that handle |
| click a line | select it |
| ⌫ | delete the selected measurement |
| ⌘R | use the selected measurement as the reference |
| ⌘Z / ⇧⌘Z | undo / redo |
| ⌘+ ⌘− ⌘0 | zoom in, out, fit |
| pinch | zoom |

Measurements are stored in image coordinates, per page. Change the reference, its
length, or the unit at any time and every label recalculates. Each page carries its
own reference, so a multi-page PDF can mix scales.

## Scope

Proof of concept. No export, nothing saved to disk. Undo covers geometry and the
reference choice, not the typed length or unit. PDF pages render at 3× their point
size, so zooming far past 300% goes soft.
