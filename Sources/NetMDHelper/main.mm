// Native NetMD helper, distributed under GPL-3.0-or-later with its backend.
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include "CNetMdApi.h"
#include "CNetMdTOC.h"
#include <libusb.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <iostream>
#include <AudioToolbox/AudioToolbox.h>
#include <stdexcept>
#include <cmath>
#include <set>
#include "KnownDevices.hpp"
#include "DeviceIdentity.hpp"
#include "GaplessLayout.hpp"
#include "BootleggerUSBWrite.hpp"
#include <chrono>

using namespace netmd;

static void emit(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void check(int result, const char *operation) {
    if (result < 0) throw std::runtime_error(std::string(operation) + " (NetMD error " + std::to_string(result) + ").");
}

static std::string text(NSString *value) {
    if (![value isKindOfClass:NSString.class]) throw std::runtime_error("Invalid request text.");
    return value.UTF8String;
}

static double seconds(const NetMdTime &time) {
    return time.hour * 3600.0 + time.minute * 60.0 + time.second;
}

// NetMD titles use the legacy half-width character set. Transliterate unsupported characters.
static std::string mdTitle(NSString *title) {
    NSString *latin = [title stringByApplyingTransform:NSStringTransformToLatin reverse:NO];
    latin = [latin stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    NSData *encoded = [latin dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    if (!encoded) return "Untitled";
    return std::string((const char *)encoded.bytes, std::min((NSUInteger)120, encoded.length));
}

static NSString *fingerprint(NSDictionary *disc) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:disc options:NSJSONWritingSortedKeys error:nil];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString string];
    for (unsigned char byte : digest) [result appendFormat:@"%02x", byte];
    return result;
}

static NSDictionary *inspect(netmd_pp &api) {
    int flags = api.discFlags();
    check(flags, "Cannot read inserted disc protection");
    DiscCapacity capacity{};
    check(api.discCapacity(capacity), "Cannot read inserted disc capacity");
    int count = api.trackCount();
    check(count, "Cannot read inserted disc track count");
    std::string title;
    check(api.discTitle(title), "Cannot read inserted disc title");
    NSMutableArray *tracks = [NSMutableArray array];
    for (int index = 0; index < count; ++index) {
        TrackTime time{};
        std::string name;
        check(api.trackTime(index, time), "Cannot read track duration");
        check(api.trackTitle(index, name), "Cannot read track title");
        [tracks addObject:@{ @"title": [[NSString alloc] initWithBytes:name.data() length:name.size() encoding:NSISOLatin1StringEncoding] ?: @"",
                            @"duration": @(time.mMinutes * 60.0 + time.mSeconds + time.mTenthSecs / 100.0) }];
    }
    NSMutableDictionary *disc = [@{
        @"device": [NSString stringWithUTF8String:api.getDeviceName().c_str()],
        @"title": [[NSString alloc] initWithBytes:title.data() length:title.size() encoding:NSISOLatin1StringEncoding] ?: @"",
        @"trackCount": @(count), @"tracks": tracks, @"writable": @((flags & 0x10) && !(flags & 0x40)),
        @"availableSeconds": @(seconds(capacity.available)), @"totalSeconds": @(seconds(capacity.total)),
        @"supportsLPEncoding": @(api.otfEncodeSupported()), @"supportsGaplessSP": @(api.tocManipSupported()),
        @"supportsSoftwareSP": @(api.spUploadSupported()), @"supportsSoftwareLP": @YES
    } mutableCopy];
    disc[@"fingerprint"] = fingerprint(disc);
    return disc;
}

static void validate(NSDictionary *request, NSDictionary *disc) {
    if (![request[@"fingerprint"] isEqual:disc[@"fingerprint"]])
        throw std::runtime_error("The device or disc changed. Refresh it and review the export again.");
    if (![disc[@"writable"] boolValue]) throw std::runtime_error("The inserted disc is write-protected or not recordable.");
}

