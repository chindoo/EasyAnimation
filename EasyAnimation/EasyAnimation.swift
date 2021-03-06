//
//  EasyAnimation.swift
//
//  Created by Marin Todorov on 4/11/15.
//  Copyright (c) 2015 Underplot ltd. All rights reserved.
//
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import UIKit
import ObjectiveC

// MARK: EA private structures

private struct PendingAnimation {
    let layer: CALayer
    let keyPath: String
    let fromValue: AnyObject
}

private class AnimationContext {
    var duration: NSTimeInterval = 1.0
    var delay: NSTimeInterval = 0.0
    var options: UIViewAnimationOptions? = nil
    var pendingAnimations = [PendingAnimation]()
    
    //spring additions
    var springDamping: CGFloat = 0.0
    var springVelocity: CGFloat = 0.0
}

private var didEAInitialize = false
private var didEAForLayersInitialize = false
private var activeAnimationContexts = [AnimationContext]()

// MARK: animatable properties

private let vanillaLayerKeys = [
    "anchorPoint", "backgroundColor", "borderColor", "borderWidth", "bounds",
    "contentsRect", "cornerRadius",
    "opacity", "position",
    "shadowColor", "shadowOffset", "shadowOpacity", "shadowRadius",
    "sublayerTransform", "transform", "zPosition"
]

private let specializedLayerKeys: [String: [String]] = [
    CAEmitterLayer.self.description(): ["emitterPosition", "emitterZPosition", "emitterSize", "spin", "velocity", "birthRate", "lifetime"],
    CAGradientLayer.self.description(): ["colors", "locations", "endPoint", "startPoint"],
    CAReplicatorLayer.self.description(): ["instanceDelay", "instanceTransform", "instanceColor", "instanceRedOffset", "instanceGreenOffset", "instanceBlueOffset", "instanceAlphaOffset"],
    CAShapeLayer.self.description(): ["path", "fillColor", "lineDashPhase", "lineWidth", "miterLimit", "strokeColor", "strokeStart", "strokeEnd"],
    CATextLayer.self.description(): ["fontSize", "foregroundColor"]
]

/**
    A `UIView` extension that adds super powers to animateWithDuration:animations: and the like.
    Check the README for code examples of what features this extension adds.
*/

extension UIView {
    
    public var animationPath: CGPath? {
        get {
            return nil
        }
        set {
            //TODO: add keyframe path animation
        }
    }
    
    // MARK: setup UIView
    
    override public static func initialize() {
        if !didEAInitialize {
            replaceAnimationMethods()
            didEAInitialize = true
        }
    }
    
    private static func replaceAnimationMethods() {
        //replace actionForLayer...
        method_exchangeImplementations(
            class_getInstanceMethod(self, "actionForLayer:forKey:"),
            class_getInstanceMethod(self, "EA_actionForLayer:forKey:"))
        
        //replace animateWithDuration...
        method_exchangeImplementations(
            class_getClassMethod(self, "animateWithDuration:animations:"),
            class_getClassMethod(self, "EA_animateWithDuration:animations:"))
        method_exchangeImplementations(
            class_getClassMethod(self, "animateWithDuration:animations:completion:"),
            class_getClassMethod(self, "EA_animateWithDuration:animations:completion:"))
        method_exchangeImplementations(
            class_getClassMethod(self, "animateWithDuration:delay:options:animations:completion:"),
            class_getClassMethod(self, "EA_animateWithDuration:delay:options:animations:completion:"))
        method_exchangeImplementations(
            class_getClassMethod(self, "animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:"),
            class_getClassMethod(self, "EA_animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:"))
        
    }
    
    // MARK: actionForLayer:forKey: replacement
    
