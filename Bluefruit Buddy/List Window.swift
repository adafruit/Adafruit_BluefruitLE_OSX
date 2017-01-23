//
//  Bluefruit Buddy
//
//  Created by Kevin Kachikian on 7/29/15.
//  Copyright © 2015 Adafruit Industries. All rights reserved.
//
//	Only one of these app wide
//

import Cocoa



class ListViewController: NSViewController {
	
	@IBOutlet private var deviceListTableView: NSTableView!
	@IBOutlet private var progressIndicator: NSProgressIndicator!
	@IBOutlet private var scanningMsg: NSTextField!
	@IBOutlet private var deviceListHandler: DeviceListHandler!				// A connection (as set up in IB) to our DeviceListHandler object
	
	var bleComms: ServiceDiscovery!
	
	
	override func viewWillAppear() {
		
		super.viewWillAppear()
		
		bleComms = ServiceDiscovery(delegate: deviceListHandler)			// Set up our communications object and set its delegate to the device list handler
		
		deviceListHandler.tableView = deviceListTableView					// Tell the device list handler who its table view is. Also set our window so can't be called from viewDidLoad
		
		scanningStatus(true)
		
	}
	
	
	@IBAction func clearButton(_ sender: AnyObject) {
		
		bleComms.discoveryReset()
		
	}
	
	
	func scanningStatus(_ scanning: Bool) {
		
		if scanning {
			progressIndicator.startAnimation(self)
		} else {
			progressIndicator.stopAnimation(self)
		}
		
		scanningMsg.isHidden = !scanning
		
	}
	
}