static double pcmDuration(NSString *path) {
    if (![path isKindOfClass:NSString.class]) throw std::runtime_error("Missing prepared audio file.");
    AudioFileID file = nullptr;
    if (AudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], kAudioFileReadPermission, 0, &file) != noErr)
        throw std::runtime_error("Cannot read prepared audio file.");
    AudioStreamBasicDescription format{};
    UInt32 size = sizeof(format);
    OSStatus result = AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format);
    UInt64 packets = 0;
    size = sizeof(packets);
    OSStatus packetResult = AudioFileGetProperty(file, kAudioFilePropertyAudioDataPacketCount, &size, &packets);
    AudioFileClose(file);
    if (result || packetResult || format.mFormatID != kAudioFormatLinearPCM || format.mSampleRate != 44100 ||
        format.mBitsPerChannel != 16 || format.mChannelsPerFrame != 2)
        throw std::runtime_error("Prepared audio must be 44.1 kHz, 16-bit stereo PCM.");
    return packets * double(format.mFramesPerPacket) / format.mSampleRate;
}

static double atracDuration(NSString *path, NSString *mode) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data || data.length < 152) throw std::runtime_error("Cannot read prepared ATRAC audio.");
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    auto integer = [&](size_t at, size_t count) -> uint32_t {
        if (at + count > data.length) throw std::runtime_error("Truncated ATRAC header.");
        uint32_t value = 0;
        for (size_t i = 0; i < count; ++i) value |= uint32_t(bytes[at + i]) << (8 * i);
        return value;
    };
    if ([mode isEqual:@"sp"]) {
        if (data.length <= 2048 || integer(0, 4) != 2048 || bytes[264] != 2 || (data.length - 2048) % 424)
            throw std::runtime_error("Software SP requires stereo ATRAC1 in an AEA container.");
        return double(data.length - 2048) / 424 * 512 / 44100;
    }
    if (memcmp(bytes, "RIFF", 4) || memcmp(bytes + 8, "WAVEfmt ", 8) || integer(20, 2) != 0x0270 ||
        integer(22, 2) != 2 || integer(24, 4) != 44100)
        throw std::runtime_error("Software LP requires stereo ATRAC3 in a RIFF container.");
    uint32_t block = [mode isEqual:@"lp2"] ? 384 : 192;
    if (integer(32, 2) != block) throw std::runtime_error("ATRAC bitrate does not match the selected MD mode.");
    size_t cursor = 12;
    while (cursor + 8 <= data.length) {
        uint32_t size = integer(cursor + 4, 4);
        if (size > data.length - cursor - 8) throw std::runtime_error("Truncated ATRAC data.");
        if (!memcmp(bytes + cursor, "data", 4)) {
            if (size == 0 || size % block) throw std::runtime_error("Incomplete ATRAC frames.");
            return double(size / block) * 1024 / 44100;
        }
        cursor += 8 + size + size % 2;
    }
    throw std::runtime_error("Missing ATRAC audio data.");
}

