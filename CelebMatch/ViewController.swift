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

class ViewController: UIViewController {

    @IBOutlet weak var celebFaceView:UIImageView!
    @IBOutlet weak var userFaceView:UIImageView!
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
extension ViewController: UIImagePickerControllerDelegate,UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        
        let cmeraImg = info[UIImagePickerControllerEditedImage] as? UIImage
        self.userFaceView.image = cmeraImg
        picker.dismiss(animated: true, completion: nil)
    }
}

