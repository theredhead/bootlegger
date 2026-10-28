#include "CNetMdApi.h"
#include "CNetMdTOC.h"
#include "md_toc.h"
#include "GaplessLayout.hpp"
#include "DeviceIdentity.hpp"
#include "BootleggerUSBWrite.hpp"
#include <cassert>
#include <iostream>
#include <set>

using namespace netmd;

int main() {
    std::vector<size_t> progressUpdates;
    usbWriteProgress = [&](size_t bytes) { progressUpdates.push_back(bytes); };
    size_t expectedOffset = 0;
    int calls = 0;
    const size_t transferLength = 1'048'576 + 123;
    int sent = boundedUSBWrite(transferLength, [&](size_t offset, int requested, int& completed) {
        assert(offset == expectedOffset && requested > 0 && requested <= 16384);
        completed = std::min(requested, 7000); // Exercise short successful writes.
        expectedOffset += completed;
        ++calls;
        return LIBUSB_SUCCESS;
    });
    assert(sent == transferLength && expectedOffset == transferLength && calls > 64);
    assert(progressUpdates.size() == static_cast<size_t>(calls));
    assert(progressUpdates.front() > 0 && progressUpdates.back() == transferLength);
    assert(std::is_sorted(progressUpdates.begin(), progressUpdates.end()));
    usbWriteProgress = nullptr;
    assert(boundedUSBWrite(100, [](size_t, int, int& completed) { completed = 0; return LIBUSB_SUCCESS; }) < 0);
    assert(boundedUSBWrite(100, [](size_t, int, int& completed) { completed = 4; return LIBUSB_ERROR_TIMEOUT; }) == LIBUSB_ERROR_TIMEOUT);
    int interruptions = 0;
    assert(boundedUSBWrite(100, [&](size_t, int, int& completed) {
        completed = 0; ++interruptions; return LIBUSB_ERROR_INTERRUPTED;
    }) < 0 && interruptions <= 9);
    std::cout << "PASS: bounded USB requests preserve a multi-packet stream and stop on timeout/zero-progress.\n";
    USBIdentity first{0x054c, 0x0286, 2, 2, {1, 1}};
    auto reset = first;
    reset.address = 4;
    assert(stableDeviceIdentity(first) == stableDeviceIdentity(reset));
    auto moved = first;
    moved.ports = {1, 2};
    assert(stableDeviceIdentity(first) != stableDeviceIdentity(moved));
    auto different = first;
    different.product = 0x0075;
    assert(stableDeviceIdentity(first) != stableDeviceIdentity(different));
    auto unavailable = first;
    unavailable.ports.clear();
    bool missingPathRejected = false;
    try { stableDeviceIdentity(unavailable); } catch (const std::exception &) { missingPathRejected = true; }
    assert(missingPathRejected);
    std::cout << "PASS: stable USB identity survives address reassignment but detects port/model changes.\n";
    CNetMdApi::setLogLevel(CRITICAL);
    CNetMdApi::setLogStream(std::cerr);
    static_assert(sizeof(toc::TOC) == 2352 * 3);
    toc::TOC data{};
    data.mTracks.ntracks = 1;
    data.mTracks.trackmap[1] = 1;
    data.mTracks.fraglist[1].start = static_cast<toc::discaddr>(CSG(10000));
    data.mTracks.fraglist[1].end = static_cast<toc::discaddr>(CSG(11055));
    data.mTracks.fraglist[1].mode = toc::DEF_TRACK_MODE;
    data.mTracks.free_track_slot = 2;
    data.mTitles.free_title_slot = 1;
    data.mTimes.free_time_slot = 1;
    auto originalRanges = audioRanges(data, 1);
    // Split a six-cluster continuous recording at two different lengths.
    CNetMdTOC layout(3, 12000, reinterpret_cast<uint8_t *>(&data));
    time_t now = 0;
    assert(layout.addTrack(1, 2000, "First", now) == 0);
    assert(layout.addTrack(2, 3000, "Second", now) == 0);
    assert(layout.addTrack(3, 7000, "Third", now) == 0);
    assert(layout.setDiscTitle("Concert") == 0);
    assert(layout.trackCount() == 3);
    assert(layout.trackTitle(1) == "First" && layout.trackTitle(3) == "Third");
    assert(layout.discTitle() == "Concert");
    std::set<uint32_t> groups;
    uint32_t previousEnd = 9999;
    for (int track = 1; track <= 3; ++track) {
        int fragment = data.mTracks.trackmap[track];
        assert(fragment > 0);
        int iterations = 0;
        while (fragment) {
            assert(++iterations <= 255);
            const auto &part = data.mTracks.fraglist[fragment];
            uint32_t start = static_cast<uint32_t>(CSG(part.start));
            uint32_t end = static_cast<uint32_t>(CSG(part.end));
            assert(start == previousEnd + 1 && end >= start);
            for (uint32_t group = start; group <= end; ++group) assert(groups.insert(group).second);
            previousEnd = end;
            fragment = part.link;
        }
    }
    assert(groups.size() == 1056 && previousEnd == 11055);
    assert(audioRanges(data, 3) == originalRanges);
    auto corrupted = data;
    corrupted.mTracks.fraglist[corrupted.mTracks.trackmap[1]].link = corrupted.mTracks.trackmap[1];
    bool rejected = false;
    try { audioRanges(corrupted, 3); } catch (const std::exception &) { rejected = true; }
    assert(rejected);
    std::cout << "PASS: native gapless TOC splitting preserves all audio groups, order, titles and boundaries.\n";
}
