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

Measurements are numbered on the image and in the inspector.

## Keys and gestures

| | |
|---|---|
| ⇧ drag | lock the line to 90° |
| click a line | choose the whole line |
| click a square | choose that end |
| drag a square | move that endpoint |
| drag the line body | slide the dimension off the feature |
| arrows | nudge whatever is chosen, 1 px |
| ⇧ arrows | nudge 10 px |
| ⌫ | delete the selected measurement |
| ⌘R | use the selected measurement as the reference |
| ⌘Z / ⇧⌘Z | undo / redo |
| ⌘E | export |
| ⌘W | close the current file |
| ⌘+ ⌘− | zoom in, out |
| ⌘0 / ⌘9 | actual size, fit to window |
| ⌘⌥I | show or hide the inspector |
| pinch, ⌘ or ⌥ scroll | zoom |

Lines are drawn thin, with no halo, and end in a perpendicular tick so the measured
point stays readable. Selection darkens the colour rather than changing any size, so
nothing shifts under the pointer.

Click a line to choose the whole line; click one of its open squares to choose that
end. Arrows move whatever is chosen. A run of arrow presses collapses into a single
undo step. Only the chosen line offers handles, so a drag near an old line starts a
new measurement instead of moving it.

Drag a chosen line by its body to slide the dimension off the feature, the way an
architectural drawing does. Thin witness lines stay behind, running back to the two
points actually measured. The value never changes — only where the line is drawn.

Labels sit beside their line, never across it, and the measurement number rides its
own badge outside the value box so it cannot be read as part of the value.

**Measurement colour** in the inspector sets the colour for every measurement, and
saves with the file. The reference keeps its own colour so it stays distinct.

Name a measurement in the inspector and the name joins its label on the image.

The inspector shows the derived scale — `1 px = 0.2500 mm` — and warns when the
reference is too short to trust, or when other lines dwarf it.

Measurements are stored in image coordinates, per page. Change the reference, its
length, or the unit at any time and every label recalculates.

Each page carries its own reference, and the **Reference** picker lets a page borrow
the scale of another page. Useful when several photos come from the same setup. A
borrowing page cannot itself lend, so a scale never chains.

## Saving

⌘S writes the measurements back into the files you opened. There is no Caliper
document and no sidecar.

- **Images** get a real XMP packet under the `caliper` namespace. Any XMP-aware
  tool can see it, and the file keeps its type and extension. The image is
  re-encoded, so saving a JPEG costs one generation.
- **PDFs** get a hidden note annotation instead. PDFKit exposes no XMP writer and
  drops unknown Info-dictionary keys, so this is the only carrier that survives a
  write without overwriting a user-visible field like Subject or Keywords.

A page that borrows another page's scale records the lender by filename and page
number. Reopen both files together and the link comes back; open the borrower alone
and it falls back to pixels until you re-pick.

Quitting with unsaved measurements asks first.

## Exporting

⌘E writes a copy for people who do not have Caliper.

- **Images** export as PNG with the lines and labels burned in, at full pixel
  resolution.
- **PDFs** export as a PDF with real `/Line` annotations plus a free-text caption
  per measurement, so other readers list them as annotations instead of flattened
  pixels. Export covers every page of that PDF, not just the current one.

## Scope

Proof of concept. Undo covers geometry and the reference choice, not the typed
length, unit, or name. PDF pages render at 3× their point size, so zooming far past
300% goes soft. How a free-text caption looks depends on the PDF reader.
