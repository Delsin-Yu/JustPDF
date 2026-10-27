#ifndef JUSTPDF_PDF_ANNOT_WRITER_H
#define JUSTPDF_PDF_ANNOT_WRITER_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

enum JustPdfAnnotStatus {
    JUSTPDF_ANNOT_OK = 0,
    JUSTPDF_ANNOT_ERR_ARGS = 1,
    JUSTPDF_ANNOT_ERR_OPEN = 2,
    JUSTPDF_ANNOT_ERR_PARSE = 3,
    JUSTPDF_ANNOT_ERR_ENCRYPT = 4,
    JUSTPDF_ANNOT_ERR_PAGE = 5,
    JUSTPDF_ANNOT_ERR_WRITE = 6
};

struct JustPdfPolylineStroke {
    int pageIndex = 0;
    std::string uniqueId;
    uint32_t lineColor = 0;
    float opacity = 1.0f;
    std::vector<double> xs;
    std::vector<double> ys;
    std::string title;
    std::string content;
    std::string subject;
};

struct JustPdfAnnotWriteResult {
    int status = JUSTPDF_ANNOT_ERR_ARGS;
    int writtenStrokeCount = 0;
    int writtenPageCount = 0;
    std::string message;
};

JustPdfAnnotWriteResult JustPdf_WritePolylines(
    const std::string& inputPath,
    const std::string& outputPath,
    const std::vector<JustPdfPolylineStroke>& strokes);

#endif
