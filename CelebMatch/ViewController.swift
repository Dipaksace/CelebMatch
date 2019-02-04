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


class ViewController: UIViewController {
    
    // Main view for showing camera content.
    @IBOutlet weak var previewView: UIView?
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
    
    let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy : CIDetectorAccuracyHigh])
    
    // AVCapture variables to hold sequence data
    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?
    
    var captureDevice: AVCaptureDevice?
    var captureDeviceResolution: CGSize = CGSize()
    
    // Layer UI for drawing Vision results
    var rootLayer: CALayer?
    var detectionOverlayLayer: CALayer?
    var detectedFaceRectangleShapeLayer: CAShapeLayer?
    var detectedFaceLandmarksShapeLayer: CAShapeLayer?
    
    // Vision requests
    private var detectionRequests: [VNDetectFaceRectanglesRequest]?
    private var trackingRequests: [VNTrackObjectRequest]?
    
    lazy var sequenceRequestHandler = VNSequenceRequestHandler()
    var i = 0
    
    // MARK: UIViewController overrides
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.session = self.setupAVCaptureSession()
        
        self.tblRecognizedFace.tableFooterView = UIView.init(frame: CGRect.zero)
        self.tblRecognizedFace.estimatedRowHeight = 50
        
        self.session?.startRunning()
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
    
    /// - Tag: CreateCaptureSession
    fileprivate func setupAVCaptureSession() -> AVCaptureSession? {
        let captureSession = AVCaptureSession()
        do {
            let inputDevice = try self.configureFrontCamera(for: captureSession, position: .front)
            self.configureVideoDataOutput(for: inputDevice.device, resolution: inputDevice.resolution, captureSession: captureSession)
            self.designatePreviewLayer(for: captureSession)
            return captureSession
        } catch let executionError   as NSError {
            self.presentError(executionError)
        } catch {
            self.presentErrorAlert(message: "An unexpected failure has occured")
        }
        
        self.teardownAVCapture()
        
        return nil
    }
    @IBAction func switchCameraTapped(sender: Any) {
        //Change camera source
        if let sess = self.session {
            //Indicate that some changes will be made to the session
            sess.stopRunning()
            sess.beginConfiguration()
            
            //Remove existing input
            guard let currentCameraInput: AVCaptureInput = sess.inputs.first else {
                return
            }
            
            sess.removeInput(currentCameraInput)
            
            //Get new input
            var newCamera: AVCaptureDevice! = nil
            if let input = currentCameraInput as? AVCaptureDeviceInput {
                if (input.device.position == .back) {
                    newCamera = cameraWithPosition(position: .front)
                } else {
                    newCamera = cameraWithPosition(position: .back)
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
                sess.addInput(newVideoInput)
            }
            
            //Commit all the configuration changes at once
            sess.commitConfiguration()
            sess.startRunning()
        }
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
    
    /// - Tag: ConfigureDeviceResolution
    fileprivate func highestResolution420Format(for device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, resolution: CGSize)? {
        var highestResolutionFormat: AVCaptureDevice.Format? = nil
        var highestResolutionDimensions = CMVideoDimensions(width: 0, height: 0)
        
        for format in device.formats {
            let deviceFormat = format as AVCaptureDevice.Format
            
            let deviceFormatDescription = deviceFormat.formatDescription
            if CMFormatDescriptionGetMediaSubType(deviceFormatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
                let candidateDimensions = CMVideoFormatDescriptionGetDimensions(deviceFormatDescription)
                if (highestResolutionFormat == nil) || (candidateDimensions.width > highestResolutionDimensions.width) {
                    highestResolutionFormat = deviceFormat
                    highestResolutionDimensions = candidateDimensions
                }
            }
        }
        
        if highestResolutionFormat != nil {
            let resolution = CGSize(width: CGFloat(highestResolutionDimensions.width), height: CGFloat(highestResolutionDimensions.height))
            return (highestResolutionFormat!, resolution)
        }
        
        return nil
    }
    
    fileprivate func configureFrontCamera(for captureSession: AVCaptureSession,position: AVCaptureDevice.Position) throws -> (device: AVCaptureDevice, resolution: CGSize) {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        
        if let device = deviceDiscoverySession.devices.first {
            if let deviceInput = try? AVCaptureDeviceInput(device: device) {
                if captureSession.canAddInput(deviceInput) {
                    captureSession.addInput(deviceInput)
                }
                
                if let highestResolution = self.highestResolution420Format(for: device) {
                    try device.lockForConfiguration()
                    device.activeFormat = highestResolution.format
                    device.unlockForConfiguration()
                    
                    return (device, highestResolution.resolution)
                }
            }
        }
        
        throw NSError(domain: "ViewController", code: 1, userInfo: nil)
    }
    
    /// - Tag: CreateSerialDispatchQueue
    fileprivate func configureVideoDataOutput(for inputDevice: AVCaptureDevice, resolution: CGSize, captureSession: AVCaptureSession) {
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        // Create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured.
        // A serial dispatch queue must be used to guarantee that video frames will be delivered in order.
        let videoDataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.VisionFaceTrack")
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        videoDataOutput.videoSettings[kCVPixelBufferPixelFormatTypeKey as String] = Int(kCVPixelFormatType_32BGRA)
        videoDataOutput.connection(with: .video)?.isEnabled = true
        
        if let captureConnection = videoDataOutput.connection(with: AVMediaType.video) {
            if captureConnection.isCameraIntrinsicMatrixDeliverySupported {
                captureConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }
        
        self.videoDataOutput = videoDataOutput
        self.videoDataOutputQueue = videoDataOutputQueue
        
        self.captureDevice = inputDevice
        self.captureDeviceResolution = resolution
    }
    
    /// - Tag: DesignatePreviewLayer
    fileprivate func designatePreviewLayer(for captureSession: AVCaptureSession) {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer = videoPreviewLayer
        
        videoPreviewLayer.name = "CameraPreview"
        videoPreviewLayer.backgroundColor = UIColor.black.cgColor
        videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        if let previewRootLayer = self.previewView?.layer {
            self.rootLayer = previewRootLayer
            
            previewRootLayer.masksToBounds = true
            self.view.layoutIfNeeded()
            videoPreviewLayer.frame = previewRootLayer.frame
            previewRootLayer.addSublayer(videoPreviewLayer)
        }
    }
    
    // Removes infrastructure for AVCapture as part of cleanup.
    fileprivate func teardownAVCapture() {
        self.videoDataOutput = nil
        self.videoDataOutputQueue = nil
        
        if let previewLayer = self.previewLayer {
            previewLayer.removeFromSuperlayer()
            self.previewLayer = nil
        }
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
    
}
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate)
        let ciImage = CIImage(cvImageBuffer: pixelBuffer!, options: attachments as! [String : Any]?)
        let options: [String : Any] = [CIDetectorImageOrientation: exifOrientation(orientation: UIDevice.current.orientation),
                                       CIDetectorSmile: true,
                                       CIDetectorEyeBlink: true]
        let allFeatures = faceDetector?.features(in: ciImage, options: options)
        
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        let cleanAperture = CMVideoFormatDescriptionGetCleanAperture(formatDescription!, false)
        
        guard let features = allFeatures else { return }
        
        if let faceFeature = features.first as? CIFaceFeature,
            faceFeature.hasLeftEyePosition, faceFeature.hasRightEyePosition ,faceFeature.hasMouthPosition ,
            self.i < 1, self.bottomContraintOfPreview.constant == 0  {
            let ciimage : CIImage = CIImage(cvPixelBuffer: pixelBuffer!)
            let image : UIImage = self.convert(cmage: ciimage)
            
            if let rotatedImg = image.rotate(radians: .pi/2),
                let data1 = UIImageJPEGRepresentation(rotatedImg, 0){
                self.imageToSendToAPI = rotatedImg
                self.i = self.i+1
                self.sendImageToRekognition(celebImageData: data1)
            }
            
        }
        
        DispatchQueue.main.async {
            if features.count == 0 {
                self.printFaceLayer(layer: self.previewLayer!, faceObjects: [], cleanAperture: cleanAperture)
                
                if let shwDate = self.showDate, Date().timeIntervalSince(shwDate) < 8 {
                    return
                }
                
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: [.curveEaseInOut], animations: {
                    self.bottomContraintOfPreview.constant = 0
                    self.view.layoutIfNeeded()
                }, completion: { (isCompleted) in
                    
                })
            }else {
                
                self.printFaceLayer(layer: self.previewLayer!, faceObjects: features as? [CIFaceFeature] ?? [], cleanAperture: cleanAperture)
            }
        }
        
    }
    
    
    func convert(cmage:CIImage) -> UIImage
    {
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(cmage, from: cmage.extent)!
        let image:UIImage = UIImage.init(cgImage: cgImage)
        return image
    }
    
    func exifOrientation(orientation: UIDeviceOrientation) -> Int {
        switch orientation {
        case .portraitUpsideDown:
            return 8
        case .landscapeLeft:
            return 3
        case .landscapeRight:
            return 1
        default:
            return 6
        }
    }
    
    func videoBox(frameSize: CGSize, apertureSize: CGSize) -> CGRect {
        let apertureRatio = apertureSize.height / apertureSize.width
        let viewRatio = frameSize.width / frameSize.height
        
        var size = CGSize.zero
        
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width
            size.height = apertureSize.width * (frameSize.width / apertureSize.height)
        } else {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width)
            size.height = frameSize.height
        }
        
        var videoBox = CGRect(origin: .zero, size: size)
        
        if (size.width < frameSize.width) {
            videoBox.origin.x = (frameSize.width - size.width)
        } else {
            videoBox.origin.x = (size.width - frameSize.width)
        }
        
        if (size.height < frameSize.height) {
            videoBox.origin.y = (frameSize.height - size.height) / 2.0
        } else {
            videoBox.origin.y = (size.height - frameSize.height) / 2.0
        }
        
        return videoBox
    }
    func printFaceLayer(layer: CALayer, faceObjects: [CIFaceFeature],cleanAperture:CGRect) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        // hide all the face layers
        var faceLayers = [CALayer]()
        for layer: CALayer in layer.sublayers! {
            if layer.name == "face" {
                faceLayers.append(layer)
            }
        }
        for faceLayer in faceLayers {
            faceLayer.removeFromSuperlayer()
        }
        for faceObject in faceObjects {
            let featureLayer = CALayer()
            let faceFrame = self.calculateFaceRect(facePosition: faceObject.mouthPosition, faceBounds: faceObject.bounds, clearAperture: cleanAperture)
            featureLayer.frame = faceFrame
            featureLayer.borderColor = UIColor.init(red: 50/255, green: 152/255, blue: 218/255, alpha: 1.0).cgColor
            featureLayer.borderWidth = 3.0
            featureLayer.cornerRadius = 10
            featureLayer.masksToBounds = true
            featureLayer.name = "face"
            layer.addSublayer(featureLayer)
        }
        CATransaction.commit()
    }
    func calculateFaceRect(facePosition: CGPoint, faceBounds: CGRect, clearAperture: CGRect) -> CGRect {
        let parentFrameSize = previewLayer!.frame.size
        let previewBox = videoBox(frameSize: parentFrameSize, apertureSize: clearAperture.size)
        
        var faceRect = faceBounds
        
        swap(&faceRect.size.width, &faceRect.size.height)
        swap(&faceRect.origin.x, &faceRect.origin.y)
        
        let widthScaleBy = previewBox.size.width / clearAperture.size.height
        let heightScaleBy = previewBox.size.height / clearAperture.size.width
        
        faceRect.size.width *= widthScaleBy
        faceRect.size.height *= heightScaleBy
        faceRect.origin.x *= widthScaleBy
        faceRect.origin.y *= heightScaleBy
        
        faceRect = faceRect.offsetBy(dx: 0.0, dy: previewBox.origin.y)
        
        if let input = session?.inputs.first as? AVCaptureDeviceInput {
            if (input.device.position == .back) {
                let frame = CGRect(x: parentFrameSize.width - faceRect.origin.x, y: faceRect.origin.y, width: faceRect.width, height: faceRect.height)
                return frame

            } else {
                let frame = CGRect(x: parentFrameSize.width - faceRect.origin.x - faceRect.size.width / 2.0 - previewBox.origin.x, y: faceRect.origin.y, width: faceRect.width, height: faceRect.height)
                return frame
            }
        }
        return CGRect.zero
 
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




