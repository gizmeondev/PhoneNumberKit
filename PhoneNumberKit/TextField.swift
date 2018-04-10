//
//  TextField.swift
//  PhoneNumberKit
//
//  Created by Roy Marmelstein on 07/11/2015.
//  Copyright © 2015 Roy Marmelstein. All rights reserved.
//

import Foundation
import UIKit

public protocol PhoneNumberTextFieldDelegate: class {
    func checkForValidPhoneNumber(isValid:Bool)
}

/// Custom text field that formats phone numbers
public class PhoneNumberTextField: UITextField, UITextFieldDelegate {
    
    let phoneNumberKit = PhoneNumberKit()
    open weak var myDelegate: PhoneNumberTextFieldDelegate?

    /// Override setText so number will be automatically formatted when setting text by code
    override open var text: String? {
        set {
            if newValue != nil {
                let formattedNumber = partialFormatter.formatPartial(newValue! as String)
                super.text = formattedNumber
            }
            else {
                super.text = newValue
            }
        }
        get {
            return super.text
        }
    }
    
    /// allows text to be set without formatting
    open func setTextUnformatted(newValue:String?) {
        super.text = newValue
    }
    
    /// Override region to set a custom region. Automatically uses the default region code.
    public var defaultRegion = PhoneNumberKit.defaultRegionCode() {
        didSet {
            partialFormatter.defaultRegion = defaultRegion
        }
    }
    
    public var withPrefix: Bool = true {
        didSet {
            partialFormatter.withPrefix = withPrefix
            if withPrefix == false {
                self.keyboardType = UIKeyboardType.numberPad
            }
            else {
                self.keyboardType = UIKeyboardType.phonePad
            }
        }
    }
    public var isPartialFormatterEnabled = true
    
    public var maxDigits: Int? {
        didSet {
            partialFormatter.maxDigits = maxDigits
        }
    }
    
    let partialFormatter: PartialFormatter
    
    let nonNumericSet: NSCharacterSet = {
        var mutableSet = NSMutableCharacterSet.decimalDigit().inverted
        mutableSet.remove(charactersIn: PhoneNumberConstants.plusChars)
        return mutableSet as NSCharacterSet
    }()
    
    weak private var _delegate: UITextFieldDelegate?
    
    override open var delegate: UITextFieldDelegate? {
        get {
            return _delegate
        }
        set {
            self._delegate = newValue
            supportObj.delegate = delegate
            super.delegate=supportObj
        }
    }
    
    //MARK: Status
    
    public var currentRegion: String {
        get {
            return partialFormatter.currentRegion
        }
    }
    
    public var nationalNumber: String {
        get {
            let rawNumber = self.text ?? String()
            return partialFormatter.nationalNumber(from: rawNumber)
        }
    }
    
    public var isValidNumber: Bool {
        get {
            let rawNumber = self.text ?? String()
            do {
                let _ = try phoneNumberKit.parse(rawNumber, withRegion: currentRegion)
                return true
            } catch {
                return false
            }
        }
    }
    
    public var currentCountryRegion = String()
    //MARK: Lifecycle
    
    /**
     Init with frame
     
     - parameter frame: UITextfield F
     
     - returns: UITextfield
     */
    override public init(frame:CGRect)
    {
        self.partialFormatter = PartialFormatter(phoneNumberKit: phoneNumberKit, defaultRegion: defaultRegion, withPrefix: withPrefix)
        super.init(frame:frame)
        self.setup()
    }
    
    /**
     Init with coder
     
     - parameter aDecoder: decoder
     
     - returns: UITextfield
     */
    required public init(coder aDecoder: NSCoder) {
        self.partialFormatter = PartialFormatter(phoneNumberKit: phoneNumberKit, defaultRegion: defaultRegion, withPrefix: withPrefix)
        super.init(coder: aDecoder)!
        self.setup()
    }
    
