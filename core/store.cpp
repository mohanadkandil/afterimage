#include "store.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <fcntl.h>
#include <fstream>
#include <iomanip>
#include <set>
#include <sstream>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>

namespace afterimage {
namespace {
void syncMedia(const fs::path& path) {
    int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        throw std::runtime_error("Cannot open media for durable publication");
    }
    int result = fsync(fd);
    close(fd);
    if (result != 0) {
        throw std::runtime_error("Cannot flush media to disk");
    }
}

// A quick lookup fingerprint; candidates are always compared byte-for-byte.
std::string imageKey(const std::vector<unsigned char>& bytes) {
    uint64_t hash = 14695981039346656037ULL;
    for (auto byte : bytes) {
        hash = (hash ^ byte) * 1099511628211ULL;
    }
    std::ostringstream out;
    out << std::hex << hash << ":" << bytes.size();
    return out.str();
}

std::vector<unsigned char> readBytes(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("Could not read stored image");
    }
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}

struct Stmt {
    sqlite3_stmt* p = nullptr;
    sqlite3* db;

    Stmt(sqlite3* d, const char* s) : db(d) {
        if (sqlite3_prepare_v2(d, s, -1, &p, nullptr) != SQLITE_OK) {
            throw std::runtime_error(sqlite3_errmsg(d));
        }
    }

    ~Stmt() {
        sqlite3_finalize(p);
    }

    void bind(int n, const std::string& s) {
        sqlite3_bind_text(p, n, s.c_str(), -1, SQLITE_TRANSIENT);
    }

    void bind(int n, double v) {
        sqlite3_bind_double(p, n, v);
    }

    void bind(int n, long long v) {
        sqlite3_bind_int64(p, n, v);
    }

    int step() {
        int r = sqlite3_step(p);
        if (r != SQLITE_ROW && r != SQLITE_DONE) {
            throw std::runtime_error(sqlite3_errmsg(db));
        }
        return r;
    }
};

std::string col(sqlite3_stmt* p, int n) {
    auto t = sqlite3_column_text(p, n);
    return t ? reinterpret_cast<const char*>(t) : "";
}

const char* columns = "f.id,f.time,f.app,f.bundle,f.title,f.text,f.width,f."
                      "height,f.boxes,f.source,f.bytes";
} // namespace

double now() {
    return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch())
        .count();
}

void Store::exec(const char* sql) {
    char* error = nullptr;
    if (sqlite3_exec(db_, sql, nullptr, nullptr, &error) != SQLITE_OK) {
        std::string e = error ? error : "Database error";
        sqlite3_free(error);
        throw std::runtime_error(e);
    }
}

