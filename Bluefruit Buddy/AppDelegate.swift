//
//  Bluefruit Buddy
//
//  Created by Kevin Kachikian on 7/29/15.
//  Copyright © 2015 Adafruit Industries. All rights reserved.
//

import Cocoa



var verboseConsoleLog = false {
	didSet {
		if verboseConsoleLog {
			NSLog("Bluefruit Buddy debug log Enabled")
		} else {
			NSLog("Bluefruit Buddy debug log Disabled")
		}
	}
}



@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
	
	// Buddy > Console Debugging. Handle in app delegate because we want this no matter what window is up
	func consoleDebuggingMenu(sender: NSMenuItem) {
		
		switch sender.state {
		case NSOffState:
			sender.state = NSOnState
			verboseConsoleLog = true
			NSWorkspace.sharedWorkspace().openFile("/Applications/Utilities/Console.app")

		case NSOnState:
			sender.state = NSOffState
			verboseConsoleLog = false
			
		default: preconditionFailure("invalid menu state")
		}
		
	}
	
}

