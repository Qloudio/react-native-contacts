#import <AddressBook/AddressBook.h>
#import <UIKit/UIKit.h>
#import "RCTContacts.h"

@implementation RCTContacts

RCT_EXPORT_MODULE();

- (NSDictionary *)constantsToExport
{
  return @{
    @"PERMISSION_DENIED": @"denied",
    @"PERMISSION_AUTHORIZED": @"authorized",
    @"PERMISSION_UNDEFINED": @"undefined"
  };
}

RCT_EXPORT_METHOD(checkPermission:(RCTResponseSenderBlock) callback)
{
  int authStatus = ABAddressBookGetAuthorizationStatus();
  if ( authStatus == kABAuthorizationStatusDenied || authStatus == kABAuthorizationStatusRestricted){
    callback(@[[NSNull null], @"denied"]);
  } else if (authStatus == kABAuthorizationStatusAuthorized){
    callback(@[[NSNull null], @"authorized"]);
  } else { //ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusNotDetermined
    callback(@[[NSNull null], @"undefined"]);
  }
}

RCT_EXPORT_METHOD(requestPermission:(RCTResponseSenderBlock) callback)
{
  ABAddressBookRequestAccessWithCompletion(ABAddressBookCreateWithOptions(NULL, nil), ^(bool granted, CFErrorRef error) {
    if (!granted){
      [self checkPermission:callback];
      return;
    }
    [self checkPermission:callback];
  });
}

-(void) getAllContacts:(RCTResponseSenderBlock) callback
        withThumbnails:(BOOL) withThumbnails
{
    ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
    int authStatus = ABAddressBookGetAuthorizationStatus();
    if(authStatus != kABAuthorizationStatusAuthorized){
        ABAddressBookRequestAccessWithCompletion(addressBookRef, ^(bool granted, CFErrorRef error) {
            if(granted){
                [self retrieveContactsFromAddressBook:addressBookRef withThumbnails:withThumbnails withCallback:callback];
            }else{
                NSDictionary *error = @{
                                        @"type": @"permissionDenied"
                                        };
                callback(@[error, [NSNull null]]);
            }
        });
    }
    else{
        [self retrieveContactsFromAddressBook:addressBookRef withThumbnails:withThumbnails withCallback:callback];
    }
}

RCT_EXPORT_METHOD(getAll:(RCTResponseSenderBlock) callback)
{
    [self getAllContacts:callback withThumbnails:true];
}

RCT_EXPORT_METHOD(getAllWithoutPhotos:(RCTResponseSenderBlock) callback)
{
    [self getAllContacts:callback withThumbnails:false];
}

-(void) retrieveContactsFromAddressBook:(ABAddressBookRef)addressBookRef
                         withThumbnails:(BOOL) withThumbnails
                           withCallback:(RCTResponseSenderBlock) callback
{
  NSArray *allContacts = (__bridge_transfer NSArray *)ABAddressBookCopyArrayOfAllPeopleInSourceWithSortOrdering(addressBookRef, NULL, kABPersonSortByLastName);
  int totalContacts = (int)[allContacts count];
  int currentIndex = 0;
  int maxIndex = --totalContacts;

  NSMutableArray *contacts = [[NSMutableArray alloc] init];

  while (currentIndex <= maxIndex){
    NSDictionary *contact = [self dictionaryRepresentationForABPerson: (ABRecordRef)[allContacts objectAtIndex:(long)currentIndex] withThumbnails:withThumbnails];

    if(contact){
      [contacts addObject:contact];
    }
    currentIndex++;
  }
  callback(@[[NSNull null], contacts]);
}

