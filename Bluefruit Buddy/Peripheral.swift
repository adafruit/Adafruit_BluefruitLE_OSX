//
//  Bluefruit Buddy
//
//  Created by Kevin Kachikian on 8/23/15.
//  Copyright © 2015 Adafruit. All rights reserved.
//

import AppKit
import Foundation
import CoreBluetooth



private let DisconnectTimeOut: TimeInterval = 20																// The # secs within which advertising does not show up causes us to think the device has gone AWOL



// Data model for each found Peripheral
// Goes disabled (gray) after an X second timeout if no advertisement data is sent indicating the peripheral is out of range or has shut off or otherwise disconnected
class Peripheral: NSObject, CBPeripheralDelegate {																// Must subclass from NSObject so NSTimer works!
	
	enum GATT {																									// Records the Services and Characteristics returned by a Peripheral
		case service(CBService)
		case characteristic(CBCharacteristic)
	}
	var displayGATT: [GATT] = []																				// The Characteristic and Service data to display. NOTE: The service field in a Characteristic is unowned(unsafe) and does not maintain its Service information
	
	var detailsController: DetailsWindowController?																// The details window connected to this Peripheral
	
	private let manager: CBCentralManager
	let peripheral: CBPeripheral																				// Side note: The UUID identifier is assigned by the Mac and not the actual UUID on the Peripheral. It is not persisted across Mac reboot/power offs
	let advertisementData: [String : AnyObject]
	var RSSI: NSNumber {
		didSet {
			if RSSI != 127 {																					// 127 is used to indicate 'n/a' RSSI & is set when our autodisable timer fires
				restartAutodisableTimer()
			}
		}
	}
	
	private var delegate: BLEPeripheralListHandlerDelegate?
	var deviceDisabled = true {																					// Start in a disabled (unselectable) state b/c we are about to do a Services lookup
		didSet {
			delegate?.refreshPeripheralList()
		}
	}
	
	private var rememberedSeconds: TimeInterval = 0
	private var disableTimer: Timer?																			// A timer to disable Peripherals in the list that are not continuously reporting advertising packets (and that are not already connect to the Mac)
	
	private var allServices: [CBService]!
	private var serviceIdx = 0																					// Index into allServices
	private var allCharacteristicsForService: [CBCharacteristic]!
	private var characteristicIdx = 0																			// Index into allCharacteristics
	var completeDISdata = false																					// Logs status of if we have obtained all the characteristics for this device yet or not
	
	
	// MARK: -
	
	init(manager: CBCentralManager, peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber, refreshDelegate: BLEPeripheralListHandlerDelegate) {
		
		self.manager = manager
		self.peripheral = peripheral
		self.advertisementData = advertisementData
		self.RSSI = RSSI
		self.delegate = refreshDelegate
		
		super.init()
		
	}
	
	
	deinit {
		
		disableTimer?.invalidate()
		
	}
	
	
	// CBPeripheralDelegate
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		
		if verboseConsoleLog { NSLog("didDiscoverServices: peripheral=\(peripheral)"); if error != nil { NSLog("ERROR=\(error!)") } }
		
		if peripheral.services == nil {																			// An error in Service discovery
			advance(peripheral)																					// Keep us going anyway
			return
		}
		
		allServices = peripheral.services!																		// Record all Services this Peripheral offers in case CB changes the order of discovered services (unlikely but not documented not to)
		serviceIdx = 0																							// Start discovering the 1st one
		
