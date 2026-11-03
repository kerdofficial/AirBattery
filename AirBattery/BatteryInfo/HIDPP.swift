//
//  HIDPP.swift
//  AirBattery
//
//  Portions adapted from LinearMouse (https://github.com/linearmouse/linearmouse),
//  Copyright (c) 2021-2024 LinearMouse, MIT License
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
import Foundation
import IOKit.hid

enum HIDPPFeatureID: UInt16 {
    case root = 0x0000
    case deviceName = 0x0005
    case deviceFriendlyName = 0x0007
    case batteryStatus = 0x1000
    case batteryVoltage = 0x1001
    case unifiedBattery = 0x1004
    case adcMeasurement = 0x1F20
}

/// An open HID interface that can send an output report and wait for a matching input report.
/// Input reports are delivered on a private queue, so callers must not request from that queue.
final class HIDChannel {
    let device: IOHIDDevice
    let maxOutputReportSize: Int
    private let queue = DispatchQueue(label: "com.lihaoyun6.AirBattery.hid.channel")
    private let reportBuffer: UnsafeMutablePointer<UInt8>
    private let reportBufferSize: Int
    private let lock = NSLock()
    private var accept: ((Data) -> Bool)?
    private var response: Data?
    private let semaphore = DispatchSemaphore(value: 0)
    private let cancelled = DispatchSemaphore(value: 0)
    private var isClosed = false

    /// Manager-owned devices cannot take their own callbacks, so the channel creates a separate device for the same service.
    init?(managedDevice: IOHIDDevice) {
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, IOHIDDeviceGetService(managedDevice)) else { return nil }
        self.device = device
        maxOutputReportSize = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        reportBufferSize = max(IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0, 64)
        reportBuffer = .allocate(capacity: reportBufferSize)
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            reportBuffer.deallocate()
            return nil
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, reportBufferSize, { context, _, _, _, _, report, length in
            guard let context else { return }
            Unmanaged<HIDChannel>.fromOpaque(context).takeUnretainedValue().receive(Data(bytes: report, count: length))
        }, context)
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceSetCancelHandler(device) { [cancelled] in cancelled.signal() }
        IOHIDDeviceActivate(device)
    }

    func close() {
        lock.lock()
        guard !isClosed else { lock.unlock(); return }
        isClosed = true
        lock.unlock()
        IOHIDDeviceCancel(device)
        _ = cancelled.wait(timeout: .now() + 1)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        reportBuffer.deallocate()
    }

    private func receive(_ report: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard let accept, response == nil, accept(report) else { return }
        response = report
        semaphore.signal()
    }

    /// Sends `report` (first byte is the report ID) and returns the first input report accepted by `accept`.
    func request(_ report: Data, timeout: TimeInterval, accept: @escaping (Data) -> Bool) -> Data? {
        lock.lock()
        guard !isClosed else { lock.unlock(); return nil }
        self.accept = accept
        response = nil
        lock.unlock()
        while semaphore.wait(timeout: .now()) == .success {}

        let result = report.withUnsafeBytes { buffer -> IOReturn in
            guard let bytes = buffer.bindMemory(to: UInt8.self).baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(bytes[0]), bytes, report.count)
        }
        if result == kIOReturnSuccess {
            _ = semaphore.wait(timeout: .now() + timeout)
        }

        lock.lock()
        defer { lock.unlock() }
        self.accept = nil
        let reply = response
        response = nil
        return reply
    }
}

/// HID++ 2.0 requests addressed to one device index of a receiver.
struct HIDPPTransport {
    static let softwareID: UInt8 = 0x08
    private static let shortReportID: UInt8 = 0x10
    private static let longReportID: UInt8 = 0x11
    private static let busyAttempts = 3

    let channel: HIDChannel
    let deviceIndex: UInt8
    let timeout: TimeInterval
    private let reportID: UInt8
    private let reportLength: Int

    init?(channel: HIDChannel, deviceIndex: UInt8, timeout: TimeInterval = 0.25) {
        if channel.maxOutputReportSize >= 20 {
            reportID = Self.longReportID
            reportLength = 20
        } else if channel.maxOutputReportSize >= 7 {
            reportID = Self.shortReportID
            reportLength = 7
        } else {
            return nil
        }
        self.channel = channel
        self.deviceIndex = deviceIndex
        self.timeout = timeout
    }

    func featureIndex(for id: HIDPPFeatureID) -> UInt8? {
        guard let payload = request(featureIndex: 0, function: 0, parameters: [UInt8(id.rawValue >> 8), UInt8(id.rawValue & 0xFF)]),
              let index = payload.first, index != 0 else { return nil }
        return index
    }

    /// Returns the reply payload, or nil on timeout or error reply.
    func request(featureIndex: UInt8, function: UInt8, parameters: [UInt8] = []) -> [UInt8]? {
        guard parameters.count <= reportLength - 4 else { return nil }
        let address = (function << 4) | Self.softwareID
        var report = [UInt8](repeating: 0, count: reportLength)
        report[0] = reportID
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = address
        for (i, byte) in parameters.enumerated() { report[4 + i] = byte }

        let deviceIndex = deviceIndex
        let accept: (Data) -> Bool = { data in
            let reply = [UInt8](data)
            guard reply.count >= 7, reply[0] == Self.shortReportID || reply[0] == Self.longReportID, reply[1] == deviceIndex else { return false }
            switch reply[2] {
            case 0x8F: return reply[3] == featureIndex
            case 0xFF: return reply[3] == featureIndex && reply[4] == address
            default: return reply[2] == featureIndex && reply[3] == address
            }
        }

        for _ in 0 ..< Self.busyAttempts {
            guard let data = channel.request(Data(report), timeout: timeout, accept: accept) else { return nil }
            let reply = [UInt8](data)
            if reply[2] == 0x8F { return nil }
            if reply[2] == 0xFF {
                let busy: UInt8 = 0x08
                if reply[5] == busy { continue }
                return nil
            }
            return Array(reply.dropFirst(4))
        }
        return nil
    }
}
