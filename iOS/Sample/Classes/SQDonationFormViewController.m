//
// Copyright 2011 Square Inc.
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
// http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "SQDonationFormViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "SQDonation.h"
#import "SQMoney.h"
#import "SQDonationConfirmationViewController.h"

static NSArray *stateNameArray = nil;
static NSDictionary *stateDictionary = nil;

@interface SQDonationFormViewController ()

@property (nonatomic, retain) NSArray *formTextFields;
@property (nonatomic, retain) UIPickerView *statePicker;

- (void)_loadFormValuesFromModel;
- (void)_saveFormValuesToModel;

- (void)_validateFields;
- (BOOL)_fieldsValid;

- (void)_scootToField:(UITextField *)textField animated:(BOOL)animated;

- (void)_releaseOutlets;

- (void)_registerForKeyboardNotifications;
- (void)_removeKeyboardObservers;

@end

@implementation SQDonationFormViewController

@synthesize scrollView;
@synthesize formView;
@synthesize legaleseView;

@synthesize donationAmount;
@synthesize name;
@synthesize email;
@synthesize street;
@synthesize city;
@synthesize state;
@synthesize zip;
@synthesize employer;
@synthesize occupation;

@synthesize contributeButton;

@synthesize formTextFields;
@synthesize statePicker;

#pragma mark - Initialization

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    return [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
}

- (void)dealloc
{
    [self _removeKeyboardObservers];
    [self _releaseOutlets];
    
    [super dealloc];
}

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if (!stateDictionary) {
        stateDictionary = [[NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"UnitedStates" ofType:@"plist"]] retain];
        stateNameArray = [[stateDictionary.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] retain];
    }
    
    if (!self.statePicker) {
        self.statePicker = [[[UIPickerView alloc] init] autorelease];
        self.statePicker.delegate = self;
        self.statePicker.dataSource = self;
        self.statePicker.showsSelectionIndicator = YES;
        
        self.state.inputView = self.statePicker;
    }
    
    self.navigationItem.title = NSLocalizedString(@"Donate", @"Donate view title");
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    
    self.scrollView.contentSize = self.formView.bounds.size;
    
    // Don't scale the background texture on 2x screens.
    UIImage *patternImage = [UIImage imageNamed:@"Background.png"];
    patternImage = [UIImage imageWithCGImage:[patternImage CGImage] scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
    self.scrollView.backgroundColor = [UIColor colorWithPatternImage:patternImage];
    
    self.formTextFields = [NSArray arrayWithObjects:donationAmount, name, email, street, city, state, zip, employer, occupation, nil];
        
    for (UITextField *formTextField in self.formTextFields) {
        formTextField.borderStyle = UITextBorderStyleRoundedRect;        
    }
    
    self.legaleseView.layer.cornerRadius = 6.0f;
    
    [self _loadFormValuesFromModel];    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    [self _registerForKeyboardNotifications];
    
    [self _loadFormValuesFromModel];
    
    if ([[SQDonation donation].amount isZero]) {
        // If we are about to display with a zero donation amount, treat this as a clean form--
        // scroll up to to show the logo, resign all first responders to drop the keyboard.
        for (UITextField *textField in self.formTextFields) {
            [textField resignFirstResponder];
        }
        
        self.scrollView.contentOffset = CGPointZero;
        
        // Unsatisfying, but at this point a keyboard might be left over from a previous run
        // and there will be no keyboard drop notification from the resigns we just did.
        // Since we're resigning them all anyway, just set our contentInset back to 0.
        UIEdgeInsets contentInsets = UIEdgeInsetsZero;
        scrollView.contentInset = contentInsets;
        scrollView.scrollIndicatorInsets = contentInsets;
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self _removeKeyboardObservers];
}

- (void)viewDidUnload
{
    [self _saveFormValuesToModel];
    [self _releaseOutlets];
    
    [super viewDidUnload];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    if (textField != self.donationAmount && textField != self.state) {
        // Allow free edits to all fields other than the donation amount (which we'll handle ourselves here) or state, which we'll allow only through the picker.
        return YES;
    } else {
        SQMoney *amount = [SQDonation donation].amount;
        NSString *amountString = [amount cents];
        
        // We only want to accept whole dollars, so knock off the 00 cents from the end of the string while we add or cut from it.
        if ([amountString hasSuffix:@"00"]) {
            amountString = [amountString substringToIndex:([amountString length] - 2)];
        }
        
        if (string.length == 1) {
            // Someone typed a digit, append that to the number of cents and stuff it back in.
            amountString = [amountString stringByAppendingString:string];
        }
        
        if (string.length == 0) {
            // Someone wants to remove a digit, kill the last digit of the cents and stuff it back in.
            amountString = [amountString substringToIndex:[amountString length] - 1];
        }
        
        // Promote to dollars.
        amountString = [amountString stringByAppendingString:@"00"];
        amount = [SQMoney moneyWithCents:amountString currency:[SQMoney defaultCurrency]];
        
        // Save back the amount to the model immediately.
        [SQDonation donation].amount = amount;
        self.donationAmount.text = [amount displayValue];
        
        return NO;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    NSInteger nextTag = textField.tag + 1;
    UIResponder *nextResponder = [textField.superview viewWithTag:nextTag];
    
    if (nextResponder) {
        [nextResponder becomeFirstResponder];
    } else if ([self _fieldsValid]) {
        [self continue:self];
    } else {
        [textField resignFirstResponder];
    }
    
    // We do not want UITextField to insert line-breaks.    
    return NO;
}

#pragma mark - UIPickerViewDelegate/DataSource

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)aPickerView;
{
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)aPickerView numberOfRowsInComponent:(NSInteger)component;
{
    return stateNameArray.count;
}

