//
//  Bluefruit Buddy
//
//  Created by Kevin Kachikian on 8/4/15.
//  Copyright © 2015 Adafruit Industries. All rights reserved.
//

import AppKit
import Foundation
import CoreBluetooth



func delayRunOnMainQ(_ delay: Double, closure: @escaping (Void)->Void) {
	
	let delayTime = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
	DispatchQueue.main.asyncAfter(deadline: delayTime) {
		closure()
	}
	
}




extension NSWindow {
	
	func alert(_ message: String, infoText: String, completion: (()->Void)? = nil) {
		
		delayRunOnMainQ(0) {
			let alert = NSAlert()																									// Must be run on main thread. Sometimes called from another thread
			alert.messageText = message
			alert.addButton(withTitle: "OK")
			alert.informativeText = infoText
			
			alert.beginSheetModal(for: self, completionHandler: { (NSModalResponse)->Void in
				completion?()																										// Call any optional completion after the user clicks
			})
		}
		
	}
	
	
	// Checks that BLE is OK, otherwise report a problem.
	func reportBLEStatus(_ manager: CBCentralManager) {
		
		let info: String
		
		switch manager.state {
		case .poweredOn:
                        // All is well. Just exit & don't call completion
                        return
		case .poweredOff: info = "Bluetooth is currently powered off. Enable Bluetooth in the System Settings.";
		case .resetting: info = "The connection was momentarily lost; an update is imminent. Try again shortly."
		case .unauthorized: info = "This application is not authorized to use Bluetooth Low Energy.";
		case .unsupported: info = "This Mac does not support Bluetooth Low Energy."
		case .unknown: info = "The current state of the Central Manager is unknown; an update is imminent. Try again shortly."
		}
		
		manager.stopScan()																											// Errors stop scanning until they are resolved
		
		self.alert("Bluetooth snag", infoText: info)
		
	}

}




// Load up a list of known GATT Characteristics (once). 16-bit UUIDs are defined by the Bluetooth SIG, 128-bit UUIDs are custom. There will be 32-bit UUIDs in the future
private var gattCharacteristicNames: Dictionary<String, String> = {

	let path = Bundle.main.path(forResource: "GATT-characteristic-names", ofType: "plist")
        return NSDictionary(contentsOfFile: path!) as! Dictionary<String, String>

}()




extension CBUUID {
	
	// Given a characteristic UUID, return it's name if known
        var characteristicName: String {
		return gattCharacteristicNames[uuidString] ?? uuidString
	}
	
	
	// Some needed UUID constants as defined in GATT-characteristic-names.plist
        static let UARTService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        static let UARTTxCharacteristic = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        static let UARTRxCharacteristic = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
        static let DFUService = CBUUID(string: "00001530-1212-EFDE-1523-785FEABCD123")
        static let DFUVersion = CBUUID(string: "00001534-1212-EFDE-1523-785FEABCD123")
	
        static let BatteryLevel = CBUUID(string: "2A19")
        static let CurrentTime = CBUUID(string: "2A2B")
        static let LocalTimeInfo = CBUUID(string: "2A0F")
}

extension String {
        
        // Allow String subscripting such as "AString"[3...4] which would return "ri"
        subscript (r: Range<Int>) -> String {
                let startI = characters.index(startIndex, offsetBy: r.lowerBound)
                let endI = characters.index(startIndex, offsetBy: r.upperBound)
                return substring(with: startI..<endI)
        }
        
}

extension Data {
        var lowercaseHexString: String {
                let nibble = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
                var result = ""
                for i in 0..<count {
                        let byte = self[i]
                        let high = Int((byte >> 4) & 0xf)
                        let low = Int(byte & 0xf)
                        result.append(nibble[high])
                        result.append(nibble[low])
                }
                return result
        }
}

extension String {

        // BTLE characteristic values can return Data with embedded NUL bytes. String(data:encoding:) will happily quote those.
        static func fromBTLE(utf8 data: Data) -> String {
                if let nulIndex = data.index(where: { $0 == 0 }) {
                        let prefix = data.subdata(in: 0..<nulIndex)
                        return String(data: prefix, encoding: .utf8) ?? "Not UTF-8"
                }
                return String(data: data, encoding: .utf8) ?? "Not UTF-8"
        }
}
