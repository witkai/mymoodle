//
//  SettingsSite.m
//  Moodle
//
//  Created by Jerome Mouneyrac on 21/03/11.
//  Copyright 2011 Moodle. All rights reserved.
//

#import "SettingsSiteViewController.h"
#import "WSClient.h"
#import "Constants.h"
#import "XMLRPCRequest.h"
#import "NSDataAdditions.h"
#import "ASIFormDataRequest.h"
#import "CJSONDeserializer.h"

@implementation SettingsSiteViewController
@synthesize fieldLabels;
@synthesize fieldValues;
@synthesize textFieldBeingEdited;

# pragma mark - Button actions
-(IBAction)cancel:(id)sender{
    [self.navigationController popViewControllerAnimated:YES];
}

-(void)deleteSite {
    UIActionSheet *deleteActionSheet = [[UIActionSheet alloc]
                                            initWithTitle:NSLocalizedString(@"deletesite", "Delete the site")
                                            delegate:self
                                            cancelButtonTitle: NSLocalizedString(@"donotdeletesite", "Do not delete the site")
                                            destructiveButtonTitle: NSLocalizedString(@"dodeletesite", "Do delete the site")
                                            otherButtonTitles:nil];
    [deleteActionSheet showInView: self.view];
    [deleteActionSheet release];
}

-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    //there is only one action sheet on this view, so we can check the buttonIndex against the cancel button
    if (buttonIndex != [actionSheet cancelButtonIndex]) {
        //delete the entry
        [appDelegate.managedObjectContext deleteObject: appDelegate.site];
        NSError *error;
        if (![appDelegate.managedObjectContext save:&error]) {
            NSLog(@"Error saving entity: %@", [error localizedDescription]);
        }
        //return the list of sites
        [self.navigationController popViewControllerAnimated:YES];
        NSArray *allControllers = self.navigationController.viewControllers;
        UITableViewController *parent = [allControllers lastObject];
        [parent.tableView reloadData];
    }
}

