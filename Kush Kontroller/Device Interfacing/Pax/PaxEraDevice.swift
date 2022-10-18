//
//  PaxEraDevice.swift
//  PaxEraDevice
//
//  Created by Tristan Seifert on 20210827.
//

import Foundation
import OSLog
import CoreBluetooth

/**
 * Device behaviors specific to the Pax Era device
 */
class PaxEraDevice: PaxDevice {
    /// Temperature set point, in °C
    @Published private(set) public var temperature: Float = Float.nan

    // MARK: - Initialization
    override init(_ peripheral: CBPeripheral) {
        super.init(peripheral)
        // from iOS app UI (these may not be totally correct?)
        self.validTempRange = 220.0...420.0
        self.type = .PaxEra
    }

    /**
     * Fetch our additional set of attributes when the connection is set up.
     */
    override func readDefaultAttributes() throws {
        try super.readDefaultAttributes()
        
        // read our types
        let packet = StatusUpdateMessage(attributes: Self.DefaultAttributes)
        try self.writePacket(packet)
    }
    
    // MARK: - Attributes
    /**
     * Handles packets specific to the Pax Era. Any unhandled packets are punted to the super implementation.
     */
    override internal func processPacket(_ packet: Data) throws {
        switch packet[0] {
            case PaxMessageType.HeaterSetPoint.rawValue:
                let message = try HeaterSetPointMessage(fromPacket: packet)
                self.temperature = message.temperature

            // unhandled packets go to super
            default:
                try super.processPacket(packet)
        }
    }
    
    // MARK: Setters
    /**
     * Sets the desired oven set point temperature.
     */
    public func setTemperature(_ temp: Float) throws {
        // TODO: remove hardcoded limits (based on iOS app)
        guard temp >= 220, temp <= 420 else {
            throw Errors.invalidTemperature(temp)
        }

        let message = HeaterSetPointMessage(temperature: temp)
        try self.writePacket(message)

        // ensure the value is updated
        try self.reloadAttributes([.HeaterSetPoint])
    }
    
    // MARK: - Types and constants
    enum Errors: Error {
        /// The provided temperature value is invalid
        case invalidTemperature(_ temperature: Float)
    }

    /// Additional attributes to read from device
    private static let DefaultAttributes: Set<PaxMessageType> = [.PodInserted, .HeaterSetPoint,
                                                                 .ShellColor, .HeatingParams,
                                                                 .HeaterRanges, .DisplayName]
}