    func setup(){
        self.autocorrectionType = .no
        self.keyboardType = UIKeyboardType.phonePad
        super.delegate = self
        
        validateOnCharacterChanged = true
        isMandatory = true
        validateOnResign = true
        popUpColor = ColorPopUpBg
        strLengthValidationMsg = MsgValidateLength.copy() as! String
        
        supportObj.validateOnCharacterChanged = validateOnCharacterChanged
        supportObj.validateOnResign = validateOnResign
        let notify = NotificationCenter.default
        notify.addObserver(self, selector: #selector(PhoneNumberTextField.didHideKeyboard), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    
    // MARK: Phone number formatting
    
    /**
     *  To keep the cursor position, we find the character immediately after the cursor and count the number of times it repeats in the remaining string as this will remain constant in every kind of editing.
     */
    
    internal struct CursorPosition {
        let numberAfterCursor: String
        let repetitionCountFromEnd: Int
    }
    
    internal func extractCursorPosition() -> CursorPosition? {
        var repetitionCountFromEnd = 0
        // Check that there is text in the UITextField
        guard let text = text, let selectedTextRange = selectedTextRange else {
            return nil
        }
        let textAsNSString = text as NSString
        let cursorEnd = offset(from: beginningOfDocument, to: selectedTextRange.end)
        // Look for the next valid number after the cursor, when found return a CursorPosition struct
        for i in cursorEnd ..< textAsNSString.length  {
            let cursorRange = NSMakeRange(i, 1)
            let candidateNumberAfterCursor: NSString = textAsNSString.substring(with: cursorRange) as NSString
            if (candidateNumberAfterCursor.rangeOfCharacter(from: nonNumericSet as CharacterSet).location == NSNotFound) {
                for j in cursorRange.location ..< textAsNSString.length  {
                    let candidateCharacter = textAsNSString.substring(with: NSMakeRange(j, 1))
                    if candidateCharacter == candidateNumberAfterCursor as String {
                        repetitionCountFromEnd += 1
                    }
                }
                return CursorPosition(numberAfterCursor: candidateNumberAfterCursor as String, repetitionCountFromEnd: repetitionCountFromEnd)
            }
        }
        return nil
    }
    
    // Finds position of previous cursor in new formatted text
    internal func selectionRangeForNumberReplacement(textField: UITextField, formattedText: String) -> NSRange? {
        let textAsNSString = formattedText as NSString
        var countFromEnd = 0
        guard let cursorPosition = extractCursorPosition() else {
            return nil
        }
        
        for i in stride(from: (textAsNSString.length - 1), through: 0, by: -1) {
            let candidateRange = NSMakeRange(i, 1)
            let candidateCharacter = textAsNSString.substring(with: candidateRange)
            if candidateCharacter == cursorPosition.numberAfterCursor {
                countFromEnd += 1
                if countFromEnd == cursorPosition.repetitionCountFromEnd {
                    return candidateRange
                }
            }
        }
        
        return nil
    }
    
    open func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = text else {
            return false
        }
        
        // allow delegate to intervene
        guard _delegate?.textField?(textField, shouldChangeCharactersIn: range, replacementString: string) ?? true else {
            return false
        }
        guard isPartialFormatterEnabled else {
            return true
        }
        
        let textAsNSString = text as NSString
        let changedRange = textAsNSString.substring(with: range) as NSString
        let modifiedTextField = textAsNSString.replacingCharacters(in: range, with: string)
        
        let filteredCharacters = modifiedTextField.filter {
            return  String($0).rangeOfCharacter(from: (textField as! PhoneNumberTextField).nonNumericSet as CharacterSet) == nil
        }
        let rawNumberString = String(filteredCharacters)
        //print("rawNumberString:",rawNumberString)
        partialFormatter.defaultRegion = currentCountryRegion
        let formattedNationalNumber = partialFormatter.formatPartial(rawNumberString as String)
        //print("formattedNationalNumber:",formattedNationalNumber)
        do {
            
            let number = try phoneNumberKit.parse(rawNumberString, withRegion: currentCountryRegion, ignoreType: false)
            //phoneNumberKit.parse()
            print(number.notParsed())
            self.rightView=nil
            popUp?.removeFromSuperview()
            self.myDelegate?.checkForValidPhoneNumber(isValid:true)
        } catch {
            print("Phone number parsing error", error)
            popUp?.removeFromSuperview()
            showErrorIconForMsg("Invalid phone number.")
            self.myDelegate?.checkForValidPhoneNumber(isValid:false)

        }
       /* if rawNumberString == formattedNationalNumber
        {
            popUp?.removeFromSuperview()

            print("formattedNationalNumber:",formattedNationalNumber.count)
            let regexstring = String(format:"^.{0,%d}$",formattedNationalNumber.count)
            //self.addRegx(String(format:"^.{0,%@}$",formattedNationalNumber.count), withMsg: "Invalid phone number.")
            addRegx(regexstring, withMsg: "Invalid phone number.")
            (textField as! PhoneNumberTextField).perform(#selector(PhoneNumberTextField.validate), with: nil, afterDelay:0.1)

        }
        else
        {
            self.rightView=nil
            popUp?.removeFromSuperview()

        }*/
        var selectedTextRange: NSRange?
        
        let nonNumericRange = (changedRange.rangeOfCharacter(from: nonNumericSet as CharacterSet).location != NSNotFound)
        if (range.length == 1 && string.isEmpty && nonNumericRange)
        {
            selectedTextRange = selectionRangeForNumberReplacement(textField: textField, formattedText: modifiedTextField)
            textField.text = modifiedTextField
        }
        else {
            selectedTextRange = selectionRangeForNumberReplacement(textField: textField, formattedText: formattedNationalNumber)
            textField.text = formattedNationalNumber
        }
        sendActions(for: .editingChanged)
        if let selectedTextRange = selectedTextRange, let selectionRangePosition = textField.position(from: beginningOfDocument, offset: selectedTextRange.location) {
            let selectionRange = textField.textRange(from: selectionRangePosition, to: selectionRangePosition)
            textField.selectedTextRange = selectionRange
        }
        
        return false
    }
    
    //MARK: UITextfield Delegate
    
    open func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return _delegate?.textFieldShouldBeginEditing?(textField) ?? true
    }
    
