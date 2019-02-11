//
//  ViewController.swift
//  CelebMatch
//
//  Created by Dipak Singh on 12/19/18.
//  Copyright © 2018 TrialX. All rights reserved.
//

import UIKit
import Vision
import Photos
import AVFoundation
import SafariServices
import AWSRekognition
import NVActivityIndicatorView
import CoreImage


class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // Main view for showing camera content.
    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var bottomContraintOfPreview:NSLayoutConstraint!
    @IBOutlet weak var tblRecognizedFace:UITableView!
    @IBOutlet weak var activityView:NVActivityIndicatorView!
    @IBOutlet weak var blurView:UIView!
    @IBOutlet weak var lblMatch:UILabel!
    
    var showDate: Date!
    var imageToSendToAPI:UIImage!
    var infoLinksMap: [Int:String] = [1000:""]
    var arrRecognizedFaces = [AnyObject]()
    var rekognitionObject:AWSRekognition?
    
    private var faceDetectionRequest: VNRequest!
    
    // TODO: Decide camera position --- front or back
    private var devicePosition: AVCaptureDevice.Position = .back
    
    // Session Management
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], target: nil)
    
    private var setupResult: SessionSetupResult = .success
    
    private var videoDeviceInput:   AVCaptureDeviceInput!
    
    private var videoDataOutput:    AVCaptureVideoDataOutput!
    private var videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
    
    private var requests = [VNRequest]()
    
    var i = 0
    
    // MARK: UIViewController overrides
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up the video preview view.
        previewView.session = session
        
        
        
        /*
         Check video authorization status. Video access is required and audio
         access is optional. If audio access is denied, audio is not recorded
         during movie recording.
         */
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video){
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. We suspend the session queue to delay session
             setup until the access request has completed.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { [unowned self] granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Why not do all of this on the main queue?
         Because AVCaptureSession.startRunning() is a blocking call which can
         take a long time. We dispatch session setup to the sessionQueue so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        
        sessionQueue.async { [unowned self] in
            self.configureSession()
        }
        
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async { [unowned self] in
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("AVCamBarcode doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera")
                    let    alertController = UIAlertController(title: "AppleFaceDetection", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .`default`, handler: { action in
                        UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AppleFaceDetection", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // Ensure that the interface stays locked in Portrait.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    // Ensure that the interface stays locked in Portrait.
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    // MARK: AVCapture Setup
    
    @IBAction func switchCameraTapped(sender: Any) {
        //Change camera source
        
        //Indicate that some changes will be made to the session
        self.session.stopRunning()
        self.session.beginConfiguration()
        
        //Remove existing input
        guard let currentCameraInput: AVCaptureInput = self.session.inputs.first else {
            return
        }
        
        self.session.removeInput(currentCameraInput)
        
        //Get new input
        var newCamera: AVCaptureDevice! = nil
        if let input = currentCameraInput as? AVCaptureDeviceInput {
            if (input.device.position == .back) {
                newCamera = cameraWithPosition(position: .front)
                self.devicePosition = .front
            } else {
                newCamera = cameraWithPosition(position: .back)
                self.devicePosition = .back
            }
        }
        
        //Add input to session
        var err: NSError?
        var newVideoInput: AVCaptureDeviceInput!
        do {
            newVideoInput = try AVCaptureDeviceInput(device: newCamera)
        } catch let err1 as NSError {
            err = err1
            newVideoInput = nil
        }
        
        if newVideoInput == nil || err != nil {
            print("Error creating capture device input: \(err?.localizedDescription)")
        } else {
            self.session.addInput(newVideoInput)
        }
        
        //Commit all the configuration changes at once
        self.session.commitConfiguration()
        self.session.startRunning()
    }
    
    // Find a camera with the specified AVCaptureDevicePosition, returning nil if one is not found
    func cameraWithPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .unspecified)
        for device in discoverySession.devices {
            if device.position == position {
                return device
            }
        }
        
        return nil
    }
    
    
    // MARK: Helper Methods for Error Presentation
    
    fileprivate func presentErrorAlert(withTitle title: String = "Unexpected Failure", message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        self.present(alertController, animated: true)
    }
    
    fileprivate func presentError(_ error: NSError) {
        self.presentErrorAlert(withTitle: "Failed with error \(error.code)", message: error.localizedDescription)
    }
    
    // MARK: Helper Methods for Handling Device Orientation & EXIF
    
    fileprivate func radiansForDegrees(_ degrees: CGFloat) -> CGFloat {
        return CGFloat(Double(degrees) * Double.pi / 180.0)
    }
    
    func exifOrientationForDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        
        switch deviceOrientation {
        case .portraitUpsideDown:
            return .rightMirrored
            
        case .landscapeLeft:
            return .downMirrored
            
        case .landscapeRight:
            return .upMirrored
            
        default:
            return .leftMirrored
        }
        
    }
    
    
    func imageFromSampleBuffer(sampleBuffer : CMSampleBuffer) -> UIImage?
    {
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        let  imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly);
        
        
        // Get the number of bytes per row for the pixel buffer
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer!);
        
        // Get the number of bytes per row for the pixel buffer
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer!);
        // Get the pixel buffer width and height
        let width = CVPixelBufferGetWidth(imageBuffer!);
        let height = CVPixelBufferGetHeight(imageBuffer!);
        
        // Create a device-dependent RGB color space
        let colorSpace = CGColorSpaceCreateDeviceRGB();
        
        // Create a bitmap graphics context with the sample buffer data
        var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue
        bitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
        //let bitmapInfo: UInt32 = CGBitmapInfo.alphaInfoMask.rawValue
        let context = CGContext.init(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        // Create a Quartz image from the pixel data in the bitmap graphics context
        let quartzImage = context?.makeImage();
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly);
        if let img = quartzImage {
            let imgToReturn =  UIImage.init(cgImage: img)
            return imgToReturn
            
        }else {
            return nil
        }
        // Create an image object from the Quartz image
        
        //        return (image);
    }
}
// Video Sessions
extension ViewController {
    private func configureSession() {
        if setupResult != .success { return }
        
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // Add video input.
        addVideoDataInput()
        
        // Add video output.
        addVideoDataOutput()
        
        session.commitConfiguration()
        
    }
    
