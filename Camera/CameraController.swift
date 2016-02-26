//
//  CameraController.swift
//  Camera
//
//  Created by Matteo Caldari on 20/01/15.
//  Copyright (c) 2015 Matteo Caldari. All rights reserved.
//

import AVFoundation
import UIKit
import GLKit

let CameraControllerDidStartSession = "CameraControllerDidStartSession"
let CameraControllerDidStopSession = "CameraControllerDidStopSession"

let CameraControlObservableSettingLensPosition = "CameraControlObservableSettingLensPosition"
let CameraControlObservableSettingExposureTargetOffset = "CameraControlObservableSettingExposureTargetOffset"
let CameraControlObservableSettingExposureDuration = "CameraControlObservableSettingExposureDuration"
let CameraControlObservableSettingISO = "CameraControlObservableSettingISO"
let CameraControlObservableSettingWBGains = "CameraControlObservableSettingWBGains"
let CameraControlObservableSettingAdjustingFocus = "CameraControlObservableSettingAdjustingFocus"
let CameraControlObservableSettingAdjustingExposure = "CameraControlObservableSettingAdjustingExposure"
let CameraControlObservableSettingAdjustingWhiteBalance = "CameraControlObservableSettingAdjustingWhiteBalance"

protocol CameraControllerDelegate : class {
	func cameraController(cameraController:CameraController, didDetectFaces faces:Array<(id:Int,frame:CGRect)>)
}


enum CameraControllePreviewType {
	case PreviewLayer
	case Manual
}


@objc protocol CameraSettingValueObserver {
	func cameraSetting(setting:String, valueChanged value:AnyObject)
}


extension AVCaptureWhiteBalanceGains {
	mutating func clampGainsToRange(minVal:Float, maxVal:Float) {
		blueGain = max(min(blueGain, maxVal), minVal)
		redGain = max(min(redGain, maxVal), minVal)
		greenGain = max(min(greenGain, maxVal), minVal)
	}
}


class WhiteBalanceValues {
	var temperature:Float
	var tint:Float
	
	init(temperature:Float, tint:Float) {
		self.temperature = temperature
		self.tint = tint
	}
	
	convenience init(temperatureAndTintValues:AVCaptureWhiteBalanceTemperatureAndTintValues) {
		self.init(temperature: temperatureAndTintValues.temperature, tint:temperatureAndTintValues.tint)
	}
}


class CameraController: NSObject {

	weak var delegate:CameraControllerDelegate?
	var previewType:CameraControllePreviewType
	
	var previewLayer:AVCaptureVideoPreviewLayer!

	var enableBracketedCapture:Bool = false {
		didSet {
			// TODO: if true, prepare for capture
		}
	}
	
	private var currentCameraDevice:AVCaptureDevice?

	
	// MARK: Private properties
	
	private var sessionQueue:dispatch_queue_t = dispatch_queue_create("com.example.session_access_queue", DISPATCH_QUEUE_SERIAL)
	
	private var session:AVCaptureSession!
	private var backCameraDevice:AVCaptureDevice?
	private var frontCameraDevice:AVCaptureDevice?
	private var stillCameraOutput:AVCaptureStillImageOutput!
	private var videoOutput:AVCaptureVideoDataOutput!
	private var metadataOutput:AVCaptureMetadataOutput!
	
	private var lensPositionContext = 0
	private var adjustingFocusContext = 0
	private var adjustingExposureContext = 0
	private var adjustingWhiteBalanceContext = 0
	private var exposureDuration = 0
	private var ISO = 0
	private var exposureTargetOffsetContext = 0
	private var deviceWhiteBalanceGainsContext = 0

	private var controlObservers = [String: [AnyObject]]()
	
	// MARK: - Initialization
	
