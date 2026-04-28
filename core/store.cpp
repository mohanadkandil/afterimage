#include "store.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <sys/stat.h>

namespace litt {
namespace {
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

Store::Store(fs::path root) : root_(std::move(root)) {
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
    exec("BEGIN IMMEDIATE");
    try {
        bool hasImageKey = false;
        {
            Stmt columns(db_, "PRAGMA table_info(frames)");
            while (columns.step() == SQLITE_ROW) {
                if (col(columns.p, 1) == "image_hash") {
                    hasImageKey = true;
                }
            }
        }
        if (!hasImageKey) {
            exec("ALTER TABLE frames ADD COLUMN image_hash TEXT; ALTER TABLE frames ADD COLUMN "
                 "storage_id INTEGER; PRAGMA user_version=2;");
        }
        exec("COMMIT");
    } catch (...) {
        exec("ROLLBACK");
        throw;
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
        path = root_ / "frames" / (std::to_string(id) + ".jpg");
        if (fs::exists(path)) {
            fs::remove(path);
        }
        auto existing = duplicate(bytes);
        long long storageId = id;
        bool linked = false;
        if (existing) {
            std::error_code error;
            fs::create_hard_link(root_ / "frames" / (std::to_string(existing->first) + ".jpg"),
                                 path, error);
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

fs::path Store::image(long long id) {
    frame(id);
    return root_ / "frames" / (std::to_string(id) + ".jpg");
}

std::optional<std::pair<long long, long long>>
Store::duplicate(const std::vector<unsigned char>& bytes, long long exclude) {
    Stmt candidates(db_,
                    "SELECT id, coalesce(storage_id,id) FROM frames WHERE image_hash=? AND id<>?");
    candidates.bind(1, imageKey(bytes));
    candidates.bind(2, exclude);
    while (candidates.step() == SQLITE_ROW) {
        auto id = sqlite3_column_int64(candidates.p, 0);
        auto path = root_ / "frames" / (std::to_string(id) + ".jpg");
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
            Stmt rows(db_, "SELECT id FROM frames ORDER BY id");
            while (rows.step() == SQLITE_ROW) {
                ids.push_back(sqlite3_column_int64(rows.p, 0));
            }
        }
        for (auto id : ids) {
            auto path = root_ / "frames" / (std::to_string(id) + ".jpg");
            auto bytes = readBytes(path);
            auto existing = duplicate(bytes, id);
            long long storageId = id;
            if (existing) {
                auto source = root_ / "frames" / (std::to_string(existing->first) + ".jpg");
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
                       "FROM frames GROUP BY coalesce(storage_id,id))");
    physical.step();
    j["imageBytes"] = sqlite3_column_int64(physical.p, 0);
    j["uniqueImages"] = sqlite3_column_int64(physical.p, 1);
    j["deduplicatedBytes"] =
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
        if (e.is_regular_file()) {
            disk += e.file_size();
        }
    }
    j["diskBytes"] = disk + j["imageBytes"].get<long long>();
    return j;
}

void Store::erase(long long id) {
    std::lock_guard lock(mutex_);
    auto path = image(id);
    Stmt s(db_, "DELETE FROM frames WHERE id=?");
    s.bind(1, id);
    s.step();
    std::error_code ec;
    fs::remove(path, ec);
    if (ec) {
        throw std::runtime_error("Index removed, but image deletion failed: " + ec.message());
    }
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
    for (auto id : ids) {
        erase(id);
    }
    exec("PRAGMA wal_checkpoint(TRUNCATE)");
    return (int)ids.size();
}

json Store::settings() {
    std::lock_guard lock(mutex_);
    json j = {
        {"interval", 2}, {"retentionDays", 14}, {"excluded", json::array()}, {"displayId", 0}};
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
} // namespace litt