Store::Store(fs::path root, SegmentCodec codec) : codec_(std::move(codec)), root_(std::move(root)) {
    fs::create_directories(root_ / "segments");
    chmod((root_ / "segments").c_str(), 0700);
    fs::create_directories(root_ / "frames");
    chmod(root_.c_str(), 0700);
    chmod((root_ / "frames").c_str(), 0700);
    if (sqlite3_open((root_ / "archive.sqlite").c_str(), &db_) != SQLITE_OK) {
        std::string e = sqlite3_errmsg(db_);
        sqlite3_close(db_);
        db_ = nullptr;
        throw std::runtime_error(e);
    }
    sqlite3_busy_timeout(db_, 5000);
    exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA "
         "foreign_keys=ON; PRAGMA secure_delete=ON;");
    exec("CREATE TABLE IF NOT EXISTS frames(id INTEGER PRIMARY KEY "
         "AUTOINCREMENT,time REAL NOT NULL,app TEXT NOT NULL,bundle TEXT NOT "
         "NULL,title TEXT NOT NULL,text TEXT NOT NULL,width INTEGER,height "
         "INTEGER,boxes TEXT,source TEXT,bytes INTEGER);CREATE INDEX IF NOT "
         "EXISTS frames_time ON frames(time);CREATE INDEX IF NOT EXISTS "
         "frames_bundle_time ON frames(bundle,time);CREATE TABLE IF NOT EXISTS "
         "settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);CREATE VIRTUAL "
         "TABLE IF NOT EXISTS search USING "
         "fts5(title,text,app,content='frames',content_rowid='id',tokenize='"
         "unicode61');CREATE TRIGGER IF NOT EXISTS frames_ai AFTER INSERT ON "
         "frames BEGIN INSERT INTO search(rowid,title,text,app) "
         "VALUES(new.id,new.title,new.text,new.app);END;CREATE TRIGGER IF NOT "
         "EXISTS frames_ad AFTER DELETE ON frames BEGIN INSERT INTO "
         "search(search,rowid,title,text,app) "
         "VALUES('delete',old.id,old.title,old.text,old.app);END;");
    int schemaVersion = 0;
    {
        Stmt version(db_, "PRAGMA user_version");
        version.step();
        schemaVersion = sqlite3_column_int(version.p, 0);
    }
    if (schemaVersion < 3) {
        exec("BEGIN IMMEDIATE");
        try {
            bool hasImageKey = false;
            bool hasSegments = false;
            {
                Stmt columns(db_, "PRAGMA table_info(frames)");
                while (columns.step() == SQLITE_ROW) {
                    if (col(columns.p, 1) == "segment") {
                        hasSegments = true;
                    }
                    if (col(columns.p, 1) == "image_hash") {
                        hasImageKey = true;
                    }
                }
            }
            if (!hasImageKey) {
                exec("ALTER TABLE frames ADD COLUMN image_hash TEXT; ALTER TABLE frames ADD COLUMN "
                     "storage_id INTEGER; PRAGMA user_version=2;");
            }
            if (!hasSegments) {
                exec("ALTER TABLE frames ADD COLUMN segment TEXT NOT NULL DEFAULT ''; ALTER TABLE "
                     "frames ADD COLUMN segment_index INTEGER; ALTER TABLE frames ADD COLUMN "
                     "keep_still INTEGER NOT NULL DEFAULT 0;");
            }
            exec("CREATE TABLE IF NOT EXISTS segments(name TEXT PRIMARY KEY,bytes INTEGER NOT "
                 "NULL); CREATE INDEX IF NOT EXISTS frames_segment ON frames(segment); PRAGMA "
                 "user_version=3;");
            exec("COMMIT");
        } catch (...) {
            exec("ROLLBACK");
            throw;
        }
    }
    exec("CREATE INDEX IF NOT EXISTS frames_image_hash ON frames(image_hash)");
    chmod((root_ / "archive.sqlite").c_str(), 0600);
}

Store::~Store() {
    if (db_) {
        sqlite3_close(db_);
    }
}

long long Store::add(const Frame& f, const std::vector<unsigned char>& bytes) {
    std::lock_guard lock(mutex_);
    if (bytes.empty() || f.width <= 0 || f.height <= 0 || !std::isfinite(f.time)) {
        throw std::invalid_argument("Invalid image or timestamp");
    }
    exec("BEGIN IMMEDIATE");
    fs::path path;
    try {
        Stmt s(db_, "INSERT INTO "
                    "frames(time,app,bundle,title,text,width,height,boxes,source,"
                    "bytes) VALUES(?,?,?,?,?,?,?,?,?,?)");
        s.bind(1, f.time);
        s.bind(2, f.app);
        s.bind(3, f.bundle);
        s.bind(4, f.title);
        s.bind(5, f.text);
        s.bind(6, (long long)f.width);
        s.bind(7, (long long)f.height);
        s.bind(8, f.boxes.dump());
        s.bind(9, f.source);
        s.bind(10, (long long)bytes.size());
        s.step();
        auto id = sqlite3_last_insert_rowid(db_);
        bool png = bytes.size() >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e &&
                   bytes[3] == 0x47;
        path = root_ / "frames" / (std::to_string(id) + (png ? ".png" : ".jpg"));
        if (fs::exists(path)) {
            fs::remove(path);
        }
        auto existing = duplicate(bytes);
        long long storageId = id;
        bool linked = false;
        if (existing) {
            std::error_code error;
            fs::create_hard_link(still(existing->first), path, error);
            if (!error) {
                linked = true;
                storageId = existing->second;
            }
        }
        if (!linked) {
            std::ofstream out(path, std::ios::binary);
            out.write((const char*)bytes.data(), bytes.size());
            out.close();
            if (!out) {
                throw std::runtime_error("Could not store image");
            }
        }
        Stmt update(db_, "UPDATE frames SET image_hash=?, storage_id=? WHERE id=?");
        update.bind(1, imageKey(bytes));
        update.bind(2, storageId);
        update.bind(3, (long long)id);
        update.step();
        chmod(path.c_str(), 0600);
        syncMedia(path);
        syncMedia(root_ / "frames");
        exec("COMMIT");
        return id;
    } catch (...) {
        exec("ROLLBACK");
        if (!path.empty()) {
            std::error_code e;
            fs::remove(path, e);
        }
        throw;
    }
}

