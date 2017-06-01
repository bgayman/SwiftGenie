//
//  ViewController.swift
//  GenieEffect
//
//  Created by App Partner on 5/31/17.
//  Copyright © 2017 App Partner. All rights reserved.
//

import UIKit

class ViewController: UIViewController
{
    
    @IBOutlet var buttons: [UIButton]!
    @IBOutlet weak var boundingBox: UIView!
    @IBOutlet weak var durationSlider: UISlider!
    @IBOutlet weak var draggedView: UIView!
    var viewIsIn = false

    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        //draggedView.center = view.center
        draggedView.layer.cornerRadius = 15.0
    }
    
    func genie(to rect: CGRect, edge: RectEdge)
    {
        let duration = TimeInterval(self.durationSlider.value)
        let endRect = rect.insetBy(dx: 5.0, dy: 5.0)
        
        buttons.forEach { $0.isEnabled = false }
        if viewIsIn
        {
            self.draggedView.genieOutTransition(duration: duration, startRect: endRect, startEdge: edge)
            { [unowned self] in
                self.draggedView.isUserInteractionEnabled = true
                self.buttons.forEach { $0.isEnabled = true }
            }
        }
        else
        {
            draggedView.isUserInteractionEnabled = false
            draggedView.genieInTransition(duration: duration, destinationRect: endRect, destinationEdge: edge)
            { [unowned self] in
                self.buttons.forEach { $0.isEnabled = true }
            }
        }
        viewIsIn = !viewIsIn
    }
    
    @IBAction func bottomButtonTapped(_ sender: UIButton)
    {
        genie(to: sender.frame, edge: .bottom)
    }
    
    @IBAction func rightButtonTapped(_ sender: UIButton)
    {
        genie(to: sender.frame, edge: .right)
    }
    
    @IBAction func topButtonTapped(_ sender: UIButton)
    {
        genie(to: sender.frame, edge: .top)
    }
    
    @IBAction func leftButtonTapped(_ sender: UIButton)
    {
        genie(to: sender.frame, edge: .left)
    }
    
    @IBAction func pan(_ sender: UIPanGestureRecognizer)
    {
        guard !viewIsIn else { return }
        let translation = sender.translation(in: self.view)
        let bbFrame = boundingBox.frame
        var frame = draggedView.frame
        
        frame.origin.x += translation.x
        frame.origin.y += translation.y
        
        frame.origin.x = max(bbFrame.minX, min(frame.origin.x, bbFrame.maxX - frame.width))
        frame.origin.y = max(bbFrame.minY, min(frame.origin.y, bbFrame.maxY - frame.height))
        
        draggedView.frame = frame
        sender.setTranslation(.zero, in: view)
    }
}