		handleCharacteristicDiscoveryForService(peripheral, aService: allServices[serviceIdx])					// Iterate through each Service and see what Characteristics it has
		
	}
	
	
	// Called for each Service
	func handleCharacteristicDiscoveryForService(_ peripheral: CBPeripheral, aService: CBService) {
		
		if verboseConsoleLog { NSLog("Discovered Service: \(aService), isPrimary=\(aService.isPrimary)") }
		
		displayGATT.append(.service(aService))																	// Remember the Service
		
		peripheral.discoverCharacteristics(nil, for: aService)											// Discover ALL the Characteristics for this Service. Chains to didDiscoverCharacteristicsForService
		
	}
	
	
	// CBPeripheralDelegate
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		
		if verboseConsoleLog { NSLog("didDiscoverCharacteristicsForService: peripheral=\(peripheral), service=\(service)"); if error != nil { NSLog("ERROR=\(error!)") } }
		
		if peripheral.services == nil {																			// An error in Characteristic discovery
			advance(peripheral)																					// Keep us going anyway
			return
		}
		
		allCharacteristicsForService = service.characteristics!													// Record all Characteristics this Service offers in case CB changes the order of discovered Characteristics (unlikely but not documented not to)
		characteristicIdx = 0																					// Start discovering the 1st Characteristic's data
		
		handleValueAquisitionForCharacteristic(peripheral, characteristic: allCharacteristicsForService[characteristicIdx])	// Iterate through all the Characteristics for this Service and get their Values if readable
		
	}
	
	
	// Called for each Characteristic for each Service
	func handleValueAquisitionForCharacteristic(_ peripheral: CBPeripheral, characteristic: CBCharacteristic) {
		
		if verboseConsoleLog { NSLog("Discovered Characteristic: \(characteristic) \(characteristic.properties) \(characteristic.uuid.characteristicName)") }
		
		if characteristic.properties.contains(.read) {					// This Characteristic allows reading
			peripheral.readValue(for: characteristic)												// Reads the value by chaining to didUpdateValueForCharacteristic
			peripheral.setNotifyValue(true, for: characteristic)									// Set up for any changes to the Characteristic. Also chains to didUpdateValueForCharacteristic
		} else {
			if verboseConsoleLog { NSLog("Characteristic does not support reading") }
			
			displayGATT.append(.characteristic(characteristic))													// Remember for display
			
			advance(peripheral)																					// Can't read anything from it so advance to the next Characteristic or Service
		}
		
	}
	
	
	// CBPeripheralDelegate
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		
		if verboseConsoleLog {
                        let byteString: String
                        let characteristicValue: String
                        
                        if let value = characteristic.value {
                                byteString = value.lowercaseHexString
                                characteristicValue = String.fromBTLE(utf8: value)
                        } else {
                                byteString = ""
                                characteristicValue = "n/a"
                        }
			NSLog("didUpdateValueForCharacteristic: peripheral=\(peripheral)")
			NSLog("service=\(characteristic.service), characteristic=\(characteristic) \(characteristic.uuid.characteristicName), bytes=\(byteString) \"\(characteristicValue)\"")
			if error != nil { NSLog("ERROR=\(error!)") }
		}
		
		displayGATT.append(.characteristic(characteristic))														// Remember for display
		delegate!.refreshPeripheralList()																		// Tell to refresh when new or updated data come in
		
		advance(peripheral)
		
	}
	
	
	// Acquire the next Characteristic for this Service or the next Service if all the Characteristics have been obtained
	// When all Services have been queried, disconnect from the Peripheral to allow it to advertise again
	func advance(_ peripheral: CBPeripheral) {
		
		characteristicIdx += 1
		if characteristicIdx < allCharacteristicsForService.count {												// Next Charactertistic
			handleValueAquisitionForCharacteristic(peripheral, characteristic: allCharacteristicsForService[characteristicIdx])
			return
		}
		
		serviceIdx += 1
		if serviceIdx < allServices.count {																		// If more services, discover the Characteristics
			handleCharacteristicDiscoveryForService(peripheral, aService: allServices[serviceIdx])
			return
		}
		
		// Done with all Services & all Characteristics
		manager.cancelPeripheralConnection(peripheral)															// Disconnect from the Peripheral so it will start advertising itself again
		
		allServices = nil																						// Free up (potentially memory if CB copy on write had happened)
		allCharacteristicsForService = nil
		
		startAutodisableTimer(seconds: DisconnectTimeOut)														// # of seconds of inactivity - no advertisement data - makes this Peripheral automatically go disabled (gray and unselectable)
		
		completeDISdata = true
		
	}
	
	
	private func startAutodisableTimer(seconds: TimeInterval) {										// Create a timer that needs to be tickled every 'second' seconds otherwise it will fire
		
		rememberedSeconds = seconds
		restartAutodisableTimer()
		delegate!.refreshPeripheralList()
		
	}
	
	
	private func restartAutodisableTimer() {																	// 'Tickle' the timer (can be called from non-main threads)
		
		deviceDisabled = false
		
		delayRunOnMainQ(0) {																					// Timers MUST be instantiated on the main thread
			self.disableTimer?.invalidate()
			self.disableTimer = Timer.scheduledTimer(timeInterval: self.rememberedSeconds, target: self, selector: #selector(Peripheral.disablePeripheral), userInfo: nil, repeats: false)
		}
		
	}
	
	
	/* private */ func disablePeripheral() {																	// NSTimer target functions can't be private {:~(
		
		deviceDisabled = true
		RSSI = 127																								// Indicate to show n/a for RSSI
		
	}
	
	
	func supports(service uuid: CBUUID) -> Bool {
		
		if self.displayGATT.index(where: {
			switch $0 {																							// Syntactically unattractive, but amazing how Swift does the magic
			case let .service(aServ): if aServ.uuid == uuid { return true }
			case .characteristic(_): return false
			}
			return false
		}) != nil {																								// Found the Service
			return true
		} else {
			return false
		}
		
	}
	
	
	class func findPeripheral(_ id: UUID) -> Peripheral {
		
		let periph = foundPeripherals.filter() { $0.peripheral.identifier == id }
		guard periph.count != 0 else { preconditionFailure("searched peripheral not located") }					// If we are searching for it, it must be in foundPeripherals, otherwise big problem...
		
		return periph[0]
		
	}
	
} // Peripheral

