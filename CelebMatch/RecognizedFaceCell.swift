//
//  RecognizedFaceCell.swift
//  CelebMatch
//
//  Created by Dipak Singh on 1/15/19.
//  Copyright © 2019 TrialX. All rights reserved.
//

import UIKit
import AWSRekognition

class RecognizedFaceCell: UITableViewCell {

    @IBOutlet weak var lblRecognizedDesc:UILabel!
    @IBOutlet weak var btnKnowMore:UIButton!
    @IBOutlet weak var progressBar:UIProgressView!
    @IBOutlet weak var faceImgView:UIImageView!
    var faceData:AWSRekognitionCelebrity!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
