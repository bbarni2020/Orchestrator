import Foundation
import IOKit
import IOKit.hid

protocol HIDDevice: AnyObject {
    var vendorID: Int { get }
    var productID: Int { get }
    var name: String { get }
    func setColor(red: UInt8, green: UInt8, blue: UInt8) -> Bool
}

protocol HIDWriteProbeCapable {
    func probeWriteAccess() -> Bool
}

class HIDDeviceConnection {
    private var device: IOHIDDevice?
    private var manager: IOHIDManager?
    private let vendorID: Int
    private let productID: Int
    
    init(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
    }
    
    func connect() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let matchingDict = NSMutableDictionary()
        matchingDict[kIOHIDVendorIDKey] = NSNumber(value: vendorID)
        matchingDict[kIOHIDProductIDKey] = NSNumber(value: productID)
        
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard openStatus == kIOReturnSuccess else {
            print("[HID] Manager failed to open: status \(openStatus)")
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return false
        }
        
        let devices = Array((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [])
        print("[HID] VID:0x\(String(vendorID, radix: 16)) PID:0x\(String(productID, radix: 16)) → Found \(devices.count) device(s)")
        
        guard !devices.isEmpty else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return false
        }
        
        if let foundDevice = devices.first {
            let deviceResult = IOHIDDeviceOpen(foundDevice, IOOptionBits(kIOHIDOptionsTypeNone))
            if deviceResult == kIOReturnSuccess {
                self.device = foundDevice
                self.manager = manager
                return true
            }
        }
        
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return false
    }
    
    func sendReport(data: [UInt8], reportID: UInt8? = nil) -> Bool {
        guard let device = device else { return false }

        return sendReport(to: device, data: data, reportID: reportID)
    }

    func sendReportToMatchingDevices(data: [UInt8], reportID: UInt8? = nil) -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matchingDict = NSMutableDictionary()
        matchingDict[kIOHIDVendorIDKey] = NSNumber(value: vendorID)
        matchingDict[kIOHIDProductIDKey] = NSNumber(value: productID)

        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return false
        }

        let devices = Array((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [])
        var success = false

        for device in devices {
            let deviceOpenStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard deviceOpenStatus == kIOReturnSuccess else { continue }

            if sendReport(to: device, data: data, reportID: reportID) {
                success = true
            }

            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return success
    }

    func connectAndDisconnectProbe() -> Bool {
        let connected = connect()
        disconnect()
        return connected
    }

    private func sendReport(to device: IOHIDDevice, data: [UInt8], reportID: UInt8?) -> Bool {
        var mutableData = data
        let resolvedReportID = CFIndex(reportID ?? data.first ?? 0)

        let outputResult = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            resolvedReportID,
            &mutableData,
            mutableData.count
        )

        if outputResult == kIOReturnSuccess {
            return true
        }

        let featureResult = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeFeature,
            resolvedReportID,
            &mutableData,
            mutableData.count
        )

        return featureResult == kIOReturnSuccess
    }
    
    func disconnect() {
        if let device = device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager = manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        self.device = nil
        self.manager = nil
    }
    
    deinit {
        disconnect()
    }
}