    open func textFieldDidBeginEditing(_ textField: UITextField) {
        _delegate?.textFieldDidBeginEditing?(textField)
    }
    
    open func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return _delegate?.textFieldShouldEndEditing?(textField) ?? true
    }
    
    open func textFieldDidEndEditing(_ textField: UITextField) {
        _delegate?.textFieldDidEndEditing?(textField)
    }
    
    open func textFieldShouldClear(_ textField: UITextField) -> Bool {
        return _delegate?.textFieldShouldClear?(textField) ?? true
    }
    
    open func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return _delegate?.textFieldShouldReturn?(textField) ?? true
    }
    
    /*
     // Only override drawRect: if you perform custom drawing.
     // An empty implementation adversely affects performance during animation.
     override func drawRect(rect: CGRect) {
     // Drawing code
     }
     */
    override open func textRect(forBounds bounds: CGRect) -> CGRect
    {
        return bounds.insetBy(dx: 5, dy: 5)
    }
    
    override open func placeholderRect(forBounds bounds: CGRect) -> CGRect
    {
        return bounds.insetBy(dx: 5, dy: 5)
        
    }
    
    override open func editingRect(forBounds bounds: CGRect) -> CGRect
    {
        return bounds.insetBy(dx: 5, dy: 5)
        
    }
    
    var strLengthValidationMsg = ""
    var supportObj:TextFieldValidatorSupport = TextFieldValidatorSupport()
    var strMsg = ""
    var arrRegx:NSMutableArray = []
    var popUp :IQPopUp?
    
    @IBInspectable var isMandatory:Bool = true   /**< Default is YES*/
    
    @IBOutlet var presentInView:UIView?    /**< Assign view on which you want to show popup and it would be good if you provide controller's view*/
    
    @IBInspectable var popUpColor:UIColor?   /**< Assign popup background color, you can also assign default popup color from macro "ColorPopUpBg" at the top*/
    
    fileprivate var _validateOnCharacterChanged  = false
    @IBInspectable var validateOnCharacterChanged:Bool { /**< Default is YES, Use it whether you want to validate text on character change or not.*/
        
        get {
            return _validateOnCharacterChanged
        }
        set {
            supportObj.validateOnCharacterChanged = newValue
            _validateOnCharacterChanged = newValue
        }
    }
    
    fileprivate var _validateOnResign = false
    @IBInspectable var validateOnResign:Bool {
        get {
            return _validateOnResign
        }
        set {
            supportObj.validateOnResign = newValue
            _validateOnResign = newValue
        }
    }
    
    fileprivate var ColorPopUpBg = UIColor(red: 0.702, green: 0.000, blue: 0.000, alpha: 1.000)
    fileprivate var MsgValidateLength = NSLocalizedString("THIS_FIELD_CANNOT_BE_BLANK", comment: "This field can not be blank")
    
 /*   open override var delegate:UITextFieldDelegate? {
        didSet {
            supportObj.delegate = delegate
            super.delegate=supportObj
        }
    }*/
    
    open func addRegx(_ strRegx:String, withMsg msg:String) {
        let dic:NSDictionary = ["regx":strRegx, "msg":msg]
        arrRegx.add(dic)
    }
    
    open func updateLengthValidationMsg(_ msg:String){
        strLengthValidationMsg = msg
    }
    
    open func addConfirmValidationTo(_ txtConfirm:PhoneNumberTextField, withMsg msg:String) {
        let dic = [txtConfirm:"confirm", msg:"msg"] as [AnyHashable : String]
        arrRegx.add(dic)
    }
    
    @objc open func validate() -> Bool {
        if isMandatory {
            if self.text?.count == 0 {
                self.showErrorIconForMsg(strLengthValidationMsg)
                return false
            }
        }
        
        for i in 0 ..< arrRegx.count {
            
            let dic = arrRegx.object(at: i)
            
            if (dic as AnyObject).object(forKey: "confirm") != nil {
                let txtConfirm = (dic as AnyObject).object(forKey: "confirm") as! PhoneNumberTextField
                if txtConfirm.text != self.text {
                    self.showErrorIconForMsg((dic as AnyObject).object(forKey: "msg") as! String)
                    return false
                }
            } else if (dic as AnyObject).object(forKey: "regx") as! String != "" &&
                self.text?.count != 0 &&
                !self.validateString(self.text!, withRegex:(dic as AnyObject).object(forKey: "regx") as! String) {
                self.showErrorIconForMsg((dic as AnyObject).object(forKey: "msg") as! String)
                return false
            }
        }
        self.rightView=nil
        return true
    }
    
    open func dismissPopup() {
        self.rightView=nil
        popUp?.removeFromSuperview()
    }
    
    // MARK: Internal methods
    
    @objc func didHideKeyboard() {
        popUp?.removeFromSuperview()
    }
    
    @objc func tapOnError() {
        //self.showErrorWithMsg(strMsg)
        self.dismissPopup()
    }
    
    func validateString(_ stringToSearch:String, withRegex regexString:String) ->Bool {
        let regex = NSPredicate(format: "SELF MATCHES %@", regexString)
        return regex.evaluate(with: stringToSearch)
    }
    
    func showErrorIconForMsg(_ msg:String) {
        let btnError = UIButton(frame: CGRect(x: 0, y: 0, width: 25, height: 25))
        btnError.addTarget(self, action: #selector(PhoneNumberTextField.tapOnError), for: UIControlEvents.touchUpInside)
        btnError.setBackgroundImage(UIImage(named: "icon_error"), for: UIControlState())
        
        self.rightView = btnError
        self.rightViewMode = UITextFieldViewMode.always
        strMsg = msg
        self.showErrorWithMsg(strMsg)
    }
    
    func showErrorWithMsg(_ msg:String) {
        
        if (presentInView == nil) {
            
            //            [TSMessage showNotificationWithTitle:msg type:TSMessageNotificationTypeError]
            print("Should set `Present in view` for the UITextField")
            return
        }
        
        popUp = IQPopUp(frame: CGRect.zero)
        popUp!.strMsg = msg as NSString
        popUp!.popUpColor = popUpColor
        popUp!.showOnRect = self.convert(self.rightView!.frame, to: presentInView)
        
        popUp!.fieldFrame = self.superview?.convert(self.frame, to: presentInView)
        popUp!.backgroundColor = UIColor.clear
        
        presentInView!.addSubview(popUp!)
        
        popUp!.translatesAutoresizingMaskIntoConstraints = false
        let dict = ["v1":popUp!]
        
        popUp?.superview?.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[v1]-0-|", options: NSLayoutFormatOptions(), metrics: nil, views: dict))
        
        popUp?.superview?.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[v1]-0-|", options: NSLayoutFormatOptions(), metrics: nil, views: dict))
        
        supportObj.popUp=popUp
        
        
    }
    
}