- (IBAction)saveButtonPressed: (id)sender
{
    NSManagedObjectContext *context = appDelegate.managedObjectContext;
    if (textFieldBeingEdited != nil)
    {
        NSNumber *tagAsNum= [[NSNumber alloc]
                             initWithInt:textFieldBeingEdited.tag];
        [fieldValues setObject:textFieldBeingEdited.text forKey: tagAsNum];
        [tagAsNum release];

    }

    NSString *siteurl;
    if (!newEntry) {
        //retrieve site url (case of update)
        siteurl = [appDelegate.site valueForKey:@"url"];
    } else {
        //case of creation: just some allocation to not cause a none initialize error during code analyze
        siteurl = @"";
    }
    NSString *username;
    NSString *password;
    //retrieve site url (case of creation)
    for (NSNumber *key in [fieldValues allKeys])
    {
        switch ([key intValue]) {
            case kUrlIndex:
                siteurl = [fieldValues objectForKey:key];
                break;
                //TODO: retrieve username/password
            case kUsernameIndex:
                username = [fieldValues objectForKey:key];
                break;
            case kPasswordIndex:
                password = [fieldValues objectForKey:key];
                break;
            default:
                break;
        }
    }
    NSLog(@"Username: %@", username);
    NSLog(@"Password: %@", password);
    NSLog(@"Start ws call %@", siteurl);

    NSString *tokenURL = [NSString stringWithFormat:@"%@/login/token.php", siteurl];
    NSURL *url = [NSURL URLWithString: tokenURL];
    NSLog(@"%@", tokenURL);
    ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
    [request setPostValue: username forKey: @"username"];
    [request setPostValue: password forKey: @"password"];
    [request setPostValue: @"moodle_mobile_app" forKey: @"service"];
    [request setCompletionBlock: ^{
        NSLog(@"TTT: %@", [request responseString]);
        NSDictionary *token = [[CJSONDeserializer deserializer] deserializeAsDictionary: [request responseData] error: nil];
        
        NSLog(@"%@", token);
        NSString *sitetoken = [token valueForKey: @"token"];
        @try {
            //retrieve the site name
            WSClient *client = [[[WSClient alloc] initWithToken: sitetoken withHost: siteurl] autorelease];
            NSArray *wsparams = [[NSArray alloc] initWithObjects:nil];
            NSDictionary *siteinfo = [client invoke: @"moodle_webservice_get_siteinfo" withParams: wsparams];
            [wsparams release];
            NSLog(@"siteinfo: %@", siteinfo);
            
            if ([siteinfo isKindOfClass: [NSDictionary class]]) {
                //check if the site url + userid is already in data core otherwise create a new site
                NSError *error;
                NSFetchRequest *siteRequest = [[[NSFetchRequest alloc] init] autorelease];
                NSEntityDescription *siteEntity = [NSEntityDescription entityForName:@"Site" inManagedObjectContext:context];
                [siteRequest setEntity: siteEntity];
                NSPredicate *sitePredicate = [NSPredicate predicateWithFormat:@"(url = %@ AND mainuser.userid = %@)", siteurl, [siteinfo objectForKey:@"userid"]];
                [siteRequest setPredicate:sitePredicate];
                NSArray *sites = [context executeFetchRequest:siteRequest error:&error];
                NSLog(@"Sites info %@", sites);
                
                if ([sites count] > 0) {
                    MLog(@"Site existed");
                    appDelegate.site = [sites lastObject];
                } else {
                    MLog(@"Creating new site");
                    appDelegate.site = [NSEntityDescription insertNewObjectForEntityForName: [siteEntity name] inManagedObjectContext:context];
                }
                // profile pictre
                NSString  *userpictureurl = [siteinfo objectForKey: @"userpictureurl"];
                // base64 decode
//                NSData       *data = [NSData base64DataFromString:picture];
                NSString *sitename = [siteinfo objectForKey: @"sitename"];
                //create/update the site
                [appDelegate.site setValue: sitename  forKey: @"name"];
                [appDelegate.site setValue: userpictureurl forKey: @"userpictureurl"];
                [appDelegate.site setValue: sitetoken forKey: @"token"];
                [appDelegate.site setValue: siteurl   forKey: @"url"];
                
                NSManagedObject *user;
                //retrieve participant main user
                if (newEntry) {
                    NSEntityDescription *mainUserDesc = [NSEntityDescription entityForName:@"MainUser" inManagedObjectContext:context];
                    user = [NSEntityDescription insertNewObjectForEntityForName: [mainUserDesc name]
                                                         inManagedObjectContext: context];
                } else {
                    user = [appDelegate.site valueForKey:@"mainuser"];
                }
                
                [user setValue: [siteinfo objectForKey:@"userid"] forKey:@"userid"];
                [user setValue: [siteinfo objectForKey:@"username"] forKey:@"username"];
                [user setValue: [siteinfo objectForKey:@"firstname"] forKey:@"firstname"];
                [user setValue: [siteinfo objectForKey:@"lastname"] forKey:@"lastname"];
                [user setValue: appDelegate.site forKey:@"site"];
                
                [appDelegate.site setValue: user forKey: @"mainuser"];
                
                //save the modification
                if (![context save: &error]) {
                    NSLog(@"Failed to save to data store: %@", [error localizedDescription]);
                    NSArray *detailedErrors = [[error userInfo] objectForKey: NSDetailedErrorsKey];
                    if(detailedErrors != nil && [detailedErrors count] > 0) {
                        for(NSError* detailedError in detailedErrors) {
                            NSLog(@"Detailed Error: %@", [detailedError userInfo]);
                        }
                    }
                    else {
                        NSLog(@"  %@", [error userInfo]);
                    }
                }
                [self.navigationController popToRootViewControllerAnimated:YES];
            }
        }
        @catch (NSException *exception) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[exception name] message:[exception reason] delegate:self cancelButtonTitle:@"Continue" otherButtonTitles: nil];
            [alert show];
            [alert release];
        }

    }];
    [request startAsynchronous];
}

