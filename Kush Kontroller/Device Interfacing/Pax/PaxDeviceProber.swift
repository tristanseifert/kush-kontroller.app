//
//  PaxDeviceProber.swift
//  PaxDeviceProber
//
//  Created by Tristan Seifert on 20210827.
//

import Foundation
import OSLog
import CoreBluetooth

/**
 * Provides support for reading out the device manufacturer and model information to try to determine what type of Pax we have.
 */
class PaxDeviceProber: NSObject, CBPeripheralDelegate {
    static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "device.pax.prober")
    
    /// All currently in progress device probes
    private var states = [ProbeState]()
    
    /**
     * Read the model information for the provided Bluetooth device to determine what kind of Pax it is. On success, the callback is
     * invoked with an allocated (but not yet started) instance of the device, or an error.
     */
    public func probe(_ peripheral: CBPeripheral, _ callback: @escaping (Result<PaxDevice, Error>) -> Void) {
        // register state
        let info = ProbeState(device: peripheral, callback)
        
        peripheral.delegate = self
        self.states.append(info)
        
        // try to discover the info service
        peripheral.discoverServices([Self.DeviceInfoService])
    }
    
    // MARK: - Helpers
    /**
     * Actually probes a device once all information has been read out.
     */
    private func performProbe(_ peripheral: CBPeripheral, _ info: ProbeState) {
        Self.L.trace("Determining device type for manufacturer='\(info.manufacturer ?? "(null)")', model='\(info.model ?? "(null)")'")
        
        precondition(info.manufacturer != nil)
        precondition(info.model != nil)
        
        // ensure manufacturer
        guard info.manufacturer == Self.ExpectedManufacturer else {
            return self.handleError(peripheral, Errors.invalidManufacturer(info.manufacturer!))
        }
        
        // check out the model names
        switch info.model! {
            case Self.ModelNameEra:
                let device = PaxEraDevice(peripheral)
                return self.handleSuccess(peripheral, device)
            case Self.ModelNamePax3:
                let device = Pax3Device(peripheral)
                return self.handleSuccess(peripheral, device)
            
            default:
                return self.handleError(peripheral, Errors.unsupportedDevice(info.model!))
        }
    }
    
    /**
     * Handles an error that occurred at some stage of the probing process.
     */
    private func handleError(_ peripheral: CBPeripheral, _ error: Error) {
        Self.L.error("Fatal probe error for \(peripheral): \(error.localizedDescription)")
        
        // get the info struct
        guard let info = self.states.first(where: { $0.device == peripheral }) else {
            fatalError("Error for peripheral \(peripheral) with no info struct!")
        }

        // remove info structure and invoke the callback
        peripheral.delegate = info.oldDelegate
        self.states.removeAll(where: { $0.device == peripheral })
        
        info.callback(.failure(error))
    }
    
    /**
     * Handles a successful probe.
     */
    private func handleSuccess(_ peripheral: CBPeripheral, _ device: PaxDevice) {
        Self.L.trace("Device for \(peripheral): \(device)")
        
        // get the info struct
        guard let info = self.states.first(where: { $0.device == peripheral }) else {
            fatalError("No info struct for \(peripheral)!")
        }
        
        // remove info structure and invoke the callback
        // NOTE: we do not set the delegate; it has been replaced by the device object
        self.states.removeAll(where: { $0.device == peripheral })
        
        info.callback(.success(device))
    }
    
    // MARK: - Peripheral delegate
    /**
     * We've discovered services; depending on whether it's the Pax control or device info endpoint, discover the appropriate
     * characteristics.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error {
            return self.handleError(peripheral, err)
        }
        
        // once the info service is found, get the manufacturer and model characteristics
        guard let infoSvc = peripheral.services?.first(where: { $0.uuid == Self.DeviceInfoService }) else {
            fatalError("Failed to find device info service!")
        }
        
        peripheral.discoverCharacteristics([Self.ManufacturerCharacteristic,
                                            Self.ModelNumberCharacteristic], for: infoSvc)
    }
    
    /**
     * Characteristics have been discovered; request to read both the manufacturer and model number.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error {
            return self.handleError(peripheral, err)
        }
        
        // read all discovered characteristics; this _should_ just be the two we requested
        if service.uuid == Self.DeviceInfoService {
            service.characteristics!.forEach {
                peripheral.readValue(for: $0)
            }
        } else {
            Self.L.warning("Unexpected characteristics for \(service): \(service.characteristics!)")
        }
    }
    
    /**
     * Data has been read from the peripheral.
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            return self.handleError(peripheral, err)
        }
        guard let info = self.states.first(where: { $0.device == peripheral }) else {
            fatalError("Failed to get info struct for \(peripheral)")
        }
        
        // handle info characteristic reads
        if characteristic.service?.uuid == Self.DeviceInfoService {
            if let data = characteristic.value {
                switch characteristic.uuid {
                    case Self.ManufacturerCharacteristic:
                        info.manufacturer = String(bytes: data, encoding: .utf8)
                    case Self.ModelNumberCharacteristic:
                        info.model = String(bytes: data, encoding: .utf8)
                        
                    default:
                        Self.L.trace("Unexpected device info update for \(characteristic.uuid): \(data.hexEncodedString())")
                }
            }
            
            // perform probing if all data has been found
            if info.manufacturer != nil && info.model != nil {
                self.performProbe(peripheral, info)
            }
        }
        // no handler available
        else {
            if let data = characteristic.value {
                Self.L.trace("Received unexpected characteristic update for \(characteristic): \(data.hexEncodedString())")
            } else {
                Self.L.trace("Received unexpected characteristic update for \(characteristic)")
            }
        }
    }
    
    // MARK: - Types and constants
    class ProbeState {
        init(device: CBPeripheral, _ callback: @escaping (Result<PaxDevice, Error>) -> Void) {
            self.device = device
            self.oldDelegate = device.delegate
            
            self.callback = callback
        }
        
        /// Device being probed
        var device: CBPeripheral
        var oldDelegate: CBPeripheralDelegate?
        
        var manufacturer: String!
        var model: String!
        
        /// Method to invoke once we've determined its state
        var callback: ((Result<PaxDevice, Error>) -> Void)
    }
    
    enum Errors: Error {
        /// The manufacturer of the device is invalid
        case invalidManufacturer(_ manufacturer: String)
        /// The model name of the device us unknown
        case unsupportedDevice(_ model: String)
    }
    
    private static let DeviceInfoService = CBUUID(string: "180A")
    private static let ManufacturerCharacteristic = CBUUID(string: "2A29")
    private static let ModelNumberCharacteristic = CBUUID(string: "2A24")
    
    /// Expected manufacturer name string
    private static let ExpectedManufacturer = "PAX Labs, Inc"
    /// Model name string for the Pax Era
    private static let ModelNameEra = "ERA"
    /// Model name string for the Pax 3
    private static let ModelNamePax3 = "PAX3"
}
