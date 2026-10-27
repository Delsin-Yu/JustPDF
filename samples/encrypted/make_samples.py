#!/usr/bin/env python3
"""Generate encrypted JustPDF test PDFs. Password: 1234"""

from __future__ import annotations

import io
from pathlib import Path

from pypdf import PdfReader, PdfWriter

PASSWORD = "1234"
OUT_DIR = Path(__file__).resolve().parent


def pdf_literal(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def build_plain_pdf(labels: list[str]) -> bytes:
    objects: list[str] = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [%s] /Count %d >>"
        % (" ".join(f"{4 + i * 2} 0 R" for i in range(len(labels))), len(labels)),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    for index, label in enumerate(labels):
        page_obj = 4 + index * 2
        content_obj = page_obj + 1
        stream = (
            "BT\n/F1 28 Tf\n72 720 Td\n(%s) Tj\n0 -40 Td\n"
            "(Password 1234) Tj\n0 -36 Td\n(Draw a line on this page, save, reopen.) Tj\nET\n"
            % pdf_literal(label)
        )
        objects.append(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            "/Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>" % content_obj
        )
        objects.append("<< /Length %d >>\nstream\n%s\nendstream" % (len(stream.encode("ascii")), stream))

    chunks: list[bytes] = [b"%PDF-1.4\n"]
    offsets = [0]
    for number, body in enumerate(objects, start=1):
        offsets.append(sum(len(chunk) for chunk in chunks))
        chunks.append(("%d 0 obj\n%s\nendobj\n" % (number, body)).encode("ascii"))
    xref_at = sum(len(chunk) for chunk in chunks)
    xref = ["xref\n0 %d\n" % (len(objects) + 1), "0000000000 65535 f \n"]
    for offset in offsets[1:]:
        xref.append("%010d 00000 n \n" % offset)
    chunks.append("".join(xref).encode("ascii"))
    chunks.append(
        ("trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref_at)).encode("ascii")
    )
    return b"".join(chunks)


def encrypt_pdf(plain: bytes, dest: Path, algorithm: str) -> None:
    reader = PdfReader(io.BytesIO(plain))
    writer = PdfWriter()
    writer.append(reader)
    writer.encrypt(user_password=PASSWORD, owner_password=PASSWORD, algorithm=algorithm)
    with dest.open("wb") as handle:
        writer.write(handle)


def main() -> None:
    samples = [
        ("encrypted-1page-aes256-password-1234.pdf", ["Page 1 / 1  JustPDF AES-256"], "AES-256"),
        (
            "encrypted-3page-aes256-password-1234.pdf",
            [
                "Page 1 / 3  JustPDF AES-256",
                "Page 2 / 3  JustPDF AES-256",
                "Page 3 / 3  JustPDF AES-256",
            ],
            "AES-256",
        ),
        ("encrypted-1page-rc4-password-1234.pdf", ["Page 1 / 1  JustPDF RC4-128"], "RC4-128"),
    ]
    for name, labels, algorithm in samples:
        dest = OUT_DIR / name
        encrypt_pdf(build_plain_pdf(labels), dest, algorithm)
        print("wrote", dest.name, dest.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
