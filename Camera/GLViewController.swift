//
//  GLViewController.swift
//  Camera
//
//  Created by Matteo Caldari on 28/01/15.
//  Copyright (c) 2015 Matteo Caldari. All rights reserved.
//

import UIKit
import GLKit
import CoreImage
import OpenGLES

class GLViewController: UIViewController {


	var cameraController:CameraController!
	
	private var glContext:EAGLContext?
	private var ciContext:CIContext?
	private var renderBuffer:GLuint = GLuint()
	
	private var glView:GLKView {
		get {
			return view as! GLKView
		}
	}


	override func viewDidLoad() {
        super.viewDidLoad()
	
		glContext = EAGLContext(API: .OpenGLES2)
		
		
		glView.context = glContext!
//		glView.drawableDepthFormat = .Format24
		glView.transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
		if let window = glView.window {
			glView.frame = window.bounds
		}
		
		ciContext = CIContext(EAGLContext: glContext!)

//		cameraController = CameraController(previewType: .Manual, delegate: self)
	}

	
	override func viewDidAppear(animated: Bool) {
		cameraController.startRunning()
	}
	
	
	// MARK: CameraControllerDelegate

	func cameraController(cameraController: CameraController, didDetectFaces faces: NSArray) {
		
	}

	
	func cameraController(cameraController: CameraController, didOutputImage image: CIImage) {

		if glContext != EAGLContext.currentContext() {
			EAGLContext.setCurrentContext(glContext)
		}
		
		glView.bindDrawable()

		ciContext?.drawImage(image, inRect:image.extent, fromRect: image.extent)

		glView.display()
	}
}