std::string literalQuery(const std::string& input) {
    std::string result, word;
    auto emit = [&] {
        if (word.empty()) {
            return;
        }
        if (!result.empty()) {
            result += " AND ";
        }
        result += '"';
        for (char c : word) {
            result += c;
            if (c == '"') {
                result += '"';
            }
        }
        result += '"';
        word.clear();
    };
    for (unsigned char c : input) {
        if (std::isspace(c)) {
            emit();
        } else {
            word += c;
        }
    }
    emit();
    return result;
}

json Store::row(sqlite3_stmt* p) const {
    auto boxes = json::parse(col(p, 8), nullptr, false);
    if (boxes.is_discarded()) {
        boxes = json::array();
    }
    return {{"id", sqlite3_column_int64(p, 0)},
            {"time", sqlite3_column_double(p, 1)},
            {"app", col(p, 2)},
            {"bundle", col(p, 3)},
            {"title", col(p, 4)},
            {"text", col(p, 5)},
            {"width", sqlite3_column_int(p, 6)},
            {"height", sqlite3_column_int(p, 7)},
            {"boxes", boxes},
            {"source", col(p, 9)},
            {"bytes", sqlite3_column_int64(p, 10)}};
}

json Store::frames(std::string query, std::string bundle, double from, double to, int limit,
                   int offset) {
    std::lock_guard lock(mutex_);
    auto q = literalQuery(query);
    std::string sql = "SELECT ";
    sql += columns;
    sql += " FROM frames f ";
    if (!q.empty()) {
        sql += "JOIN search ON search.rowid=f.id ";
    }
    sql += "WHERE f.time>=? AND f.time<? AND (?='' OR f.bundle=?) ";
    if (!q.empty()) {
        sql += "AND search MATCH ? ";
    }
    sql += "ORDER BY f.time DESC,f.id DESC LIMIT ? OFFSET ?";
    Stmt s(db_, sql.c_str());
    s.bind(1, from);
    s.bind(2, to);
    s.bind(3, bundle);
    s.bind(4, bundle);
    int n = 5;
    if (!q.empty()) {
        s.bind(n++, q);
    }
    s.bind(n++, (long long)std::clamp(limit, 1, 1000));
    s.bind(n, (long long)std::max(offset, 0));
    json a = json::array();
    while (s.step() == SQLITE_ROW) {
        a.push_back(row(s.p));
    }
    return a;
}

json Store::frame(long long id) {
    std::lock_guard lock(mutex_);
    std::string sql = "SELECT ";
    sql += columns;
    sql += " FROM frames f WHERE id=?";
    Stmt s(db_, sql.c_str());
    s.bind(1, id);
    if (s.step() != SQLITE_ROW) {
        throw std::runtime_error("Frame not found");
    }
    return row(s.p);
}

fs::path Store::still(long long id) const {
    auto png = root_ / "frames" / (std::to_string(id) + ".png");
    return fs::exists(png) ? png : root_ / "frames" / (std::to_string(id) + ".jpg");
}