    func EA_actionForLayer(layer: CALayer!, forKey key: String!) -> CAAction! {

        let result = EA_actionForLayer(layer, forKey: key)
        
        if activeAnimationContexts.count > 0 {
            if let result = result as? NSNull {
                
                if contains(vanillaLayerKeys, key) ||
                    (specializedLayerKeys[layer.classForCoder.description()] != nil && contains(specializedLayerKeys[layer.classForCoder.description()]!, key)) {
                    
                        //found an animatable property - add the pending animation
                        activeAnimationContexts.last!.pendingAnimations.append(
                            PendingAnimation(layer: layer, keyPath: key, fromValue: layer.valueForKey(key)!
                        )
                    )
                }
            }
        }
        
        return result
    }

    // MARK: animateWithDuration replacements...
    
    class func EA_animateWithDuration(duration: NSTimeInterval, delay: NSTimeInterval, usingSpringWithDamping dampingRatio: CGFloat, initialSpringVelocity velocity: CGFloat, options: UIViewAnimationOptions, animations: () -> Void, completion: ((Bool) -> Void)?) {
        //create context
        let context = AnimationContext()
        context.duration = duration
        context.delay = CACurrentMediaTime() + delay
        context.options = options
        context.springDamping = dampingRatio
        context.springVelocity = velocity
        
        //push context
        activeAnimationContexts.append(context)
        
        //enable layer actions
        CATransaction.begin()
        CATransaction.setDisableActions(false)
        
        //spring animations
        EA_animateWithDuration(duration, delay: delay, usingSpringWithDamping: dampingRatio, initialSpringVelocity: velocity, options: options, animations: animations, completion: completion)
        
        //pop context
        activeAnimationContexts.removeLast()
        
        //run pending animations
        for anim in context.pendingAnimations {
            anim.layer.addAnimation(EA_animation(anim, context: context), forKey: nil)
        }
        
        CATransaction.commit()
    }
    
    class func EA_animateWithDuration(duration: NSTimeInterval, delay: NSTimeInterval, options: UIViewAnimationOptions, animations: () -> Void, completion: ((Bool) -> Void)?) {

        //create context
        let context = AnimationContext()
        context.duration = duration
        context.delay = CACurrentMediaTime() + delay
        context.options = options
        
        //push context
        activeAnimationContexts.append(context)
        
        //enable layer actions
        CATransaction.begin()
        CATransaction.setDisableActions(false)
        
        //animations
        EA_animateWithDuration(duration, delay: delay, options: options, animations: animations, completion: completion)
        
        //pop context
        activeAnimationContexts.removeLast()
        
        //run pending animations
        for anim in context.pendingAnimations {
            anim.layer.addAnimation(EA_animation(anim, context: context), forKey: nil)
        }
        
        CATransaction.commit()
    }
    
    class func EA_animateWithDuration(duration: NSTimeInterval, animations: () -> Void, completion: ((Bool) -> Void)?) {
        animateWithDuration(duration, delay: 0.0, options: nil, animations: animations, completion: completion)
    }
    
    class func EA_animateWithDuration(duration: NSTimeInterval, animations: () -> Void) {
        animateWithDuration(duration, animations: animations, completion: nil)
    }
    
    // MARK: create CA animation
    
    private class func EA_animation(pending: PendingAnimation, context: AnimationContext) -> CAAnimation {
        
        let anim: CAAnimation
        
        if (context.springDamping > 0.0) {
            //create a layer spring animation
            anim = RBBSpringAnimation(keyPath: pending.keyPath)
            if let anim = anim as? RBBSpringAnimation {
                
                anim.from = pending.fromValue
                anim.to = pending.layer.valueForKey(pending.keyPath)

                //TODO: refine the spring animation setup
                //lotta magic numbers to mimic UIKit springs
                let epsilon = 0.001
                anim.damping = -2.0 * log(epsilon) / context.duration
                anim.stiffness = Double(pow(anim.damping, 2)) / Double(pow(context.springDamping * 2, 2))
                anim.mass = 1.0
                anim.velocity = 0.0

                //NSLog("mass: %.2f", anim.mass)
                //NSLog("damping: %.2f", anim.damping)
                //NSLog("velocity: %.2f", anim.velocity)
                //NSLog("stiffness: %.2f", anim.stiffness)
            }
        } else {
            //create property animation
            anim = CABasicAnimation(keyPath: pending.keyPath)
            (anim as! CABasicAnimation).fromValue = pending.fromValue
            (anim as! CABasicAnimation).toValue = pending.layer.valueForKey(pending.keyPath)
        }
        
