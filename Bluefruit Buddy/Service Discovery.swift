//
//  Bluefruit Buddy
//
//  Created by Kevin Kachikian on 8/4/15.
//  Copyright © 2015 Adafruit Industries. All rights reserved.
//
//	Some good best practices when using Core BT to communicate with external BLE devices:
//		https://developer.apple.com/library/ios/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/BestPracticesForInteractingWithARemotePeripheralDevice/BestPracticesForInteractingWithARemotePeripheralDevice.html
//

import AppKit
import Foundation
import CoreBluetooth



let cbManagerQ = DispatchQueue(label: "com.adafruit.blebud.queue", attributes: DispatchQueue.Attributes.concurrent)					// Define our own queue to put Central events onto

var foundPeripherals: [Peripheral] = []																			// Array of found devices. Items are never removed, just marked as disconnected



// This kicks off the communications with a BLE peripheral device by searching for whomever is advertising
class ServiceDiscovery: NSObject, CBCentralManagerDelegate {
	
	fileprivate var manager: CBCentralManager!																		// Two-phase initialize manager (since it requires self - define as var)
	fileprivate let delegate: BLEPeripheralListHandlerDelegate
	
	
	init(delegate: BLEPeripheralListHandlerDelegate) {
		
		self.delegate = delegate
		
		super.init()
		
		manager = CBCentralManager(delegate: self, queue: cbManagerQ)											// Start up the BLE Manager. Fires off an initial call to centralManagerDidUpdateState
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManagerDidUpdateState(_ manager: CBCentralManager) {
		
		if manager.state == .poweredOn {
			// Scan for all BLE peripherals no matter their Service ID. Can call scanForPeripheralsWithServices multiple times even if a scan is currently in progress
			// Pass in true so we keep receiving advertising messages to let us indicate when a peripheral goes offline and to constantly get its RSSI
			// The CBCentralManagerScanOptionAllowDuplicatesKey parameter doesn't seem to have any effect (on 10.10.5) but set here as needed anyway
			manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])	// Chains to didDiscoverPeripheral
		} else {
			delegate.window.reportBLEStatus(manager)															// Report an error
		}
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
		
		if verboseConsoleLog { NSLog("didDiscoverPeripheral: peripheral=\(peripheral), RSSI=\(RSSI) dBm, advertisementData=\(advertisementData)") }
		
		let existingPeripheral = foundPeripherals.filter() { $0.peripheral.identifier == peripheral.identifier } // Search to see if we have previously seen this particular device
		
		if existingPeripheral.count == 0 {																		// New, never before seen peripheral
			
			let newDevice = Peripheral(manager: manager, peripheral: peripheral, advertisementData: advertisementData as [String : AnyObject], RSSI: RSSI, refreshDelegate: delegate)	// Chains to didConnectPeripheral by way of a connectPeripheral call
			foundPeripherals.append(newDevice)																	// Record a new device
			
				// Start a Services lookup
			delayRunOnMainQ(0.1) {																				// Delay the lookup so we can return to report back the advertisement info already discovered while the services lookup commences
				peripheral.delegate = newDevice
				self.manager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey : true])	// Connect to the newly found Peripheral. Chains to didConnectPeripheral or didFailToConnectPeripheral
			}
		
		} else {																								// Previously known device
			existingPeripheral[0].RSSI = RSSI																	// Just update its RSSI
		}
		
		delegate.refreshPeripheralList()
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		
		if verboseConsoleLog { NSLog("didConnectPeripheral: peripheral=\(peripheral)") }
		
		peripheral.discoverServices(nil)																		// Discover ALL Services for this peripheral. This could be many but will likely be few. Chains to didDiscoverServices in Peripheral
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		
		if verboseConsoleLog { NSLog("didFailToConnectPeripheral: peripheral=\(peripheral), ERROR=\(error!)") }
		
		delegate.window!.alert("Failed to connect", infoText: error!.localizedDescription)
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		
		if verboseConsoleLog { NSLog("didDisconnectPeripheral: peripheral=\(peripheral), ERROR=\(error)") }
		
		if error != nil {
			delegate.window!.alert("Peripheral disconnected", infoText: error!.localizedDescription)
		}
		
	}
	
	
	// Resets all found peripherals. Scanning continues
	func discoveryReset() {
		
		foundPeripherals.removeAll()
		delegate.refreshPeripheralList()
		
	}
	
} // ServiceDiscovery

