//
//  Bluefruit Buddy
//
//  Created by Kevin Kachikian on 8/13/15.
//  Copyright © 2015 Adafruit. All rights reserved.
//
//	One of these per selected Peripherial device (selected from the device list)
//

import Cocoa
import CoreBluetooth



class DetailsWindowController: NSWindowController, NSWindowDelegate {
	
	var device: Peripheral!	{																									// This windows Peripheral
		didSet {
			self.window!.title = device.peripheral.name!
			(window!.contentViewController as! DetailsViewController).device = device											// The DetailsWindowController and the DetailsViewController are inextricably linked. Tell DetailsViewController where its data resides
		}
	}
	
	
	override func windowDidLoad() {
		
		self.windowFrameAutosaveName = "BluefruitBuddy \(NSApplication.sharedApplication().windows.count)"						// Remember window frames
		
	}
	
	
	// NSWindowDelegate
	func windowWillClose(notification: NSNotification) {
		
		device.detailsController = nil																							// Disconnect us from the peripheral
		
	}
	
}




class DetailsViewController: NSViewController, CBCentralManagerDelegate, CBPeripheralDelegate, NSTextViewDelegate {
	
	var device: Peripheral!																										// DetailsWindowController sets
	
	@IBOutlet var noServicesText: NSTextField!
	
	@IBOutlet var UARTTextArea: NSBox!																							// Container view holding all things related to UART Tx/Rx
	@IBOutlet var UARTTextView: NSTextView!
	
	@IBOutlet var sendBtn: NSButton!
	@IBOutlet var returnSendsTextBtn: NSButton!
	@IBOutlet var alsoSendReturnBtn: NSButton!
	@IBOutlet var echoOutgoingTextBtn: NSButton!
	@IBOutlet var receiveTextBtn: NSButton!
	@IBOutlet var clearBtn: NSButton!
	
	@IBOutlet var firmwareUpdateButton: NSButton!
	
	private var manager: CBCentralManager!																						// Two-phase initialize manager (since it requires self - define as var)
	private var UARTPeripheral: CBPeripheral?
	private var UARTRxCharacteristic: CBCharacteristic? {
		didSet {
			if UARTRxCharacteristic != nil {
				UARTPeripheral?.setNotifyValue(receiveTextBtn.state == NSOnState, forCharacteristic: UARTRxCharacteristic!)		// Tell peripheral to notify us (or not). Chains to didUpdateValueForCharacteristic if Rx is on
			}
			receiveTextBtn.enabled = UARTRxCharacteristic != nil																// Don't enable Receive Text button until we can communicate with the Rx Characteristic
		}
	}
	private var UARTTxCharacteristic: CBCharacteristic? {
		didSet {																												// Enable send options only after we can communicate with the Tx Characteristic
			UARTTextView.editable = UARTTxCharacteristic != nil
			returnSendsTextBtn.enabled = UARTTxCharacteristic != nil
			alsoSendReturnBtn.enabled = UARTTxCharacteristic != nil
			sendBtn.enabled = UARTTxCharacteristic != nil
			echoOutgoingTextBtn.enabled = UARTTxCharacteristic != nil
			clearBtn.enabled = UARTTxCharacteristic != nil
		}
	}
	
	private var sendInsertionPosition = 0
	
	
	// MARK: -
	