	required init(previewType:CameraControllePreviewType, delegate:CameraControllerDelegate) {
		self.delegate = delegate
		self.previewType = previewType
	
		super.init()
		
		initializeSession()
	}
	
	
	convenience init(delegate:CameraControllerDelegate) {
		self.init(previewType: .PreviewLayer, delegate: delegate)
	}
	
	
	func initializeSession() {
		
		session = AVCaptureSession()
		session.sessionPreset = AVCaptureSessionPresetPhoto
		
		if previewType == .PreviewLayer {
            previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
//			previewLayer = AVCaptureVideoPreviewLayer.layerWithSession(self.session) as AVCaptureVideoPreviewLayer
		}

		let authorizationStatus = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)
		
		switch authorizationStatus {
		case .NotDetermined:
			AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo,
				completionHandler: { (granted:Bool) -> Void in
					if granted {
						self.configureSession()
					}
					else {
						self.showAccessDeniedMessage()
					}
			})
		case .Authorized:
			configureSession()
		case .Denied, .Restricted:
			showAccessDeniedMessage()
		}
	}
	
	
	// MARK: - Camera Control
	
	func startRunning() {
		performConfiguration { () -> Void in
			self.observeValues()
			self.session.startRunning()
			NSNotificationCenter.defaultCenter().postNotificationName(CameraControllerDidStartSession, object: self)
		}
	}

	
	func stopRunning() {
		performConfiguration { () -> Void in
			self.unobserveValues()
			self.session.stopRunning()
		}
	}
	
	
	func registerObserver<T where T:NSObject, T:CameraSettingValueObserver>(observer:T, property:String) {
		var propertyObservers = controlObservers[property]
		if propertyObservers == nil {
			propertyObservers = [AnyObject]()
		}
		
		propertyObservers?.append(observer)
		controlObservers[property] = propertyObservers
	}
	
	
	func unregisterObserver<T where T:NSObject, T:CameraSettingValueObserver>(observer:T, property:String) {
		var indexes = [Int]()
		if let propertyObservers = controlObservers[property] {
			let filteredPropertyObservers = propertyObservers.filter({ (obs) -> Bool in
				obs as! NSObject != observer
			})
			controlObservers[property] = filteredPropertyObservers
		}
	}

	
	// MARK: Focus

	func enableContinuousAutoFocus() {
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			if currentDevice.isFocusModeSupported(.ContinuousAutoFocus) {
				currentDevice.focusMode = .ContinuousAutoFocus
			}
		}
	}

	
	func isContinuousAutoFocusEnabled() -> Bool {
		return currentCameraDevice!.focusMode == .ContinuousAutoFocus
	}

	
	func lockFocusAtPointOfInterest(pointInView:CGPoint) {
		var pointInCamera = previewLayer.captureDevicePointOfInterestForPoint(pointInView)
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			if currentDevice.focusPointOfInterestSupported {
				currentDevice.focusPointOfInterest = pointInCamera
				currentDevice.focusMode = .AutoFocus
			}
		}
	}

	
	func lockFocusAtLensPosition(lensPosition:CGFloat) {
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			currentDevice.setFocusModeLockedWithLensPosition(Float(lensPosition)) {
				(time:CMTime) -> Void in
				
			}
		}
	}
	
	
	func currentLensPosition() -> Float? {
		return self.currentCameraDevice?.lensPosition
	}
	
	
	// MARK: Exposure
	

	func enableContinuousAutoExposure() {
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			if currentDevice.isExposureModeSupported(.ContinuousAutoExposure) {
				currentDevice.exposureMode = .ContinuousAutoExposure
			}
		}
	}
	
	
	func isContinuousAutoExposureEnabled() -> Bool {
		return currentCameraDevice!.exposureMode == .ContinuousAutoExposure
	}
	
	
	func lockExposureAtPointOfInterest(pointInView:CGPoint) {
		var pointInCamera = previewLayer.captureDevicePointOfInterestForPoint(pointInView)
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			if currentDevice.exposurePointOfInterestSupported {
				currentDevice.exposurePointOfInterest = pointInCamera
				currentDevice.exposureMode = .AutoExpose
			}
		}
	}
	
	
	func setCustomExposureWithISO(iso:Float) {
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			currentDevice.setExposureModeCustomWithDuration(AVCaptureExposureDurationCurrent, ISO: iso, completionHandler: nil)
		}
	}
	
	
	func setCustomExposureWithDuration(duration:Float) {
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			let activeFormat = currentDevice.activeFormat
			let finalDuration = CMTimeMakeWithSeconds(Float64(duration), 1_000_000)
			let durationRange = CMTimeRangeFromTimeToTime(activeFormat.minExposureDuration, activeFormat.maxExposureDuration)

			if CMTimeRangeContainsTime(durationRange, finalDuration)  {
				currentDevice.setExposureModeCustomWithDuration(finalDuration, ISO: AVCaptureISOCurrent, completionHandler: nil)
			}
		}
	}
	
	
	func setExposureTargetBias(bias:Float) {
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			currentDevice.setExposureTargetBias(bias, completionHandler: nil)
		}
	}
	
	
	func currentExposureDuration() -> Float? {
		if let exposureDuration = currentCameraDevice?.exposureDuration {
			return Float(CMTimeGetSeconds(exposureDuration))
		}
		else {
			return nil
		}
	}
	
	
	func currentISO() -> Float? {
		return currentCameraDevice?.ISO
	}

	
	func currentExposureTargetOffset() -> Float? {
		return currentCameraDevice?.exposureTargetOffset
	}
	
	
	// MARK: White balance
	
	func enableContinuousAutoWhiteBalance() {
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			if currentDevice.isWhiteBalanceModeSupported(.ContinuousAutoWhiteBalance) {
				currentDevice.whiteBalanceMode = .ContinuousAutoWhiteBalance
			}
		}
	}
	
	
	func isContinuousAutoWhiteBalanceEnabled() -> Bool {
		return currentCameraDevice!.whiteBalanceMode == .ContinuousAutoWhiteBalance
	}

	
	func setCustomWhiteBalanceWithTemperature(temperature:Float) {
		
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			if currentDevice.isWhiteBalanceModeSupported(.Locked) {
				let currentGains = currentDevice.deviceWhiteBalanceGains
				let currentTint = currentDevice.temperatureAndTintValuesForDeviceWhiteBalanceGains(currentGains).tint
				let temperatureAndTintValues = AVCaptureWhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: currentTint)
				
				var deviceGains = currentDevice.deviceWhiteBalanceGainsForTemperatureAndTintValues(temperatureAndTintValues)
				var maxWhiteBalanceGain = currentDevice.maxWhiteBalanceGain
				deviceGains.clampGainsToRange(1, maxVal: maxWhiteBalanceGain)
				
				currentDevice.setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains(deviceGains) {
					(timestamp:CMTime) -> Void in
				}
			}
		}
	}

	
	func setCustomWhiteBalanceWithTint(tint:Float) {
		
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			if currentDevice.isWhiteBalanceModeSupported(.Locked) {
				var maxWhiteBalanceGain = currentDevice.maxWhiteBalanceGain
				var currentGains = currentDevice.deviceWhiteBalanceGains
				currentGains.clampGainsToRange(1, maxVal: maxWhiteBalanceGain)
				let currentTemperature = currentDevice.temperatureAndTintValuesForDeviceWhiteBalanceGains(currentGains).temperature
				let temperatureAndTintValues = AVCaptureWhiteBalanceTemperatureAndTintValues(temperature: currentTemperature, tint: tint)
				
				var deviceGains = currentDevice.deviceWhiteBalanceGainsForTemperatureAndTintValues(temperatureAndTintValues)
				deviceGains.clampGainsToRange(1, maxVal: maxWhiteBalanceGain)

				currentDevice.setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains(deviceGains) {
					(timestamp:CMTime) -> Void in
				}
			}
		}
	}

	
	func currentTemperature() -> Float? {
		if let gains = currentCameraDevice?.deviceWhiteBalanceGains {
			var tempAndTint = currentCameraDevice?.temperatureAndTintValuesForDeviceWhiteBalanceGains(gains)
			return tempAndTint?.temperature
		}
		return nil
	}
	
	
	func currentTint() -> Float? {
		if let gains = currentCameraDevice?.deviceWhiteBalanceGains {
			var tempAndTint = currentCameraDevice?.temperatureAndTintValuesForDeviceWhiteBalanceGains(gains)
			return tempAndTint?.tint
		}
		return nil
	}

	// MARK: Still image capture
	
	func captureStillImage(completionHandler handler:((image:UIImage, metadata:NSDictionary) -> Void)) {
		if enableBracketedCapture {
			bracketedCaptureStillImage(completionHandler:handler);
		}
		else {
			captureSingleStillImage(completionHandler:handler)
		}
	}
	
	/*!
	Capture a photo
	
	:param: handler executed on the main queue
	*/
	func captureSingleStillImage(completionHandler handler: ((image:UIImage, metadata:NSDictionary) -> Void)) {
		dispatch_async(sessionQueue) { () -> Void in

			let connection = self.stillCameraOutput.connectionWithMediaType(AVMediaTypeVideo)
			
			connection.videoOrientation = AVCaptureVideoOrientation(rawValue: UIDevice.currentDevice().orientation.rawValue)!
			
			self.stillCameraOutput.captureStillImageAsynchronouslyFromConnection(connection) {
				(imageDataSampleBuffer, error) -> Void in
				
				if error == nil {
					let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    
                    let metadata:NSDictionary = CMCopyDictionaryOfAttachments(nil, imageDataSampleBuffer, kCMAttachmentMode_ShouldNotPropagate)!
//					let metadata:NSDictionary = CMCopyDictionaryOfAttachments(nil, imageDataSampleBuffer, CMAttachmentMode(kCMAttachmentMode_ShouldPropagate)).takeUnretainedValue()

					if let image = UIImage(data: imageData) {
						dispatch_async(dispatch_get_main_queue()) { () -> Void in
							handler(image: image, metadata:metadata)
						}
					}
				}
				else {
					NSLog("error while capturing still image: \(error)")
				}
			}
		}
	}
	
	
	func bracketedCaptureStillImage(completionHandler handler: ((image:UIImage, metadata:NSDictionary) -> Void)) {
		dispatch_async(sessionQueue) { () -> Void in
			
			let connection = self.stillCameraOutput.connectionWithMediaType(AVMediaTypeVideo)
			connection.videoOrientation = AVCaptureVideoOrientation(rawValue: UIDevice.currentDevice().orientation.rawValue)!

			var settings = [-1.0, 0.0, 1.0].map {
				(bias:Float) -> AVCaptureAutoExposureBracketedStillImageSettings in
				
				AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettingsWithExposureTargetBias(bias)
			}
			
			self.stillCameraOutput.captureStillImageBracketAsynchronouslyFromConnection(connection, withSettingsArray: settings, completionHandler: {
				(sampleBuffer, captureSettings, error) -> Void in

				// TODO: stitch images
				
				if error == nil {
					let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer)
					
					let metadata:NSDictionary = CMCopyDictionaryOfAttachments(nil, sampleBuffer, kCMAttachmentMode_ShouldNotPropagate)!
                        
					
					if let image = UIImage(data: imageData) {
						dispatch_async(dispatch_get_main_queue()) { () -> Void in
							handler(image: image, metadata:metadata)
						}
					}
				}
				else {
					NSLog("error while capturing still image: \(error)")
				}
			})
		}
	}
	

	// MARK: - Notifications
	
	func subjectAreaDidChange(notification:NSNotification) {
	}
	
    
	override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
		var key = ""
		var newValue: AnyObject = change![NSKeyValueChangeNewKey]!
		
		switch context {
		case &lensPositionContext:
			key = CameraControlObservableSettingLensPosition
			
		case &exposureDuration:
			key = CameraControlObservableSettingExposureDuration
			
		case &ISO:
			key = CameraControlObservableSettingISO
			
		case &deviceWhiteBalanceGainsContext:
			key = CameraControlObservableSettingWBGains
			
			if let newNSValue = newValue as? NSValue {
				var gains:AVCaptureWhiteBalanceGains? = nil
				newNSValue.getValue(&gains)
				if let newTemperatureAndTint = currentCameraDevice?.temperatureAndTintValuesForDeviceWhiteBalanceGains(gains!) {
					newValue = WhiteBalanceValues(temperatureAndTintValues: newTemperatureAndTint)
				}
			}
		case &adjustingFocusContext:
			key = CameraControlObservableSettingAdjustingFocus
		case &adjustingExposureContext:
			key = CameraControlObservableSettingAdjustingExposure
		case &adjustingWhiteBalanceContext:
			key = CameraControlObservableSettingAdjustingWhiteBalance
		default:
			key = "unknown context"
		}
		
		notifyObservers(key, value: newValue)
	}
}


	// MARK: - Delegate methods