-(NSDictionary*) dictionaryRepresentationForABPerson:(ABRecordRef) person
                                      withThumbnails:(BOOL)withThumbnails
{
  NSMutableDictionary* contact = [NSMutableDictionary dictionary];

  NSNumber *recordID = [NSNumber numberWithInteger:(ABRecordGetRecordID(person))];
  NSString *givenName = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonFirstNameProperty));
  NSString *familyName = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonLastNameProperty));
  NSString *middleName = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonMiddleNameProperty));
  NSString *prefix = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonPrefixProperty));
  NSString *suffix = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonSuffixProperty));
  NSString *nickname = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonNicknameProperty));
  NSString *company = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonOrganizationProperty));
  NSString *department = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonDepartmentProperty));
  NSString *jobTitle = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonJobTitleProperty));
  NSString *note = (__bridge_transfer NSString *)(ABRecordCopyValue(person, kABPersonNoteProperty));

  [contact setObject: recordID forKey: @"recordID"];

  BOOL hasName = false;
  if (givenName) {
    [contact setObject: givenName forKey:@"givenName"];
    hasName = true;
  }

  if (familyName) {
    [contact setObject: familyName forKey:@"familyName"];
    hasName = true;
  }

  if(middleName){
    [contact setObject: (middleName) ? middleName : @"" forKey:@"middleName"];
  }

  if(prefix){
    [contact setObject: (prefix) ? prefix : @"" forKey:@"prefix"];
  }

  if(suffix){
    [contact setObject: (suffix) ? suffix : @"" forKey:@"suffix"];
  }

  if(nickname){
    [contact setObject: (nickname) ? nickname : @"" forKey:@"nickname"];
    if(!hasName) {
        [contact setObject: nickname forKey:@"givenName"];
        hasName = true;
    }
  }

  if(company){
    [contact setObject: (company) ? company : @"" forKey:@"company"];
    if(!hasName) {
        [contact setObject: company forKey:@"givenName"];
        hasName = true;
    }
  }

  if(department){
    [contact setObject: (department) ? department : @"" forKey:@"department"];
  }

  if(jobTitle){
    [contact setObject: (jobTitle) ? jobTitle : @"" forKey:@"jobTitle"];
  }

  if(note){
    [contact setObject: (note) ? note : @"" forKey:@"note"];
  }

  if(!hasName){
    //nameless contact, do not include in results
    return nil;
  }

  //handle phone numbers
  NSMutableArray *phoneNumbers = [[NSMutableArray alloc] init];

  ABMultiValueRef multiPhones = ABRecordCopyValue(person, kABPersonPhoneProperty);
  for(CFIndex i=0;i<ABMultiValueGetCount(multiPhones);i++) {
    CFStringRef phoneNumberRef = ABMultiValueCopyValueAtIndex(multiPhones, i);
    CFStringRef phoneLabelRef = ABMultiValueCopyLabelAtIndex(multiPhones, i);
    NSString *phoneNumber = (__bridge_transfer NSString *) phoneNumberRef;
    NSString *phoneLabel = (__bridge_transfer NSString *) ABAddressBookCopyLocalizedLabel(phoneLabelRef);
    if(phoneNumberRef){
      CFRelease(phoneNumberRef);
    }
    if(phoneLabelRef){
      CFRelease(phoneLabelRef);
    }
    NSMutableDictionary* phone = [NSMutableDictionary dictionary];
    [phone setObject: phoneNumber forKey:@"number"];
    [phone setObject: phoneLabel forKey:@"label"];
    [phoneNumbers addObject:phone];
  }

  [contact setObject: phoneNumbers forKey:@"phoneNumbers"];
  //end phone numbers

  //handle emails
  NSMutableArray *emailAddreses = [[NSMutableArray alloc] init];

  ABMultiValueRef multiEmails = ABRecordCopyValue(person, kABPersonEmailProperty);
  for(CFIndex i=0;i<ABMultiValueGetCount(multiEmails);i++) {
    CFStringRef emailAddressRef = ABMultiValueCopyValueAtIndex(multiEmails, i);
    CFStringRef emailLabelRef = ABMultiValueCopyLabelAtIndex(multiEmails, i);
    NSString *emailAddress = (__bridge_transfer NSString *) emailAddressRef;
    NSString *emailLabel = (__bridge_transfer NSString *) ABAddressBookCopyLocalizedLabel(emailLabelRef);
    if(emailAddressRef){
      CFRelease(emailAddressRef);
    }
    if(emailLabelRef){
      CFRelease(emailLabelRef);
    }
    NSMutableDictionary* email = [NSMutableDictionary dictionary];
    [email setObject: emailAddress forKey:@"email"];
    [email setObject: emailLabel forKey:@"label"];
    [emailAddreses addObject:email];
  }
  //end emails

  [contact setObject: emailAddreses forKey:@"emailAddresses"];

  NSMutableArray *postalAddresses = [[NSMutableArray alloc] init];
  ABMultiValueRef multiPostalAddresses = ABRecordCopyValue(person, kABPersonAddressProperty);
  for(CFIndex i=0;i<ABMultiValueGetCount(multiPostalAddresses);i++) {
    NSMutableDictionary* address = [NSMutableDictionary dictionary];

    NSDictionary *addressDict = (__bridge NSDictionary *)ABMultiValueCopyValueAtIndex(multiPostalAddresses, i);
    NSString* street = [addressDict objectForKey:(NSString*)kABPersonAddressStreetKey];
    if(street){
      [address setObject:street forKey:@"street"];
    }
    NSString* city = [addressDict objectForKey:(NSString*)kABPersonAddressCityKey];
    if(city){
      [address setObject:city forKey:@"city"];
    }
    NSString* region = [addressDict objectForKey:(NSString*)kABPersonAddressStateKey];
    if(region){
      [address setObject:region forKey:@"region"];
    }
    NSString* postCode = [addressDict objectForKey:(NSString*)kABPersonAddressZIPKey];
    if(postCode){
      [address setObject:postCode forKey:@"postCode"];
    }
    NSString* country = [addressDict objectForKey:(NSString*)kABPersonAddressCountryCodeKey];
    if(country){
      [address setObject:country forKey:@"country"];
    }

    CFStringRef addresssLabelRef = ABMultiValueCopyLabelAtIndex(multiPostalAddresses, i);
    NSString *addressLabel = (__bridge_transfer NSString *) ABAddressBookCopyLocalizedLabel(addresssLabelRef);
    if(addresssLabelRef){
      CFRelease(addresssLabelRef);
    }
    [address setObject:addressLabel forKey:@"label"];

    [postalAddresses addObject:address];
  }
  CFRelease(multiPostalAddresses);
  [contact setObject:postalAddresses forKey:@"postalAddresses"];

  [contact setValue:[NSNumber numberWithBool:ABPersonHasImageData(person)] forKey:@"hasThumbnail"];
  if (withThumbnails) {
    [contact setObject: [self getABPersonThumbnailFilepath:person] forKey:@"thumbnailPath"];
  }
  return contact;
}

