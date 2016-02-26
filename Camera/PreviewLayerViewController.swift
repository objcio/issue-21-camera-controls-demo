//
//  PreviewLayerViewController.swift
//  Camera
//
//  Created by Matteo Caldari on 27/03/15.
//  Copyright (c) 2015 Matteo Caldari. All rights reserved.
//

import UIKit
import AVFoundation

class PreviewLayerView : UIView {
	override class func layerClass() -> AnyClass {
		return AVCaptureVideoPreviewLayer.self
	}
}



class PreviewLayerViewController: UIViewController, CameraPreviewViewController {
	
	var previewLayer:AVCaptureVideoPreviewLayer! {
		get {
			return view.layer as! AVCaptureVideoPreviewLayer
		}
	}
	
	var cameraController:CameraController? {
		didSet {
			cameraController?.previewLayer = previewLayer
		}
	}

	override func loadView() {
		view = PreviewLayerView()
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
	}
}
