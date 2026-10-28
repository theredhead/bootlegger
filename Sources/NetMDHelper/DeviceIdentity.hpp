// GPL-3.0-or-later. USB addresses can change when the backend resets a recorder.
#pragma once
#include <cstdint>
#include <sstream>
#include <stdexcept>
#include <vector>

struct USBIdentity {
    uint16_t vendor;
    uint16_t product;
    uint8_t bus;
    uint8_t address;
    std::vector<uint8_t> ports;
};

inline std::string stableDeviceIdentity(const USBIdentity &device) {
    if (device.ports.empty()) throw std::runtime_error("Cannot determine a stable USB port path. Reconnect the recorder and Refresh.");
    std::ostringstream identity;
    identity << std::hex << device.vendor << ':' << device.product << ':' << unsigned(device.bus);
    for (uint8_t port : device.ports) identity << ':' << unsigned(port);
    return identity.str();
}
