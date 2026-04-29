#include "store.hpp"
#include <iostream>
#include <thread>
#include <unistd.h>
using namespace afterimage;

void check(bool ok, const char* message) {
    if (!ok) {
        throw std::runtime_error(message);
    }
}

int main() {
    auto path = fs::temp_directory_path() / ("afterimage-tests-" + std::to_string(getpid()));
    fs::remove_all(path);
    try {
        {
            Store store(path);
            Frame f;
            f.time = now();
            f.app = "Editor";
            f.bundle = "app.editor";
            f.title = "Sensor notes";
            f.text = "robot localization calibration";
            f.width = 100;
            f.height = 80;
            auto id = store.add(f, {1, 2, 3});
            check(store.frame(id)["text"] == f.text, "Round trip");
            check(store.frames("robot calibration").size() == 1, "AND search");
            check(store.frames("robot absent").empty(), "AND semantics");
            check(store.frames("\" OR *").empty(), "Literal FTS escaping");
            check(store.frames("robot", "app.other").empty(), "App filtering");
            check(store.frames("", "", f.time + 1, f.time + 2).empty(), "Time filtering");
            check(fs::exists(store.image(id)), "Image persisted");
            auto duplicateId = store.add(f, {1, 2, 3});
            check(fs::equivalent(store.image(id), store.image(duplicateId)),
                  "Duplicate images share storage");
            check(store.stats()["imageBytes"] == 3, "Physical bytes count shared image once");
            check(store.stats()["logicalImageBytes"] == 6, "Logical bytes retain both moments");
            store.erase(duplicateId);
            check(fs::exists(store.image(id)), "Deleting shared frame preserves other frame");
            auto optimized = store.optimize();
            check(optimized["after"]["count"] == 1, "Optimization preserves moments");

            f.time -= 86400 * 20;
            f.title = "Old";
            store.add(f, {4, 5});
            check(store.prune(14, now()) == 1, "Retention deletes old frames");
            check(store.stats()["count"] == 1, "Retention count");
            store.settings({{"interval", 5}, {"excluded", json::array({"private.app"})}});
            check(store.settings()["interval"] == 5, "Settings persisted");
            bool rejected = false;
            try {
                store.settings({{"interval", 0}});
            } catch (...) {
                rejected = true;
            }
            check(rejected, "Invalid settings rejected");
            check(store.settings()["interval"] == 5, "Bad settings atomic");
            std::thread writer([&] {
                Store other(path);
                for (int i = 0; i < 10; i++) {
                    f.time = now();
                    other.add(f, {1, 2});
                }
            });
            for (int i = 0; i < 10; i++) {
                store.frames();
            }
            writer.join();
            check(store.stats()["count"] == 11, "Concurrent reader/writer");
            store.erase(id);
            check(store.frames("Sensor").empty(), "Deletion updates index");
            check(!fs::exists(path / "frames" / (std::to_string(id) + ".jpg")),
                  "Deletion removes image");
        }
        {
            Store reopened(path);
            check(reopened.stats()["count"] == 10, "Persistent reopen");
            check(reopened.settings()["excluded"][0] == "private.app", "Persistent preferences");
        }
        {
            SegmentCodec failing;
            failing.encode = [](const auto&, const fs::path&, double) {
                throw std::runtime_error("Injected encoder failure");
            };
            failing.decode = [](const fs::path&, int, const fs::path&) {};
            Store store(path, failing);
            bool failed = false;
            try {
                store.compact();
            } catch (...) {
                failed = true;
            }
            check(failed, "Encoding failure propagates");
            check(store.stats()["count"] == 10, "Encoding failure preserves rows");
            for (auto& frame : store.frames()) {
                check(fs::exists(store.image(frame["id"])),
                      "Encoding failure preserves image files");
            }
        }
        ChangeGate gate;
        std::vector<unsigned char> pixels(14400, 50);
        check(gate.changed(pixels, "app", 100), "Initial frame");
        check(!gate.changed(pixels, "app", 102), "Duplicate skipped");
        check(gate.changed(pixels, "other", 104), "Context change preserved");
        pixels[0] = 51;
        check(!gate.changed(pixels, "other", 106), "Tiny change skipped");
        for (int i = 0; i < 150; i++) {
            pixels[i] = 120;
        }
        check(gate.changed(pixels, "other", 108), "Content change preserved");
        check(gate.changed(pixels, "other", 140), "Checkpoint");
        fs::remove_all(path);
        std::cout << "All archive, search, retention, concurrency and change-gate "
                     "tests passed\n";
        return 0;
    } catch (const std::exception& e) {
        fs::remove_all(path);
        std::cerr << e.what() << '\n';
        return 1;
    }
}