extension CameraController: AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
	
	func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
		
		let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
		let image = CIImage(CVPixelBuffer: pixelBuffer!)
		
//		self.delegate?.cameraController?(self, didOutputImage: image)
	}
	
	
	func captureOutput(captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [AnyObject]!, fromConnection connection: AVCaptureConnection!) {
		
		var faces = Array<(id:Int,frame:CGRect)>()
		
		for metadataObject in metadataObjects as! [AVMetadataObject] {
			if metadataObject.type == AVMetadataObjectTypeFace {
				if let faceObject = metadataObject as? AVMetadataFaceObject {
					var transformedMetadataObject = previewLayer.transformedMetadataObjectForMetadataObject(metadataObject)
					let face:(id: Int, frame: CGRect) = (faceObject.faceID, transformedMetadataObject.bounds)
					faces.append(face)
				}
			}
		}
		
		if let delegate = self.delegate {
			dispatch_async(dispatch_get_main_queue()) {
				delegate.cameraController(self, didDetectFaces: faces)
			}
		}
	}
}



// MARK: - Private

private extension CameraController {
	
	func performConfiguration(block: (() -> Void)) {
		dispatch_async(sessionQueue) { () -> Void in
			block()
		}
	}

	
	func performConfigurationOnCurrentCameraDevice(block: ((currentDevice:AVCaptureDevice) -> Void)) {
		if let currentDevice = self.currentCameraDevice {
			performConfiguration { () -> Void in
				//var error:NSError?
                
                do{
                    try! currentDevice.lockForConfiguration()
                    block(currentDevice: currentDevice)
                    currentDevice.unlockForConfiguration()
                }
                catch {
                    print("Something went wrong")
                }

//				if currentDevice.lockForConfiguration(error) {
//					block(currentDevice: currentDevice)
//					currentDevice.unlockForConfiguration()
//				}
			}
		}
	}
	
	
	func configureSession() {
		configureDeviceInput()
		configureStillImageCameraOutput()
		configureFaceDetection()
		
		if previewType == .Manual {
			configureVideoOutput()
		}
	}
	
	
	func configureDeviceInput() {
		
		performConfiguration { () -> Void in
			
			let availableCameraDevices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
			for device in availableCameraDevices as! [AVCaptureDevice] {
				if device.position == .Back {
					self.backCameraDevice = device
				}
				else if device.position == .Front {
					self.frontCameraDevice = device
				}
			}
			
			
			// let's set the back camera as the initial device
			
			self.currentCameraDevice = self.backCameraDevice
//			var error:NSError?
            do{
                let possibleCameraInput: AnyObject? = try AVCaptureDeviceInput.init(device: self.backCameraDevice)
                if let backCameraInput = possibleCameraInput as? AVCaptureDeviceInput {
                    if self.session.canAddInput(backCameraInput) {
                        self.session.addInput(backCameraInput)
                    }
                }
            }
            catch let error as NSError{
                print (error.description)
            }
		}
	}
	
	
	func configureStillImageCameraOutput() {
		performConfiguration { () -> Void in
			self.stillCameraOutput = AVCaptureStillImageOutput()
			self.stillCameraOutput.outputSettings = [
				AVVideoCodecKey  : AVVideoCodecJPEG,
				AVVideoQualityKey: 0.9
			]
			
			if self.session.canAddOutput(self.stillCameraOutput) {
				self.session.addOutput(self.stillCameraOutput)
			}
		}
	}
	
	
	func configureVideoOutput() {
		performConfiguration { () -> Void in
			self.videoOutput = AVCaptureVideoDataOutput()
			self.videoOutput.setSampleBufferDelegate(self, queue: dispatch_queue_create("sample buffer delegate", DISPATCH_QUEUE_SERIAL))
			if self.session.canAddOutput(self.videoOutput) {
				self.session.addOutput(self.videoOutput)
			}
		}
	}
	
	
	func configureFaceDetection() {
		performConfiguration { () -> Void in
			self.metadataOutput = AVCaptureMetadataOutput()
			self.metadataOutput.setMetadataObjectsDelegate(self, queue: self.sessionQueue)
			
			if self.session.canAddOutput(self.metadataOutput) {
				self.session.addOutput(self.metadataOutput)
			}
            let StringArray = self.metadataOutput.availableMetadataObjectTypes as! [NSString]!
            
            if StringArray.contains(AVMetadataObjectTypeFace)
            {
                self.metadataOutput.metadataObjectTypes = [AVMetadataObjectTypeFace]
            }
            
		}
	}
	
	
	func observeValues() {
		currentCameraDevice?.addObserver(self, forKeyPath: "lensPosition", options: .New, context: &lensPositionContext)
		currentCameraDevice?.addObserver(self, forKeyPath: "adjustingFocus", options: .New, context: &adjustingFocusContext)
		currentCameraDevice?.addObserver(self, forKeyPath: "adjustingExposure", options: .New, context: &adjustingExposureContext)
		currentCameraDevice?.addObserver(self, forKeyPath: "adjustingWhiteBalance", options: .New, context: &adjustingWhiteBalanceContext)
		currentCameraDevice?.addObserver(self, forKeyPath: "exposureDuration", options: .New, context: &exposureDuration)
		currentCameraDevice?.addObserver(self, forKeyPath: "ISO", options: .New, context: &ISO)
		currentCameraDevice?.addObserver(self, forKeyPath: "deviceWhiteBalanceGains", options: .New, context: &deviceWhiteBalanceGainsContext)
	}
	
	
	func unobserveValues() {
		currentCameraDevice?.removeObserver(self, forKeyPath: "lensPosition", context: &lensPositionContext)
		currentCameraDevice?.removeObserver(self, forKeyPath: "adjustingFocus", context: &adjustingFocusContext)
		currentCameraDevice?.removeObserver(self, forKeyPath: "adjustingExposure", context: &adjustingExposureContext)
		currentCameraDevice?.removeObserver(self, forKeyPath: "adjustingWhiteBalance", context: &adjustingWhiteBalanceContext)
		currentCameraDevice?.removeObserver(self, forKeyPath: "exposureDuration", context: &exposureDuration)
		currentCameraDevice?.removeObserver(self, forKeyPath: "ISO", context: &ISO)
		currentCameraDevice?.removeObserver(self, forKeyPath: "deviceWhiteBalanceGains", context: &deviceWhiteBalanceGainsContext)
	}
	
	
	func showAccessDeniedMessage() {
		
	}


	func notifyObservers(key:String, value:AnyObject) {
		if let lensPositionObservers = controlObservers[key] {
			for obj in lensPositionObservers as [AnyObject] {
				if let observer = obj as? CameraSettingValueObserver {
					notifyObserver(observer, setting: key, value: value)
				}
			}
		}
	}
	
	
	func notifyObserver<T where T:CameraSettingValueObserver>(observer:T, setting:String, value:AnyObject) {
		observer.cameraSetting(setting, valueChanged: value)
	}
}


