//
//  Types.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import Foundation

enum PairingError: LocalizedError {
    /// The device already has been paired
    case deviceExists
    /// Pairing timed out
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .deviceExists:
            return NSLocalizedString("PairingError.deviceExists.desc", tableName: "PairingTypes", comment: "")
        case .timeout:
            return NSLocalizedString("PairingError.timeout.desc", tableName: "PairingTypes", comment: "")
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .deviceExists:
            return NSLocalizedString("PairingError.deviceExists.recovery", tableName: "PairingTypes", comment: "")
        default:
            return nil
        }
    }
}