    private func addVideoDataInput() {
        do {
            var defaultVideoDevice: AVCaptureDevice!
            
            if devicePosition == .front {
                if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .front) {
                    defaultVideoDevice = frontCameraDevice
                }
            }
            else {
                // Choose the back dual camera if available, otherwise default to a wide angle camera.
                if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: AVMediaType.video, position: .back) {
                    defaultVideoDevice = dualCameraDevice
                }
                    
                else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back) {
                    defaultVideoDevice = backCameraDevice
                }
            }
            
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice!)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                DispatchQueue.main.async {
                    /*
                     Why are we dispatching this to the main queue?
                     Because AVCaptureVideoPreviewLayer is the backing layer for PreviewView and UIView
                     can only be manipulated on the main thread.
                     Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                     on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                     
                     Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
                     handled by CameraViewController.viewWillTransition(to:with:).
                     */
                    let statusBarOrientation = UIApplication.shared.statusBarOrientation
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if statusBarOrientation != .unknown {
                        if let videoOrientation = statusBarOrientation.videoOrientation {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    self.previewView?.videoPreviewLayer.connection!.videoOrientation = initialVideoOrientation
                }
            }
            
        }
        catch {
            print("Could not add video device input to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
    }
    
    private func addVideoDataOutput() {
        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
        
        
        if session.canAddOutput(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            session.addOutput(videoDataOutput)
        }
        else {
            print("Could not add metadata output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
    }
}

// MARK: -- Observers and Event Handlers
extension ViewController {
    private func addObservers() {
        /*
         Observe the previewView's regionOfInterest to update the AVCaptureMetadataOutput's
         rectOfInterest when the user finishes resizing the region of interest.
         */
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: Notification.Name("AVCaptureSessionRuntimeErrorNotification"), object: session)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: Notification.Name("AVCaptureSessionWasInterruptedNotification"), object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: Notification.Name("AVCaptureSessionInterruptionEndedNotification"), object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func sessionRuntimeError(_ notification: Notification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else { return }
        
        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async { [unowned self] in
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }
    
    @objc func sessionWasInterrupted(_ notification: Notification) {
        /*
         In some scenarios we want to enable the user to resume the session running.
         For example, if music playback is initiated via control center while
         using AVCamBarcode, then the user can let AVCamBarcode resume
         the session running, which will stop music playback. Note that stopping
         music playback in control center will not automatically resume the session
         running. Also note that it is not always possible to resume, see `resumeInterruptedSession(_:)`.
         */
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?, let reasonIntegerValue = userInfoValue.integerValue, let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
        }
    }
    
    @objc func sessionInterruptionEnded(_ notification: Notification) {
        print("Capture session interruption ended")
    }
}

// MARK: -- Helpers
extension ViewController {
    func setupVision() {
        self.requests = [faceDetectionRequest]
    }
    
    func handleFaces(request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            //perform all the UI updates on the main queue
            guard let results = request.results as? [VNFaceObservation] else { return }
            self.previewView?.removeMask()
            for face in results {
                self.previewView.drawFaceboundingBox(face: face)
            }
        }
    }
    
    func handleFaceLandmarks(request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            //perform all the UI updates on the main queue
            guard let results = request.results as? [VNFaceObservation] else { return }
            self.previewView.removeMask()
            for face in results {
                self.previewView.drawFaceWithLandmarks(face: face)
            }
        }
    }
    
}

