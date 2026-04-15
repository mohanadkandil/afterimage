#pragma once
#include <filesystem>
#include <mutex>
#include <nlohmann/json.hpp>
#include <sqlite3.h>
#include <string>
#include <vector>
namespace litt {
using json = nlohmann::json;
namespace fs = std::filesystem;
struct Frame {
  double time = 0;
  std::string app, bundle, title, text, source = "capture";
  int width = 0, height = 0;
  json boxes = json::array();
};
class Store {
  sqlite3 *db_ = nullptr;
  fs::path root_;
  mutable std::recursive_mutex mutex_;
  void exec(const char *sql);
  json row(sqlite3_stmt *) const;
  void cleanup();

public:
  explicit Store(fs::path root);
  ~Store();
  Store(const Store &) = delete;
  Store &operator=(const Store &) = delete;
  fs::path root() const { return root_; }
  long long add(const Frame &, const std::vector<unsigned char> &image);
  json frames(std::string query = "", std::string bundle = "", double from = 0,
              double to = 1e15, int limit = 200, int offset = 0);
  json frame(long long id);
  fs::path image(long long id);
  json stats();
  void erase(long long id);
  int prune(int days, double now);
  json settings();
  void settings(const json &);
};
class ChangeGate {
  std::vector<unsigned char> previous_;
  std::string context_;
  double saved_ = 0;

public:
  bool changed(const std::vector<unsigned char> &pixels,
               const std::string &context, double time);
  void reset() {
    previous_.clear();
    context_.clear();
    saved_ = 0;
  }
};
std::string literalQuery(const std::string &);
double now();
} // namespace litt
