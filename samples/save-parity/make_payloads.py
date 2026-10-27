#!/usr/bin/env python3
"""JustPDF save-parity payloads: bookmarks + polyline width/dates. Password 1234."""

from __future__ import annotations

import io
from pathlib import Path

from pypdf import PdfReader, PdfWriter

PASSWORD = "1234"
OUT_DIR = Path(__file__).resolve().parent


def pdf_literal(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def utf16be_hex(text: str) -> str:
    return "FEFF" + text.encode("utf-16-be").hex().upper()


def assemble(objects: list[str], extra_catalog: str = "") -> bytes:
    catalog = "<< /Type /Catalog /Pages 2 0 R%s >>" % extra_catalog
    objects = [catalog] + objects
    chunks: list[bytes] = [b"%PDF-1.4\n"]
    offsets = [0]
    for number, body in enumerate(objects, start=1):
        offsets.append(sum(len(chunk) for chunk in chunks))
        chunks.append(("%d 0 obj\n%s\nendobj\n" % (number, body)).encode("latin-1"))
    xref_at = sum(len(chunk) for chunk in chunks)
    xref = ["xref\n0 %d\n" % (len(objects) + 1), "0000000000 65535 f \n"]
    for offset in offsets[1:]:
        xref.append("%010d 00000 n \n" % offset)
    chunks.append("".join(xref).encode("ascii"))
    chunks.append(
        ("trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref_at)).encode("ascii")
    )
    return b"".join(chunks)


def page_content(title: str, hint: str) -> str:
    stream = (
        "BT\n/F1 22 Tf\n72 720 Td\n(%s) Tj\n0 -32 Td\n(%s) Tj\nET\n"
        % (pdf_literal(title), pdf_literal(hint))
    )
    return "<< /Length %d >>\nstream\n%s\nendstream" % (len(stream.encode("ascii")), stream)


def polyline_pair(
    page_obj: int,
    form_obj: int,
    annot_obj: int,
    xs: list[float],
    ys: list[float],
    width: float,
    r: float,
    g: float,
    b: float,
    unique_id: str,
    created: str,
    modified: str,
) -> tuple[str, str]:
    pad = width + 1.0
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    x0, y0 = min_x - pad, min_y - pad
    bw, bh = (max_x + pad) - x0, (max_y + pad) - y0
    path = []
    for i, (x, y) in enumerate(zip(xs, ys)):
        path.append("%.2f %.2f %s" % (x - x0, y - y0, "m" if i == 0 else "l"))
    content = "q\n%.3f %.3f %.3f RG\n%.2f w\n1 J\n1 j\n%s\nS\nQ\n" % (r, g, b, width, "\n".join(path))
    form = (
        "<< /Type /XObject /Subtype /Form /FormType 1 /BBox [0 0 %.2f %.2f] "
        "/Resources << /ProcSet [/PDF] >> /Length %d >>\nstream\n%s\nendstream"
        % (bw, bh, len(content.encode("ascii")), content)
    )
    verts = " ".join("%.2f %.2f" % pair for pair in zip(xs, ys))
    annot = (
        "<< /Type /Annot /Subtype /PolyLine /P %d 0 R /F 4 /CA 1 "
        "/NM <%s> /T <%s> /Subj <%s> /Contents <%s> "
        "/C [%.3f %.3f %.3f] /Vertices [%s] "
        "/Rect [%.2f %.2f %.2f %.2f] /LE [/None /None] "
        "/Border [0 0 %.2f] /BS << /Type /Border /W %.2f /S /S >> "
        "/AP << /N %d 0 R >> /CreationDate (%s) /M (%s) >>"
        % (
            page_obj,
            utf16be_hex(unique_id),
            utf16be_hex("Width %.0fpt" % width),
            utf16be_hex("JustPDF-Layer"),
            utf16be_hex("id=w%.0f;order=0;visible=1" % width),
            r,
            g,
            b,
            verts,
            min_x - pad,
            min_y - pad,
            max_x + pad,
            max_y + pad,
            width,
            width,
            form_obj,
            created,
            modified,
        )
    )
    return form, annot


def build_bookmark_pages() -> bytes:
    labels = [
        ("Page 1 / 3  bookmarks", "Add / rename / delete a bookmark, then save."),
        ("Page 2 / 3  bookmarks", "Nested outline should jump here."),
        ("Page 3 / 3  bookmarks", "Child bookmark should jump here."),
    ]
    objects = [
        "<< /Type /Pages /Kids [4 0 R 6 0 R 8 0 R] /Count 3 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    for i, (title, hint) in enumerate(labels):
        content_obj = 5 + i * 2
        objects.append(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            "/Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>" % content_obj
        )
        objects.append(page_content(title, hint))
    return assemble(objects, " /PageMode /UseOutlines")


def attach_outlines(plain: bytes) -> bytes:
    reader = PdfReader(io.BytesIO(plain))
    writer = PdfWriter()
    writer.append(reader)
    writer.add_outline_item("第 1 页", 0)
    chapter = writer.add_outline_item("章节 A", 1)
    writer.add_outline_item("第 2 页", 1, parent=chapter)
    writer.add_outline_item("第 3 页", 2, parent=chapter)
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


def build_polyline_widths() -> bytes:
    strokes = [
        ([80, 220, 360], [560, 600, 540], 1.0, 0.9, 0.2, 0.2, "width-1", "D:20200101120000", "D:20200102120000"),
        ([80, 220, 360], [440, 480, 420], 3.0, 0.2, 0.5, 0.9, "width-3", "D:20240615153000", "D:20240616153000"),
        ([80, 220, 360], [320, 360, 300], 6.0, 0.1, 0.7, 0.3, "width-6", "D:20261027120000", "D:20261027123000"),
    ]
    page_obj, form0, annot0 = 4, 6, 7
    annot_refs = []
    extra = []
    for i, stroke in enumerate(strokes):
        form_obj = form0 + i * 2
        annot_obj = annot0 + i * 2
        form, annot = polyline_pair(page_obj, form_obj, annot_obj, *stroke)
        extra.extend([form, annot])
        annot_refs.append("%d 0 R" % annot_obj)
    objects = [
        "<< /Type /Pages /Kids [4 0 R] /Count 1 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        "/Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R "
        "/Annots [%s] >>" % " ".join(annot_refs),
        page_content(
            "Polyline widths 1 / 3 / 6 pt",
            "Import annotate mode, save, reopen. Lines should keep thickness.",
        ),
    ]
    objects.extend(extra)
    return assemble(objects)


def encrypt_pdf(plain: bytes, dest: Path) -> None:
    reader = PdfReader(io.BytesIO(plain))
    writer = PdfWriter()
    writer.append(reader)
    writer.encrypt(user_password=PASSWORD, owner_password=PASSWORD, algorithm="AES-256")
    with dest.open("wb") as handle:
        writer.write(handle)


def write_bytes(name: str, data: bytes) -> None:
    dest = OUT_DIR / name
    dest.write_bytes(data)
    print("wrote", dest.name, dest.stat().st_size, "bytes")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bookmarks = attach_outlines(build_bookmark_pages())
    write_bytes("three-page-nested-bookmarks.pdf", bookmarks)
    encrypt_pdf(bookmarks, OUT_DIR / "encrypted-bookmarks-password-1234.pdf")
    print("wrote encrypted-bookmarks-password-1234.pdf")
    polylines = build_polyline_widths()
    write_bytes("polyline-widths-dates.pdf", polylines)
    encrypt_pdf(polylines, OUT_DIR / "encrypted-polyline-widths-password-1234.pdf")
    print("wrote encrypted-polyline-widths-password-1234.pdf")

    reader = PdfReader(str(OUT_DIR / "three-page-nested-bookmarks.pdf"))
    print("bookmarks outlines=", len(reader.outline) if reader.outline else 0, "pages=", len(reader.pages))
    enc = PdfReader(str(OUT_DIR / "encrypted-bookmarks-password-1234.pdf"))
    print("encrypted bookmarks open=", enc.decrypt(PASSWORD) > 0)


if __name__ == "__main__":
    main()
