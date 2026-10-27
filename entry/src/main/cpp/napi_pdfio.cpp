#include "pdf_annot_writer.h"

#include <hilog/log.h>
#include <napi/native_api.h>
#include <string>
#include <vector>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0000
#define LOG_TAG "JustPdfPdf"

static bool ReadUtf8(napi_env env, napi_value value, std::string& out)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    std::vector<char> buffer(length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copied) != napi_ok) {
        return false;
    }
    out.assign(buffer.data(), copied);
    return true;
}

static bool ReadNumber(napi_env env, napi_value object, const char* name, double& out)
{
    napi_value value = nullptr;
    if (napi_get_named_property(env, object, name, &value) != napi_ok) {
        return false;
    }
    return napi_get_value_double(env, value, &out) == napi_ok;
}

static bool ReadInt32(napi_env env, napi_value object, const char* name, int32_t& out)
{
    napi_value value = nullptr;
    if (napi_get_named_property(env, object, name, &value) != napi_ok) {
        return false;
    }
    return napi_get_value_int32(env, value, &out) == napi_ok;
}

static bool ReadBool(napi_env env, napi_value object, const char* name, bool& out)
{
    napi_value value = nullptr;
    if (napi_get_named_property(env, object, name, &value) != napi_ok) {
        return false;
    }
    return napi_get_value_bool(env, value, &out) == napi_ok;
}

static bool ReadString(napi_env env, napi_value object, const char* name, std::string& out)
{
    napi_value value = nullptr;
    if (napi_get_named_property(env, object, name, &value) != napi_ok) {
        return false;
    }
    return ReadUtf8(env, value, out);
}

static bool ReadNumberArray(napi_env env, napi_value object, const char* name, std::vector<double>& out)
{
    napi_value value = nullptr;
    if (napi_get_named_property(env, object, name, &value) != napi_ok) {
        return false;
    }
    bool isArray = false;
    if (napi_is_array(env, value, &isArray) != napi_ok || !isArray) {
        return false;
    }
    uint32_t length = 0;
    napi_get_array_length(env, value, &length);
    out.clear();
    out.reserve(length);
    for (uint32_t i = 0; i < length; i++) {
        napi_value item = nullptr;
        napi_get_element(env, value, i, &item);
        double number = 0;
        if (napi_get_value_double(env, item, &number) != napi_ok) {
            return false;
        }
        out.push_back(number);
    }
    return true;
}

static bool ReadIntArray(napi_env env, napi_value value, std::vector<int>& out)
{
    bool isArray = false;
    if (napi_is_array(env, value, &isArray) != napi_ok || !isArray) {
        return false;
    }
    uint32_t length = 0;
    napi_get_array_length(env, value, &length);
    out.clear();
    out.reserve(length);
    for (uint32_t i = 0; i < length; i++) {
        napi_value item = nullptr;
        napi_get_element(env, value, i, &item);
        int32_t number = 0;
        if (napi_get_value_int32(env, item, &number) != napi_ok) {
            return false;
        }
        out.push_back(number);
    }
    return true;
}

