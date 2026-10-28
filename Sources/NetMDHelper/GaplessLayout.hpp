// GPL-3.0-or-later. Validate a complete layout before any modified TOC reaches the recorder.
#pragma once
#include "CNetMdTOC.h"
#include "md_toc.h"
#include <algorithm>
#include <set>
#include <stdexcept>
#include <utility>
#include <vector>

using AudioRange = std::pair<uint32_t, uint32_t>;

inline std::vector<AudioRange> audioRanges(const netmd::toc::TOC &toc, size_t expectedTracks) {
    if (toc.mTracks.ntracks != expectedTracks) throw std::runtime_error("Unexpected gapless TOC track count.");
    std::vector<AudioRange> ranges;
    std::set<int> fragments;
    for (size_t track = 1; track <= expectedTracks; ++track) {
        int fragment = toc.mTracks.trackmap[track];
        if (!fragment) throw std::runtime_error("A gapless track has no audio fragment.");
        while (fragment) {
            if (!fragments.insert(fragment).second) throw std::runtime_error("Gapless TOC contains a shared or cyclic fragment.");
            const auto &part = toc.mTracks.fraglist[fragment];
            uint32_t start = static_cast<uint32_t>(netmd::CSG(part.start));
            uint32_t end = static_cast<uint32_t>(netmd::CSG(part.end));
            if (end < start || end > 0x3fff * 176u + 175u) throw std::runtime_error("Invalid gapless audio addresses.");
            ranges.emplace_back(start, end);
            fragment = part.link;
        }
    }
    std::sort(ranges.begin(), ranges.end());
    std::vector<AudioRange> merged;
    for (const auto &range : ranges) {
        if (!merged.empty() && range.first <= merged.back().second)
            throw std::runtime_error("Gapless TOC audio fragments overlap.");
        if (!merged.empty() && range.first == merged.back().second + 1) merged.back().second = range.second;
        else merged.push_back(range);
    }
    return merged;
}
