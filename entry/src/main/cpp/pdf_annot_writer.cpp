#include "pdf_annot_writer.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <fstream>
#include <ios>
#include <map>
#include <ostream>
#include <sstream>
#include <zlib.h>

namespace {

enum class Kind {
    Null,
    Bool,
    Int,
    Real,
    Name,
    String,
    Ref,
    Array,
    Dict
};

struct Ref {
    int obj = 0;
    int gen = 0;
};

struct Value {
    Kind kind = Kind::Null;
    bool b = false;
    long long i = 0;
    double r = 0;
    std::string text;
    Ref ref;
    std::vector<Value> items;
    std::vector<std::pair<std::string, Value>> fields;
};

struct XRefEntry {
    int obj = 0;
    int gen = 0;
    long long offset = -1;
    int objStm = -1;
    int objStmIndex = -1;
    bool free = false;
};

struct StreamObj {
    Value dict;
    std::vector<unsigned char> data;
    bool hasStream = false;
};

class Parser {
public:
    std::string error;
    std::vector<unsigned char> bytes;
    std::vector<unsigned char>* active = nullptr;
    std::map<int, XRefEntry> xref;
    Value trailer;
    int size = 0;
    long long lastXrefOffset = 0;

    bool loadFile(const std::string& path)
    {
        std::ifstream in(path.c_str(), std::ios::binary);
        if (!in) {
            error = "open failed";
            return false;
        }
        in.seekg(0, std::ios::end);
        const std::streamoff len = in.tellg();
        if (len < 8) {
            error = "file too small";
            return false;
        }
        in.seekg(0, std::ios::beg);
        bytes.resize(static_cast<size_t>(len));
        in.read(reinterpret_cast<char*>(bytes.data()), len);
        active = &bytes;
        return parseXRefChain();
    }

    bool parseObject(int obj, StreamObj& out)
    {
        const auto it = xref.find(obj);
        if (it == xref.end() || it->second.free) {
            error = "missing object";
            return false;
        }
        if (it->second.objStm >= 0) {
            return parseFromObjStm(it->second, out);
        }
        size_t pos = static_cast<size_t>(it->second.offset);
        return parseIndirectAt(pos, obj, out);
    }

    bool getPageRef(int pageIndex, Ref& out)
    {
        const Value* root = dictGet(trailer, "Root");
        if (root == nullptr || root->kind != Kind::Ref) {
            error = "no Root";
            return false;
        }
        StreamObj catalog;
        if (!parseObject(root->ref.obj, catalog)) {
            return false;
        }
        const Value* pages = dictGet(catalog.dict, "Pages");
        if (pages == nullptr || pages->kind != Kind::Ref) {
            error = "no Pages";
            return false;
        }
        int walked = 0;
        return walkPages(pages->ref, pageIndex, walked, out);
    }

    int nextObjectNumber() const
    {
        int maxObj = size > 0 ? size - 1 : 0;
        for (const auto& item : xref) {
            if (item.first > maxObj) {
                maxObj = item.first;
            }
        }
        return maxObj + 1;
    }

    bool isPolylineAnnot(const Value& item)
    {
        Value resolved = item;
        if (!resolveValue(resolved) || resolved.kind != Kind::Dict) {
            return false;
        }
        const Value* subtype = dictGet(resolved, "Subtype");
        return subtype != nullptr && subtype->kind == Kind::Name && subtype->text == "PolyLine";
    }

    bool getCatalogRef(Ref& out) const
    {
        const Value* root = dictGet(trailer, "Root");
        if (root == nullptr || root->kind != Kind::Ref) {
            return false;
        }
        out = root->ref;
        return true;
    }

private:
    bool parseXRefChain()
    {
        long long start = findStartXref();
        if (start < 0) {
            error = "startxref not found";
            return false;
        }
        lastXrefOffset = start;
        long long current = start;
        int guard = 0;
        while (current >= 0 && guard < 64) {
            guard++;
            Value sectionTrailer;
            if (!parseOneXref(current, sectionTrailer)) {
                return false;
            }
            if (guard == 1) {
                trailer = sectionTrailer;
            }
            if (dictGet(sectionTrailer, "Encrypt") != nullptr) {
                error = "encrypted";
                return false;
            }
            const Value* prev = dictGet(sectionTrailer, "Prev");
            if (prev == nullptr) {
                break;
            }
            current = asInt(*prev);
        }
        const Value* sizeVal = dictGet(trailer, "Size");
        if (sizeVal != nullptr) {
            size = static_cast<int>(asInt(*sizeVal));
        }
        return true;
    }

    long long findStartXref() const
    {
        const size_t n = active->size();
        const size_t window = n > 8192 ? 8192 : n;
        const std::string tail(reinterpret_cast<const char*>(active->data() + n - window), window);
        const char* key = "startxref";
        const size_t found = tail.rfind(key);
        if (found == std::string::npos) {
            return -1;
        }
        size_t i = found + std::strlen(key);
        while (i < tail.size() && std::isspace(static_cast<unsigned char>(tail[i]))) {
            i++;
        }
        long long value = 0;
        bool any = false;
        while (i < tail.size() && std::isdigit(static_cast<unsigned char>(tail[i]))) {
            value = value * 10 + (tail[i] - '0');
            any = true;
            i++;
        }
        return any ? value : -1;
    }

    bool parseOneXref(long long offset, Value& sectionTrailer)
    {
        size_t pos = static_cast<size_t>(offset);
        skipWs(pos);
        if (matchWord(pos, "xref")) {
            return parseXrefTable(pos, sectionTrailer);
        }
        StreamObj stm;
        if (!parseIndirectAt(pos, -1, stm) || !stm.hasStream) {
            error = "xref stream parse failed";
            return false;
        }
        return parseXrefStream(stm, sectionTrailer);
    }

    bool parseXrefTable(size_t& pos, Value& sectionTrailer)
    {
        skipWs(pos);
        while (pos < active->size() && std::isdigit((*active)[pos])) {
            const long long start = parseIntAt(pos);
            skipWs(pos);
            const long long count = parseIntAt(pos);
            skipWs(pos);
            for (long long i = 0; i < count; i++) {
                if (pos + 20 > active->size()) {
                    error = "truncated xref";
                    return false;
                }
                const long long off = parseIntAt(pos);
                skipWs(pos);
                const int gen = static_cast<int>(parseIntAt(pos));
                skipWs(pos);
                const bool freeEntry = pos < active->size() && ((*active)[pos] == 'f' || (*active)[pos] == 'F');
                while (pos < active->size() && (*active)[pos] != '\n' && (*active)[pos] != '\r') {
                    pos++;
                }
                skipWs(pos);
                const int obj = static_cast<int>(start + i);
                if (xref.find(obj) != xref.end()) {
                    continue;
                }
                XRefEntry entry;
                entry.obj = obj;
                entry.gen = gen;
                entry.offset = off;
                entry.free = freeEntry;
                xref[obj] = entry;
            }
        }
        skipWs(pos);
        if (!matchWord(pos, "trailer")) {
            error = "missing trailer";
            return false;
        }
        skipWs(pos);
        return parseValue(pos, sectionTrailer) && sectionTrailer.kind == Kind::Dict;
    }