-(IBAction)textFieldDone:(id)sender {
    UITableViewCell *cell =
    (UITableViewCell *)[[sender superview] superview];
    UITableView *table = (UITableView *)[cell superview];
    NSIndexPath *textFieldIndexPath = [table indexPathForCell:cell];
    NSUInteger row = [textFieldIndexPath row];
    row++;
    if (row >= kNumberOfEditableRows) {
        row = 0;
    }
    NSUInteger newIndex[] = {0, row};
    NSIndexPath *newPath = [[NSIndexPath alloc] initWithIndexes:newIndex length:2];
    UITableViewCell *nextCell = [self.tableView cellForRowAtIndexPath:newPath];
    UITextField *nextField = nil;
    for (UIView *oneView in nextCell.contentView.subviews) {
        if ([oneView isMemberOfClass:[UITextField class]]) {
            nextField = (UITextField *)oneView;
        }
    }
    [newPath release];
    [nextField becomeFirstResponder];
}

#pragma mark - View lifecycle

- (id)initWithNew: (NSString *)new {
    if ((self = [self init])) {
    }
    NSLog(@"init param: %@", new);
    if ([new isEqualToString:@"no"]) {
        newEntry = NO;
    } else {
        newEntry = YES;
    }

    return self;
}

- (void)dealloc {
    [textFieldBeingEdited release];
    [fieldValues release];
    [fieldLabels release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"Settings view did load");
    if (newEntry) {
        NSLog(@"It's new entry");
    } else {
        NSLog(@"Update existing entry");
    }
    appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];

    NSArray *array = [[NSArray alloc] initWithObjects:@"URL:", @"Username:", @"Password:", nil];
    self.fieldLabels = array;
    [array release];

    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc]
                                     initWithTitle:NSLocalizedString(@"cancel", "cancel button label")
                                     style:UIBarButtonItemStylePlain
                                     target:self
                                     action:@selector(cancel:)];
    self.navigationItem.leftBarButtonItem = cancelButton;
    [cancelButton release];

    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc]
                                   initWithTitle: NSLocalizedString(@"save", "Save")
                                   style:UIBarButtonItemStyleDone
                                   target:self
                                   action:@selector(saveButtonPressed:)];
    self.navigationItem.rightBarButtonItem = saveButton;
    [saveButton release];

    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    self.fieldValues = dict;
    [dict release];

    if (!newEntry) {
        // case of Updating a site
        self.title = NSLocalizedString(@"updatesite", @"Update the site");

        //create a footer view on the bottom of the tabeview with a Delete button
        UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(10, 0, 300, 270)];
        //Cacaco framework doesn't have a style for the 'Delete contact' red button! We need to simulate it with a background image
        UIImage *buttonImage = [[UIImage imageNamed:@"redbutton.png"] stretchableImageWithLeftCapWidth:8 topCapHeight:8];
        //create the button
        UIButton *btnDelete = [UIButton buttonWithType:UIButtonTypeCustom];
        [btnDelete setBackgroundImage:buttonImage forState:UIControlStateNormal];
        btnDelete.frame = CGRectMake(0, 170, 300, 40); //button position at the bottom of the screen (a bit clunky)
        [btnDelete setTitle:NSLocalizedString(@"delete", "delete") forState:UIControlStateNormal];
        [btnDelete.titleLabel setFont:[UIFont boldSystemFontOfSize:20]];
        // [btnDelete setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [btnDelete addTarget:self action:@selector(deleteSite) forControlEvents:UIControlEventTouchUpInside];
        //add the button to the footer
        [footerView addSubview:btnDelete];
        //add the footer to the tableView
        self.tableView.tableFooterView = footerView;
        [footerView release];
    } else {
        //case of Adding a new site
        self.title = NSLocalizedString(@"addasite", @"add a site");
    }
}

