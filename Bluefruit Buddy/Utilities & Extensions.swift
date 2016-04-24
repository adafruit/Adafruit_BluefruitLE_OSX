//
//  Bluefruit Buddy
//
//  Created by Kevin Kachikian on 8/4/15.
//  Copyright © 2015 Adafruit Industries. All rights reserved.
//

import AppKit
import Foundation
import CoreBluetooth



func delayRunOnMainQ(delay: Double, closure: Void->Void) {
	
	let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC)))
	dispatch_after(delayTime, dispatch_get_main_queue()) {
		closure()
	}
	
}




extension NSWindow {
	
	func alert(message: String, infoText: String, completion: (()->Void)? = nil) {
		
		delayRunOnMainQ(0) {
			let alert = NSAlert()																									// Must be run on main thread. Sometimes called from another thread
			alert.messageText = message
			alert.addButtonWithTitle("OK")
			alert.informativeText = infoText
			
			alert.beginSheetModalForWindow(self, completionHandler: { (NSModalResponse)->Void in
				completion?()																										// Call any optional completion after the user clicks
			})
		}
		
	}
	
	
	// Checks that BLE is OK, otherwise report a problem and call the optional completion handler after the user clicks OK
	func reportBLEStatus(manager: CBCentralManager, completion: (()->Void)? = nil) {
		
		let info: String
		
		switch manager.state {
		case .PoweredOn: return																										// All is well. Just exit & don't call completion
		case .PoweredOff: info = "Bluetooth is currently powered off. Enable Bluetooth in the System Settings.";
		case .Resetting: info = "The connection was momentarily lost; an update is imminent. Try again shortly."
		case .Unauthorized: info = "This application is not authorized to use Bluetooth Low Energy.";
		case .Unsupported: info = "This Mac does not support Bluetooth Low Energy."
		case .Unknown: info = "The current state of the Central Manager is unknown; an update is imminent. Try again shortly."
		}
		
		manager.stopScan()																											// Errors stop scanning until they are resolved
		
		self.alert("Bluetooth snag", infoText: info)
		
	}

}




// Load up a list of known GATT Characteristics (once). 16-bit UUIDs are defined by the Bluetooth SIG, 128-bit UUIDs are custom. There will be 32-bit UUIDs in the future
var gattCharacteristicNames: Dictionary<String, String>! = {

	let path = NSBundle.mainBundle().pathForResource("GATT-characteristic-names", ofType: "plist")
	let names = NSDictionary(contentsOfFile: path!) as? Dictionary<String, String>
	return names

}()




extension CBUUID {
	
	// Given a characteristic UUID, return it's name if known
	func characteristicNameForUUID() -> String {  
		
		if let name = gattCharacteristicNames[self.UUIDString] {
			return name
		}
		return self.UUIDString
		
	}
	
	
	// Some needed UUID constants as defined in GATT-characteristic-names.plist
	enum UUIDs: String {
		case UARTService = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
		case UARTTxCharacteristic = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
		case UARTRxCharacteristic = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
		case DFUService = "00001530-1212-EFDE-1523-785FEABCD123"
		case DFUVersion = "00001534-1212-EFDE-1523-785FEABCD123"
	}
	
}




extension String {
	
	// Allow String subscripting such as "AString"[3...4] which would return "ri"
	subscript (i: Int) -> Character {
		return self[self.startIndex.advancedBy(i)]
	}
	
	subscript (i: Int) -> String {
		return String(self[i] as Character)
	}
	
	subscript (r: Range<Int>) -> String {
		let startI = startIndex.advancedBy(r.startIndex)
		let endI = startIndex.advancedBy(r.endIndex)
		return substringWithRange(startI..<endI)
	}
	
	
	// Convert "4164616672756974".hexToPrintableString() to "Adafruit"
	func hexToPrintableString() -> String {
		
		let validHex = self.lowercaseString.characters.filter() {													// Strip out any non-hex characters
			let alpha = ($0 >= "a" && $0 <= "f")																	// XC 7.3 / Swift 2.2 complains when these 3 lines are combined
			let numeric = ($0 >= "0" && $0 <= "9")
			return alpha || numeric
		}
		let validHexStr = String(validHex)
		
		if validHexStr.characters.count % 2 == 1 { return "" }														// Must be an even number of hex characters
		
		var printableString = ""
		for i in 0.stride(to: validHexStr.characters.count, by: 2) {												// Convert 2 consecutive characters
			let v = Int(validHexStr[i...i+1], radix: 16)!
			printableString += UnicodeScalar(v).escape(asASCII: true)
		}
		
		return printableString
	}
	
}