    bool parseXrefStream(const StreamObj& stm, Value& sectionTrailer)
    {
        sectionTrailer = stm.dict;
        std::vector<unsigned char> decoded;
        if (!decodeStream(stm, decoded)) {
            return false;
        }
        const Value* wVal = dictGet(stm.dict, "W");
        if (wVal == nullptr || wVal->kind != Kind::Array || wVal->items.size() < 3) {
            error = "bad xref W";
            return false;
        }
        const int w0 = static_cast<int>(asInt(wVal->items[0]));
        const int w1 = static_cast<int>(asInt(wVal->items[1]));
        const int w2 = static_cast<int>(asInt(wVal->items[2]));
        const int row = w0 + w1 + w2;
        if (row <= 0) {
            error = "bad xref row";
            return false;
        }
        std::vector<std::pair<int, int>> spans;
        const Value* indexVal = dictGet(stm.dict, "Index");
        if (indexVal != nullptr && indexVal->kind == Kind::Array && indexVal->items.size() >= 2) {
            for (size_t i = 0; i + 1 < indexVal->items.size(); i += 2) {
                spans.push_back({
                    static_cast<int>(asInt(indexVal->items[i])),
                    static_cast<int>(asInt(indexVal->items[i + 1]))
                });
            }
        } else {
            const Value* sizeVal = dictGet(stm.dict, "Size");
            spans.push_back({ 0, sizeVal != nullptr ? static_cast<int>(asInt(*sizeVal)) : 0 });
        }
        if (!undoPredictor(stm.dict, decoded, row)) {
            return false;
        }
        size_t cursor = 0;
        for (const auto& span : spans) {
            for (int i = 0; i < span.second; i++) {
                if (cursor + static_cast<size_t>(row) > decoded.size()) {
                    error = "xref stream short";
                    return false;
                }
                const int type = w0 == 0 ? 1 : readPacked(decoded.data() + cursor, w0);
                const int field1 = readPacked(decoded.data() + cursor + w0, w1);
                const int field2 = readPacked(decoded.data() + cursor + w0 + w1, w2);
                cursor += static_cast<size_t>(row);
                const int obj = span.first + i;
                if (xref.find(obj) != xref.end()) {
                    continue;
                }
                XRefEntry entry;
                entry.obj = obj;
                if (type == 0) {
                    entry.free = true;
                    entry.gen = field2;
                } else if (type == 1) {
                    entry.offset = field1;
                    entry.gen = field2;
                } else if (type == 2) {
                    entry.objStm = field1;
                    entry.objStmIndex = field2;
                    entry.gen = 0;
                }
                xref[obj] = entry;
            }
        }
        return true;
    }

    bool parseFromObjStm(const XRefEntry& entry, StreamObj& out)
    {
        StreamObj stm;
        if (!parseObject(entry.objStm, stm) || !stm.hasStream) {
            error = "bad ObjStm";
            return false;
        }
        std::vector<unsigned char> decoded;
        if (!decodeStream(stm, decoded)) {
            return false;
        }
        const Value* nVal = dictGet(stm.dict, "N");
        const Value* firstVal = dictGet(stm.dict, "First");
        if (nVal == nullptr || firstVal == nullptr) {
            error = "bad ObjStm dict";
            return false;
        }
        const int n = static_cast<int>(asInt(*nVal));
        const int first = static_cast<int>(asInt(*firstVal));
        size_t pos = 0;
        std::vector<int> nums(static_cast<size_t>(n), 0);
        std::vector<int> offs(static_cast<size_t>(n), 0);
        std::vector<unsigned char>* previous = active;
        active = &decoded;
        for (int i = 0; i < n; i++) {
            skipWs(pos);
            nums[static_cast<size_t>(i)] = static_cast<int>(parseIntAt(pos));
            skipWs(pos);
            offs[static_cast<size_t>(i)] = static_cast<int>(parseIntAt(pos));
        }
        if (entry.objStmIndex < 0 || entry.objStmIndex >= n) {
            active = previous;
            error = "ObjStm index";
            return false;
        }
        size_t objPos = static_cast<size_t>(first + offs[static_cast<size_t>(entry.objStmIndex)]);
        skipWs(objPos);
        const bool parsed = parseValue(objPos, out.dict);
        active = previous;
        if (!parsed) {
            error = "ObjStm value";
            return false;
        }
        out.hasStream = false;
        return true;
    }

    bool parseIndirectAt(size_t pos, int expected, StreamObj& out)
    {
        skipWs(pos);
        const int obj = static_cast<int>(parseIntAt(pos));
        skipWs(pos);
        parseIntAt(pos);
        skipWs(pos);
        if (!matchWord(pos, "obj")) {
            error = "missing obj";
            return false;
        }
        if (expected >= 0 && obj != expected) {
            error = "object number mismatch";
            return false;
        }
        skipWs(pos);
        if (!parseValue(pos, out.dict)) {
            return false;
        }
        skipWs(pos);
        if (matchWord(pos, "stream")) {
            if (pos < active->size() && (*active)[pos] == '\r') {
                pos++;
            }
            if (pos < active->size() && (*active)[pos] == '\n') {
                pos++;
            }
            const Value* lengthVal = dictGet(out.dict, "Length");
            Value lengthResolved = lengthVal != nullptr ? *lengthVal : Value();
            if (lengthVal != nullptr && lengthVal->kind == Kind::Ref) {
                StreamObj lengthObj;
                if (!parseObject(lengthVal->ref.obj, lengthObj)) {
                    return false;
                }
                lengthResolved = lengthObj.dict;
            }
            const long long length = asInt(lengthResolved);
            if (length < 0 || pos + static_cast<size_t>(length) > active->size()) {
                error = "bad stream length";
                return false;
            }
            out.data.assign(bytes.begin() + static_cast<std::ptrdiff_t>(pos),
                bytes.begin() + static_cast<std::ptrdiff_t>(pos + static_cast<size_t>(length)));
            out.hasStream = true;
        }
        return true;
    }