fs::path Store::image(long long id) {
    std::lock_guard lock(mutex_);
    std::string segment;
    {
        Stmt row(db_, "SELECT segment FROM frames WHERE id=?");
        row.bind(1, id);
        if (row.step() != SQLITE_ROW) {
            throw std::runtime_error("Frame not found");
        }
        segment = col(row.p, 0);
    }
    if (segment.empty()) {
        return still(id);
    }
    if (!codec_.decode) {
        throw std::runtime_error("Video decoding is unavailable");
    }
    auto cache = root_ / "cache";
    fs::create_directories(cache);
    chmod(cache.c_str(), 0700);
    auto output = cache / (std::to_string(id) + ".png");
    if (!fs::exists(output)) {
        // The writer transaction also serializes cross-process cache publication and deletion.
        exec("BEGIN IMMEDIATE");
        try {
            Stmt current(db_, "SELECT segment,segment_index FROM frames WHERE id=?");
            current.bind(1, id);
            if (current.step() != SQLITE_ROW) {
                throw std::runtime_error("Frame was deleted");
            }
            segment = col(current.p, 0);
            if (segment.empty()) {
                exec("COMMIT");
                return still(id);
            }
            auto temp = cache / (std::to_string(id) + ".partial.png");
            codec_.decode(root_ / "segments" / segment, sqlite3_column_int(current.p, 1), temp);
            chmod(temp.c_str(), 0600);
            fs::rename(temp, output);
            std::vector<fs::directory_entry> entries;
            uintmax_t bytes = 0;
            for (auto& entry : fs::directory_iterator(cache)) {
                if (entry.is_regular_file() && entry.path() != output) {
                    entries.push_back(entry);
                }
                if (entry.is_regular_file()) {
                    bytes += entry.file_size();
                }
            }
            std::sort(entries.begin(), entries.end(),
                      [](auto& a, auto& b) { return a.last_write_time() < b.last_write_time(); });
            size_t count = entries.size() + 1;
            for (auto& entry : entries) {
                if (count <= 8 && bytes <= 32 * 1024 * 1024) {
                    break;
                }
                bytes -= entry.file_size();
                fs::remove(entry.path());
                // Also cap count, independently of file size.
                --count;
            }
            exec("COMMIT");
        } catch (...) {
            exec("ROLLBACK");
            throw;
        }
    }
    return output;
}

// Call only while holding the SQLite writer transaction. Leftovers from an interrupted
// publication can be removed because committed metadata is the authority.
void Store::cleanupMedia() {
    std::set<std::string> liveSegments, liveStills;
    Stmt rows(db_, "SELECT id,segment FROM frames");
    while (rows.step() == SQLITE_ROW) {
        auto name = col(rows.p, 1);
        if (name.empty()) {
            liveStills.insert(still(sqlite3_column_int64(rows.p, 0)).filename().string());
        } else {
            liveSegments.insert(name);
        }
    }
    for (auto& entry : fs::directory_iterator(root_ / "segments")) {
        if (entry.is_regular_file() && !liveSegments.count(entry.path().filename().string())) {
            fs::remove(entry.path());
        }
    }
    for (auto& entry : fs::directory_iterator(root_ / "frames")) {
        if (entry.is_regular_file() && !liveStills.count(entry.path().filename().string())) {
            fs::remove(entry.path());
        }
    }
}