	override func viewWillAppear() {
		
		super.viewWillAppear()
		
		UARTTextArea.hidden = !device.supportsService(CBUUID.UUIDs.UARTService.rawValue)										// Check for a (Nordic) UART Service & show the UART text area if it exists
		firmwareUpdateButton.hidden = !device.supportsService(CBUUID.UUIDs.DFUService.rawValue)									// Check for Firmware Update Service & show firmware update button
		
		noServicesText.hidden = !(UARTTextArea.hidden && firmwareUpdateButton.hidden)											// If we don't recognize any services, show "Supported Services Not Found"
		
		if !UARTTextArea.hidden {																								// This peripheral supports UART comms, start-er up
			manager = CBCentralManager(delegate: self, queue: cbManagerQ)														// Start up a BLE Manager. Fires off an initial call to centralManagerDidUpdateState. Must rescan to discover the selected peripheral
		}
		
	}
	
	
	deinit {
		
		manager = nil																											// Disconnect from the peripheral
		
	}
	
	
	@IBAction func returnSendsText(sender: NSButton) {
		
		alsoSendReturnBtn.enabled = returnSendsTextBtn.state == NSOnState
		
	}
	
	
	@IBAction func echoTypedText(sender: NSButton) {
		
		returnSendsTextBtn.enabled = echoOutgoingTextBtn.state == NSOnState
		alsoSendReturnBtn.enabled = echoOutgoingTextBtn.state == NSOnState
		sendBtn.enabled = echoOutgoingTextBtn.state == NSOnState
		
	}
	
	
	@IBAction func receiveText(sender: NSButton) {
		
		if UARTRxCharacteristic != nil {
			UARTPeripheral?.setNotifyValue(receiveTextBtn.state == NSOnState, forCharacteristic: UARTRxCharacteristic!)			// Tell peripheral about changes to check box. Chains to didUpdateValueForCharacteristic if Rx is on
		}
		
	}
	
	
	@IBAction func send(sender: AnyObject) {
		
		let fromPosition = sendInsertionPosition
		sendInsertionPosition = UARTTextView.string!.characters.count
		sendString(UARTTextView.string![fromPosition..<sendInsertionPosition])
		
	}
	
	
	@IBAction func clear(sender: AnyObject) {
		
		UARTTextView.string! = ""
		sendInsertionPosition = 0
		
	}
	
	
	@IBAction func firmware(sender: AnyObject) {
	}
	
	
	// MARK: -
	
	// File > Export UART Text
	@IBAction func exportUARTText(sender: AnyObject) {

		let savePanel = NSSavePanel()
		savePanel.nameFieldLabel = "Export"
		savePanel.canCreateDirectories = true
		savePanel.showsTagField = false
		savePanel.allowedFileTypes = ["txt"]
		savePanel.nameFieldStringValue = device.peripheral.name!
		
		savePanel.beginSheetModalForWindow(self.view.window!) { (result: Int) -> Void in										// Export as a plain text .txt file
			if result == NSFileHandlingPanelOKButton {
				do {
					
					let range = NSMakeRange(0, self.UARTTextView.textStorage!.length)
					let attribs = [NSDocumentTypeDocumentAttribute : NSPlainTextDocumentType]
					let fileWrapper = try self.UARTTextView.textStorage!.fileWrapperFromRange(range, documentAttributes: attribs)

					do {
						try fileWrapper.writeToURL(savePanel.URL!, options: .Atomic, originalContentsURL: nil)
					} catch let error as NSError {
						savePanel.orderOut(nil)
						self.view.window!.alert("File not saved", infoText: error.localizedDescription)
					}
					
				} catch let error as NSError {
					savePanel.orderOut(nil)
					self.view.window!.alert("File not saved", infoText: error.localizedDescription)
				} catch {
				}
			}
		}
		
	}

	
	// MARK: -
	
	// CBCentralManagerDelegate
	func centralManagerDidUpdateState(manager: CBCentralManager) {
	
		if manager.state == .PoweredOn {
			let desiredServices = [CBUUID(string: CBUUID.UUIDs.UARTService.rawValue)]
			// The CBCentralManagerScanOptionAllowDuplicatesKey parameter doesn't seem to have any effect (on 10.10.5) but set here as needed anyway
			manager.scanForPeripheralsWithServices(desiredServices, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])	// Find only one occurance when advertised. Chains to didDiscoverPeripheral
		} else {
			self.view.window!.reportBLEStatus(manager)																			// Report an error
		}
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
		
		if verboseConsoleLog { NSLog("didDiscoverPeripheral: peripheral=\(peripheral), RSSI=\(RSSI) dBm, advertisementData=\(advertisementData)") }
		