    bool walkPages(const Ref& nodeRef, int target, int& walked, Ref& out)
    {
        StreamObj node;
        if (!parseObject(nodeRef.obj, node)) {
            return false;
        }
        const Value* kids = dictGet(node.dict, "Kids");
        if (kids == nullptr) {
            if (walked == target) {
                out = nodeRef;
                return true;
            }
            walked++;
            return false;
        }
        Value kidsVal = *kids;
        if (!resolveValue(kidsVal) || kidsVal.kind != Kind::Array) {
            error = "bad Kids";
            return false;
        }
        for (const Value& kid : kidsVal.items) {
            if (kid.kind != Kind::Ref) {
                continue;
            }
            if (walkPages(kid.ref, target, walked, out)) {
                return true;
            }
        }
        return false;
    }

    bool resolveValue(Value& value)
    {
        int guard = 0;
        while (value.kind == Kind::Ref && guard < 8) {
            StreamObj obj;
            if (!parseObject(value.ref.obj, obj)) {
                return false;
            }
            value = obj.dict;
            guard++;
        }
        return true;
    }

    bool decodeStream(const StreamObj& stm, std::vector<unsigned char>& out)
    {
        std::vector<std::string> filters;
        const Value* filter = dictGet(stm.dict, "Filter");
        if (filter != nullptr) {
            if (filter->kind == Kind::Name) {
                filters.push_back(filter->text);
            } else if (filter->kind == Kind::Array) {
                for (const Value& item : filter->items) {
                    if (item.kind == Kind::Name) {
                        filters.push_back(item.text);
                    }
                }
            }
        }
        out = stm.data;
        for (const std::string& name : filters) {
            if (name == "FlateDecode") {
                if (!inflateFlate(out)) {
                    error = "flate failed";
                    return false;
                }
            } else {
                error = "unsupported filter " + name;
                return false;
            }
        }
        return true;
    }

    bool undoPredictor(const Value& dict, std::vector<unsigned char>& data, int columns)
    {
        const Value* parms = dictGet(dict, "DecodeParms");
        if (parms == nullptr) {
            parms = dictGet(dict, "DP");
        }
        Value resolved = parms != nullptr ? *parms : Value();
        if (parms != nullptr && !resolveValue(resolved)) {
            return false;
        }
        if (resolved.kind != Kind::Dict) {
            return true;
        }
        const Value* predictorVal = dictGet(resolved, "Predictor");
        if (predictorVal == nullptr || asInt(*predictorVal) != 12) {
            return true;
        }
        const Value* colsVal = dictGet(resolved, "Columns");
        const int cols = colsVal != nullptr ? static_cast<int>(asInt(*colsVal)) : columns;
        if (cols <= 0) {
            return true;
        }
        const size_t row = static_cast<size_t>(cols) + 1;
        if (row == 0 || data.size() % row != 0) {
            error = "predictor size";
            return false;
        }
        std::vector<unsigned char> raw;
        raw.resize((data.size() / row) * static_cast<size_t>(cols));
        std::vector<unsigned char> prev(static_cast<size_t>(cols), 0);
        size_t out = 0;
        for (size_t i = 0; i < data.size(); i += row) {
            if (data[i] != 2 && data[i] != 0) {
                error = "predictor tag";
                return false;
            }
            for (int c = 0; c < cols; c++) {
                unsigned char value = data[i + 1 + static_cast<size_t>(c)];
                if (data[i] == 2) {
                    value = static_cast<unsigned char>(value + prev[static_cast<size_t>(c)]);
                }
                raw[out++] = value;
                prev[static_cast<size_t>(c)] = value;
            }
        }
        data.swap(raw);
        return true;
    }

    static bool inflateFlate(std::vector<unsigned char>& data)
    {
        if (data.empty()) {
            return true;
        }
        z_stream stream;
        std::memset(&stream, 0, sizeof(stream));
        if (inflateInit(&stream) != Z_OK) {
            return false;
        }
        stream.next_in = data.data();
        stream.avail_in = static_cast<uInt>(data.size());
        std::vector<unsigned char> out;
        unsigned char buf[4096];
        int ret = Z_OK;
        while (ret != Z_STREAM_END) {
            stream.next_out = buf;
            stream.avail_out = sizeof(buf);
            ret = inflate(&stream, Z_NO_FLUSH);
            if (ret != Z_OK && ret != Z_STREAM_END) {
                inflateEnd(&stream);
                return false;
            }
            out.insert(out.end(), buf, buf + (sizeof(buf) - stream.avail_out));
        }
        inflateEnd(&stream);
        data.swap(out);
        return true;
    }

    bool parseValue(size_t& pos, Value& out)
    {
        skipWs(pos);
        if (pos >= active->size()) {
            error = "eof";
            return false;
        }
        const unsigned char ch = (*active)[pos];
        if (ch == '<') {
            if (pos + 1 < active->size() && (*active)[pos + 1] == '<') {
                return parseDict(pos, out);
            }
            return parseHex(pos, out);
        }
        if (ch == '(') {
            return parseLiteral(pos, out);
        }
        if (ch == '[') {
            return parseArray(pos, out);
        }
        if (ch == '/') {
            return parseName(pos, out);
        }
        if (matchWord(pos, "true")) {
            out.kind = Kind::Bool;
            out.b = true;
            return true;
        }
        if (matchWord(pos, "false")) {
            out.kind = Kind::Bool;
            out.b = false;
            return true;
        }
        if (matchWord(pos, "null")) {
            out.kind = Kind::Null;
            return true;
        }
        return parseNumberOrRef(pos, out);
    }

    bool parseDict(size_t& pos, Value& out)
    {
        pos += 2;
        out.kind = Kind::Dict;
        while (true) {
            skipWs(pos);
            if (pos + 1 < active->size() && (*active)[pos] == '>' && (*active)[pos + 1] == '>') {
                pos += 2;
                return true;
            }
            Value key;
            if (!parseName(pos, key)) {
                return false;
            }
            Value val;
            if (!parseValue(pos, val)) {
                return false;
            }
            out.fields.push_back({ key.text, val });
        }
    }

    bool parseArray(size_t& pos, Value& out)
    {
        pos++;
        out.kind = Kind::Array;
        while (true) {
            skipWs(pos);
            if (pos < active->size() && (*active)[pos] == ']') {
                pos++;
                return true;
            }
            Value item;
            if (!parseValue(pos, item)) {
                return false;
            }
            out.items.push_back(item);
        }
    }

