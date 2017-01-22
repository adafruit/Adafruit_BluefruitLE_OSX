//
//  Bluefruit Buddy
//
//  Created by Kevin Kachikian on 8/4/15.
//  Copyright © 2015 Adafruit Industries. All rights reserved.
//

import AppKit
import CoreBluetooth



protocol BLEPeripheralListHandlerDelegate {
	var window: NSWindow! { get }
	func refreshPeripheralList()
}



// Handles the display and selection of all found BLE peripherals
class DeviceListHandler: NSObject, NSTableViewDataSource, NSTableViewDelegate, BLEPeripheralListHandlerDelegate {
	
	var window: NSWindow!
	var tableView: NSTableView! {
		didSet {
			self.window = self.tableView.window
		}
	}
	private var reloadInProgress = false
	
	
	// NSTableViewDataSource
	func numberOfRows(in tableView: NSTableView) -> Int {
		
		return foundPeripherals.count
		
	}
	
	
	// NSTableViewDelegate
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		
		let cellsView = tableView.make(withIdentifier: tableColumn!.identifier, owner: self) as! BLEDeviceCell
		
		if tableColumn!.identifier == "BLEDevicesColumn" {																		// We only have 1 column, but check in case we add more later
			
			let device = foundPeripherals[row]
			
			let inUse = (device.detailsController != nil)																		// Details window openened
			
			if let name = device.peripheral.name {																				// Display the device name
				cellsView.textField!.stringValue = name
			} else if let name = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String {							// The CBAdvertisementDataLocalNameKey is a backup just in case peripheral.name doesn't exist. Likely not needed however
				cellsView.textField!.stringValue = name
			} else {
				cellsView.textField!.stringValue = "unknown"
			}
			
			if device.deviceDisabled && !inUse {																				// Gray out the name if this device is disabled & we are not already using it
				cellsView.textField!.textColor = NSColor.gray
			} else {
				cellsView.textField!.textColor = NSColor.black															// Set it back to its 'selectable' color
			}
			
			if device.RSSI == 127 {																								// 127 reserved for unavailable RSSI's
				cellsView.rangeDBm.stringValue = "n/a dBm"
				cellsView.rangeDBm.textColor = NSColor.gray
			} else {
				cellsView.rangeDBm.stringValue = "\(device.RSSI) dBm"															// Display the RSSI value in dBm
				cellsView.rangeDBm.textColor = NSColor(red: 0.1, green: 0.2, blue: 1, alpha: 1)
			}
			
			switch (device.RSSI.intValue) {																					// Display a signal strength indicator based on the RSSI
			case -84..<(-72): cellsView.imageView!.image = NSImage(named:"signalStrength-1")!
			case -72..<(-60): cellsView.imageView!.image = NSImage(named:"signalStrength-2")!
			case -60..<(-48): cellsView.imageView!.image = NSImage(named:"signalStrength-3")!
			case -48..<(127): cellsView.imageView!.image = NSImage(named:"signalStrength-4")!
			default: cellsView.imageView!.image = NSImage(named:"signalStrength-0")!											// < -84 dBm as well as 127
			}

			if inUse {																											// Has this device already been selected?
				cellsView.connectionState.stringValue = "In Use"
			} else {
				cellsView.connectionState.stringValue = (device.peripheral.state == .disconnected ? "Disconnected" : device.peripheral.state == .connected ? "Connected" : "Connecting")		// Display the current connection (to this Mac) state
			}
			
			if let txPowerLevel = device.advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {					// Display the transmitters output power if present. Usually from +4dBm down to -30dBm
				cellsView.txPowerLevel.stringValue = "Tx power: \(String(txPowerLevel.intValue)) dBm"
			} else {																											// This should never happen b/c CBAdvertisementDataTxPowerLevelKey is a mandatory advertising parameter. Put in to handle rogue BLE devices
				cellsView.txPowerLevel.isHidden = true
			}
			
			if let connectable = device.advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber {						// Display the connectable status if present. Not connectable means an advertise only device
				let isConnectable = connectable.intValue == 1
				cellsView.connectableState.stringValue = isConnectable ? "Device is connectable" : "Device is not connectable (advertise only)"
				if isConnectable == false { cellsView.textField!.textColor = NSColor.gray }								// Gray out the name to indicate it's not clickable
			} else {																											// This should never happen b/c CBAdvertisementDataIsConnectable is a mandatory advertising parameter. Put in to handle possible rogue BLE devices
				cellsView.connectableState.isHidden = true
			}
			
			if let serviceUUIDs = device.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {					// Display any and all service UUID's if present
				cellsView.serviceUUIDs.stringValue = "Services available: "
				for aUUID in serviceUUIDs {	cellsView.serviceUUIDs.stringValue += aUUID.characteristicName + "\n" }
			} else {
				cellsView.serviceUUIDs.isHidden = true
			}
			
				// Build the DIS information when we have it all
			if device.completeDISdata {																							// All Device Information Status information has been downloaded
				var str = ""
				
				var firstTime = true
				for aDisplayItem in device.displayGATT {
					if !firstTime { str += "\n" } else { firstTime = false }
					
					switch aDisplayItem {
						
					case let .service(aServ):
						str += "\(aServ.uuid.characteristicName)"
						
					case let .characteristic(aChar):
						
						let allowsReading = aChar.properties.contains(.read)
						
						if allowsReading {																						// Show the data if this Characteristic allowed reading
							
							let valueString: String
							if aChar.uuid == CBUUID.DFUVersion {										// Special case (oooohhhh nooooo) printing of the DFU Version. It's not a string. Print its raw data
								valueString = aChar.value!.description
							} else {																							// Otherwise print the UTF-8 string
								var byteString = "n/a"; if let value = aChar.value { byteString = value.description }
								valueString = byteString.hexToPrintableString()
							}
							
							str += "    \(aChar.uuid.characteristicName) \"\(valueString)\""
						} else {																								// Doesn't allow reading so print characteristic name only
							
							str += "    \(aChar.uuid.characteristicName)"
						}

					} // switch
				} // for
				
				if str != cellsView.deviceInfoStatus.string {																	// Update only if changed
					cellsView.deviceInfoStatus.string = str
				}
			} else {																											// Device Information Status has not completed download
				cellsView.deviceInfoStatus.string = "\n\n\t\t   Acquiring Device Information Status"
			}
			
		}
		