#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    return kNumberOfEditableRows;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *SiteSettingCellIdentifier = @"SiteSettingCellIdentifier";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:
                             SiteSettingCellIdentifier];
    if (cell == nil) {

        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:SiteSettingCellIdentifier] autorelease];
        UILabel *label = [[UILabel alloc] initWithFrame:
                          CGRectMake(10, 10, 75, 25)];
        label.textAlignment = UITextAlignmentRight;
        label.tag = kLabelTag;
        label.font = [UIFont boldSystemFontOfSize:14];
        [cell.contentView addSubview:label];
        [label release];


        UITextField *textField = [[UITextField alloc] initWithFrame:
                                  CGRectMake(90, 12, 200, 25)];
        textField.clearsOnBeginEditing = NO;
        [textField setDelegate:self];
        [textField addTarget:self
                      action:@selector(textFieldDone:)
            forControlEvents:UIControlEventEditingDidEndOnExit];
        [cell.contentView addSubview:textField];
    }
    NSUInteger row = [indexPath row];

    UILabel *label = (UILabel *)[cell viewWithTag:kLabelTag];
    UITextField *textField = nil;
    for (UIView *oneView in cell.contentView.subviews)
    {
        if ([oneView isMemberOfClass:[UITextField class]])
            textField = (UITextField *)oneView;
    }
    label.text = [fieldLabels objectAtIndex:row];
    NSNumber *rowAsNum = [[NSNumber alloc] initWithInt:row];
    switch (row) {
        case kUrlIndex:
            textField.keyboardType = UIKeyboardTypeURL;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            if ([[fieldValues allKeys] containsObject:rowAsNum]) {
                textField.text = [fieldValues objectForKey:rowAsNum];
            } else {
                if (!newEntry) {
                    textField.text = [appDelegate.site valueForKey:@"url"];
                }
            }
            //DEBUG MODE - comment out
            if (newEntry) {
                //textField.text = @"http://jerome.moodle.local/~jerome/Moodle_HEAD"; //Jerome's site
                //textField.text = @"http://jerome.moodle.net"; // Internet
                textField.text = @"http://dsmacbook.moodle.local/moodlews"; // Dongsheng's site
                [fieldValues setObject:textField.text forKey:[[NSNumber alloc] initWithInt:textField.tag]];
            }
            break;
        case kUsernameIndex:
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            if ([[fieldValues allKeys] containsObject:rowAsNum]) {
                textField.text = [fieldValues objectForKey:rowAsNum];
            } else {
                if (!newEntry) {
                    textField.text = [appDelegate.site valueForKeyPath:@"mainuser.username"];
                }
            }
            break;
        case kPasswordIndex:
            textField.secureTextEntry = YES;
            if ([[fieldValues allKeys] containsObject:rowAsNum]) {
                textField.text = [fieldValues objectForKey:rowAsNum];
            }
            if (!newEntry) {
                textField.text = @"********";
            }
            break;

        default:
            break;
    }
    if (textFieldBeingEdited == textField) {
        textFieldBeingEdited = nil;
    }

    textField.tag = row;
    [rowAsNum release];
    return cell;
}
#pragma mark -
#pragma mark Table Delegate Methods
- (NSIndexPath *)tableView:(UITableView *)tableView
  willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    return nil;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Account details";
}
#pragma mark Text Field Delegate Methods
- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    self.textFieldBeingEdited = textField;
}
- (void)textFieldDidEndEditing:(UITextField *)textField
{
    NSNumber *tagAsNum = [[NSNumber alloc] initWithInt:textField.tag];
    [fieldValues setObject: [textField text] forKey:tagAsNum];
    [tagAsNum release];
}
@end