//  -----------------------------------------------


class TextFieldValidatorSupport : NSObject, UITextFieldDelegate {
    
    var delegate:UITextFieldDelegate?
    var validateOnCharacterChanged: Bool = false
    var validateOnResign = false
    var popUp :IQPopUp?
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        /* if delegate!.responds(to: "textFieldShouldBeginEditing") {
         return delegate!.textFieldShouldBeginEditing!(textField)
         }
         */
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        
        /*  if delegate!.responds(to: "textFieldDidBeginEditing") {
         delegate!.textFieldDidEndEditing!(textField)
         }*/
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        
        /*  if delegate!.responds(to: "textFieldShouldEndEditing") {
         return delegate!.textFieldShouldEndEditing!(textField)
         }*/
        
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        
        /* if delegate!.responds(to: "textFieldDidEndEditing") {
         delegate?.textFieldDidEndEditing!(textField)
         
         }*/
        popUp?.removeFromSuperview()
        if validateOnResign {
            _ = (textField as! PhoneNumberTextField).validate()
        }
    }
    
    /*func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        (textField as! PhoneNumberTextField).dismissPopup()
        
        if validateOnCharacterChanged {
            
            (textField as! PhoneNumberTextField).perform(#selector(PhoneNumberTextField.validate), with: nil, afterDelay:0.1)
        }
        else {
            (textField as! PhoneNumberTextField).rightView = nil
        }
        
        if delegate!.responds(to: #selector(UITextFieldDelegate.textField(_:shouldChangeCharactersIn:replacementString:))) {
            return delegate!.textField!(textField, shouldChangeCharactersIn: range, replacementString: string)
        }
        return true
    }*/
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        
        /* if delegate!.responds(to: "textFieldShouldClear"){
         delegate?.textFieldShouldClear!(textField)
         }*/
        return true
        
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        /*  if delegate!.responds(to: "textFieldShouldReturn") {
         delegate?.textFieldShouldReturn!(textField)
         }*/
        return true
    }
}

