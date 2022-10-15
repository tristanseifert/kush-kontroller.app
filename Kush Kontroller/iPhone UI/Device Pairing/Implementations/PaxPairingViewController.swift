//
//  PaxPairingViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import UIKit

class PaxPairingViewController: UIViewController {
    /// Types of supported devices
    public enum DeviceType {
        case Pax3, PaxEra
    }
    /// Device type to search for
    public var type: DeviceType!
}