    bool parseName(size_t& pos, Value& out)
    {
        if (pos >= active->size() || (*active)[pos] != '/') {
            error = "name";
            return false;
        }
        pos++;
        out.kind = Kind::Name;
        std::string name;
        while (pos < active->size() && !isDelim((*active)[pos]) && !std::isspace((*active)[pos])) {
            if ((*active)[pos] == '#' && pos + 2 < active->size()) {
                name.push_back(static_cast<char>(
                    (hexVal((*active)[pos + 1]) << 4) | hexVal((*active)[pos + 2])));
                pos += 3;
            } else {
                name.push_back(static_cast<char>((*active)[pos]));
                pos++;
            }
        }
        out.text = name;
        return true;
    }

    bool parseLiteral(size_t& pos, Value& out)
    {
        pos++;
        out.kind = Kind::String;
        int depth = 1;
        std::string text;
        while (pos < active->size() && depth > 0) {
            const unsigned char ch = (*active)[pos++];
            if (ch == '\\' && pos < active->size()) {
                text.push_back(static_cast<char>((*active)[pos++]));
                continue;
            }
            if (ch == '(') {
                depth++;
            } else if (ch == ')') {
                depth--;
                if (depth == 0) {
                    break;
                }
            }
            if (depth > 0) {
                text.push_back(static_cast<char>(ch));
            }
        }
        out.text = text;
        return true;
    }

    bool parseHex(size_t& pos, Value& out)
    {
        pos++;
        out.kind = Kind::String;
        std::string hex;
        while (pos < active->size() && (*active)[pos] != '>') {
            if (!std::isspace((*active)[pos])) {
                hex.push_back(static_cast<char>((*active)[pos]));
            }
            pos++;
        }
        if (pos < active->size() && (*active)[pos] == '>') {
            pos++;
        }
        out.text = hex;
        return true;
    }

    bool parseNumberOrRef(size_t& pos, Value& out)
    {
        const size_t saved = pos;
        const bool neg = pos < active->size() && (*active)[pos] == '-';
        if (neg || (pos < active->size() && (*active)[pos] == '+')) {
            pos++;
        }
        if (pos >= active->size() ||
            (!std::isdigit((*active)[pos]) && (*active)[pos] != '.')) {
            error = "number";
            return false;
        }
        pos = saved;
        const long long first = parseIntAt(pos);
        const size_t afterFirst = pos;
        skipWs(pos);
        if (pos < active->size() && (std::isdigit((*active)[pos]) || (*active)[pos] == '+' || (*active)[pos] == '-')) {
            const size_t genPos = pos;
            const long long gen = parseIntAt(pos);
            skipWs(pos);
            if (matchWord(pos, "R")) {
                out.kind = Kind::Ref;
                out.ref.obj = static_cast<int>(first);
                out.ref.gen = static_cast<int>(gen);
                return true;
            }
            pos = genPos;
        }
        pos = afterFirst;
        out.kind = Kind::Int;
        out.i = first;
        if (pos < active->size() && (*active)[pos] == '.') {
            out.kind = Kind::Real;
            out.r = static_cast<double>(first);
            pos++;
            double place = 0.1;
            while (pos < active->size() && std::isdigit((*active)[pos])) {
                out.r += ((*active)[pos] - '0') * place;
                place *= 0.1;
                pos++;
            }
        }
        return true;
    }

    void skipWs(size_t& pos)
    {
        while (pos < active->size()) {
            if ((*active)[pos] == '%') {
                while (pos < active->size() && (*active)[pos] != '\n' && (*active)[pos] != '\r') {
                    pos++;
                }
                continue;
            }
            if (!std::isspace((*active)[pos])) {
                break;
            }
            pos++;
        }
    }

    long long parseIntAt(size_t& pos)
    {
        skipWs(pos);
        bool neg = false;
        if (pos < active->size() && (*active)[pos] == '+') {
            pos++;
        } else if (pos < active->size() && (*active)[pos] == '-') {
            neg = true;
            pos++;
        }
        long long value = 0;
        while (pos < active->size() && std::isdigit((*active)[pos])) {
            value = value * 10 + ((*active)[pos] - '0');
            pos++;
        }
        return neg ? -value : value;
    }

    bool matchWord(size_t& pos, const char* word)
    {
        const size_t n = std::strlen(word);
        if (pos + n > active->size()) {
            return false;
        }
        if (std::memcmp(active->data() + pos, word, n) != 0) {
            return false;
        }
        if (pos + n < active->size() && std::isalnum((*active)[pos + n])) {
            return false;
        }
        pos += n;
        return true;
    }

    static const Value* dictGet(const Value& dict, const char* name)
    {
        if (dict.kind != Kind::Dict) {
            return nullptr;
        }
        for (const auto& field : dict.fields) {
            if (field.first == name) {
                return &field.second;
            }
        }
        return nullptr;
    }

    static long long asInt(const Value& value)
    {
        if (value.kind == Kind::Int) {
            return value.i;
        }
        if (value.kind == Kind::Real) {
            return static_cast<long long>(value.r);
        }
        return 0;
    }

    static int readPacked(const unsigned char* p, int width)
    {
        int value = 0;
        for (int i = 0; i < width; i++) {
            value = (value << 8) | p[i];
        }
        return value;
    }

    static bool isDelim(unsigned char ch)
    {
        return ch == '(' || ch == ')' || ch == '<' || ch == '>' || ch == '[' || ch == ']' ||
            ch == '{' || ch == '}' || ch == '/' || ch == '%';
    }

