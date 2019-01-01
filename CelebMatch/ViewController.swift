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
import SafariServices
import AWSRekognition


class ViewController: UIViewController {

    @IBOutlet weak var userFaceView:UIImageView!
    var rekognitionObject:AWSRekognition?
    var infoLinksMap: [Int:String] = [1000:""]

    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func addPhotoClicked(_ sender:UIButton){
        
        let actionSheet = UIAlertController(title: "Choose Source", message: "", preferredStyle: .actionSheet)
        
        let photoAction = UIAlertAction(title: "Gallery", style: UIAlertActionStyle.default) { (action) in
            self.performGalleryFunction()
        }
        
        let camAction = UIAlertAction(title: "Camera", style: UIAlertActionStyle.default) { (action) in
            self.performCameraFunction()
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: nil)
        
        actionSheet.addAction(camAction)
        actionSheet.addAction(photoAction)
        actionSheet.addAction(cancelAction)
        
        self.present(actionSheet, animated: true, completion: nil)
        
    }
    
    func performCameraFunction(){
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
            imagePickerController.delegate = self
            self.present(imagePickerController, animated: true, completion: nil)
        } else {
            debugPrint("Cam unavail")
        }
    }
    
    
    func performGalleryFunction(){
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            break
        case .denied:
            showAlert(title: "Give access to photos", message: "",b1Title:"Go to Settings", onB1Click: {
                guard let settingsURL = URL(string: UIApplicationOpenSettingsURLString) else { return }
                if UIApplication.shared.canOpenURL(settingsURL){
                    UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
                }
            })
            break
        case .notDetermined:
            break
        case .restricted:
            break
        }
        
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            let imagePickerController = UIImagePickerController()
            imagePickerController.sourceType = .photoLibrary
            imagePickerController.allowsEditing = true
            imagePickerController.delegate = self
            self.present(imagePickerController, animated: true, completion: nil)
        } else {
            debugPrint("Photo Library unavail")
        }
    }
    //MARK: - AWS Methods
    func sendImageToRekognition(celebImageData: Data){
        
        //Delete older labels or buttons
        DispatchQueue.main.async {
            [weak self] in
            for subView in (self?.userFaceView.subviews)! {
                subView.removeFromSuperview()
            }
        }
        
        rekognitionObject = AWSRekognition.default()
        let celebImageAWS = AWSRekognitionImage()
        celebImageAWS?.bytes = celebImageData
        let celebRequest = AWSRekognitionRecognizeCelebritiesRequest()
        celebRequest?.image = celebImageAWS
        
        rekognitionObject?.recognizeCelebrities(celebRequest!){
            (result, error) in
            if error != nil{
                print(error!)
                return
            }
            
            //1. First we check if there are any celebrities in the response
            if ((result!.celebrityFaces?.count)! > 0){
                
                //2. Celebrities were found. Lets iterate through all of them
                for (index, celebFace) in result!.celebrityFaces!.enumerated(){
                    
                    //Check the confidence value returned by the API for each celebirty identified
                    if(celebFace.matchConfidence!.intValue > 50){ //Adjust the confidence value to whatever you are comfortable with
                        
                        //We are confident this is celebrity. Lets point them out in the image using the main thread
                        DispatchQueue.main.async {
                            [weak self] in
                            
                            //Create an instance of Celebrity. This class is availabe with the starter application you downloaded
                            let celebrityInImage = Celebrity()
                            
                            celebrityInImage.scene = (self?.userFaceView)!
                            
                            //Get the coordinates for where this celebrity face is in the image and pass them to the Celebrity instance
                            celebrityInImage.boundingBox = ["height":celebFace.face?.boundingBox?.height, "left":celebFace.face?.boundingBox?.left, "top":celebFace.face?.boundingBox?.top, "width":celebFace.face?.boundingBox?.width] as! [String : CGFloat]
                            
                            //Get the celebrity name and pass it along
                            celebrityInImage.name = celebFace.name!
                            //Get the first url returned by the API for this celebrity. This is going to be an IMDb profile link
                            if (celebFace.urls!.count > 0){
                                celebrityInImage.infoLink = celebFace.urls![0]
                            }
                                //If there are no links direct them to IMDB search page
                            else{
                                celebrityInImage.infoLink = "https://www.imdb.com/search/name-text?bio="+celebrityInImage.name
                            }
                            //Update the celebrity links map that we will use next to create buttons
                            self?.infoLinksMap[index] = "https://"+celebFace.urls![0]
                            
                            //Create a button that will take users to the IMDb link when tapped
                            let infoButton:UIButton = celebrityInImage.createInfoButton()
                            infoButton.tag = index
                            infoButton.addTarget(self, action: #selector(self?.handleTap), for: UIControlEvents.touchUpInside)
                            self?.userFaceView.addSubview(infoButton)
                        }
                    }
                    
                }
            }
                //If there were no celebrities in the image, lets check if there were any faces (who, granted, could one day become celebrities)
            else if ((result!.unrecognizedFaces?.count)! > 0){
                //Faces are present. Point them out in the Image (left as an exercise for the reader)
                /**/
                self.showAlert(title: "No Celeb Found", message: "There is no matching found for the respective image", onB1Click: {
                    
                })
            }
            else{
                //No faces were found (presumably no people were found either)
                print("No faces in this pic")
            }
        }
        
    }
    @objc func handleTap(sender:UIButton){
        print("tap recognized")
        let celebURL = URL(string: self.infoLinksMap[sender.tag]!)
        let safariController = SFSafariViewController(url: celebURL!)
        safariController.delegate = self
        self.present(safariController, animated:true)
    }
}
extension UIViewController:SFSafariViewControllerDelegate {
    
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
extension ViewController:AVCapturePhotoCaptureDelegate{
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {
        
    }
    
}

extension ViewController: UIImagePickerControllerDelegate,UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        
        let cmeraImg = info[UIImagePickerControllerEditedImage] as? UIImage
        self.userFaceView.image = cmeraImg
        
        let celebImage:Data = UIImageJPEGRepresentation(cmeraImg!, 0.2)!
        
        //Demo Line
        sendImageToRekognition(celebImageData: celebImage)

        picker.dismiss(animated: true, completion: nil)
    }
}