-(NSString *) getABPersonThumbnailFilepath:(ABRecordRef) person
{
    if (ABPersonHasImageData(person)){

        NSNumber *recordID = [NSNumber numberWithInteger:(ABRecordGetRecordID(person))];
        NSString* filepath = [NSString stringWithFormat:@"%@/contact_%@.png", [self getPathForDirectory:NSCachesDirectory], recordID];

        NSData *contactImageData = (__bridge NSData *)ABPersonCopyImageDataWithFormat(person, kABPersonImageFormatThumbnail);
        BOOL success = [[NSFileManager defaultManager] createFileAtPath:filepath contents:contactImageData attributes:nil];
        
        if (!success) {
            NSLog(@"Unable to copy image");
            return @"";
        }
        
        return filepath;
    }
    
    return @"";
}

- (NSString *)getPathForDirectory:(int)directory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES);
    return [paths firstObject];
}

RCT_EXPORT_METHOD(getPhotoForId:(nonnull NSNumber *)recordID callback:(RCTResponseSenderBlock)callback)
{
    ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
    int authStatus = ABAddressBookGetAuthorizationStatus();
    if(authStatus != kABAuthorizationStatusAuthorized){
        ABAddressBookRequestAccessWithCompletion(addressBookRef, ^(bool granted, CFErrorRef error) {
            if(granted){
                callback(@[[NSNull null], [self getABPersonThumbnailFilepathForId:recordID addressBook:addressBookRef]]);
            }else{
                NSDictionary *error = @{
                                        @"type": @"permissionDenied"
                                        };
                callback(@[error, [NSNull null]]);
            }
        });
    }
    else{
        callback(@[[NSNull null], [self getABPersonThumbnailFilepathForId:recordID addressBook:addressBookRef]]);
    }
}

-(NSString *) getABPersonThumbnailFilepathForId:(NSNumber *)recordID
                                    addressBook:(ABAddressBookRef)addressBookRef
{
    ABRecordID abRecordId = (ABRecordID)[recordID intValue];
    ABRecordRef person = ABAddressBookGetPersonWithRecordID(addressBookRef, abRecordId);
    return [self getABPersonThumbnailFilepath:person];
}


RCT_EXPORT_METHOD(addContact:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
  //@TODO keep addressbookRef in singleton
  ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
  ABRecordRef newPerson = ABPersonCreate();

  CFErrorRef error = NULL;
  ABAddressBookAddRecord(addressBookRef, newPerson, &error);
  //@TODO error handling

  [self updateRecord:newPerson onAddressBook:addressBookRef withData:contactData completionCallback:callback];
}

RCT_EXPORT_METHOD(updateContact:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
  ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
  int recordID = (int)[contactData[@"recordID"] integerValue];
  ABRecordRef record = ABAddressBookGetPersonWithRecordID(addressBookRef, recordID);
  [self updateRecord:record onAddressBook:addressBookRef withData:contactData completionCallback:callback];
}

