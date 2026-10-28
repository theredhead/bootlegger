// Bootlegger adapter, GPL-3.0-or-later. Preserve the logical byte stream across bounded host requests.
#pragma once
#include <libusb.h>
#include <algorithm>
#include <climits>
#include <cstddef>
#include <functional>

namespace netmd {

// Synchronous callbacks owned by the native helper for the active transfer only.
inline std::function<void(size_t)> usbWriteProgress;
inline std::function<void(size_t, size_t)> trackTransferProgress;

template <typename Transfer>
int boundedUSBWrite(size_t length, Transfer transfer) {
    if (length > INT_MAX) return LIBUSB_ERROR_INVALID_PARAM;
    size_t completed = 0;
    unsigned int emptyInterruptions = 0;
    while (completed < length) {
        int requested = static_cast<int>(std::min<size_t>(length - completed, 16 * 1024));
        int sent = 0;
        int result = transfer(completed, requested, sent);
        if (sent < 0 || sent > requested) return LIBUSB_ERROR_IO;
        completed += static_cast<size_t>(sent);
        if (sent > 0 && usbWriteProgress) usbWriteProgress(completed);
        if (result != LIBUSB_SUCCESS && result != LIBUSB_ERROR_INTERRUPTED) return result;
        if (sent == 0) {
            if (result == LIBUSB_SUCCESS || ++emptyInterruptions > 8) return LIBUSB_ERROR_IO;
        } else emptyInterruptions = 0;
    }
    return static_cast<int>(completed);
}

}