static void splitGapless(netmd_pp &api, NSDictionary *request) {
    check(api.startHBSession(USB_EXEC), "Could not prepare gapless track markers");
    struct SessionCleanup {
        netmd_pp &api;
        ~SessionCleanup() { api.endHBSession(USB_EXEC); }
    } cleanup{api};
    NetMDByteVector toc;
    for (int sector = 0; sector < 3; ++sector) {
        auto bytes = api.readUTOCSector(static_cast<UTOCSector>(sector));
        if (bytes.size() != 2352) throw std::runtime_error("Cannot read complete TOC. Audio remains as one concert track.");
        toc.insert(toc.end(), bytes.begin(), bytes.end());
    }
    NSString *recovery = request[@"recoveryPath"];
    NSError *error = nil;
    if (![recovery isKindOfClass:NSString.class] ||
        ![NSFileManager.defaultManager createDirectoryAtPath:recovery withIntermediateDirectories:YES attributes:nil error:&error])
        throw std::runtime_error("Cannot save recovery TOC. Audio remains as one concert track.");
    NSData *backup = [NSData dataWithBytes:toc.data() length:toc.size()];
    if (![backup writeToFile:[recovery stringByAppendingPathComponent:@"original.toc"] options:NSDataWritingAtomic error:&error])
        throw std::runtime_error("Cannot save recovery TOC. Audio remains as one concert track.");
    NSArray *tracks = request[@"tracks"];
    double total = 0;
    for (NSDictionary *track in tracks) total += [track[@"duration"] doubleValue];
    static_assert(sizeof(toc::TOC) == 2352 * 3);
    const auto originalRanges = audioRanges(*reinterpret_cast<const toc::TOC *>(toc.data()), 1);
    CNetMdTOC layout((int)tracks.count, (uint32_t)std::llround(total * 1000), toc.data());
    time_t now = time(nullptr);
    // Round cumulative boundaries so per-track rounding cannot accumulate across a concert.
    double elapsed = 0;
    uint32_t previous = 0;
    int number = 1;
    for (NSDictionary *track in tracks) {
        elapsed += [track[@"duration"] doubleValue];
        uint32_t boundary = (uint32_t)std::llround(elapsed * 1000);
        check(layout.addTrack(number++, boundary - previous, mdTitle(track[@"title"]), now), "Cannot prepare gapless track layout");
        previous = boundary;
    }
    check(layout.setDiscTitle(mdTitle(request[@"title"])), "Cannot prepare gapless disc title");
    if (audioRanges(*reinterpret_cast<const toc::TOC *>(toc.data()), tracks.count) != originalRanges)
        throw std::runtime_error("Gapless layout changed audio coverage. Original TOC has been preserved.");
    NSData *modified = [NSData dataWithBytes:toc.data() length:toc.size()];
    if (![modified writeToFile:[recovery stringByAppendingPathComponent:@"split.toc"] options:NSDataWritingAtomic error:&error])
        throw std::runtime_error("Cannot save split TOC before writing.");
    for (int sector = 0; sector < 3; ++sector) {
        NetMDByteVector bytes(toc.begin() + sector * 2352, toc.begin() + (sector + 1) * 2352);
        int result = api.writeUTOCSector(static_cast<UTOCSector>(sector), bytes);
        if (result < 0) throw std::runtime_error("Gapless TOC update failed. Keep the recorder connected. Recovery TOC: " + text(recovery));
    }
    check(api.finalizeTOC(), "Cannot finalize gapless track markers; keep the recorder connected and retain the recovery TOC");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        try {
            if (argc != 2) throw std::runtime_error("Expected a JSON request file.");
            NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
            NSDictionary *request = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (![request isKindOfClass:NSDictionary.class]) throw std::runtime_error("Invalid NetMD request.");
            NSString *requestedCommand = request[@"command"];
            if (![@[@"devices", @"inspect", @"erase", @"write"] containsObject:requestedCommand ?: @""])
                throw std::runtime_error("Unknown NetMD command.");
            NSString *lockPath = [NSString stringWithFormat:@"%@Bootlegger-NetMD-%u.lock", NSTemporaryDirectory(), getuid()];
            int lock = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
            if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0)
                throw std::runtime_error("Another Bootlegger window is using NetMD. Wait for it to finish.");
            netmd_pp::setLogStream(std::cerr);
            netmd_pp::setLogLevel([request[@"diagnostics"] boolValue] ? DEBUG : WARN);
            libusb_context *context = nullptr;
            if (libusb_init(&context) != 0) throw std::runtime_error("Cannot initialize USB.");
            libusb_device **devices = nullptr;
            ssize_t count = libusb_get_device_list(context, &devices);
            int compatible = 0;
            NSMutableArray *attached = [NSMutableArray array];
            NSString *location = @"";
            std::string recognizedName;
            for (ssize_t i = 0; i < count; ++i) {
                libusb_device_descriptor descriptor{};
                if (libusb_get_device_descriptor(devices[i], &descriptor) == 0 &&
                    knownDevices.count((uint32_t(descriptor.idVendor) << 16) | descriptor.idProduct)) {
                    ++compatible;
                    recognizedName = knownDevices.at((uint32_t(descriptor.idVendor) << 16) | descriptor.idProduct);
                    uint8_t ports[8];
                    int portCount = libusb_get_port_numbers(devices[i], ports, sizeof(ports));
                    USBIdentity identity{descriptor.idVendor, descriptor.idProduct,
                        libusb_get_bus_number(devices[i]), libusb_get_device_address(devices[i]), {}};
                    if (portCount > 0) identity.ports.assign(ports, ports + portCount);
                    location = [NSString stringWithUTF8String:stableDeviceIdentity(identity).c_str()];
                    [attached addObject:@{ @"id": location, @"name": [NSString stringWithUTF8String:recognizedName.c_str()] }];
                }
            }
            if (devices) libusb_free_device_list(devices, 1);
            libusb_exit(context);
            if ([requestedCommand isEqual:@"devices"]) {
                emit(@{ @"type": @"devices", @"devices": attached });
                return 0;
            }
            if (compatible > 1) throw std::runtime_error("Connect only one NetMD recorder at a time.");
            if (compatible == 0)
                throw std::runtime_error("No supported NetMD recorder is visible over USB. Check recorder power and the USB data cable, then reconnect it and Refresh.");
            netmd_pp api;
            int ready = api.initDevice();
            if (ready < 0)
                throw std::runtime_error("Detected " + recognizedName + ", but could not open it or read its disc. Close other MiniDisc applications and insert a disc in standard MD mode. NetMD error " + std::to_string(ready) + ".");
            NSMutableDictionary *disc = [inspect(api) mutableCopy];
            disc[@"location"] = location;
            [disc removeObjectForKey:@"fingerprint"];
            disc[@"fingerprint"] = fingerprint(disc);
            NSString *command = request[@"command"];
            if ([command isEqual:@"inspect"]) {
                emit(@{ @"type": @"disc", @"disc": disc });
            } else if ([command isEqual:@"erase"]) {
                validate(request, disc);
                check(api.eraseDisc(), "Could not erase disc");
                NSMutableDictionary *erased = [inspect(api) mutableCopy];
                erased[@"location"] = location;
                [erased removeObjectForKey:@"fingerprint"];
                erased[@"fingerprint"] = fingerprint(erased);
                emit(@{ @"type": @"disc", @"disc": erased });
            } else if ([command isEqual:@"write"]) {
                validate(request, disc);
                NSArray *tracks = request[@"tracks"];
                if (![tracks isKindOfClass:NSArray.class] || tracks.count == 0 || tracks.count + [disc[@"trackCount"] intValue] > 255)
                    throw std::runtime_error("A MiniDisc supports at most 255 tracks.");
                NSString *mode = request[@"mode"];
                NSString *encoding = request[@"encoding"] ?: @"recorder";
                if (![@[@"recorder", @"software"] containsObject:encoding]) throw std::runtime_error("Unknown MD encoder.");
                bool software = [encoding isEqual:@"software"];
                double factor = [mode isEqual:@"lp2"] ? 2 : [mode isEqual:@"lp4"] ? 4 : 1;
                if (software && factor == 1 && ![disc[@"supportsSoftwareSP"] boolValue])
                    throw std::runtime_error("This recorder cannot receive pre-encoded ATRAC1. Use recorder SP encoding.");
                if (software && factor != 1 && ![disc[@"supportsSoftwareLP"] boolValue])
                    throw std::runtime_error("This recorder cannot receive pre-encoded ATRAC3.");
                if (!software && factor != 1 && ![disc[@"supportsLPEncoding"] boolValue])
                    throw std::runtime_error("This recorder cannot encode LP2/LP4 over USB. Use SP.");
                bool gapless = [request[@"gapless"] boolValue];
                if (gapless && (software || factor != 1 || ![disc[@"supportsGaplessSP"] boolValue] || [disc[@"trackCount"] intValue] != 0))
                    throw std::runtime_error("Gapless SP requires a compatible recorder and an empty MD.");
                if (![mode isEqual:@"sp"] && ![mode isEqual:@"lp2"] && ![mode isEqual:@"lp4"])
                    throw std::runtime_error("Invalid NetMD recording mode.");
                size_t titleCells = 0;
                auto cells = [](size_t bytes) { return (bytes + 6) / 7; };
                for (NSDictionary *existing in disc[@"tracks"])
                    titleCells += cells([existing[@"title"] lengthOfBytesUsingEncoding:NSISOLatin1StringEncoding]);
                titleCells += [disc[@"trackCount"] intValue] == 0 ? cells(mdTitle(request[@"title"]).size())
                    : cells([disc[@"title"] lengthOfBytesUsingEncoding:NSISOLatin1StringEncoding]);
                for (NSDictionary *track in tracks) titleCells += cells(mdTitle(track[@"title"]).size());
                if (titleCells > 255) throw std::runtime_error("Track titles exceed this MD's title storage. Use shorter track or album titles.");
                const double clusterSeconds = 176.0 * 512 / 44100;
                double required = 0;
                double totalDuration = 0;
                for (NSDictionary *track in tracks) {
                    double duration = [track[@"duration"] doubleValue];
                    if (!std::isfinite(duration) || duration < 0.024) throw std::runtime_error("MiniDisc tracks must be at least 24 milliseconds long.");
                    // Conservatively reserve complete 2.04-second allocation clusters per track.
                    totalDuration += duration;
                    double encodedDuration = duration;
                    if (!gapless) {
                        encodedDuration = software ? atracDuration(track[@"path"], mode) : pcmDuration(track[@"path"]);
                        if (std::abs(encodedDuration - duration) > (software ? 0.15 : 0.05))
                            throw std::runtime_error("Prepared audio duration does not match the selected track.");
                    }
                    required += (std::ceil(std::max(duration, encodedDuration) / factor / clusterSeconds) + 1) * clusterSeconds;
                }
                if (gapless) {
                    required = (std::ceil(totalDuration / clusterSeconds) + 1) * clusterSeconds;
                    if (std::abs(pcmDuration(tracks[0][@"path"]) - totalDuration) > 0.05)
                        throw std::runtime_error("Prepared concert duration does not match the selected tracks.");
                }
                if (required > [disc[@"availableSeconds"] doubleValue])
                    throw std::runtime_error("The selected tracks do not fit on this disc. Deselect tracks or erase the disc first.");
                DiskFormat format = software ? NO_ONTHEFLY_CONVERSION : factor == 2 ? NETMD_DISKFORMAT_LP2 : factor == 4 ? NETMD_DISKFORMAT_LP4 : NO_ONTHEFLY_CONVERSION;
                NSUInteger index = 0;
                double completedDuration = 0;
                double activeDuration = gapless ? totalDuration : [tracks[0][@"duration"] doubleValue];
                auto lastUpdate = std::chrono::steady_clock::now() - std::chrono::seconds(1);
                trackTransferProgress = [&](size_t sent, size_t total) {
                    auto now = std::chrono::steady_clock::now();
                    if (sent != total && now - lastUpdate < std::chrono::milliseconds(100)) return;
                    lastUpdate = now;
                    double fraction = total ? std::min(1.0, double(sent) / total) : 0;
                    // Keep a small part of each track for recorder finalization/commit.
                    double overall = (completedDuration + activeDuration * fraction * 0.98) / totalDuration;
                    emit(@{ @"type": @"progress", @"progress": @(overall) });
                };
                struct ClearProgress { ~ClearProgress() { trackTransferProgress = nullptr; } } clearProgress;
                if (gapless) {
                    if ([NSFileManager.defaultManager fileExistsAtPath:request[@"cancelPath"] ?: @""]) {
                        emit(@{ @"type": @"cancelled" }); return 0;
                    }
                    emit(@{ @"type": @"progress", @"progress": @0, @"message": @"Writing continuous concert audio… Keep the recorder connected." });
                    check(api.sendAudioFile(text(tracks[0][@"path"]), mdTitle(request[@"title"]), format), "Concert transfer failed");
                    emit(@{ @"type": @"progress", @"progress": @0.98, @"message": @"Finalizing gapless track markers…" });
                    splitGapless(api, request);
                } else for (NSDictionary *track in tracks) {
                    if ([NSFileManager.defaultManager fileExistsAtPath:request[@"cancelPath"] ?: @""]) {
                        emit(@{ @"type": @"cancelled" });
                        return 0;
                    }
                    activeDuration = [track[@"duration"] doubleValue];
                    emit(@{ @"type": @"progress", @"progress": @(completedDuration / totalDuration),
                            @"message": [NSString stringWithFormat:@"Writing %lu/%lu: %@", index + 1, tracks.count, track[@"title"]] });
                    bool hostSP = software && factor == 1;
                    struct HostSession {
                        netmd_pp &api;
                        bool active;
                        ~HostSession() { if (active) api.endHBSession(SP_UPLOAD); }
                    } session{api, hostSP};
                    if (hostSP) check(api.startHBSession(SP_UPLOAD), "Cannot prepare ATRAC1 upload on this recorder");
                    check(api.sendAudioFile(text(track[@"path"]), mdTitle(track[@"title"]), format), "Track transfer failed");
                    completedDuration += activeDuration;
                    emit(@{ @"type": @"progress", @"progress": @(completedDuration / totalDuration) });
                    ++index;
                }
                // Preserve an existing album's disc title when appending tracks.
                if ([disc[@"trackCount"] intValue] == 0) check(api.setDiscTitle(mdTitle(request[@"title"])), "Cannot set disc title");
                emit(@{ @"type": @"complete", @"message": @"MiniDisc export complete." });
            } else throw std::runtime_error("Unknown NetMD command.");
            return 0;
        } catch (const std::exception &error) {
            emit(@{ @"type": @"error", @"message": [NSString stringWithUTF8String:error.what()] ?: @"NetMD failed." });
            return 1;
        }
    }
}
