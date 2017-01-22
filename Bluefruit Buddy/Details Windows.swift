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
		
		self.windowFrameAutosaveName = "BluefruitBuddy \(NSApplication.shared().windows.count)"						// Remember window frames
		
	}
	
	
	// NSWindowDelegate
	func windowWillClose(_ notification: Notification) {
		
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
				UARTPeripheral?.setNotifyValue(receiveTextBtn.state == NSOnState, for: UARTRxCharacteristic!)		// Tell peripheral to notify us (or not). Chains to didUpdateValueForCharacteristic if Rx is on
			}
			receiveTextBtn.isEnabled = UARTRxCharacteristic != nil																// Don't enable Receive Text button until we can communicate with the Rx Characteristic
		}
	}
	private var UARTTxCharacteristic: CBCharacteristic? {
		didSet {																												// Enable send options only after we can communicate with the Tx Characteristic
			UARTTextView.isEditable = UARTTxCharacteristic != nil
			returnSendsTextBtn.isEnabled = UARTTxCharacteristic != nil
			alsoSendReturnBtn.isEnabled = UARTTxCharacteristic != nil
			sendBtn.isEnabled = UARTTxCharacteristic != nil
			echoOutgoingTextBtn.isEnabled = UARTTxCharacteristic != nil
			clearBtn.isEnabled = UARTTxCharacteristic != nil
		}
	}
	
	private var sendInsertionPosition = 0
	
	
	// MARK: -
	
	override func viewWillAppear() {
		
		super.viewWillAppear()
		
                UARTTextArea.isHidden = !device.supports(service: CBUUID.UARTService)										// Check for a (Nordic) UART Service & show the UART text area if it exists
                firmwareUpdateButton.isHidden = !device.supports(service: CBUUID.DFUService)									// Check for Firmware Update Service & show firmware update button
		
		noServicesText.isHidden = !(UARTTextArea.isHidden && firmwareUpdateButton.isHidden)											// If we don't recognize any services, show "Supported Services Not Found"
		
		if !UARTTextArea.isHidden {																								// This peripheral supports UART comms, start-er up
			manager = CBCentralManager(delegate: self, queue: cbManagerQ)														// Start up a BLE Manager. Fires off an initial call to centralManagerDidUpdateState. Must rescan to discover the selected peripheral
		}
		
	}
	
	
	deinit {
		
		manager = nil																											// Disconnect from the peripheral
		
	}
	
	
	@IBAction func returnSendsText(_ sender: NSButton) {
		
		alsoSendReturnBtn.isEnabled = returnSendsTextBtn.state == NSOnState
		
	}
	
	
	@IBAction func echoTypedText(_ sender: NSButton) {
		
		returnSendsTextBtn.isEnabled = echoOutgoingTextBtn.state == NSOnState
		alsoSendReturnBtn.isEnabled = echoOutgoingTextBtn.state == NSOnState
		sendBtn.isEnabled = echoOutgoingTextBtn.state == NSOnState
		
	}
	
	
	@IBAction func receiveText(_ sender: NSButton) {
		
		if UARTRxCharacteristic != nil {
			UARTPeripheral?.setNotifyValue(receiveTextBtn.state == NSOnState, for: UARTRxCharacteristic!)			// Tell peripheral about changes to check box. Chains to didUpdateValueForCharacteristic if Rx is on
		}
		
	}
	
	
	@IBAction func send(_ sender: AnyObject) {
		
		let fromPosition = sendInsertionPosition
		sendInsertionPosition = UARTTextView.string!.characters.count
                send(string: UARTTextView.string![fromPosition..<sendInsertionPosition])
		
	}
	
	
	@IBAction func clear(_ sender: AnyObject) {
		
		UARTTextView.string! = ""
		sendInsertionPosition = 0
		
	}
	
	
	@IBAction func firmware(_ sender: AnyObject) {
	}
	
	
	// MARK: -
	
	// File > Export UART Text
	@IBAction func exportUARTText(_ sender: AnyObject) {

		let savePanel = NSSavePanel()
		savePanel.nameFieldLabel = "Export"
		savePanel.canCreateDirectories = true
		savePanel.showsTagField = false
		savePanel.allowedFileTypes = ["txt"]
		savePanel.nameFieldStringValue = device.peripheral.name!
		
		savePanel.beginSheetModal(for: self.view.window!) { (result: Int) -> Void in										// Export as a plain text .txt file
			if result == NSFileHandlingPanelOKButton {
				do {
					
					let range = NSMakeRange(0, self.UARTTextView.textStorage!.length)
					let attribs = [NSDocumentTypeDocumentAttribute : NSPlainTextDocumentType]
					let fileWrapper = try self.UARTTextView.textStorage!.fileWrapper(from: range, documentAttributes: attribs)

					do {
						try fileWrapper.write(to: savePanel.url!, options: .atomic, originalContentsURL: nil)
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
	func centralManagerDidUpdateState(_ manager: CBCentralManager) {
	
		if manager.state == .poweredOn {
			let desiredServices = [CBUUID.UARTService]
			// The CBCentralManagerScanOptionAllowDuplicatesKey parameter doesn't seem to have any effect (on 10.10.5) but set here as needed anyway
			manager.scanForPeripherals(withServices: desiredServices, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])	// Find only one occurance when advertised. Chains to didDiscoverPeripheral
		} else {
			self.view.window!.reportBLEStatus(manager)																			// Report an error
		}
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
		
		if verboseConsoleLog { NSLog("didDiscoverPeripheral: peripheral=\(peripheral), RSSI=\(RSSI) dBm, advertisementData=\(advertisementData)") }
		
		let selectedPeripheral = foundPeripherals.filter() { $0.peripheral.identifier == device.peripheral.identifier }
		if selectedPeripheral.count != 0 {																						// Make sure this is the peripheral we tapped on. Should always be true

			manager.stopScan()

			UARTPeripheral = peripheral
			UARTTxCharacteristic = nil																							// Clear them both out
			UARTRxCharacteristic = nil

			peripheral.delegate = self
			self.manager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey : true])		// Connect to the found Peripheral. Chains to didConnectPeripheral or didFailToConnectPeripheral

		}
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		
		if verboseConsoleLog { NSLog("didConnectPeripheral: peripheral=\(peripheral)") }
		
		peripheral.discoverServices([CBUUID.UARTService])										// Chains to didDiscoverServices
		
	}
	
	
	// CBCentralManagerDelegate
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		
		if verboseConsoleLog { NSLog("didFailToConnectPeripheral: peripheral=\(peripheral), ERROR=\(error!)") }
		
		self.view.window!.alert("Failed to connect", infoText: error!.localizedDescription)

	}
	
	
	
	// CBCentralManagerDelegate
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		
		if verboseConsoleLog {
                        NSLog("didDisconnectPeripheral: peripheral=\(peripheral), ERROR=\(error)")
                }

                if let error = error {
                        if let cbError = error as? CBError, cbError.code == .connectionTimeout {
                                self.view.window!.alert(peripheral.name! + " disconnected", infoText: "")
                        } else {
                                self.view.window!.alert("Peripheral disconnected", infoText: error.localizedDescription)
			}
		}
		
		Peripheral.findPeripheral(peripheral.identifier).deviceDisabled = true													// Record a disconnected peripheral
		UARTTxCharacteristic = nil
		UARTRxCharacteristic = nil
		
	}
	
	
	// CBPeripheralDelegate
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		
		if verboseConsoleLog { NSLog("didDiscoverServices: peripheral=\(peripheral)"); if error != nil { NSLog("ERROR=\(error!)") } }
		
		if error == nil {
			
			for aService in peripheral.services! {																				// Should be only 1 service - the one we asked for above
				let desiredCharacteristics = [CBUUID.UARTTxCharacteristic, CBUUID.UARTRxCharacteristic]
				peripheral.discoverCharacteristics(desiredCharacteristics, for: aService)								// Chains to didDiscoverCharacteristicsForService
			}
			
		} else {
			self.view.window!.alert("Failed to discover", infoText: error!.localizedDescription)
		}
		
	}
	
	
	// CBPeripheralDelegate
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		
		if verboseConsoleLog { NSLog("didDiscoverCharacteristicsForService: peripheral=\(peripheral), service=\(service)"); if error != nil { NSLog("ERROR=\(error!)") } }
		
		for aCharacteristic in service.characteristics! {
			if aCharacteristic.uuid == CBUUID.UARTRxCharacteristic {
				UARTRxCharacteristic = aCharacteristic
			} else if aCharacteristic.uuid == CBUUID.UARTTxCharacteristic {
				UARTTxCharacteristic = aCharacteristic
			}
		}
		
	}
	
	
	// CBPeripheralDelegate
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {	// Incoming text from device
		
		if verboseConsoleLog {
			var byteString = "n/a"																									// Default in case of error
			if let value = characteristic.value { byteString = value.description }
			NSLog("didUpdateValueForCharacteristic: peripheral=\(peripheral)")
			NSLog("service=\(characteristic.service), characteristic=\(characteristic) \(characteristic.uuid.characteristicName), bytes=\(byteString) \"\(byteString.hexToPrintableString())\"")
			if error != nil { NSLog("ERROR=\(error!)") }
		}
		
		if characteristic.uuid == CBUUID.UARTRxCharacteristic {											// Check to make sure this is our receive Characteristic. Should always pass
			if let value = characteristic.value {																					// And check to make sure we have valid data. Should also always pass
				
				if verboseConsoleLog { let crText = value.description.replacingOccurrences(of: "\n", with: "•"); NSLog("receiving \"\(crText)\"") }
				
					// Insert received text & color it to indicate received text
				if let receivedStr = NSString(data: value, encoding: NSString.defaultCStringEncoding) as? String {
					
					let remoteGreenString = NSAttributedString(string: receivedStr, attributes: [NSForegroundColorAttributeName : NSColor(red: 0, green: 0.7, blue: 0, alpha: 1)])
					self.UARTTextView.textStorage!.append(remoteGreenString)
					
					sendInsertionPosition = UARTTextView.string!.characters.count
					
					delayRunOnMainQ(0) {
						self.UARTTextView.scrollRangeToVisible(NSMakeRange(self.sendInsertionPosition, 0))							// Must be run on main Q. We are called from another thread
					}

				}
			
			}
		}
		
	}
	
	
	func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		
		if verboseConsoleLog { NSLog("didWriteValueForCharacteristic: peripheral=\(peripheral)"); if error != nil { NSLog("ERROR=\(error!)") } }
		
		if error != nil {
			self.view.window!.alert("Failed to write value", infoText: error!.localizedDescription)
		}
		
	}
	
	
	// MARK:-
	
	// NSTextViewDelegate
	func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {	// Outgoing text to device
		
		if echoOutgoingTextBtn.state == NSOffState {																				// When echo is on, send the characters 1 at a time & don't display
			send(string: replacementString!)
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
			send(string: sendText)
		}
		
		if replacementString!.characters.count != 0 {																				// Handle inserting local text so we can ensure it's blue
			let localBlueString = NSAttributedString(string: replacementString!, attributes: [NSForegroundColorAttributeName : NSColor.blue])
			UARTTextView.textStorage!.append(localBlueString)
			UARTTextView.scrollRangeToVisible(NSMakeRange(sendInsertionPosition, 0))
			return false
		}
		
		return true																													// Let NSTextView handle things like delete
		
	}
	
	
	// MARK:-
	
	private func send(string: String) {
                guard !string.isEmpty else {
                        return
                }
		
		if verboseConsoleLog {
                        let crText = string.replacingOccurrences(of: "\n", with: "•");
                        NSLog("sending \"\(crText)\"")
                }
		
                // Default to "peripheral doesn't support response"
                var writeType = CBCharacteristicWriteType.withoutResponse
                
                // If it responds, we'd rather have that
                // And if it handles neither (not likely), we'll display an error message upon sending
                // TJW: Was this code intending to check for .withResponse?
		if UARTTxCharacteristic!.properties.contains(.write) {
			writeType = .withResponse
                }
                
                // Send the data in max blocks of 20 chars as per the GATT Characteristic size limit
                // TJW: My change here sends 20 *bytes* at a time instead of 20 characters. It is unclear, since there is no reference to documentation on the limit, if we really could send 20 characters (possibly many, many more bytes for non-ASCII characters). Of course, this means the receiver needs to recombine and validate UTF-8 sequences if they really want non-ASCII (probably should be doing that anyway).
                let utf8Data = string.data(using: .utf8)!
                let utf8Length = utf8Data.count

                var sendIndex = 0;
                while sendIndex < utf8Length {
                        let sendLength = min(20, utf8Length - sendIndex)
                        UARTPeripheral?.writeValue(utf8Data.subdata(in: sendIndex..<(sendIndex+sendLength)), for: UARTTxCharacteristic!, type: writeType)
                        sendIndex += 20
                }
		
	}
	
}