json Store::compact(bool flush) {
    if (!codec_.encode || !codec_.decode) {
        throw std::runtime_error("HEVC encoder is unavailable");
    }
    std::lock_guard lock(mutex_);
    if (!flush) {
        Stmt pending(db_, "SELECT count(*) FROM (SELECT id FROM frames WHERE segment='' AND "
                          "keep_still=0 LIMIT 30)");
        pending.step();
        if (sqlite3_column_int(pending.p, 0) < 30 &&
            sqlite3_column_int64(pending.p, 1) < 32 * 1024 * 1024) {
            return {{"packedFrames", 0}};
        }
    }
    auto before = stats();
    auto mode = settings().value("compressionMode", "balanced");
    if (mode == "jpeg") {
        return {{"before", before}, {"after", before}, {"packedFrames", 0}};
    }
    double quality = mode == "sharp" ? 0.90 : 0.80;
    int packed = 0;
    while (true) {
        exec("BEGIN IMMEDIATE");
        fs::path stagingOutput, validationOutput, publishedOutput;
        try {
            std::vector<long long> ids;
            std::vector<fs::path> paths;
            int width = 0, height = 0;
            bool boundary = false;
            uintmax_t stagedBytes = 0;
            {
                Stmt rows(db_, "SELECT id,width,height FROM frames WHERE segment='' AND "
                               "keep_still=0 ORDER BY time,id LIMIT 30");
                while (rows.step() == SQLITE_ROW) {
                    int w = sqlite3_column_int(rows.p, 1), h = sqlite3_column_int(rows.p, 2);
                    if (!ids.empty() && (w != width || h != height)) {
                        boundary = true;
                        break;
                    }
                    width = w;
                    height = h;
                    auto id = sqlite3_column_int64(rows.p, 0);
                    ids.push_back(id);
                    paths.push_back(still(id));
                    stagedBytes += fs::file_size(paths.back());
                    if (stagedBytes >= 32 * 1024 * 1024) {
                        boundary = true;
                        break;
                    }
                }
            }
            if (ids.empty() || (!flush && ids.size() < 30 && !boundary)) {
                exec("COMMIT");
                break;
            }
            auto name =
                std::to_string(ids.front()) + "-" +
                std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()) +
                ".mp4";
            auto temp = root_ / "segments" / (name + ".partial.mp4");
            auto output = root_ / "segments" / name;
            stagingOutput = temp;
            publishedOutput = output;
            codec_.encode(paths, temp, quality);
            // Decode both boundaries before committing; append failures abort inside the codec.
            auto probe = root_ / "segments" / (name + ".check.png");
            validationOutput = probe;
            codec_.decode(temp, 0, probe);
            codec_.decode(temp, (int)ids.size() - 1, probe);
            fs::remove(probe);
            auto videoBytes = fs::file_size(temp);
            uintmax_t stillBytes = 0;
            std::set<std::string> unique;
            for (auto& path : paths) {
                auto bytes = readBytes(path);
                if (unique.insert(imageKey(bytes)).second) {
                    stillBytes += bytes.size();
                }
            }
            if (videoBytes >= stillBytes) {
                fs::remove(temp);
                for (auto id : ids) {
                    Stmt mark(db_, "UPDATE frames SET keep_still=1 WHERE id=?");
                    mark.bind(1, id);
                    mark.step();
                }
            } else {
                chmod(temp.c_str(), 0600);
                syncMedia(temp);
                fs::rename(temp, output);
                syncMedia(root_ / "segments");
                Stmt segment(db_, "INSERT INTO segments(name,bytes) VALUES(?,?)");
                segment.bind(1, name);
                segment.bind(2, (long long)videoBytes);
                segment.step();
                for (size_t i = 0; i < ids.size(); i++) {
                    Stmt update(db_, "UPDATE frames SET segment=?,segment_index=? WHERE id=?");
                    update.bind(1, name);
                    update.bind(2, (long long)i);
                    update.bind(3, ids[i]);
                    update.step();
                }
                packed += (int)ids.size();
            }
            exec("COMMIT");
            if (fs::exists(output)) {
                for (auto& path : paths) {
                    std::error_code ignored;
                    fs::remove(path, ignored);
                }
            }
        } catch (...) {
            if (!sqlite3_get_autocommit(db_)) {
                exec("ROLLBACK");
            }
            std::error_code ignored;
            if (!stagingOutput.empty()) {
                fs::remove(stagingOutput, ignored);
            }
            if (!validationOutput.empty()) {
                fs::remove(validationOutput, ignored);
            }
            if (!publishedOutput.empty()) {
                Stmt exists(db_, "SELECT 1 FROM segments WHERE name=?");
                exists.bind(1, publishedOutput.filename().string());
                if (exists.step() != SQLITE_ROW) {
                    fs::remove(publishedOutput, ignored);
                }
            }
            throw;
        }
    }
    if (flush) {
        exec("BEGIN IMMEDIATE");
        try {
            cleanupMedia();
            exec("COMMIT");
        } catch (...) {
            exec("ROLLBACK");
            throw;
        }
    }
    exec("PRAGMA wal_checkpoint(TRUNCATE)");
    return {{"before", before}, {"after", stats()}, {"packedFrames", packed}};
}

