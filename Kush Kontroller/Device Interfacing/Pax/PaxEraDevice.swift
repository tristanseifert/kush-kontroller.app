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
    // MARK: - Initialization
    override init(_ peripheral: CBPeripheral) {
        super.init(peripheral)
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
            // unhandled packets go to super
            default:
                try super.processPacket(packet)
        }
    }
    
    // MARK: - Types and constants
    /// Additional attributes to read from device
    private static let DefaultAttributes: Set<PaxMessageType> = [.PodInserted, .HeaterSetPoint,
                                                                 .ShellColor, .HeatingParams,
                                                                 .HeaterRanges, .DisplayName]
}
