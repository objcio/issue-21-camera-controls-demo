
//
//  GLPreviewViewController.swift
//  Camera
//
//  Created by Matteo Caldari on 28/01/15.
//  Copyright (c) 2015 Matteo Caldari. All rights reserved.
//

import UIKit
import GLKit
import CoreImage
import OpenGLES

class GLPreviewViewController: UIViewController, CameraPreviewViewController, CameraFramesDelegate {


	var cameraController:CameraController? {
		didSet {
			cameraController?.framesDelegate = self
		}
	}
	
	private var glContext:EAGLContext?
	private var ciContext:CIContext?
	private var renderBuffer:GLuint = GLuint()
	
	private var filter = CIFilter(name:"CIPhotoEffectMono")
	
	private var glView:GLKView {
		get {
			return view as! GLKView
		}
	}

	override func loadView() {
		self.view = GLKView()
	}

	override func viewDidLoad() {
        super.viewDidLoad()
	
		glContext = EAGLContext(API: .OpenGLES2)
		
		glView.context = glContext!
		glView.transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
		if let window = glView.window {
			glView.frame = window.bounds
		}
		
		ciContext = CIContext(EAGLContext: glContext!)
	}


	// MARK: CameraControllerDelegate

	func cameraController(cameraController: CameraController, didOutputImage image: CIImage) {

		if glContext != EAGLContext.currentContext() {
			EAGLContext.setCurrentContext(glContext)
		}
		
		glView.bindDrawable()
		
		filter!.setValue(image, forKey: "inputImage")
		let outputImage = filter!.outputImage

		ciContext?.drawImage(outputImage!, inRect:image.extent, fromRect: image.extent)

		glView.display()
	}
}