static napi_value WritePolylines(napi_env env, napi_callback_info info)
{
    size_t argc = 6;
    napi_value args[6] = { nullptr, nullptr, nullptr, nullptr, nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value result = nullptr;
    napi_create_int32(env, JUSTPDF_ANNOT_ERR_ARGS, &result);
    if (argc < 6) {
        return result;
    }

    std::string inputPath;
    std::string outputPath;
    if (!ReadUtf8(env, args[0], inputPath) || !ReadUtf8(env, args[1], outputPath)) {
        return result;
    }

    bool isArray = false;
    if (napi_is_array(env, args[2], &isArray) != napi_ok || !isArray) {
        return result;
    }
    uint32_t length = 0;
    napi_get_array_length(env, args[2], &length);
    std::vector<JustPdfPolylineStroke> strokes;
    strokes.reserve(length);
    for (uint32_t i = 0; i < length; i++) {
        napi_value item = nullptr;
        napi_get_element(env, args[2], i, &item);
        JustPdfPolylineStroke stroke;
        int32_t pageIndex = 0;
        int32_t lineColor = 0;
        int32_t borderStyle = 1;
        double opacity = 1.0;
        double borderWidth = 1.0;
        double creationTimeMs = 0;
        double modifiedTimeMs = 0;
        if (!ReadInt32(env, item, "pageIndex", pageIndex) ||
            !ReadInt32(env, item, "lineColor", lineColor) ||
            !ReadNumber(env, item, "opacity", opacity) ||
            !ReadString(env, item, "uniqueId", stroke.uniqueId) ||
            !ReadString(env, item, "title", stroke.title) ||
            !ReadString(env, item, "content", stroke.content) ||
            !ReadString(env, item, "subject", stroke.subject) ||
            !ReadNumberArray(env, item, "xs", stroke.xs) ||
            !ReadNumberArray(env, item, "ys", stroke.ys) ||
            !ReadNumber(env, item, "borderWidth", borderWidth) ||
            !ReadInt32(env, item, "borderStyle", borderStyle) ||
            !ReadNumber(env, item, "creationTimeMs", creationTimeMs) ||
            !ReadNumber(env, item, "modifiedTimeMs", modifiedTimeMs)) {
            return result;
        }
        stroke.pageIndex = pageIndex;
        stroke.lineColor = static_cast<uint32_t>(lineColor);
        stroke.opacity = static_cast<float>(opacity);
        stroke.borderWidth = static_cast<float>(borderWidth);
        stroke.borderStyle = borderStyle;
        stroke.creationTimeMs = static_cast<long long>(creationTimeMs);
        stroke.modifiedTimeMs = static_cast<long long>(modifiedTimeMs);
        strokes.push_back(stroke);
    }

    std::vector<int> stripPageIndices;
    if (!ReadIntArray(env, args[3], stripPageIndices)) {
        return result;
    }

    bool bookmarksIsArray = false;
    if (napi_is_array(env, args[4], &bookmarksIsArray) != napi_ok || !bookmarksIsArray) {
        return result;
    }
    uint32_t bookmarkCount = 0;
    napi_get_array_length(env, args[4], &bookmarkCount);
    std::vector<JustPdfBookmarkItem> bookmarks;
    bookmarks.reserve(bookmarkCount);
    for (uint32_t i = 0; i < bookmarkCount; i++) {
        napi_value item = nullptr;
        napi_get_element(env, args[4], i, &item);
        JustPdfBookmarkItem bookmark;
        int32_t pageIndex = 0;
        int32_t depth = 0;
        int32_t titleColor = 0;
        int32_t fitMode = 1;
        bool isBold = false;
        bool isItalic = false;
        bool hasLeft = false;
        bool hasTop = false;
        bool hasRight = false;
        bool hasBottom = false;
        bool hasZoom = false;
        if (!ReadString(env, item, "title", bookmark.title) ||
            !ReadInt32(env, item, "pageIndex", pageIndex) ||
            !ReadInt32(env, item, "depth", depth) ||
            !ReadInt32(env, item, "titleColor", titleColor) ||
            !ReadBool(env, item, "isBold", isBold) ||
            !ReadBool(env, item, "isItalic", isItalic) ||
            !ReadInt32(env, item, "fitMode", fitMode) ||
            !ReadNumber(env, item, "left", bookmark.left) ||
            !ReadNumber(env, item, "top", bookmark.top) ||
            !ReadNumber(env, item, "right", bookmark.right) ||
            !ReadNumber(env, item, "bottom", bookmark.bottom) ||
            !ReadNumber(env, item, "zoom", bookmark.zoom) ||
            !ReadBool(env, item, "hasLeft", hasLeft) ||
            !ReadBool(env, item, "hasTop", hasTop) ||
            !ReadBool(env, item, "hasRight", hasRight) ||
            !ReadBool(env, item, "hasBottom", hasBottom) ||
            !ReadBool(env, item, "hasZoom", hasZoom)) {
            return result;
        }
        bookmark.pageIndex = pageIndex;
        bookmark.depth = depth;
        bookmark.titleColor = static_cast<uint32_t>(titleColor);
        bookmark.isBold = isBold;
        bookmark.isItalic = isItalic;
        bookmark.fitMode = fitMode;
        bookmark.hasLeft = hasLeft;
        bookmark.hasTop = hasTop;
        bookmark.hasRight = hasRight;
        bookmark.hasBottom = hasBottom;
        bookmark.hasZoom = hasZoom;
        bookmarks.push_back(bookmark);
    }

    bool writeBookmarks = false;
    if (napi_get_value_bool(env, args[5], &writeBookmarks) != napi_ok) {
        return result;
    }

    const JustPdfAnnotWriteResult writeResult =
        JustPdf_WritePolylines(inputPath, outputPath, strokes, stripPageIndices, bookmarks, writeBookmarks);
    if (writeResult.status != JUSTPDF_ANNOT_OK) {
        OH_LOG_ERROR(LOG_APP, "写入批注失败 status=%{public}d %{public}s",
            writeResult.status, writeResult.message.c_str());
    }
    napi_create_int32(env, writeResult.status, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "writePolylines", nullptr, WritePolylines, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module pdfioModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "justpdfpdf",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterJustPdfPdfModule(void)
{
    napi_module_register(&pdfioModule);
}