		if row == foundPeripherals.count-1 {																					// When done loading, signify so
			reloadInProgress = false
		}
		
		return cellsView
		
	}
	
	
	// NSTableViewDelegate
	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		
		if reloadInProgress { return false }																					// As a safeguard
		
		let device = foundPeripherals[row]
		
		var isConnectable = true
		if let connectable = device.advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber {							// Is this device an advertiser only or does it have Services and Characteristics? This should always fall in (read above)
			isConnectable = connectable.intValue == 1
		}
		
		let selectable = (isConnectable && device.deviceDisabled == false) || device.detailsController != nil					// Selectable device even if details window is already showing
		
		if selectable {
			if device.detailsController == nil {																				// Create a new device details window if non already exists
				let storyboard = NSStoryboard(name: "Main", bundle: nil)
				device.detailsController = storyboard.instantiateController(withIdentifier: "Details Window Controller") as? DetailsWindowController
				device.detailsController!.device = device																		// Connect the window to its Peripheral data. Must do before showing
				device.detailsController!.showWindow(self)
			} else {																											// Window has been created - make sure it is frontmost
				device.detailsController!.window?.makeKeyAndOrderFront(self)
			}
		}
		
		return selectable
		
	}
	
	
	// BLEPeripheralListHandlerDelegate
	func refreshPeripheralList() {
		
		delayRunOnMainQ(0) {																									// Must be reloaded from main Q otherwise weird UI issues ensue
			self.reloadInProgress = true
			self.tableView.reloadData()
		}
		
	}
	
} // DeviceListHandler





// MARK: -

// Added fields (beyond those NSTableCellView provides) for each of the cells displayed above
class BLEDeviceCell: NSTableCellView {
	
	@IBOutlet var rangeDBm: NSTextField!
	@IBOutlet var txPowerLevel: NSTextField!
	@IBOutlet var connectionState: NSTextField!
	@IBOutlet var connectableState: NSTextField!
	@IBOutlet var serviceUUIDs: NSTextField!
	@IBOutlet var deviceInfoStatus: NSTextView!
	
}