extension Peripheral.GATT {
        var displayString: String {
                switch self {
                        
                case let .service(aServ):
                        return "\(aServ.uuid.characteristicName)"
                        
                case let .characteristic(aChar):
                        guard aChar.properties.contains(.read) else {
                                // Doesn't allow reading so print characteristic name only
                                return "    \(aChar.uuid.characteristicName)"
                        }
                        
                        let characteristicString = aChar.displayString
                        return "    \(aChar.uuid.characteristicName) \"\(characteristicString)\""
                }
        }
        
}

extension CBCharacteristic {
        var displayString: String {
                guard properties.contains(.read) else {
                        return "??"
                }
                
                guard let value = value else {
                        return "n/a"
                }
                
                switch uuid {
                case CBUUID.BatteryLevel:
                        // <https://www.bluetooth.com/specifications/gatt/viewer?attributeXmlFile=org.bluetooth.characteristic.battery_level.xml>
                        // One byte, 0.100 are the allowed values
                        if value.count == 1 {
                                let level = value[0]
                                if level <= 100 {
                                        return "\(level)%"
                                }
                        }
                        return value.lowercaseHexString

                case CBUUID.CurrentTime:
                        // https://www.bluetooth.com/specifications/gatt/viewer?attributeXmlFile=org.bluetooth.characteristic.current_time.xml
                        
                        // The current time characterisitic is supposed to be a single byte with four bits (or 255)
                        // iPhone, at least, is sending back 10 bytes...
                        if value.count == 1 {
                                let byte = value[0]
                                if byte <= 0xf {
                                        return "\(byte)"
                                }
                        }
                        return value.lowercaseHexString
                        
                case CBUUID.LocalTimeInfo:
                        // https://www.bluetooth.com/specifications/gatt/viewer?attributeXmlFile=org.bluetooth.characteristic.local_time_information.xml
                        
                        // A time zone followed by DST offset
                        if value.count == 2 {
                                return "\(timeZoneString(byte: value[0])), \(dstString(byte: value[1]))"
                        }
                        return value.lowercaseHexString
                        
                case CBUUID.DFUVersion:
                        // Special case (oooohhhh nooooo) printing of the DFU Version. It's not a string. Print its raw data
                        return value.lowercaseHexString
                        
                default:
                        return String.fromBTLE(utf8: value)
                }
        }
        
        // Time zone, as in <https://www.bluetooth.com/specifications/gatt/viewer?attributeXmlFile=org.bluetooth.characteristic.time_zone.xml>
        private func timeZoneString(byte: UInt8) -> String {
                let tz = Int8(bitPattern: byte)
                
                // The pattern of this data is regular enough that we really could code the conversion...
                switch tz {
                case -48: return "UTC-12:00"
                case -44: return "UTC-11:00"
                case -40: return "UTC-10:00"
                case -38: return "UTC-9:30"
                case -36: return "UTC-9:00"
                case -32: return "UTC-8:00"
                case -28: return "UTC-7:00"
                case -24: return "UTC-6:00"
                case -20: return "UTC-5:00"
                case -18: return "UTC-4:30"
                case -16: return "UTC-4:00"
                case -14: return "UTC-3:30"
                case -12: return "UTC-3:00"
                case -8: return "UTC-2:00"
                case -4: return "UTC-1:00"
                case 0: return "UTC+0:00"
                case 4: return "UTC+1:00"
                case 8: return "UTC+2:00"
                case 12: return "UTC+3:00"
                case 14: return "UTC+3:30"
                case 16: return "UTC+4:00"
                case 18: return "UTC+4:30"
                case 20: return "UTC+5:00"
                case 22: return "UTC+5:30"
                case 23: return "UTC+5:45"
                case 24: return "UTC+6:00"
                case 26: return "UTC+6:30"
                case 28: return "UTC+7:00"
                case 32: return "UTC+8:00"
                case 35: return "UTC+8:45"
                case 36: return "UTC+9:00"
                case 38: return "UTC+9:30"
                case 40: return "UTC+10:00"
                case 42: return "UTC+10:30"
                case 44: return "UTC+11:00"
                case 46: return "UTC+11:30"
                case 48: return "UTC+12:00"
                case 51: return "UTC+12:45"
                case 52: return "UTC+13:00"
                case 56: return "UTC+14:00"
                default: return "Unknown TZ"
                }
        }
 
        // DST info, as in <https://www.bluetooth.com/specifications/gatt/viewer?attributeXmlFile=org.bluetooth.characteristic.dst_offset.xml>
        private func dstString(byte: UInt8) -> String {
                switch (byte) {
                case 0: return "Standard"
                case 2: return "Half-hour DST"
                case 4: return "DST"
                case 8: return "Double DST"
                default: return "Unknown DST"
                }
        }

}