std::optional<std::pair<long long, long long>>
Store::duplicate(const std::vector<unsigned char>& bytes, long long exclude) {
    Stmt candidates(db_, "SELECT id, coalesce(storage_id,id) FROM frames WHERE image_hash=? AND "
                         "id<>? AND segment='' AND keep_still=0");
    candidates.bind(1, imageKey(bytes));
    candidates.bind(2, exclude);
    while (candidates.step() == SQLITE_ROW) {
        auto id = sqlite3_column_int64(candidates.p, 0);
        auto path = still(id);
        if (fs::exists(path) && readBytes(path) == bytes) {
            return std::pair<long long, long long>{id, sqlite3_column_int64(candidates.p, 1)};
        }
    }
    return std::nullopt;
}

json Store::optimize() {
    std::lock_guard lock(mutex_);
    auto before = stats();
    exec("BEGIN IMMEDIATE");
    try {
        std::vector<long long> ids;
        {
            Stmt rows(db_, "SELECT id FROM frames WHERE segment='' AND keep_still=0 ORDER BY id");
            while (rows.step() == SQLITE_ROW) {
                ids.push_back(sqlite3_column_int64(rows.p, 0));
            }
        }
        for (auto id : ids) {
            auto path = still(id);
            auto bytes = readBytes(path);
            auto existing = duplicate(bytes, id);
            long long storageId = id;
            if (existing) {
                auto source = still(existing->first);
                if (!fs::equivalent(source, path)) {
                    auto temporary = path;
                    temporary += ".dedup";
                    std::error_code ignored;
                    fs::remove(temporary, ignored);
                    fs::create_hard_link(source, temporary);
                    try {
                        fs::rename(temporary, path);
                    } catch (...) {
                        fs::remove(temporary, ignored);
                        throw;
                    }
                }
                storageId = existing->second;
            }
            Stmt update(db_, "UPDATE frames SET image_hash=?, storage_id=? WHERE id=?");
            update.bind(1, imageKey(bytes));
            update.bind(2, storageId);
            update.bind(3, id);
            update.step();
        }
        exec("COMMIT");
    } catch (...) {
        exec("ROLLBACK");
        throw;
    }
    exec("PRAGMA wal_checkpoint(TRUNCATE)");
    return {{"before", before}, {"after", stats()}};
}

json Store::stats() {
    std::lock_guard lock(mutex_);
    Stmt s(db_, "SELECT count(*),coalesce(sum(bytes),0),min(time),max(time) FROM frames");
    s.step();
    json j = {{"count", sqlite3_column_int64(s.p, 0)},
              {"imageBytes", sqlite3_column_int64(s.p, 1)},
              {"first", sqlite3_column_double(s.p, 2)},
              {"last", sqlite3_column_double(s.p, 3)}};
    j["logicalImageBytes"] = j["imageBytes"];
    Stmt physical(db_, "SELECT coalesce(sum(bytes),0),count(*) FROM (SELECT max(bytes) AS bytes "
                       "FROM frames WHERE segment='' GROUP BY coalesce(storage_id,id))");
    physical.step();
    j["stillBytes"] = sqlite3_column_int64(physical.p, 0);
    Stmt video(db_, "SELECT coalesce(sum(bytes),0),count(*) FROM segments");
    video.step();
    j["videoBytes"] = sqlite3_column_int64(video.p, 0);
    j["segments"] = sqlite3_column_int64(video.p, 1);
    j["imageBytes"] = j["stillBytes"].get<long long>() + j["videoBytes"].get<long long>();
    j["uniqueImages"] = sqlite3_column_int64(physical.p, 1);
    Stmt logicalStills(db_, "SELECT coalesce(sum(bytes),0) FROM frames WHERE segment=''");
    logicalStills.step();
    j["deduplicatedBytes"] =
        sqlite3_column_int64(logicalStills.p, 0) - j["stillBytes"].get<long long>();
    j["compressionSavedBytes"] =
        j["logicalImageBytes"].get<long long>() - j["imageBytes"].get<long long>();
    json apps = json::array();
    Stmt a(db_, "SELECT bundle,app,count(*) FROM frames GROUP BY bundle ORDER BY "
                "count(*) DESC");
    while (a.step() == SQLITE_ROW) {
        apps.push_back({{"bundle", col(a.p, 0)},
                        {"name", col(a.p, 1)},
                        {"count", sqlite3_column_int64(a.p, 2)}});
    }
    j["apps"] = apps;
    long long disk = 0;
    for (auto& e : fs::directory_iterator(root_)) {
        struct stat info;
        if (::stat(e.path().c_str(), &info) == 0 && S_ISREG(info.st_mode)) {
            disk += info.st_size;
        }
    }
    long long cacheBytes = 0;
    if (fs::exists(root_ / "cache")) {
        for (auto& e : fs::directory_iterator(root_ / "cache")) {
            struct stat info;
            if (::stat(e.path().c_str(), &info) == 0 && S_ISREG(info.st_mode)) {
                cacheBytes += info.st_size;
            }
        }
    }
    long long mediaBytes = 0;
    std::set<std::pair<dev_t, ino_t>> inodes;
    for (auto directory : {"frames", "segments"}) {
        for (auto& e : fs::directory_iterator(root_ / directory)) {
            struct stat info;
            if (::stat(e.path().c_str(), &info) == 0 && S_ISREG(info.st_mode) &&
                inodes.emplace(info.st_dev, info.st_ino).second) {
                mediaBytes += info.st_size;
            }
        }
    }
    j["workingBytes"] = std::max(0LL, mediaBytes - j["imageBytes"].get<long long>());
    j["cacheBytes"] = cacheBytes;
    j["diskBytes"] = disk + mediaBytes + cacheBytes;
    return j;
}