    static int hexVal(unsigned char ch)
    {
        if (ch >= '0' && ch <= '9') {
            return ch - '0';
        }
        if (ch >= 'a' && ch <= 'f') {
            return ch - 'a' + 10;
        }
        if (ch >= 'A' && ch <= 'F') {
            return ch - 'A' + 10;
        }
        return 0;
    }
};

void appendUtf16BeUnit(std::ostream& out, unsigned int unit)
{
    char hex[8];
    std::snprintf(hex, sizeof(hex), "%04X", unit);
    out << hex;
}

void writePdfString(std::ostream& out, const std::string& text)
{
    out << "<FEFF";
    size_t i = 0;
    while (i < text.size()) {
        const unsigned char lead = static_cast<unsigned char>(text[i]);
        unsigned int cp = 0;
        size_t used = 1;
        if (lead < 0x80) {
            cp = lead;
        } else if ((lead & 0xE0) == 0xC0 && i + 1 < text.size()) {
            cp = ((lead & 0x1F) << 6) | (static_cast<unsigned char>(text[i + 1]) & 0x3F);
            used = 2;
        } else if ((lead & 0xF0) == 0xE0 && i + 2 < text.size()) {
            cp = ((lead & 0x0F) << 12) |
                ((static_cast<unsigned char>(text[i + 1]) & 0x3F) << 6) |
                (static_cast<unsigned char>(text[i + 2]) & 0x3F);
            used = 3;
        } else if ((lead & 0xF8) == 0xF0 && i + 3 < text.size()) {
            cp = ((lead & 0x07) << 18) |
                ((static_cast<unsigned char>(text[i + 1]) & 0x3F) << 12) |
                ((static_cast<unsigned char>(text[i + 2]) & 0x3F) << 6) |
                (static_cast<unsigned char>(text[i + 3]) & 0x3F);
            used = 4;
        } else {
            i += 1;
            continue;
        }
        i += used;
        if (cp >= 0x10000) {
            cp -= 0x10000;
            appendUtf16BeUnit(out, 0xD800 + (cp >> 10));
            appendUtf16BeUnit(out, 0xDC00 + (cp & 0x3FF));
        } else {
            appendUtf16BeUnit(out, cp);
        }
    }
    out << '>';
}

void writeValue(std::ostream& out, const Value& value)
{
    switch (value.kind) {
        case Kind::Null:
            out << "null";
            break;
        case Kind::Bool:
            out << (value.b ? "true" : "false");
            break;
        case Kind::Int:
            out << value.i;
            break;
        case Kind::Real: {
            char buf[64];
            std::snprintf(buf, sizeof(buf), "%.5f", value.r);
            out << buf;
            break;
        }
        case Kind::Name:
            out << '/' << value.text;
            break;
        case Kind::String:
            writePdfString(out, value.text);
            break;
        case Kind::Ref:
            out << value.ref.obj << ' ' << value.ref.gen << " R";
            break;
        case Kind::Array:
            out << '[';
            for (size_t i = 0; i < value.items.size(); i++) {
                if (i > 0) {
                    out << ' ';
                }
                writeValue(out, value.items[i]);
            }
            out << ']';
            break;
        case Kind::Dict:
            out << "<<";
            for (const auto& field : value.fields) {
                out << " /" << field.first << ' ';
                writeValue(out, field.second);
            }
            out << " >>";
            break;
    }
}

Value makeRef(int obj)
{
    Value value;
    value.kind = Kind::Ref;
    value.ref.obj = obj;
    value.ref.gen = 0;
    return value;
}

Value makeName(const char* name)
{
    Value value;
    value.kind = Kind::Name;
    value.text = name;
    return value;
}

Value makeReal(double number)
{
    Value value;
    value.kind = Kind::Real;
    value.r = number;
    return value;
}

Value makeInt(long long number)
{
    Value value;
    value.kind = Kind::Int;
    value.i = number;
    return value;
}

Value makeString(const std::string& text)
{
    Value value;
    value.kind = Kind::String;
    value.text = text;
    return value;
}

void dictSet(Value& dict, const std::string& name, const Value& value)
{
    for (auto& field : dict.fields) {
        if (field.first == name) {
            field.second = value;
            return;
        }
    }
    dict.fields.push_back({ name, value });
}

void dictRemove(Value& dict, const std::string& name)
{
    std::vector<std::pair<std::string, Value>> kept;
    kept.reserve(dict.fields.size());
    for (const auto& field : dict.fields) {
        if (field.first != name) {
            kept.push_back(field);
        }
    }
    dict.fields.swap(kept);
}

struct StrokeGeom {
    double minX = 0;
    double minY = 0;
    double maxX = 0;
    double maxY = 0;
    double r = 0;
    double g = 0;
    double b = 0;
};

StrokeGeom measureStroke(const JustPdfPolylineStroke& stroke)
{
    StrokeGeom geom;
    geom.r = (stroke.lineColor & 0xFF) / 255.0;
    geom.g = ((stroke.lineColor >> 8) & 0xFF) / 255.0;
    geom.b = ((stroke.lineColor >> 16) & 0xFF) / 255.0;
    const size_t n = std::min(stroke.xs.size(), stroke.ys.size());
    for (size_t i = 0; i < n; i++) {
        if (i == 0 || stroke.xs[i] < geom.minX) {
            geom.minX = stroke.xs[i];
        }
        if (i == 0 || stroke.ys[i] < geom.minY) {
            geom.minY = stroke.ys[i];
        }
        if (i == 0 || stroke.xs[i] > geom.maxX) {
            geom.maxX = stroke.xs[i];
        }
        if (i == 0 || stroke.ys[i] > geom.maxY) {
            geom.maxY = stroke.ys[i];
        }
    }
    return geom;
}

void appendPdfNumber(std::ostream& out, double number)
{
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.4f", number);
    out << buf;
}

std::string pdfDateFromMs(long long ms)
{
    if (ms <= 0) {
        return "";
    }
    const time_t seconds = static_cast<time_t>(ms / 1000);
    std::tm utc;
#if defined(_WIN32)
    if (gmtime_s(&utc, &seconds) != 0) {
        return "";
    }
#else
    if (gmtime_r(&seconds, &utc) == nullptr) {
        return "";
    }
#endif
    char buf[32];
    std::snprintf(buf, sizeof(buf), "D:%04d%02d%02d%02d%02d%02d",
        utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday,
        utc.tm_hour, utc.tm_min, utc.tm_sec);
    return buf;
}

const char* borderStyleName(int style)
{
    switch (style) {
        case 2:
            return "B";
        case 3:
            return "I";
        case 4:
            return "U";
        case 5:
            return "D";
        default:
            return "S";
    }
}

double effectiveBorderWidth(const JustPdfPolylineStroke& stroke)
{
    return stroke.borderWidth > 0 ? stroke.borderWidth : 1.0;
}

void writeAppearanceForm(
    std::ostream& out,
    int formObj,
    const JustPdfPolylineStroke& stroke,
    const StrokeGeom& geom)
{
    const double pad = (stroke.borderWidth > 0 ? stroke.borderWidth : 1.0) + 1.0;
    const double x0 = geom.minX - pad;
    const double y0 = geom.minY - pad;
    const double width = (geom.maxX + pad) - x0;
    const double height = (geom.maxY + pad) - y0;
    std::ostringstream content;
    content << "q\n";
    appendPdfNumber(content, geom.r);
    content << ' ';
    appendPdfNumber(content, geom.g);
    content << ' ';
    appendPdfNumber(content, geom.b);
    content << " RG\n";
    appendPdfNumber(content, stroke.borderWidth > 0 ? stroke.borderWidth : 1.0);
    content << " w\n1 J\n1 j\n";
    const size_t n = std::min(stroke.xs.size(), stroke.ys.size());
    for (size_t i = 0; i < n; i++) {
        appendPdfNumber(content, stroke.xs[i] - x0);
        content << ' ';
        appendPdfNumber(content, stroke.ys[i] - y0);
        content << (i == 0 ? " m\n" : " l\n");
    }
    content << "S\nQ\n";
    const std::string stream = content.str();

    out << formObj << " 0 obj\n<< /Type /XObject /Subtype /Form /FormType 1 /BBox [0 0 ";
    appendPdfNumber(out, width);
    out << ' ';
    appendPdfNumber(out, height);
    out << "] /Resources << /ProcSet [/PDF] >> /Length " << stream.size() << " >>\nstream\n";
    out << stream;
    out << "endstream\nendobj\n";
}

Value makePolylineAnnot(const JustPdfPolylineStroke& stroke, int pageObj, int formObj, const StrokeGeom& geom)
{
    Value annot;
    annot.kind = Kind::Dict;
    dictSet(annot, "Type", makeName("Annot"));
    dictSet(annot, "Subtype", makeName("PolyLine"));
    dictSet(annot, "P", makeRef(pageObj));
    dictSet(annot, "F", makeInt(4));
    dictSet(annot, "CA", makeReal(stroke.opacity));
    if (!stroke.uniqueId.empty()) {
        dictSet(annot, "NM", makeString(stroke.uniqueId));
    }
    if (!stroke.title.empty()) {
        dictSet(annot, "T", makeString(stroke.title));
    }
    if (!stroke.subject.empty()) {
        dictSet(annot, "Subj", makeString(stroke.subject));
    }
    if (!stroke.content.empty()) {
        dictSet(annot, "Contents", makeString(stroke.content));
    }
    if (stroke.creationTimeMs > 0) {
        dictSet(annot, "CreationDate", makeString(pdfDateFromMs(stroke.creationTimeMs)));
    }
    if (stroke.modifiedTimeMs > 0) {
        dictSet(annot, "M", makeString(pdfDateFromMs(stroke.modifiedTimeMs)));
    }

    Value color;
    color.kind = Kind::Array;
    color.items.push_back(makeReal(geom.r));
    color.items.push_back(makeReal(geom.g));
    color.items.push_back(makeReal(geom.b));
    dictSet(annot, "C", color);

    Value vertices;
    vertices.kind = Kind::Array;
    const size_t n = std::min(stroke.xs.size(), stroke.ys.size());
    for (size_t i = 0; i < n; i++) {
        vertices.items.push_back(makeReal(stroke.xs[i]));
        vertices.items.push_back(makeReal(stroke.ys[i]));
    }
    dictSet(annot, "Vertices", vertices);
    Value rect;
    rect.kind = Kind::Array;
    rect.items.push_back(makeReal(geom.minX - 2));
    rect.items.push_back(makeReal(geom.minY - 2));
    rect.items.push_back(makeReal(geom.maxX + 2));
    rect.items.push_back(makeReal(geom.maxY + 2));
    dictSet(annot, "Rect", rect);
    Value le;
    le.kind = Kind::Array;
    le.items.push_back(makeName("None"));
    le.items.push_back(makeName("None"));
    dictSet(annot, "LE", le);

    Value border;
    border.kind = Kind::Array;
    border.items.push_back(makeInt(0));
    border.items.push_back(makeInt(0));
    border.items.push_back(makeReal(effectiveBorderWidth(stroke)));
    dictSet(annot, "Border", border);
    Value borderStyle;
    borderStyle.kind = Kind::Dict;
    dictSet(borderStyle, "Type", makeName("Border"));
    dictSet(borderStyle, "W", makeReal(effectiveBorderWidth(stroke)));
    dictSet(borderStyle, "S", makeName(borderStyleName(stroke.borderStyle)));
    dictSet(annot, "BS", borderStyle);
    Value appearance;
    appearance.kind = Kind::Dict;
    dictSet(appearance, "N", makeRef(formObj));
    dictSet(annot, "AP", appearance);
    return annot;
}

bool copyFile(const std::string& from, const std::string& to)
{
    std::ifstream in(from.c_str(), std::ios::binary);
    std::ofstream out(to.c_str(), std::ios::binary | std::ios::trunc);
    if (!in || !out) {
        return false;
    }
    out << in.rdbuf();
    return static_cast<bool>(out);
}

Value makeNull()
{
    Value value;
    value.kind = Kind::Null;
    return value;
}

Value destCoord(bool has, double number)
{
    return has ? makeReal(number) : makeNull();
}

Value makeBookmarkDest(Parser& parser, const JustPdfBookmarkItem& item)
{
    Value dest;
    dest.kind = Kind::Array;
    Ref pageRef;
    if (!parser.getPageRef(item.pageIndex, pageRef)) {
        return dest;
    }
    dest.items.push_back(makeRef(pageRef.obj));
    if (item.fitMode == 2) {
        dest.items.push_back(makeName("FitH"));
        dest.items.push_back(destCoord(item.hasTop, item.top));
    } else if (item.fitMode == 3) {
        dest.items.push_back(makeName("FitV"));
        dest.items.push_back(destCoord(item.hasLeft, item.left));
    } else if (item.fitMode == 4) {
        dest.items.push_back(makeName("FitR"));
        dest.items.push_back(makeReal(item.left));
        dest.items.push_back(makeReal(item.bottom));
        dest.items.push_back(makeReal(item.right));
        dest.items.push_back(makeReal(item.top));
    } else {
        dest.items.push_back(makeName("XYZ"));
        dest.items.push_back(destCoord(item.hasLeft, item.left));
        dest.items.push_back(destCoord(item.hasTop, item.top));
        dest.items.push_back(destCoord(item.hasZoom, item.zoom));
    }
    return dest;
}

struct WrittenObj {
    int obj = 0;
    long long offset = 0;
};

void writeOutlineTree(
    Parser& parser,
    std::ostream& out,
    int& nextObj,
    std::vector<WrittenObj>& written,
    const std::vector<JustPdfBookmarkItem>& bookmarks)
{
    Ref catalogRef;
    if (!parser.getCatalogRef(catalogRef)) {
        return;
    }
    StreamObj catalog;
    if (!parser.parseObject(catalogRef.obj, catalog)) {
        return;
    }

    if (bookmarks.empty()) {
        dictRemove(catalog.dict, "Outlines");
        const long long catalogOffset = static_cast<long long>(out.tellp());
        out << catalogRef.obj << " 0 obj\n";
        writeValue(out, catalog.dict);
        out << "\nendobj\n";
        written.push_back({ catalogRef.obj, catalogOffset });
        return;
    }

    const int rootObj = nextObj++;
    std::vector<int> itemObjs(bookmarks.size(), 0);
    for (size_t i = 0; i < bookmarks.size(); i++) {
        itemObjs[i] = nextObj++;
    }

    struct Node {
        int parent = -1;
        int prev = -1;
        int next = -1;
        int first = -1;
        int last = -1;
        int count = 0;
    };
    std::vector<Node> nodes(bookmarks.size());
    std::vector<int> stack;
    for (int i = 0; i < static_cast<int>(bookmarks.size()); i++) {
        while (!stack.empty() && bookmarks[static_cast<size_t>(stack.back())].depth >= bookmarks[static_cast<size_t>(i)].depth) {
            stack.pop_back();
        }
        nodes[static_cast<size_t>(i)].parent = stack.empty() ? -1 : stack.back();
        stack.push_back(i);
    }

    std::vector<std::vector<int>> children(bookmarks.size());
    std::vector<int> roots;
    for (int i = 0; i < static_cast<int>(bookmarks.size()); i++) {
        const int parent = nodes[static_cast<size_t>(i)].parent;
        if (parent < 0) {
            roots.push_back(i);
        } else {
            children[static_cast<size_t>(parent)].push_back(i);
        }
    }
    for (int i = 0; i < static_cast<int>(bookmarks.size()); i++) {
        const std::vector<int>& kids = children[static_cast<size_t>(i)];
        if (kids.empty()) {
            continue;
        }
        nodes[static_cast<size_t>(i)].first = kids.front();
        nodes[static_cast<size_t>(i)].last = kids.back();
        for (size_t k = 0; k < kids.size(); k++) {
            if (k > 0) {
                nodes[static_cast<size_t>(kids[k])].prev = kids[k - 1];
            }
            if (k + 1 < kids.size()) {
                nodes[static_cast<size_t>(kids[k])].next = kids[k + 1];
            }
        }
    }
    for (size_t k = 0; k < roots.size(); k++) {
        if (k > 0) {
            nodes[static_cast<size_t>(roots[k])].prev = roots[k - 1];
        }
        if (k + 1 < roots.size()) {
            nodes[static_cast<size_t>(roots[k])].next = roots[k + 1];
        }
    }

    for (int i = static_cast<int>(bookmarks.size()) - 1; i >= 0; i--) {
        int desc = static_cast<int>(children[static_cast<size_t>(i)].size());
        for (int child : children[static_cast<size_t>(i)]) {
            desc += nodes[static_cast<size_t>(child)].count;
        }
        nodes[static_cast<size_t>(i)].count = desc;
    }

    int rootCount = static_cast<int>(roots.size());
    for (int root : roots) {
        rootCount += nodes[static_cast<size_t>(root)].count;
    }

    Value rootDict;
    rootDict.kind = Kind::Dict;
    dictSet(rootDict, "Type", makeName("Outlines"));
    if (!roots.empty()) {
        dictSet(rootDict, "First", makeRef(itemObjs[static_cast<size_t>(roots.front())]));
        dictSet(rootDict, "Last", makeRef(itemObjs[static_cast<size_t>(roots.back())]));
        dictSet(rootDict, "Count", makeInt(rootCount));
    }
    const long long rootOffset = static_cast<long long>(out.tellp());
    out << rootObj << " 0 obj\n";
    writeValue(out, rootDict);
    out << "\nendobj\n";
    written.push_back({ rootObj, rootOffset });

    for (size_t i = 0; i < bookmarks.size(); i++) {
        Value item;
        item.kind = Kind::Dict;
        dictSet(item, "Title", makeString(bookmarks[i].title));
        const int parent = nodes[i].parent;
        dictSet(item, "Parent", makeRef(parent < 0 ? rootObj : itemObjs[static_cast<size_t>(parent)]));
        if (nodes[i].prev >= 0) {
            dictSet(item, "Prev", makeRef(itemObjs[static_cast<size_t>(nodes[i].prev)]));
        }
        if (nodes[i].next >= 0) {
            dictSet(item, "Next", makeRef(itemObjs[static_cast<size_t>(nodes[i].next)]));
        }
        if (nodes[i].first >= 0) {
            dictSet(item, "First", makeRef(itemObjs[static_cast<size_t>(nodes[i].first)]));
            dictSet(item, "Last", makeRef(itemObjs[static_cast<size_t>(nodes[i].last)]));
            dictSet(item, "Count", makeInt(nodes[i].count));
        }
        Value dest = makeBookmarkDest(parser, bookmarks[i]);
        if (!dest.items.empty()) {
            dictSet(item, "Dest", dest);
            Value action;
            action.kind = Kind::Dict;
            dictSet(action, "S", makeName("GoTo"));
            dictSet(action, "D", dest);
            dictSet(item, "A", action);
        }
        if (bookmarks[i].titleColor != 0) {
            Value color;
            color.kind = Kind::Array;
            color.items.push_back(makeReal((bookmarks[i].titleColor & 0xFF) / 255.0));
            color.items.push_back(makeReal(((bookmarks[i].titleColor >> 8) & 0xFF) / 255.0));
            color.items.push_back(makeReal(((bookmarks[i].titleColor >> 16) & 0xFF) / 255.0));
            dictSet(item, "C", color);
        }
        const int flags = (bookmarks[i].isItalic ? 1 : 0) | (bookmarks[i].isBold ? 2 : 0);
        if (flags != 0) {
            dictSet(item, "F", makeInt(flags));
        }
        const long long itemOffset = static_cast<long long>(out.tellp());
        out << itemObjs[i] << " 0 obj\n";
        writeValue(out, item);
        out << "\nendobj\n";
        written.push_back({ itemObjs[i], itemOffset });
    }

    dictSet(catalog.dict, "Outlines", makeRef(rootObj));
    const long long catalogOffset = static_cast<long long>(out.tellp());
    out << catalogRef.obj << " 0 obj\n";
    writeValue(out, catalog.dict);
    out << "\nendobj\n";
    written.push_back({ catalogRef.obj, catalogOffset });
}

} // namespace