        anim.duration = context.duration

        if context.delay > 0 {
            anim.beginTime = context.delay
            anim.fillMode = kCAFillModeBackwards
        }
        
        //options
        if let options = context.options?.rawValue {
            
            anim.autoreverses = (options & UIViewAnimationOptions.Autoreverse.rawValue != 0)
            if options & UIViewAnimationOptions.Repeat.rawValue != 0 {
                anim.repeatCount = Float.infinity
            }
            
            //easing
            var timingFunctionName = kCAMediaTimingFunctionEaseInEaseOut

            if options & UIViewAnimationOptions.CurveLinear.rawValue == UIViewAnimationOptions.CurveLinear.rawValue {
                //first check for linear (so it takes up only 2 bits)
                timingFunctionName = kCAMediaTimingFunctionLinear
            } else if options & UIViewAnimationOptions.CurveEaseIn.rawValue == UIViewAnimationOptions.CurveEaseIn.rawValue {
                timingFunctionName = kCAMediaTimingFunctionEaseIn
            } else if options & UIViewAnimationOptions.CurveEaseOut.rawValue == UIViewAnimationOptions.CurveEaseOut.rawValue {
                timingFunctionName = kCAMediaTimingFunctionEaseOut
            }

            anim.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        }
        
        return anim
    }
    
    // MARK: chain animations
    
    /**
        Creates and runs an animation which allows other animations to be chained to it and to each other.

        :param: duration The animation duration in seconds
        :param: delay The delay before the animation starts
        :param: options A UIViewAnimationOptions bitmask (check UIView.animationWithDuration:delay:options:animations:completion: for more info)
        :param: animations Animation closure
        :param: completion Completion closure of type (Bool)->Void
    
        :returns: The created request.
    */
    public class func animateAndChainWithDuration(duration: NSTimeInterval, delay: NSTimeInterval, options: UIViewAnimationOptions, animations: () -> Void, completion: ((Bool) -> Void)?) -> EAAnimationDelayed {
        
        let currentAnimation = EAAnimationDelayed()
        currentAnimation.duration = duration
        currentAnimation.delay = delay
        currentAnimation.options = options
        currentAnimation.animations = animations
        currentAnimation.completion = completion
        
        currentAnimation.nextDelayedAnimation = EAAnimationDelayed()
        currentAnimation.nextDelayedAnimation!.prevDelayedAnimation = currentAnimation
        currentAnimation.run()
        
        EAAnimationDelayed.animations.append(currentAnimation)
        
        return currentAnimation.nextDelayedAnimation!
    }
}

extension CALayer {
    // MARK: setup CALayer
    
    override public static func initialize() {
        super.initialize()
        
        if !didEAForLayersInitialize {
            replaceAnimationMethods()
            didEAForLayersInitialize = true
        }
    }
    
    private static func replaceAnimationMethods() {
        //replace actionForKey
        method_exchangeImplementations(
            class_getInstanceMethod(self, "actionForKey:"),
            class_getInstanceMethod(self, "EA_actionForKey:"))
    }
    
    public func EA_actionForKey(key: String!) -> CAAction! {
        
        //check if the layer has a view-delegate
        if let delegate = delegate as? UIView {
            return EA_actionForKey(key) // -> this passes the ball to UIView.actionForLayer:forKey:
        }
        
        //create a custom easy animation and add it to the animation stack
        if activeAnimationContexts.count > 0 {
            
            if contains(vanillaLayerKeys, key) ||
                (specializedLayerKeys[self.classForCoder.description()] != nil && contains(specializedLayerKeys[self.classForCoder.description()]!, key)) {
                    
                    //found an animatable property - add the pending animation
                    activeAnimationContexts.last!.pendingAnimations.append(
                        PendingAnimation(layer: self, keyPath: key, fromValue: self.valueForKey(key)!
                        )
                    )
            }
        }

        return nil
    }
}