void Store::eraseMany(const std::vector<long long>& ids) {
    std::lock_guard lock(mutex_);
    if (ids.empty()) {
        return;
    }
    std::set<long long> removed(ids.begin(), ids.end());
    exec("BEGIN IMMEDIATE");
    try {
        std::set<std::string> affected;
        for (auto id : ids) {
            Stmt row(db_, "SELECT segment FROM frames WHERE id=?");
            row.bind(1, id);
            if (row.step() == SQLITE_ROW && !col(row.p, 0).empty()) {
                affected.insert(col(row.p, 0));
            }
        }
        for (auto& segment : affected) {
            std::vector<std::pair<long long, int>> survivors;
            {
                Stmt rows(db_, "SELECT id,segment_index FROM frames WHERE segment=?");
                rows.bind(1, segment);
                while (rows.step() == SQLITE_ROW) {
                    auto id = sqlite3_column_int64(rows.p, 0);
                    if (!removed.count(id)) {
                        survivors.emplace_back(id, sqlite3_column_int(rows.p, 1));
                    }
                }
            }
            // A partially deleted chunk must not retain the deleted pixels. Materialize its
            // survivors as lossless PNGs; do not introduce another lossy encoding generation.
            for (auto [id, index] : survivors) {
                if (!codec_.decode) {
                    throw std::runtime_error("Video decoding is unavailable");
                }
                auto path = root_ / "frames" / (std::to_string(id) + ".png");
                auto temp = root_ / "frames" / (std::to_string(id) + ".partial.png");
                codec_.decode(root_ / "segments" / segment, index, temp);
                chmod(temp.c_str(), 0600);
                syncMedia(temp);
                fs::rename(temp, path);
                syncMedia(root_ / "frames");
                Stmt update(db_, "UPDATE frames SET "
                                 "segment='',segment_index=NULL,keep_still=1,storage_id=id,image_"
                                 "hash=NULL,bytes=? WHERE id=?");
                update.bind(1, (long long)fs::file_size(path));
                update.bind(2, id);
                update.step();
            }
            Stmt drop(db_, "DELETE FROM segments WHERE name=?");
            drop.bind(1, segment);
            drop.step();
        }
        for (auto id : ids) {
            Stmt drop(db_, "DELETE FROM frames WHERE id=?");
            drop.bind(1, id);
            drop.step();
        }
        exec("COMMIT");
    } catch (...) {
        exec("ROLLBACK");
        throw;
    }
    exec("BEGIN IMMEDIATE");
    try {
        cleanupMedia();
        for (auto id : ids) {
            fs::remove(root_ / "cache" / (std::to_string(id) + ".png"));
            fs::remove(root_ / "cache" / (std::to_string(id) + ".partial.png"));
        }
        exec("COMMIT");
    } catch (...) {
        exec("ROLLBACK");
        throw;
    }
}

void Store::erase(long long id) {
    frame(id);
    eraseMany({id});
}

