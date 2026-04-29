#pragma once
#include <filesystem>
#include <functional>
#include <mutex>
#include <nlohmann/json.hpp>
#include <optional>
#include <sqlite3.h>
#include <string>
#include <vector>

namespace afterimage {
using json = nlohmann::json;
namespace fs = std::filesystem;

struct Frame {
    double time = 0;
    std::string app, bundle, title, text, source = "capture";
    int width = 0, height = 0;
    json boxes = json::array();
};

struct SegmentCodec {
    std::function<void(const std::vector<fs::path>&, const fs::path&, double)> encode;
    std::function<void(const fs::path&, int, const fs::path&)> decode;
};

class Store {
    SegmentCodec codec_;
    void eraseMany(const std::vector<long long>& ids);
    fs::path still(long long id) const;
    void cleanupMedia();
    sqlite3* db_ = nullptr;
    fs::path root_;
    mutable std::recursive_mutex mutex_;
    void exec(const char* sql);
    json row(sqlite3_stmt*) const;
    std::optional<std::pair<long long, long long>> duplicate(const std::vector<unsigned char>&,
                                                             long long exclude = -1);

  public:
    explicit Store(fs::path root, SegmentCodec codec = {});
    ~Store();
    Store(const Store&) = delete;
    Store& operator=(const Store&) = delete;

    fs::path root() const {
        return root_;
    }

    long long add(const Frame&, const std::vector<unsigned char>& image);
    json frames(std::string query = "", std::string bundle = "", double from = 0, double to = 1e15,
                int limit = 200, int offset = 0);
    json frame(long long id);
    fs::path image(long long id);
    json stats();
    json optimize();
    json compact(bool flush = true);
    void clear();
    void erase(long long id);
    int prune(int days, double now);
    json settings();
    void settings(const json&);
};

class ChangeGate {
    std::vector<unsigned char> previous_;
    std::string context_;
    double saved_ = 0;

  public:
    bool changed(const std::vector<unsigned char>& pixels, const std::string& context, double time);

    void reset() {
        previous_.clear();
        context_.clear();
        saved_ = 0;
    }
};

std::string literalQuery(const std::string&);
double now();
} // namespace afterimage