//  -----------------------------------------------

class IQPopUp : UIView {
    
    var showOnRect:CGRect?
    var popWidth:Int = 0
    var fieldFrame:CGRect?
    var strMsg:NSString = ""
    var popUpColor:UIColor?
    var FontSize:CGFloat = 15
    
    var PaddingInErrorPopUp:CGFloat = 5
    var FontName = "Helvetica-Bold"
    
    let validator = PhoneNumberTextField().self
    override func draw(_ rect:CGRect) {
        let color = popUpColor!.cgColor.components
        
        UIGraphicsBeginImageContext(CGSize(width: 30, height: 20))
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setFillColor(red: (color?[0])!, green: (color?[1])!, blue: (color?[2])!, alpha: 1)
        ctx?.setShadow(offset: CGSize(width: 0, height: 0), blur: 7.0, color: UIColor.black.cgColor)
        let points = [ CGPoint(x: 15, y: 5), CGPoint(x: 25, y: 25), CGPoint(x: 5,y: 25)]
        ctx?.addLines(between: points)
        // CGContextAddLines(ctx, points, 3)
        ctx?.closePath()
        ctx?.fillPath()
        let viewImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        let imgframe = CGRect(x: (showOnRect!.origin.x + ((showOnRect!.size.width-30)/2)),
                              y: ((showOnRect!.size.height/2) + showOnRect!.origin.y)+30, width: 30, height: 13)
        
        let img = UIImageView(image: viewImage, highlightedImage: nil)
        
        self.addSubview(img)
        img.translatesAutoresizingMaskIntoConstraints = false
        var dict:Dictionary<String, AnyObject> = ["img":img]
        
        
        img.superview?.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: String(format:"H:|-%f-[img(%f)]", fieldFrame!.origin.x+fieldFrame!.size.width-imgframe.size.width+2, imgframe.size.width), options:NSLayoutFormatOptions(), metrics:nil, views:dict))
        img.superview?.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: String(format:"V:|-%f-[img(%f)]",imgframe.origin.y,imgframe.size.height), options:NSLayoutFormatOptions(),  metrics:nil, views:dict))
        
        let font = UIFont(name: FontName, size: FontSize)
        
        var size:CGSize = self.strMsg.boundingRect(with: CGSize(width: fieldFrame!.size.width - (PaddingInErrorPopUp*2), height: 1000), options: NSStringDrawingOptions.usesLineFragmentOrigin, attributes: [NSAttributedStringKey.font:font!], context: nil).size
        
        
        size = CGSize(width: ceil(size.width), height: ceil(size.height))
        
        
        let view = UIView(frame: CGRect.zero)
        self.insertSubview(view, belowSubview:img)
        view.backgroundColor=self.popUpColor
        view.layer.cornerRadius=5.0
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowRadius=5.0
        view.layer.shadowOpacity=1.0
        view.layer.shadowOffset=CGSize(width: 0, height: 0)
        view.translatesAutoresizingMaskIntoConstraints = false
        dict = ["view":view]
        
        view.superview?.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: String(format:"H:|-%f-[view(%f)]",fieldFrame!.origin.x+(fieldFrame!.size.width-(size.width + (PaddingInErrorPopUp*2))),size.width+(PaddingInErrorPopUp*2)), options:NSLayoutFormatOptions(), metrics:nil, views:dict))
        
        view.superview?.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: String(format:"V:|-%f-[view(%f)]",imgframe.origin.y+imgframe.size.height,size.height+(PaddingInErrorPopUp*2)), options:NSLayoutFormatOptions(),  metrics:nil, views:dict))
        
        let lbl = UILabel(frame: CGRect.zero)
        lbl.font = font
        lbl.numberOfLines=0
        lbl.backgroundColor = UIColor.clear
        lbl.text=self.strMsg as String
        lbl.textColor = UIColor.white
        view.addSubview(lbl)
        
        lbl.translatesAutoresizingMaskIntoConstraints = false
        dict = ["lbl":lbl]
        lbl.superview?.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: String(format:"H:|-%f-[lbl(%f)]", PaddingInErrorPopUp, size.width), options:NSLayoutFormatOptions() , metrics:nil, views:dict))
        lbl.superview?.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: String(format:"V:|-%f-[lbl(%f)]", PaddingInErrorPopUp,size.height), options:NSLayoutFormatOptions(), metrics:nil, views:dict))
        
        //        self.centerXAnchor.constraint(equalTo: (self.superview?.centerXAnchor)!).isActive = true
        
        
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        self.removeFromSuperview()
        return false
    }
}


