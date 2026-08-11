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
| click a line | select it — large dots appear |
| drag a large dot | move that endpoint |
| ⌫ | delete the selected measurement |
| ⌘R | use the selected measurement as the reference |
| ⌘Z / ⇧⌘Z | undo / redo |
| ⌘+ ⌘− ⌘0 | zoom in, out, fit |
| pinch | zoom |

Only the selected line offers handles, so a drag near an old line starts a new
measurement instead of moving it.

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

## Scope

Proof of concept. Undo covers geometry and the reference choice, not the typed
length or unit. Saving is manual — nothing warns you about unsaved measurements on
quit. PDF pages render at 3× their point size, so zooming far past 300% goes soft.