// Camera Settings & Orientation
extension ViewController {
    func availableSessionPresets() -> [String] {
        let allSessionPresets = [AVCaptureSession.Preset.photo,
                                 AVCaptureSession.Preset.low,
                                 AVCaptureSession.Preset.medium,
                                 AVCaptureSession.Preset.high,
                                 AVCaptureSession.Preset.cif352x288,
                                 AVCaptureSession.Preset.vga640x480,
                                 AVCaptureSession.Preset.hd1280x720,
                                 AVCaptureSession.Preset.iFrame960x540,
                                 AVCaptureSession.Preset.iFrame1280x720,
                                 AVCaptureSession.Preset.hd1920x1080,
                                 AVCaptureSession.Preset.hd4K3840x2160]
        
        var availableSessionPresets = [String]()
        for sessionPreset in allSessionPresets {
            if session.canSetSessionPreset(sessionPreset) {
                availableSessionPresets.append(sessionPreset.rawValue)
            }
        }
        
        return availableSessionPresets
    }
    
    func exifOrientationFromDeviceOrientation() -> UInt32 {
        enum DeviceOrientation: UInt32 {
            case top0ColLeft = 1
            case top0ColRight = 2
            case bottom0ColRight = 3
            case bottom0ColLeft = 4
            case left0ColTop = 5
            case right0ColTop = 6
            case right0ColBottom = 7
            case left0ColBottom = 8
        }
        var exifOrientation: DeviceOrientation
        
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            exifOrientation = .left0ColBottom
        case .landscapeLeft:
            exifOrientation = devicePosition == .front ? .bottom0ColRight : .top0ColLeft
        case .landscapeRight:
            exifOrientation = devicePosition == .front ? .top0ColLeft : .bottom0ColRight
        default:
            exifOrientation = devicePosition == .front ? .left0ColTop : .right0ColTop
        }
        return exifOrientation.rawValue
    }
    
    
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension ViewController {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let exifOrientation = CGImagePropertyOrientation(rawValue: exifOrientationFromDeviceOrientation()) else { return }
        var requestOptions: [VNImageOption : Any] = [:]
        
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics : cameraIntrinsicData]
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: requestOptions)
        // Set up Vision Request
        let request = VNDetectFaceLandmarksRequest { (request, error) in
            DispatchQueue.main.async {
                //perform all the UI updates on the main queue
                guard let results = request.results as? [VNFaceObservation] else { return }
                self.previewView?.removeMask()
                if let face = results.first {
                    let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.previewView.frame.height)
                    
                    let translate = CGAffineTransform.identity.scaledBy(x: self.previewView.frame.width, y: self.previewView.frame.height)
                    
                    // The coordinates are normalized to the dimensions of the processed image, with the origin at the image's lower-left corner.
                    let facebounds = face.boundingBox.applying(translate).applying(transform)
                    var faceYaw = 1.0
                    var faceRoll =  1.0
                    if #available(iOS 12.0, *) {
                        print("\(face.yaw,face.roll)")
                        faceYaw = face.yaw?.doubleValue ?? 1.0
                        faceRoll = face.roll?.doubleValue ?? 1.0
                    } else {
                        // Fallback on earlier versions
                    }
                    print("-----")
                    
                    if self.previewView.frame.contains(facebounds) {
                        if self.i < 1 && self.bottomContraintOfPreview.constant == 0 && face.confidence == 1.0 && faceYaw.isZero && faceRoll.isZero {
                            
                            let ciimage : CIImage = CIImage(cvPixelBuffer: pixelBuffer)
                            let image : UIImage = self.convert(cmage: ciimage)

                            if let rotatedImg = image.rotate(radians: .pi/2),
                                let data1 = UIImageJPEGRepresentation(rotatedImg, 0){
                                
                                self.imageToSendToAPI = rotatedImg
                                self.i = self.i+1
                                self.sendImageToRekognition(celebImageData: data1)
                                
                            }
                        }
                        for face in results {
                            self.previewView.drawFaceboundingBox(face: face)
                        }
                    }else {
                        
                    }
                    
                }else {
                    if let shwDate = self.showDate, Date().timeIntervalSince(shwDate) < 8 {
                        return
                    }
                    
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: [.curveEaseInOut], animations: {
                        self.bottomContraintOfPreview.constant = 0
                        self.view.layoutIfNeeded()
                    }, completion: { (isCompleted) in
                        
                    })

                }
                
            }
        }
        
        do {
            try imageRequestHandler.perform([request])
        }
            
        catch {
            print(error)
        }
        
    }
    func convert(cmage:CIImage) -> UIImage
    {
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(cmage, from: cmage.extent)!
        let image:UIImage = UIImage.init(cgImage: cgImage)
        return image
    }

    
}
extension UIImage {
    func rotate(radians: CGFloat) -> UIImage? {
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: CGFloat(radians)))
            .integral.size
        UIGraphicsBeginImageContext(rotatedSize)
        if let context = UIGraphicsGetCurrentContext() {
            let origin = CGPoint(x: rotatedSize.width / 2.0,
                                 y: rotatedSize.height / 2.0)
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: radians)
            draw(in: CGRect(x: -self.size.width/2, y: -self.size.height/2,
                            width: size.width, height: size.height))
            let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return rotatedImage
        }
        
        return self
    }
}
extension ViewController {
    //MARK: - AWS Methods
    func sendImageToRekognition(celebImageData: Data){
        
        rekognitionObject = AWSRekognition.default()
        let celebImageAWS = AWSRekognitionImage()
        celebImageAWS?.bytes = celebImageData
        let celebRequest = AWSRekognitionRecognizeCelebritiesRequest()
        celebRequest?.image = celebImageAWS
        
        DispatchQueue.main.async {
            self.lblMatch.isHidden = false
            self.blurView.isHidden = false
            self.activityView.startAnimating()
        }
        
        rekognitionObject?.recognizeCelebrities(celebRequest!){
            (result, error) in
            
            if error != nil{
                print(error!)
                DispatchQueue.main.async {
                    self.lblMatch.isHidden = true
                    self.blurView.isHidden = true
                    self.activityView.stopAnimating()
                }
                return
            }
            DispatchQueue.main.async {
                self.lblMatch.isHidden = true
                self.blurView.isHidden = true
                self.activityView.stopAnimating()
                
                
                guard let celebResult = result else { return }
                self.arrRecognizedFaces.removeAll()
                if !(celebResult.celebrityFaces?.isEmpty)!{
                    self.arrRecognizedFaces = celebResult.celebrityFaces ?? []
                    self.tblRecognizedFace.reloadData()
                    self.i = self.i - 1
                    
                    
                }
                else if !(celebResult.unrecognizedFaces?.isEmpty)!{
                    
                    self.arrRecognizedFaces = celebResult.unrecognizedFaces ?? []
                    self.tblRecognizedFace.reloadData()
                    
                    self.i = self.i - 1
                    
                    print("Unrecognized faces in this pic")
                    
                }
                else{
                    self.i = self.i - 1
                    print("No faces in this pic")
                }
                
                self.showDate = Date()
                
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: [.curveEaseInOut], animations: {
                    self.bottomContraintOfPreview.constant = 200
                }, completion: { (isCompleted) in
                    //1. First we check if there are any celebrities in the response
                    
                })
                
            }
            
        }
        
    }
    
    @objc func handleKnowMore(sender:UIButton){
        if let tblCell = sender.superview?.superview as? RecognizedFaceCell, let arrUrl = tblCell.faceData.urls{
            var urlStr = ""
            if !arrUrl.isEmpty{
                urlStr = "https://\(arrUrl[0])"
            }else {
                urlStr = "https://www.imdb.com/search/name-text?bio=\(tblCell.faceData.name ?? "")"
            }
            if let celebUrl = URL.init(string: urlStr) {
                let safariController = SFSafariViewController(url: celebUrl)
                safariController.delegate = self
                self.present(safariController, animated:true)
            }
            
        }
    }
}
extension UIViewController:SFSafariViewControllerDelegate {
    
}
extension ViewController:UITableViewDataSource,UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.arrRecognizedFaces.count
    }
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let faceCell = tableView.dequeueReusableCell(withIdentifier: "IDCellReconizedFace") as? RecognizedFaceCell else { return UITableViewCell()}
        if let arrOfCelebrities = self.arrRecognizedFaces as? [AWSRekognitionCelebrity] {
            let str = "Hurray!!. We have found your lookalike Celebrity. His name is \(arrOfCelebrities[indexPath.row].name ?? "")"
            let range = (str as NSString).range(of: self.arrRecognizedFaces[indexPath.row].name!)
            
            let attributedString = NSMutableAttributedString(string:str)
            attributedString.addAttribute(NSAttributedStringKey.foregroundColor, value: UIColor.init(red: 33/255, green: 79/255, blue: 161/255, alpha: 1.0) , range: range)
            attributedString.addAttribute(NSAttributedStringKey.font, value: UIFont(name: "HelveticaNeue-Bold", size: 17)!, range: range)
            faceCell.btnKnowMore.isHidden = false
            faceCell.lblRecognizedDesc.attributedText = attributedString
            faceCell.faceData = arrOfCelebrities[indexPath.row]
            faceCell.progressBar.progress = (faceCell.faceData.matchConfidence?.floatValue ?? 0)/100
            faceCell.btnKnowMore.addTarget(self, action: #selector(self.handleKnowMore(sender:)), for: .touchUpInside)
            
            if let bndingBox = arrOfCelebrities[indexPath.row].face?.boundingBox {
                let size = CGSize(width: CGFloat(bndingBox.width?.floatValue ?? 0.0) * (self.imageToSendToAPI.size.width), height:CGFloat(bndingBox.height?.floatValue ?? 0.0)  * self.imageToSendToAPI.size.height)
                let origin = CGPoint(x: CGFloat(bndingBox.left?.floatValue ?? 0.0)  * self.imageToSendToAPI.size.width, y: CGFloat(bndingBox.top?.floatValue ?? 0.0)  * self.imageToSendToAPI.size.height)
                if let croppedImage = self.imageToSendToAPI.cgImage?.cropping(to: CGRect.init(x: origin.x, y: origin.y, width: size.width, height: size.height)) {
                    
                    faceCell.faceImgView.image = UIImage.init(cgImage: croppedImage)
                }
            }
        }else {
            faceCell.lblRecognizedDesc.text = "Unfortunately!!. We have not found a match with any of the Present Celebrity. Hope you are another one."
            faceCell.progressBar.progress = 0.0
            faceCell.btnKnowMore.isHidden = true
            if let arrOfUnrecognizedFaces = self.arrRecognizedFaces as? [AWSRekognitionComparedFace] {
                if let bndingBox = arrOfUnrecognizedFaces[indexPath.row].boundingBox {
                    let size = CGSize(width: CGFloat(bndingBox.width?.floatValue ?? 0.0) * (self.imageToSendToAPI.size.width), height:CGFloat(bndingBox.height?.floatValue ?? 0.0)  * self.imageToSendToAPI.size.height)
                    let origin = CGPoint(x: CGFloat(bndingBox.left?.floatValue ?? 0.0)  * self.imageToSendToAPI.size.width, y: CGFloat(bndingBox.top?.floatValue ?? 0.0)  * self.imageToSendToAPI.size.height)
                    if let croppedImage = self.imageToSendToAPI.cgImage?.cropping(to: CGRect.init(x: origin.x, y: origin.y, width: size.width, height: size.height)) {
                        
                        faceCell.faceImgView.image = UIImage.init(cgImage: croppedImage)
                    }
                    
                }
            }
            
        }
        
        return faceCell
    }
    
}
extension UIViewController {
    
