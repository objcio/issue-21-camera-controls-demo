//
//  ControlsSegue.swift
//  Camera
//
//  Created by Matteo Caldari on 05/02/15.
//  Copyright (c) 2015 Matteo Caldari. All rights reserved.
//

import UIKit

class ControlsSegue: UIStoryboardSegue {

	var hostView:UIView?
	var currentViewController:UIViewController?
	
	override init(identifier: String!, source: UIViewController, destination: UIViewController) {
		super.init(identifier: identifier, source: source, destination: destination)
	}
	
	
	override func perform() {
		if let destinationViewController = destinationViewController as? UIViewController {
			
			if let currentControlsViewController = currentViewController {
				currentControlsViewController.willMoveToParentViewController(nil)
				currentControlsViewController.removeFromParentViewController()
				currentControlsViewController.view.removeFromSuperview()
			}

			sourceViewController.addChildViewController(destinationViewController as UIViewController)
			hostView!.addSubview(destinationViewController.view)
			destinationViewController.view.frame = hostView!.bounds
			destinationViewController.didMoveToParentViewController(sourceViewController as? UIViewController)
		}
	}
}