JustPdfAnnotWriteResult JustPdf_WritePolylines(
    const std::string& inputPath,
    const std::string& outputPath,
    const std::vector<JustPdfPolylineStroke>& strokes,
    const std::vector<int>& stripPageIndices,
    const std::vector<JustPdfBookmarkItem>& bookmarks,
    bool writeBookmarks)
{
    JustPdfAnnotWriteResult result;
    if (inputPath.empty() || outputPath.empty()) {
        result.status = JUSTPDF_ANNOT_ERR_ARGS;
        result.message = "empty args";
        return result;
    }

    Parser parser;
    if (!parser.loadFile(inputPath)) {
        result.message = parser.error;
        result.status = parser.error == "encrypted" ? JUSTPDF_ANNOT_ERR_ENCRYPT : JUSTPDF_ANNOT_ERR_PARSE;
        return result;
    }

    std::map<int, std::vector<size_t>> byPage;
    for (size_t i = 0; i < strokes.size(); i++) {
        if (strokes[i].pageIndex < 0 || strokes[i].xs.size() < 2) {
            continue;
        }
        byPage[strokes[i].pageIndex].push_back(i);
    }
    for (int pageIndex : stripPageIndices) {
        if (pageIndex >= 0) {
            byPage[pageIndex];
        }
    }

    if (!copyFile(inputPath, outputPath)) {
        result.status = JUSTPDF_ANNOT_ERR_WRITE;
        result.message = "copy failed";
        return result;
    }

    if (byPage.empty() && !writeBookmarks) {
        result.status = JUSTPDF_ANNOT_OK;
        result.message = "copied";
        return result;
    }

    std::fstream out(outputPath.c_str(), std::ios::binary | std::ios::in | std::ios::out);
    if (!out) {
        result.status = JUSTPDF_ANNOT_ERR_WRITE;
        result.message = "append failed";
        return result;
    }
    out.seekp(0, std::ios::end);
    if (!out || static_cast<long long>(out.tellp()) < 0) {
        result.status = JUSTPDF_ANNOT_ERR_WRITE;
        result.message = "seek end failed";
        return result;
    }
    out << '\n';

    std::vector<WrittenObj> written;
    int nextObj = parser.nextObjectNumber();

    for (const auto& pageItem : byPage) {
        Ref pageRef;
        if (!parser.getPageRef(pageItem.first, pageRef)) {
            result.status = JUSTPDF_ANNOT_ERR_PAGE;
            result.message = parser.error.empty() ? "page not found" : parser.error;
            return result;
        }
        StreamObj page;
        if (!parser.parseObject(pageRef.obj, page)) {
            result.status = JUSTPDF_ANNOT_ERR_PARSE;
            result.message = parser.error;
            return result;
        }

        Value annots;
        annots.kind = Kind::Array;
        const Value* existing = nullptr;
        for (const auto& field : page.dict.fields) {
            if (field.first == "Annots") {
                existing = &field.second;
                break;
            }
        }
        if (existing != nullptr) {
            Value resolved = *existing;
            int guard = 0;
            while (resolved.kind == Kind::Ref && guard < 8) {
                StreamObj obj;
                if (!parser.parseObject(resolved.ref.obj, obj)) {
                    result.status = JUSTPDF_ANNOT_ERR_PARSE;
                    result.message = parser.error;
                    return result;
                }
                resolved = obj.dict;
                guard++;
            }
            if (resolved.kind == Kind::Array) {
                for (const Value& item : resolved.items) {
                    if (parser.isPolylineAnnot(item)) {
                        continue;
                    }
                    annots.items.push_back(item);
                }
            }
        }

        for (size_t strokeIndex : pageItem.second) {
            const StrokeGeom geom = measureStroke(strokes[strokeIndex]);
            const int formObj = nextObj++;
            const int annotObj = nextObj++;
            const long long formOffset = static_cast<long long>(out.tellp());
            writeAppearanceForm(out, formObj, strokes[strokeIndex], geom);
            written.push_back({ formObj, formOffset });
            const long long annotOffset = static_cast<long long>(out.tellp());
            out << annotObj << " 0 obj\n";
            writeValue(out, makePolylineAnnot(strokes[strokeIndex], pageRef.obj, formObj, geom));
            out << "\nendobj\n";
            written.push_back({ annotObj, annotOffset });
            annots.items.push_back(makeRef(annotObj));
            result.writtenStrokeCount++;
        }

        dictSet(page.dict, "Annots", annots);
        const long long pageOffset = static_cast<long long>(out.tellp());
        out << pageRef.obj << " 0 obj\n";
        writeValue(out, page.dict);
        out << "\nendobj\n";
        written.push_back({ pageRef.obj, pageOffset });
        result.writtenPageCount++;
    }

    if (writeBookmarks && !bookmarks.empty()) {
        writeOutlineTree(parser, out, nextObj, written, bookmarks);
    }

    const long long xrefOffset = static_cast<long long>(out.tellp());
    std::sort(written.begin(), written.end(), [](const WrittenObj& a, const WrittenObj& b) {
        return a.obj < b.obj;
    });
    out << "xref\n";
    size_t i = 0;
    while (i < written.size()) {
        size_t j = i + 1;
        while (j < written.size() && written[j].obj == written[j - 1].obj + 1) {
            j++;
        }
        out << written[i].obj << ' ' << (j - i) << '\n';
        for (size_t k = i; k < j; k++) {
            char line[32];
            std::snprintf(line, sizeof(line), "%010lld 00000 n \n", written[k].offset);
            out << line;
        }
        i = j;
    }

    const int newSize = nextObj;
    out << "trailer\n<< /Size " << newSize << " /Prev " << parser.lastXrefOffset;
    for (const auto& field : parser.trailer.fields) {
        if (field.first == "Size" || field.first == "Prev" || field.first == "Type" ||
            field.first == "W" || field.first == "Index" || field.first == "Filter" ||
            field.first == "DecodeParms" || field.first == "Length" || field.first == "DP") {
            continue;
        }
        out << " /" << field.first << ' ';
        writeValue(out, field.second);
    }
    out << " >>\nstartxref\n" << xrefOffset << "\n%%EOF\n";
    if (!out) {
        result.status = JUSTPDF_ANNOT_ERR_WRITE;
        result.message = "flush failed";
        return result;
    }
    out.close();

    result.status = JUSTPDF_ANNOT_OK;
    result.message = "ok";
    return result;
}