		let selectedPeripheral = foundPeripherals.filter() { $0.peripheral.identifier == device.peripheral.identifier }
		if selectedPeripheral.count != 0 {																						// Make sure this is the peripheral we tapped on. Should always be true

			manager.stopScan()

			UARTPeripheral = peripheral
			UARTTxCharacteristic = nil																							// Clear them both out
			UARTRxCharacteristic = nil

			peripheral.delegate = self
			self.manager.connectPeripheral(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey : true])		// Connect to the found Peripheral. Chains to didConnectPeripheral or didFailToConnectPeripheral

		}
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
		
		if verboseConsoleLog { NSLog("didConnectPeripheral: peripheral=\(peripheral)") }
		
		peripheral.discoverServices([CBUUID(string: CBUUID.UUIDs.UARTService.rawValue)])										// Chains to didDiscoverServices
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
		
		if verboseConsoleLog { NSLog("didFailToConnectPeripheral: peripheral=\(peripheral), ERROR=\(error!)") }
		
		self.view.window!.alert("Failed to connect", infoText: error!.localizedDescription)

	}
	
	
	
	// CBCentralManagerDelegate
	func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
		
		if verboseConsoleLog { NSLog("didDisconnectPeripheral: peripheral=\(peripheral), ERROR=\(error)") }
		
		if error != nil {
			if error!.code == 6 {
				self.view.window!.alert(peripheral.name! + " disconnected", infoText: "")
			} else {
				self.view.window!.alert("Peripheral disconnected", infoText: error!.localizedDescription)
			}
		}
		
		Peripheral.findPeripheral(peripheral.identifier).deviceDisabled = true													// Record a disconnected peripheral
		UARTTxCharacteristic = nil
		UARTRxCharacteristic = nil
		
	}
	
	
	// CBPeripheralDelegate
	func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
		
		if verboseConsoleLog { NSLog("didDiscoverServices: peripheral=\(peripheral)"); if error != nil { NSLog("ERROR=\(error!)") } }
		
		if error == nil {
			
			for aService in peripheral.services! {																				// Should be only 1 service - the one we asked for above
				let desiredCharacteristics = [CBUUID(string: CBUUID.UUIDs.UARTTxCharacteristic.rawValue), CBUUID(string: CBUUID.UUIDs.UARTRxCharacteristic.rawValue)]
				peripheral.discoverCharacteristics(desiredCharacteristics, forService: aService)								// Chains to didDiscoverCharacteristicsForService
			}
			
		} else {
			self.view.window!.alert("Failed to discover", infoText: error!.localizedDescription)
		}
		
	}
	
	
	// CBPeripheralDelegate
	func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
		
		if verboseConsoleLog { NSLog("didDiscoverCharacteristicsForService: peripheral=\(peripheral), service=\(service)"); if error != nil { NSLog("ERROR=\(error!)") } }
		
		for aCharacteristic in service.characteristics! {
			if aCharacteristic.UUID.UUIDString == CBUUID.UUIDs.UARTRxCharacteristic.rawValue {
				UARTRxCharacteristic = aCharacteristic
			} else if aCharacteristic.UUID.UUIDString == CBUUID.UUIDs.UARTTxCharacteristic.rawValue {
				UARTTxCharacteristic = aCharacteristic
			}
		}
		
	}
	
	
	// CBPeripheralDelegate
	func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {	// Incoming text from device
		
		if verboseConsoleLog {
			var byteString = "n/a"																									// Default in case of error
			if let value = characteristic.value { byteString = value.description }
			NSLog("didUpdateValueForCharacteristic: peripheral=\(peripheral)")
			NSLog("service=\(characteristic.service), characteristic=\(characteristic) \(characteristic.UUID.characteristicNameForUUID()), bytes=\(byteString) \"\(byteString.hexToPrintableString())\"")
			if error != nil { NSLog("ERROR=\(error!)") }
		}
		
		if characteristic.UUID.UUIDString == CBUUID.UUIDs.UARTRxCharacteristic.rawValue {											// Check to make sure this is our receive Characteristic. Should always pass
			if let value = characteristic.value {																					// And check to make sure we have valid data. Should also always pass
				
				if verboseConsoleLog { let crText = value.description.stringByReplacingOccurrencesOfString("\n", withString: "•"); NSLog("receiving \"\(crText)\"") }
				
					// Insert received text & color it to indicate received text
				if let receivedStr = NSString(data: value, encoding: NSString.defaultCStringEncoding()) as? String {
					
					let remoteGreenString = NSAttributedString(string: receivedStr, attributes: [NSForegroundColorAttributeName : NSColor(red: 0, green: 0.7, blue: 0, alpha: 1)])
					self.UARTTextView.textStorage!.appendAttributedString(remoteGreenString)
					
					sendInsertionPosition = UARTTextView.string!.characters.count
					
					delayRunOnMainQ(0) {
						self.UARTTextView.scrollRangeToVisible(NSMakeRange(self.sendInsertionPosition, 0))							// Must be run on main Q. We are called from another thread
					}

				}
			
			}
		}
		
	}
	
	
	func peripheral(peripheral: CBPeripheral, didWriteValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
		
		if verboseConsoleLog { NSLog("didWriteValueForCharacteristic: peripheral=\(peripheral)"); if error != nil { NSLog("ERROR=\(error!)") } }
		
		if error != nil {
			self.view.window!.alert("Failed to write value", infoText: error!.localizedDescription)
		}
		
	}
	
	
	// MARK:-
	
	// NSTextViewDelegate
	func textView(textView: NSTextView, shouldChangeTextInRange affectedCharRange: NSRange, replacementString: String?) -> Bool {	// Outgoing text to device
		
		if echoOutgoingTextBtn.state == NSOffState {																				// When echo is on, send the characters 1 at a time & don't display
			sendString(replacementString!)
			return false
		}
		
		if affectedCharRange.location < sendInsertionPosition {																		// Once text has been sent (or received), don't allow editing it in any way
			return false
		}
		
		if replacementString! == "\n" && returnSendsTextBtn.state == NSOnState {													// RETURN pressed when we allow returns to send
			let fromPosition = sendInsertionPosition
			sendInsertionPosition = textView.string!.characters.count+1
			var sendText = textView.string![fromPosition..<sendInsertionPosition-1]
			if alsoSendReturnBtn.state == NSOnState { sendText += "\n" }
			sendString(sendText)
		}
		
		if replacementString!.characters.count != 0 {																				// Handle inserting local text so we can ensure it's blue
			let localBlueString = NSAttributedString(string: replacementString!, attributes: [NSForegroundColorAttributeName : NSColor.blueColor()])
			UARTTextView.textStorage!.appendAttributedString(localBlueString)
			UARTTextView.scrollRangeToVisible(NSMakeRange(sendInsertionPosition, 0))
			return false
		}
		
		return true																													// Let NSTextView handle things like delete
		
	}
	
	
	// MARK:-
	
	private func sendString(strToSend: String) {
		
		if strToSend.characters.count == 0 { return }
		
		if verboseConsoleLog { let crText = strToSend.stringByReplacingOccurrencesOfString("\n", withString: "•"); NSLog("sending \"\(crText)\"") }
		
		var writeType = CBCharacteristicWriteType.WithoutResponse																	// Default to 'peripheral doesnt support response'
		if (UARTTxCharacteristic!.properties.rawValue & CBCharacteristicProperties.Write.rawValue) != 0 {							// If it responds, we'd rather have that
			writeType = CBCharacteristicWriteType.WithResponse
		}																															// And if it handles neither (not likely), we'll display an error message upon sending
		
		var start = 0																												// Send the data in max blocks of 20 chars as per the GATT Characteristic size limit
		repeat {
			var end = start + 19
			if end >= strToSend.characters.count { end = strToSend.characters.count-1 }
			let str = strToSend[start...end] as NSString
			let data = NSData(bytes: str.UTF8String, length: str.length)
			UARTPeripheral?.writeValue(data, forCharacteristic: UARTTxCharacteristic!, type: writeType)
			start += 20
		} while start < strToSend.characters.count
		
	}
	
}

