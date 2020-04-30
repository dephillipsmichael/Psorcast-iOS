//
//  ImageReportManager.swift
//  Psorcast
//
//  Copyright © 2019 Sage Bionetworks. All rights reserved.
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
import BridgeApp
import Research
import MotorControl

/// Subclass the schedule manager to set up a predicate to filter the schedules.
open class ImageReportManager : SBAReportManager {
    
    /// List of keys used in the notifications sent by this manager.
    public enum NotificationKey : String {
        case videoUrl
    }
    
    /// Notification name posted by the `ImageReportManager` before the manager will send an update
    /// the url of the new video that was just created
    public static let newVideoCreated = Notification.Name(rawValue: "newVideoCreated")
    
    /// The shared access to the video report manager
    public static let shared = ImageReportManager()
    
    // The date formatter for storing image files
    public let dateFormatter = StudyProfileManager.profileDateFormatter()
    
    /// Where we store the images
    public let storageDir = FileManager.SearchPathDirectory.documentDirectory
    
    // The tasks that are currently operating
    public var videoCreatorTasks = [VideoCreator.Task]()
    
    // The path extension for image files
    public let imagePathExtension = "jpg"
    public let videoPathExtension = "mp4"
    public let fileNameSeperator = "_"
    
    fileprivate let summaryImagesIdentifiers = [
        "summary",
        "psorasisAreaPhoto",
        "summaryImage",
    ]

    public func processTaskResult(_ taskController: RSDTaskController, profileManager: StudyProfileManager?) {
        
        let taskIdentifier = taskController.task.identifier
        let result = taskController.taskViewModel.taskResult
        
        // Filter through all the results and find the image results we care about
        let summaryImageResult =
            result.stepHistory.filter({ $0 is RSDFileResult })
                .map({ $0 as? RSDFileResult })
                .filter({
                    summaryImagesIdentifiers.contains($0?.identifier ?? "") &&
                    $0?.contentType == "image/jpeg" }).first as? RSDFileResult
        
        guard let summaryImageUrl = summaryImageResult?.url else {
            return
        }
        
        // Create the image filename from
        let imageCreatedOnDateStr = self.dateFormatter.string(from: Date())
        let imageFileName = "\(taskIdentifier)\(fileNameSeperator)\(imageCreatedOnDateStr)"
        
        // Copy new video frames into the documents directory
        // Copy the result file url into a the local cache so it persists upload complete
        if FileManager.default.copyFile(at: summaryImageUrl, to: storageDir, filename: "\(imageFileName).\(imagePathExtension)") {
            // We should re-export the most recent treatment task video if we have a new frame
            self.recreateCurrentTreatmentVideo(for: taskIdentifier, using: profileManager)
        } else { // Not successful
            debugPrint("Error copying file from \(summaryImageUrl.absoluteURL)" +
                "to \(storageDir) with filename \(imageFileName)")
        }
    }
    
    public func createCurrentTreatmentVideo(for taskIdentifier: String, using profileManager: StudyProfileManager?) {
        
        guard let treatmentStartDate = profileManager?.treatmentsDate,
            let videoFilename = self.videoFilename(for: taskIdentifier, using: profileManager) else {
            return
        }
        
        // First let's check if the video has already been created
        if let existingVideo = self.findVideoUrl(for: taskIdentifier, with: treatmentStartDate) {
            debugPrint("Video is already created, do not start again")
            self.postNotification(url: existingVideo)
            return
        }
        
        // Check if it is in the process of being created
        if self.videoCreatorTasks.filter({ $0.settings.videoFilename == videoFilename }).count > 0 {
            debugPrint("Video is already being created, do not start it again")
            return
        }
        
        // Otherwise we need to re-create it
        self.recreateCurrentTreatmentVideo(for: taskIdentifier, using: profileManager)
    }
    
    fileprivate func recreateCurrentTreatmentVideo(for taskIdentifier: String, using profileManager: StudyProfileManager?) {
        guard let videoFilename = self.videoFilename(for: taskIdentifier, using: profileManager) else { return }
                
        // Cancel all identical tasks that would have different frames
        self.cancelVideoCreatorTask(videoFileName: videoFilename)
        
        let renderSettings = self.createRenderSettings(videoFilename: videoFilename)
        let task = VideoCreator.Task(renderSettings: renderSettings)
                
        // Create the new video in the background
        guard let currentTreatment = profileManager?.allTreatmentRanges.last else { return }
        let currentRange = ClosedRange<Date>(uncheckedBounds: (currentTreatment.startDate,  currentTreatment.endDate ?? Date()))
        let frames = self.findFrames(for: taskIdentifier, within: currentRange)
        task.frames = frames
        
        let startTime = Date().timeIntervalSince1970
        task.render() {
            if let url = renderSettings.outputURL {
                let endTime = Date().timeIntervalSince1970
                debugPrint("Video Render took \(endTime - startTime)ms")
                self.videoCreatorTasks.removeAll(where: { $0.settings.videoFilename == renderSettings.videoFilename })
                self.postNotification(url: url)
            }
        }
    }
    