- (NSString *)pickerView:(UIPickerView *)aPickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component;
{
    return [stateNameArray objectAtIndex:row];
}

- (void)pickerView:(UIPickerView *)aPickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component;
{
    self.state.text = [stateDictionary objectForKey:[stateNameArray objectAtIndex:row]];
}

#pragma mark - UIKeyboard notifications

- (void)keyboardWasShown:(NSNotification *)notification;
{
    NSDictionary *info = [notification userInfo];
    CGSize keyboardSize = [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, keyboardSize.height, 0.0);
    scrollView.contentInset = contentInsets;
    scrollView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillBeHidden:(NSNotification *)notification;
{
    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    scrollView.contentInset = contentInsets;
    scrollView.scrollIndicatorInsets = contentInsets;
}

#pragma mark - Actions

-(IBAction)fieldDidBeginEditing:(id)sender;
{
    [self _scootToField:sender animated:YES];
}

-(IBAction)fieldDidChange:(id)sender;
{
    // On any edits, revalidate fields.
    [self _validateFields];
}

-(IBAction)continue:(id)sender;
{
    [self _saveFormValuesToModel];

    SQDonationConfirmationViewController *legalViewController = [[SQDonationConfirmationViewController alloc] init];
    [self.navigationController pushViewController:legalViewController animated:YES];
    [legalViewController release];
}

#pragma mark - Model/View binding

- (void)_loadFormValuesFromModel;
{
    SQDonation *donation = [SQDonation donation];
    
    self.donationAmount.text = [donation.amount displayValue];
    self.name.text = [NSString stringWithFormat:@"%@ %@", donation.firstName, donation.lastName];
    self.email.text = donation.email;
    self.street.text = donation.street;
    self.city.text = donation.city;
    self.state.text = donation.state;
    self.zip.text = donation.zip;
    self.employer.text = donation.employer;
    self.occupation.text = donation.occupation;
    
    [self _validateFields];
}

- (void)_saveFormValuesToModel;
{
    // Amount is kept up to date as the user types because SQMoney doesn't parse display strings.
    SQDonation *donation = [SQDonation donation];    
    
    NSArray *names = [[self.name.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    donation.firstName = names.count > 0 ? [names objectAtIndex:0] : nil;
    donation.lastName = names.count > 1 ? [[names subarrayWithRange:NSMakeRange(1, names.count - 1)] componentsJoinedByString:@" "] : nil;
    
    donation.email = [self.email.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    donation.street = [self.street.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    donation.city = [self.city.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    donation.state = [self.state.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    donation.zip = [self.zip.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    donation.employer = [self.employer.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    donation.occupation = [self.occupation.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Private Methods

- (void)_validateFields;
{
    self.contributeButton.enabled = [self _fieldsValid];
}

- (BOOL)_fieldsValid;
{
    // We need a positive contribution amount and all fields must be populated.
    
    BOOL isValid = YES;
    
    for (UITextField *formTextField in self.formTextFields) {
        if (formTextField.text.length == 0) {
            isValid = NO;
        }        
    }
    
    if ([[SQDonation donation].amount isZero]) {
        isValid = NO;
    }
    
    return isValid;
}

- (void)_scootToField:(UITextField *)textField animated:(BOOL)animated;
{
    // Scroll to 80.0f pixels above the desired text field, but never more than the edge of the content
    // (contentSize - scrollView bounds adjusted for inset).
    const CGFloat verticalInset = 80.0f;
    CGFloat contentHeight = MIN((textField.frame.origin.y - verticalInset),
                                (self.scrollView.contentSize.height - (self.scrollView.bounds.size.height - scrollView.contentInset.bottom)));
    
    [self.scrollView setContentOffset:CGPointMake(0, contentHeight) animated:animated];
}

- (void)_releaseOutlets;
{
    self.formTextFields = nil;
    
    self.scrollView = nil;
    self.formView = nil;
    self.legaleseView = nil;
    
    self.donationAmount = nil;
    self.name = nil;
    self.email = nil;
    self.street = nil;
    self.city = nil;
    self.state = nil;
    self.zip = nil;
    self.employer = nil;
    self.occupation = nil;
    
    self.contributeButton = nil;
}

- (void)_registerForKeyboardNotifications;
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWasShown:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillBeHidden:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    
}

- (void)_removeKeyboardObservers;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

@end
