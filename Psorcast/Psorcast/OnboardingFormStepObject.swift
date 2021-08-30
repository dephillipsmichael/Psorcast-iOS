//
//  OnboardingFormStepObject.swift
//  Psorcast
//
//  Copyright © 2021 Sage Bionetworks. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import Foundation
import AVFoundation
import UIKit
import BridgeApp
import BridgeAppUI

open class OnboardingFormStepObject: RSDFormUIStepObject, RSDStepViewControllerVendor {

    public func instantiateViewController(with parent: RSDPathComponent?) -> (UIViewController & RSDStepController)? {
        return OnboardingFormStepViewController(step: self, parent: parent)
    }
    
    open override class func defaultType() -> RSDStepType {
        return .onboardingForm
    }
    
    required public init(identifier: String, type: RSDStepType? = nil) {
        super.init(identifier: identifier, type: type)
    }
    
    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}

public class OnboardingFormStepViewController: RSDTableStepViewController {
    
    override open func cancel() {
        processCancel()
    }
    
    open func processCancel() {
        var actions: [UIAlertAction] = []
        
        // Always add a choice to discard the results.
        let discardResults = UIAlertAction(title: Localization.localizedString("BUTTON_OPTION_DISCARD"), style: .destructive) { (_) in
            self.cancelTask(shouldSave: false)
        }
        actions.append(discardResults)
        
        // Only add the option to save if the task controller supports it.
        if self.stepViewModel.rootPathComponent.canSaveTaskProgress() {
            let saveResults = UIAlertAction(title: Localization.localizedString("BUTTON_OPTION_SAVE"), style: .default) { (_) in
                self.cancelTask(shouldSave: true)
            }
            actions.append(saveResults)
        }
        
        // Always add a choice to keep going.
        let keepGoing = UIAlertAction(title: Localization.localizedString("BUTTON_OPTION_CONTINUE"), style: .cancel) { (_) in
            self.didNotCancel()
        }
        actions.append(keepGoing)
        
        self.presentAlertWithActions(title: nil, message: Localization.localizedString("CANCEL_CANT_SAVE_TEXT"), preferredStyle: .actionSheet, actions: actions)
    }
}