    /// Notify about a completed video
    fileprivate func postNotification(url: URL) {
        NotificationCenter.default.post(name: ImageReportManager.newVideoCreated,
                                        object: self,
                                        userInfo: [NotificationKey.videoUrl : url])
    }
    
    func findFrames(for taskIdentifier: String, within: ClosedRange<Date>) -> [VideoCreator.RenderFrameUrl] {
        var frames = [VideoCreator.RenderFrameUrl]()
        
        var allPossibleImageFiles = FileManager.default.urls(for: storageDir)?
            .filter({ $0.pathExtension == imagePathExtension }) ?? []
        
        // Sort the files by oldest first
        allPossibleImageFiles = allPossibleImageFiles.sorted(by: { (url1, url2) -> Bool in
            guard let date1 = self.filenameComponents(url1.lastPathComponent)?.date,
                let date2 = self.filenameComponents(url2.lastPathComponent)?.date else {
                return false
            }
            return date1 < date2
        })
        
        for imageFile in allPossibleImageFiles {
            let filename = imageFile.lastPathComponent
            if let components = self.filenameComponents(filename),
                taskIdentifier == components.taskId,
                within.contains(components.date) {
                let dateStr = dateFormatter.string(from: components.date)
                frames.append(VideoCreator.RenderFrameUrl(url: imageFile, text: dateStr))
            }
        }
        
        return frames
    }
    
    func findVideoUrl(for taskIdentifier: String, with treatmentStartDate: Date) -> URL? {
        let allPossibleVideoFiles = FileManager.default.urls(for: storageDir)?
            .filter({ $0.pathExtension == videoPathExtension }) ?? []
        
        for videoFile in allPossibleVideoFiles {
            let filename = videoFile.lastPathComponent
            if let components = self.filenameComponents(filename),
                taskIdentifier == components.taskId,
                treatmentStartDate == components.date {
                return videoFile
            }
        }
        
        return nil
    }
    
    func filenameComponents(_ filename: String) -> (taskId: String, date: Date)? {
        let separators = CharacterSet(charactersIn: fileNameSeperator)
        let parts = filename
            .replacingOccurrences(of: ".\(imagePathExtension)", with: "")
            .replacingOccurrences(of: ".\(videoPathExtension)", with: "")
            .components(separatedBy: separators)
        
        guard let taskId = parts.first,
            taskId.count > 0 else {
            return nil
        }
        
        guard let dateStr = parts.last,
            let date = dateFormatter.date(from: dateStr) else {
            return nil
        }
        
        return (taskId, date)
    }
    
    open func createRenderSettings(videoFilename: String) -> VideoCreator.RenderSettings {
        var settings = VideoCreator.RenderSettings()
        settings.fileDirectory = storageDir
        settings.videoFilename = videoFilename
        settings.videoFilenameExt = ".\(videoPathExtension)"
        
        settings.fps = 30
        settings.numOfFramesPerImage = 30
        settings.numOfFramesPerTransition = 10
        settings.transition = .crossFade
        return settings
    }
    
    fileprivate func videoFilename(for taskIdentifier: String, using profileManager: StudyProfileManager?) -> String? {
        guard let treatmentStartDate = profileManager?.treatmentsDate else {
            debugPrint("ERROR: Cannot create video filename without valid profile treatment data")
            return nil
        }
        let treatmentStartDateStr = dateFormatter.string(from: treatmentStartDate)
        return "\(taskIdentifier)\(fileNameSeperator)\(treatmentStartDateStr)"
    }
    
    public func cancelVideoCreatorTask(videoFileName: String) {
        let tasksToCancel = Array(self.videoCreatorTasks.filter({ $0.settings.videoFilename == videoFileName }))
        
        for task in tasksToCancel {
            task.cancelRender()
        }
        
        self.videoCreatorTasks.removeAll(where: { $0.settings.videoFilename == videoFileName })
    }
    
    fileprivate func url(for videoFilename: String) {
        
    }
}