void Store::clear() {
    std::lock_guard lock(mutex_);
    std::vector<long long> ids;
    {
        Stmt rows(db_, "SELECT id FROM frames");
        while (rows.step() == SQLITE_ROW) {
            ids.push_back(sqlite3_column_int64(rows.p, 0));
        }
    }
    eraseMany(ids);
    exec("PRAGMA wal_checkpoint(TRUNCATE)");
}

int Store::prune(int days, double time) {
    if (days < 1 || days > 3650) {
        throw std::invalid_argument("Retention must be 1–3650 days");
    }
    std::lock_guard lock(mutex_);
    Stmt s(db_, "SELECT id FROM frames WHERE time<?");
    s.bind(1, time - days * 86400.0);
    std::vector<long long> ids;
    while (s.step() == SQLITE_ROW) {
        ids.push_back(sqlite3_column_int64(s.p, 0));
    }
    eraseMany(ids);
    exec("PRAGMA wal_checkpoint(TRUNCATE)");
    return (int)ids.size();
}

json Store::settings() {
    std::lock_guard lock(mutex_);
    json j = {{"interval", 2},
              {"retentionDays", 14},
              {"excluded", json::array()},
              {"displayId", 0},
              {"compressionMode", "balanced"}};
    Stmt s(db_, "SELECT key,value FROM settings");
    while (s.step() == SQLITE_ROW) {
        auto v = json::parse(col(s.p, 1), nullptr, false);
        if (!v.is_discarded()) {
            j[col(s.p, 0)] = v;
        }
    }
    return j;
}

void Store::settings(const json& changes) {
    std::lock_guard lock(mutex_);
    auto all = settings();
    for (auto it = changes.begin(); it != changes.end(); ++it) {
        if (!all.contains(it.key())) {
            throw std::invalid_argument("Unknown setting: " + it.key());
        }
        all[it.key()] = it.value();
    }
    if (!all["interval"].is_number_integer() || all["interval"] < 1 || all["interval"] > 30) {
        throw std::invalid_argument("Capture interval must be 1–30 seconds");
    }
    if (!all["retentionDays"].is_number_integer() || all["retentionDays"] < 1 ||
        all["retentionDays"] > 3650) {
        throw std::invalid_argument("Retention must be 1–3650 days");
    }
    if (all["compressionMode"] != "balanced" && all["compressionMode"] != "sharp" &&
        all["compressionMode"] != "jpeg") {
        throw std::invalid_argument("Unknown compression mode");
    }
    if (!all["excluded"].is_array()) {
        throw std::invalid_argument("Excluded apps must be a list");
    }
    for (auto& e : all["excluded"]) {
        if (!e.is_string() || e.get<std::string>().empty()) {
            throw std::invalid_argument("Invalid excluded app");
        }
    }
    if (!all["displayId"].is_number_integer() || all["displayId"] < 0) {
        throw std::invalid_argument("Invalid display");
    }
    exec("BEGIN IMMEDIATE");
    try {
        for (auto it = all.begin(); it != all.end(); ++it) {
            Stmt s(db_, "INSERT INTO settings VALUES(?,?) ON CONFLICT(key) DO UPDATE "
                        "SET value=excluded.value");
            s.bind(1, it.key());
            s.bind(2, it.value().dump());
            s.step();
        }
        exec("COMMIT");
    } catch (...) {
        exec("ROLLBACK");
        throw;
    }
}

bool ChangeGate::changed(const std::vector<unsigned char>& pixels, const std::string& context,
                         double time) {
    if (pixels.empty()) {
        return false;
    }
    bool take = previous_.size() != pixels.size() || context != context_ || time - saved_ >= 30 ||
                time < saved_;
    if (!take) {
        size_t changed = 0;
        double total = 0;
        for (size_t i = 0; i < pixels.size(); ++i) {
            int d = std::abs(int(pixels[i]) - int(previous_[i]));
            total += d;
            if (d > 12) {
                ++changed;
            }
        }
        take = total / pixels.size() > 0.45 || double(changed) / pixels.size() > 0.005;
    }
    if (take) {
        previous_ = pixels;
        context_ = context;
        saved_ = time;
    }
    return take;
}
} // namespace afterimage
