#pragma once
#include "store.hpp"
afterimage::SegmentCodec appleSegmentCodec();
void exportScreenshot(const std::filesystem::path& input, const std::filesystem::path& output);