    func showAlert(title: String?, message: String?,b1Title: String = "OK", onB1Click:(()->())?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: b1Title, style: UIAlertActionStyle.default, handler: { (action) in
            onB1Click?()
        }))
        
        present(alert, animated: true, completion: nil)
    }
    
    func showAlert(title: String?, message: String?, b1Title: String?, b2Title: String? , onB1Click:(()->())?, onB2Click:(()->())?,fistButtonStyle: UIAlertActionStyle = .default, secondButtonStyle: UIAlertActionStyle = .default) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: b1Title, style: fistButtonStyle, handler: { (action) in
            onB1Click?()
        }))
        
        alert.addAction(UIAlertAction(title: b2Title, style: secondButtonStyle, handler: { (action) in
            onB2Click?()
        }))
        
        present(alert, animated: true, completion: nil)
    }
    
    //MARK:- Camera Functions
    func performCameraFunction(delegate: (UIImagePickerControllerDelegate & UINavigationControllerDelegate)){
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            debugPrint("notDetermined")
        case .authorized:
            debugPrint("authorized")
        case .denied:
            showAlert(title: "Give access to Camera", message: "",b1Title:"Go to Settings", onB1Click: {
                guard let settingsURL = URL(string: UIApplicationOpenSettingsURLString) else { return }
                if UIApplication.shared.canOpenURL(settingsURL){
                    UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
                }
            })
            
        case .restricted:
            debugPrint("restricted")
        }
        
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let imagePickerController = UIImagePickerController()
            imagePickerController.sourceType = .camera
            imagePickerController.allowsEditing = true
            imagePickerController.delegate = delegate
            self.present(imagePickerController, animated: true, completion: nil)
        } else {
            debugPrint("Cam unavail")
        }
    }
}