-(void) updateRecord:(ABRecordRef)record onAddressBook:(ABAddressBookRef)addressBookRef withData:(NSDictionary *)contactData completionCallback:(RCTResponseSenderBlock)callback
{
  CFErrorRef error = NULL;
  NSString *givenName = [contactData valueForKey:@"givenName"];
  NSString *familyName = [contactData valueForKey:@"familyName"];
  NSString *middleName = [contactData valueForKey:@"middleName"];
  NSString *prefix = [contactData valueForKey:@"prefix"];
  NSString *suffix = [contactData valueForKey:@"suffix"];
  NSString *nickname = [contactData valueForKey:@"nickname"];
  NSString *company = [contactData valueForKey:@"company"];
  NSString *department = [contactData valueForKey:@"department"];
  NSString *jobTitle = [contactData valueForKey:@"jobTitle"];
  NSString *note = [contactData valueForKey:@"note"];
  ABRecordSetValue(record, kABPersonFirstNameProperty, (__bridge CFStringRef) givenName, &error);
  ABRecordSetValue(record, kABPersonLastNameProperty, (__bridge CFStringRef) familyName, &error);
  ABRecordSetValue(record, kABPersonMiddleNameProperty, (__bridge CFStringRef) middleName, &error);
  ABRecordSetValue(record, kABPersonPrefixProperty, (__bridge CFStringRef) prefix, &error);
  ABRecordSetValue(record, kABPersonSuffixProperty, (__bridge CFStringRef) suffix, &error);
  ABRecordSetValue(record, kABPersonNicknameProperty, (__bridge CFStringRef) nickname, &error);
  ABRecordSetValue(record, kABPersonOrganizationProperty, (__bridge CFStringRef) company, &error);
  ABRecordSetValue(record, kABPersonDepartmentProperty, (__bridge CFStringRef) department, &error);
  ABRecordSetValue(record, kABPersonJobTitleProperty, (__bridge CFStringRef) jobTitle, &error);
  ABRecordSetValue(record, kABPersonNoteProperty, (__bridge CFStringRef) note, &error);

  ABMutableMultiValueRef multiPhone = ABMultiValueCreateMutable(kABMultiStringPropertyType);
  NSArray* phoneNumbers = [contactData valueForKey:@"phoneNumbers"];
  for (id phoneData in phoneNumbers) {
    NSString *label = [phoneData valueForKey:@"label"];
    NSString *number = [phoneData valueForKey:@"number"];

    if ([label isEqual: @"main"]){
      ABMultiValueAddValueAndLabel(multiPhone, (__bridge CFStringRef) number, kABPersonPhoneMainLabel, NULL);
    }
    else if ([label isEqual: @"mobile"]){
      ABMultiValueAddValueAndLabel(multiPhone, (__bridge CFStringRef) number, kABPersonPhoneMobileLabel, NULL);
    }
    else if ([label isEqual: @"iPhone"]){
      ABMultiValueAddValueAndLabel(multiPhone, (__bridge CFStringRef) number, kABPersonPhoneIPhoneLabel, NULL);
    }
    else{
      ABMultiValueAddValueAndLabel(multiPhone, (__bridge CFStringRef) number, (__bridge CFStringRef) label, NULL);
    }
  }
  ABRecordSetValue(record, kABPersonPhoneProperty, multiPhone, nil);
  CFRelease(multiPhone);

  ABMutableMultiValueRef multiEmail = ABMultiValueCreateMutable(kABMultiStringPropertyType);
  NSArray* emails = [contactData valueForKey:@"emailAddresses"];
  for (id emailData in emails) {
    NSString *label = [emailData valueForKey:@"label"];
    NSString *email = [emailData valueForKey:@"email"];

    ABMultiValueAddValueAndLabel(multiEmail, (__bridge CFStringRef) email, (__bridge CFStringRef) label, NULL);
  }
  ABRecordSetValue(record, kABPersonEmailProperty, multiEmail, nil);
  CFRelease(multiEmail);

  ABAddressBookSave(addressBookRef, &error);
  if (error != NULL)
  {
    CFStringRef errorDesc = CFErrorCopyDescription(error);
    NSString *nsErrorString = (__bridge NSString *)errorDesc;
    callback(@[nsErrorString]);
    CFRelease(errorDesc);
  }
  else{
    callback(@[[NSNull null]]);
  }
}

RCT_EXPORT_METHOD(deleteContact:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
  CFErrorRef error = NULL;
  ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
  int recordID = (int)[contactData[@"recordID"] integerValue];
  ABRecordRef record = ABAddressBookGetPersonWithRecordID(addressBookRef, recordID);
  ABAddressBookRemoveRecord(addressBookRef, record, &error);
  ABAddressBookSave(addressBookRef, &error);
  //@TODO handle error
  callback(@[[NSNull null], [NSNull null]]);
}

@end
