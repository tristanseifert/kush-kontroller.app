//
//  Pax3Device.swift
//  Pax3Device
//
//  Created by Tristan Seifert on 20210827.
//

import Foundation
import OSLog
import CoreBluetooth
import Combine

/**
 * Device behaviors specific to the Pax 3 device
 */
class Pax3Device: PaxDevice {
    /// Current temperature of the oven, in °C
    @Published private(set) public var ovenTemp: Float = Float.nan
    /// Current target temperature of the oven, in °C
    @Published private(set) public var ovenTargetTemp: Float = Float.nan
    /// Desired oven set point temperature, in °C
    @Published private(set) public var ovenSetTemp: Float = Float.nan
    /// Oven heating profile
    @Published private(set) public var ovenDynamicMode: DynamicModeMessage.Mode = .standard
    /// Current heating state
    @Published private(set) public var heatingState: HeatingStateMessage.Mode = .ovenOff
    
    // MARK: - Initialization
    override init(_ peripheral: CBPeripheral) {
        super.init(peripheral)
        self.type = .Pax3
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
     * Handles packets specific to the Pax 3. Any unhandled packets are punted to the super implementation.
     */
    override internal func processPacket(_ packet: Data) throws {
        switch packet[0] {
            case PaxMessageType.ActualTemp.rawValue:
                let message = try ActualTempMessage(fromPacket: packet)
                self.ovenTemp = message.temperature
            case PaxMessageType.HeaterSetPoint.rawValue:
                let message = try HeaterSetPointMessage(fromPacket: packet)
                self.ovenSetTemp = message.temperature
            case PaxMessageType.CurrentTargetTemp.rawValue:
                let message = try CurrentTargetTempMessage(fromPacket: packet)
                self.ovenTargetTemp = message.temperature
                
            case PaxMessageType.DynamicMode.rawValue:
                let message = try DynamicModeMessage(fromPacket: packet)
                self.ovenDynamicMode = message.mode
            case PaxMessageType.HeatingState.rawValue:
                let message = try HeatingStateMessage(fromPacket: packet)
                self.heatingState = message.mode

                
            // unhandled packets go to super
            default:
                try super.processPacket(packet)
        }
    }
    
    // MARK: Setters
    /**
     * Sets the desired oven set point temperature.
     */
    public func setOvenTemp(_ temp: Float) throws {
        guard temp >= 175, temp <= 215 else {
            throw Errors.invalidTemperature(temp)
        }
        
        let message = HeaterSetPointMessage(temperature: temp)
        try self.writePacket(message)
        
        // ensure the value is updated
        try self.reloadAttributes([.HeaterSetPoint])
    }
    
    /**
     * Sets the desired oven dynamic temperature profile.
     */
    public func setOvenDynamicMode(_ mode: DynamicModeMessage.Mode) throws {
        let message = DynamicModeMessage(mode: mode)
        try self.writePacket(message)
        
        // ensure the value is updated
        try self.reloadAttributes([.DynamicMode])
    }
    
    // MARK: - Types and constants
    enum Errors: Error {
        /// The provided temperature value is invalid
        case invalidTemperature(_ temperature: Float)
    }
    
    /// Additional attributes to read from device
    private static let DefaultAttributes: Set<PaxMessageType> = [.CurrentTargetTemp, .HeaterSetPoint,
                                                                 /*.ShellColor, */ .HeatingParams,
                                                                 .HeaterRanges, .DisplayName,
                                                                 .ActualTemp, .DynamicMode,
                                                                 .HeatingState]
}

