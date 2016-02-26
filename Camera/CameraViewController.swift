//
//  CameraViewController.swift
//  Camera
//
//  Created by Matteo Caldari on 08/01/15.
//  Copyright (c) 2015 Matteo Caldari. All rights reserved.
//

import UIKit

protocol CameraPreviewViewController {
	var cameraController:CameraController? { get set }
}

class CameraViewController : UIViewController, CameraControllerDelegate, CameraSettingValueObserver {

	var cameraController:CameraController!

	@IBOutlet var videoPreviewView:UIView!
	@IBOutlet var controlsView:UIView!
	@IBOutlet var facesView:UIView!
	
	@IBOutlet var focusButton:UIButton!
	@IBOutlet var exposureButton:UIButton!
	@IBOutlet var whiteBalanceButton:UIButton!
	@IBOutlet var optionsButton:UIButton!

	@IBOutlet var adjustingFocusIndicator:UIView!
	@IBOutlet var adjustingExposureIndicator:UIView!
	@IBOutlet var adjustingWhiteBalanceIndicator:UIView!
	
	@IBOutlet var currentValuesLabel:UILabel!
	
	private var currentControlsViewController:UIViewController?
	private var previewViewController:CameraPreviewViewController?
	private var faceViews = [UIView]()

	
	override func viewDidLoad() {
		super.viewDidLoad()
		cameraController = CameraController(delegate: self)

		cameraController.registerObserver(self, property: CameraControlObservableSettingAdjustingFocus)
		cameraController.registerObserver(self, property: CameraControlObservableSettingAdjustingWhiteBalance)
		cameraController.registerObserver(self, property: CameraControlObservableSettingAdjustingExposure)
		cameraController.registerObserver(self, property: CameraControlObservableSettingLensPosition)
		cameraController.registerObserver(self, property: CameraControlObservableSettingISO)
		cameraController.registerObserver(self, property: CameraControlObservableSettingExposureDuration)
		cameraController.registerObserver(self, property: CameraControlObservableSettingExposureTargetOffset)
		cameraController.registerObserver(self, property: CameraControlObservableSettingWBGains)
		
		previewViewController?.cameraController = cameraController;
	}


	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)

		cameraController.startRunning()
	}
	
	
	override func prefersStatusBarHidden() -> Bool {
		return true
	}
	
	
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		
		if segue.identifier == "Embed Preview" {
			previewViewController = segue.destinationViewController as? CameraPreviewViewController
		}
		else if let controlsSegue = segue as? ControlsSegue {
			
			controlsSegue.currentViewController = currentControlsViewController
			controlsSegue.hostView = controlsView
			currentControlsViewController = controlsSegue.destinationViewController as? UIViewController
			if let currentControlsViewController = currentControlsViewController as? CameraControlsViewControllerProtocol {
				currentControlsViewController.cameraController = cameraController!
			}
		}
	}
	
	
	override func shouldPerformSegueWithIdentifier(identifier: String?, sender: AnyObject?) -> Bool {
		return true
	}
	
	
	// MARK: - Actions

	@IBAction func controlButtonPressed(sender: UIButton) {
		
		if sender.selected {
			sender.selected = false
			controlsView.hidden = true
		}
		else {
			var segueIdentifier:String?
			switch sender {
			case focusButton:
				segueIdentifier = "Embed Focus"
			case exposureButton:
				segueIdentifier = "Embed Exposure"
			case whiteBalanceButton:
				segueIdentifier = "Embed White Balance"
			case optionsButton:
				segueIdentifier = "Embed Options"
			default:break
			}
			
			for button in [focusButton, exposureButton, whiteBalanceButton, optionsButton] {
				button.selected = sender == button
			}
			
			controlsView.hidden = false
			self.performSegueWithIdentifier(segueIdentifier!, sender: self)
		}
	}
	
	
	@IBAction func handleShutterButton(sender: UIButton) {
		cameraController.captureStillImage { (image, metadata) -> Void in
			self.view.layer.contents = image
			UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
		}
	}
	
	
	@IBAction func focusOnPointOfInterest(sender: UITapGestureRecognizer) {
		if sender.state == UIGestureRecognizerState.Ended {
			var point = sender.locationInView(sender.view)
			cameraController.lockFocusAtPointOfInterest(point)
		}
	}
	
	
	// MARK: Camera values observation
	
	func cameraSetting(setting: String, valueChanged value: AnyObject) {
		switch setting {
		case CameraControlObservableSettingAdjustingFocus:
			if let adjusting = value as? Bool {
				adjustingFocusIndicator.hidden = !adjusting
			}
		case CameraControlObservableSettingAdjustingWhiteBalance:
			if let adjusting = value as? Bool {
				adjustingWhiteBalanceIndicator.hidden = !adjusting
			}
		case CameraControlObservableSettingAdjustingExposure:
			if let adjusting = value as? Bool {
				adjustingExposureIndicator.hidden = !adjusting
			}
		case CameraControlObservableSettingLensPosition,
			CameraControlObservableSettingExposureTargetOffset,
			CameraControlObservableSettingExposureDuration,
			CameraControlObservableSettingISO,
			CameraControlObservableSettingWBGains:

			displayCurrentValues()
			
		default: break
		}
	}
	
	
	// MARK: - CameraControllerDelegate
	
	
	func cameraController(cameraController: CameraController, didDetectFaces faces: Array<(id: Int, frame: CGRect)>) {

		prepareFaceViews(faces.count - faceViews.count)

		for (idx, face) in faces.enumerate() {
			faceViews[idx].frame = face.frame
		}
	}

}


private extension CameraViewController {
	
	func prepareFaceViews(diff:Int) {
		if diff > 0 {
			for _ in 0..<diff {
				var faceView = UIView(frame: CGRectZero)
				faceView.backgroundColor = UIColor.clearColor()
				faceView.layer.borderColor = UIColor.yellowColor().CGColor
				faceView.layer.borderWidth = 3.0
				facesView.addSubview(faceView)
				
				faceViews.append(faceView)
			}
		}
		else {
			for _ in 0..<abs(diff) {
				faceViews[0].removeFromSuperview()
				faceViews.removeAtIndex(0)
			}
		}
	}

	
	func displayCurrentValues() {
		var currentValuesTextComponents = [String]()
		
		if let lensPosition = cameraController.currentLensPosition() {
			currentValuesTextComponents.append(String(format: "F: %.2f", lensPosition))
		}
		
		if let offset = cameraController.currentExposureTargetOffset() {
			currentValuesTextComponents.append(String(format: "±: %.2f", offset))
		}

		if let speed = cameraController.currentExposureDuration() {
			currentValuesTextComponents.append(String(format: "S: %.4f", speed))
		}

		if let iso = cameraController.currentISO() {
			currentValuesTextComponents.append(String(format: "ISO: %.0f", iso))
		}
		
		if let temp = cameraController.currentTemperature() {
			currentValuesTextComponents.append(String(format: "TEMP: %.0f", temp))
		}

		if let tint = cameraController.currentTint() {
			currentValuesTextComponents.append(String(format: "TINT: %.0f", tint))
		}

        currentValuesLabel.text = currentValuesTextComponents.joinWithSeparator(" - ")
	}
	
}
