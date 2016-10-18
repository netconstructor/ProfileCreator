//
//  PFCProfile.m
//  ProfileCreator
//
//  Created by Erik Berglund.
//  Copyright (c) 2016 ProfileCreator. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "PFCConstants.h"
#import "PFCLog.h"
#import "PFCProfile.h"
#import "PFCProfileController.h"
#import "PFCProfileEditorTableViewController.h"
#import <ProfilePayloads/ProfilePayloads.h>

@interface PFCProfile ()
@property (nonatomic, strong, readwrite, nonnull) NSString *identifier;
@property (nonatomic, strong, readwrite, nonnull) NSString *savedTitle;
@property (nonatomic, strong, readwrite, nonnull) NSDictionary *savedPayloadSettings;
@property (nonatomic, strong, readwrite, nonnull) NSMutableDictionary *payloadSettings;
@property (nonatomic, strong, readwrite, nonnull) NSDictionary *savedViewSettings;
@property (nonatomic, strong, readwrite, nonnull) NSMutableArray *modifiedIdentifiers;
@end

@implementation PFCProfile

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Init/Dealloc
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (nullable instancetype)initWithTitle:(NSString *_Nullable)title
                            identifier:(NSString *_Nullable)identifier
                       payloadSettings:(NSDictionary *_Nullable)payloadSettings
                          viewSettings:(NSDictionary *_Nullable)viewSettings
                                   url:(NSURL *_Nullable)url {
    self = [super init];
    if (self != nil) {

        // ---------------------------------------------------------------------
        //  Initialize General Settings
        // ---------------------------------------------------------------------
        _modifiedIdentifiers = [[NSMutableArray alloc] init];
        _enabledPayloadIdentifiers = [[NSMutableArray alloc] init];
        _url = url;
        _title = title;
        _savedTitle = title;
        if (identifier.length == 0) {
            _identifier = [[NSUUID UUID] UUIDString];
        } else {
            _identifier = identifier;
        }

        // ---------------------------------------------------------------------
        //  Initialize Payload Settings
        // ---------------------------------------------------------------------
        _payloadSettings = [payloadSettings mutableCopy] ?: [[self.class defaultPayloadSettings] mutableCopy];
        _savedPayloadSettings = _payloadSettings;
        if (_savedPayloadSettings.count != 0) {
            for (NSString *payloadIdentifier in _savedPayloadSettings.allKeys) {
                if ([_savedPayloadSettings[payloadIdentifier][PFPSettingsKeyEnabled] boolValue] && ![payloadIdentifier isEqualToString:@"com.apple.general.pcmanifest"]) {
                    [_enabledPayloadIdentifiers addObject:payloadIdentifier];
                }
            }
        }

        // ---------------------------------------------------------------------
        //  Initialize View Settings
        // ---------------------------------------------------------------------
        _scope = [PFPUtility scopeFromInteger:[viewSettings[PFCViewSettingsKeyScope] integerValue] ?: 3];
        _distribution = [PFPUtility distributionFromInteger:[viewSettings[PFCViewSettingsKeyDistribution] integerValue] ?: 3];
        _showHidden = [viewSettings[PFCViewSettingsKeyShowHidden] boolValue];
        _showSupervised = [viewSettings[PFCViewSettingsKeyShowSupervised] boolValue];
        _showDisabled = [viewSettings[PFCViewSettingsKeyShowDisabled] boolValue];
        _savedViewSettings = viewSettings ?: @{};
    }
    return self;
} // initWithTitle:identifier:payloadSettings:viewSettings:url

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Save Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (BOOL)save {
    NSError *error;
    if (![[PFCProfileController sharedController] saveProfile:self error:&error]) {
        DDLogError(@"%@", error.localizedDescription);
        return NO;
    } else {
        [self setSavedTitle:[self.title copy]];
        [self setSavedPayloadSettings:[self.payloadSettings copy]];
        [self setSavedViewSettings:[self.viewSettings copy]];
        [[NSNotificationCenter defaultCenter] postNotificationName:PFCDidSaveProfileNotification object:self userInfo:@{ PFCNotificationUserInfoProfileIdentifiers : @[ self.identifier ] }];
        return YES;
    }
} // save

- (BOOL)isSaved {
    DDLogDebug(@"IsSaved PayloadSettings: %@", ([self.savedPayloadSettings isEqualToDictionary:self.payloadSettings]) ? @"YES" : @"NO");
    DDLogDebug(@"IsSaved ViewSettings: %@", ([self.savedViewSettings isEqualToDictionary:self.viewSettings]) ? @"YES" : @"NO");
    DDLogDebug(@"IsSaved Title: %@", ([self.savedTitle isEqualToString:self.title]) ? @"YES" : @"NO");
    DDLogDebug(@"IsSaved Title is Default: %@", ([self.title isEqualToString:PFCProfileDefaultName]) ? @"YES" : @"NO");
    return ([self.savedPayloadSettings isEqualToDictionary:self.payloadSettings] && [self.savedViewSettings isEqualToDictionary:self.viewSettings] && [self.savedTitle isEqualToString:self.title] &&
            ![self.title isEqualToString:PFCProfileDefaultName]);
} // isSaved

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Settings Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (NSDictionary *_Nonnull)viewSettings {

    // -------------------------------------------------------------------------
    //  Return Current View Settings
    // -------------------------------------------------------------------------
    return @{
        PFCViewSettingsKeyShowHidden : @(self.showHidden),
        PFCViewSettingsKeyShowSupervised : @(self.showSupervised),
        PFCViewSettingsKeyShowDisabled : @(self.showDisabled),
        PFCViewSettingsKeyScope : @(self.scope),
        PFCViewSettingsKeyDistribution : @(self.distribution)
    };
} // viewSettings

- (NSDictionary *_Nullable)payloadSettingsForExport:(NSError *_Nullable *_Nullable)error {

    // -------------------------------------------------------------------------
    //  Verify the profile is saved to avoid mismatch in UI and exported profile
    // -------------------------------------------------------------------------
    if (![self isSaved]) {
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : NSLocalizedString(@"Profile has unsaved settings.", nil),
            NSLocalizedFailureReasonErrorKey : NSLocalizedString(@"To export a profile you need to save all unsaved settings.", nil)
        };
        *error = [NSError errorWithDomain:PFCErrorDomain code:-59 userInfo:userInfo];
        return nil;
    }

    // -------------------------------------------------------------------------
    //  Return payload settings only for enabled payloads
    // -------------------------------------------------------------------------
    NSMutableDictionary *enabledPayloadSettings = [[NSMutableDictionary alloc] init];
    for (NSString *key in self.savedPayloadSettings) {
        if ([self.savedPayloadSettings[key][PFPSettingsKeyEnabled] boolValue] || [key isEqualToString:@"com.apple.general.pcmanifest"] || [key isEqualToString:PFPManifestKeyPayloadType]) {
            enabledPayloadSettings[key] = self.savedPayloadSettings[key];
        }
    }

    return [enabledPayloadSettings copy];
} // payloadSettingsForExport

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Class Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

+ (NSDictionary *_Nullable)defaultPayloadSettings {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    NSMutableDictionary *defaultSettings = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *settingsGeneral = [[NSMutableDictionary alloc] init];

    if ([ud objectForKey:PFCUserDefaultsDefaultOrganization]) {
        NSMutableDictionary *settingsOrganization = [[NSMutableDictionary alloc] init];
        settingsOrganization[PFPSettingsKeyValueTextField] = [ud objectForKey:PFCUserDefaultsDefaultOrganization];
        settingsGeneral[@"41CB1487-F133-4B35-8EF6-EA5F1410E799"] = [settingsOrganization copy];
    }

    defaultSettings[@"com.apple.general.pcmanifest"] = [settingsGeneral copy];

    return [defaultSettings copy];
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Instance Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)updateTitle:(NSString *)title {

    // -------------------------------------------------------------------------
    //  Convenience method to update both the profile title and DisplayName payload setting
    // -------------------------------------------------------------------------
    NSMutableDictionary *generalSettings = [self.payloadSettings[@"com.apple.general.pcmanifest"] mutableCopy] ?: [[NSMutableDictionary alloc] init];
    NSMutableDictionary *payloadDisplayName = [generalSettings[@"4402B07D-78EA-482F-B4FD-C8352085CE55"] mutableCopy] ?: [[NSMutableDictionary alloc] init];
    payloadDisplayName[PFPSettingsKeyValueTextField] = [title copy];
    generalSettings[@"4402B07D-78EA-482F-B4FD-C8352085CE55"] = [payloadDisplayName mutableCopy];
    self.payloadSettings[@"com.apple.general.pcmanifest"] = [generalSettings mutableCopy];
    [self setTitle:title];
} // updateTitle

- (void)enablePayloadCollection:(BOOL)enable withIdentifier:(NSString *_Nonnull)identifier {

    // -------------------------------------------------------------------------
    //  Enables/Disables payload with identifier for export
    // -------------------------------------------------------------------------
    NSMutableDictionary *payloadCollectionSettings = [self.payloadSettings[identifier] mutableCopy] ?: [[NSMutableDictionary alloc] init];
    payloadCollectionSettings[PFPSettingsKeyEnabled] = @(enable);
    self.payloadSettings[identifier] = [payloadCollectionSettings copy];

    if (enable) {
        [self.enabledPayloadIdentifiers addObject:identifier];
    } else {
        [self.enabledPayloadIdentifiers removeObject:identifier];
    }
} // enablePayloadCollection:withIdentifier

- (void)removeEditor {

    // -------------------------------------------------------------------------
    //  Cleanup when the editor window is closed
    // -------------------------------------------------------------------------
    [self setEditor:nil];
    [self setPayloadCollections:nil];
    [self setPayloadSettings:[self.savedPayloadSettings mutableCopy]];
    [self setTitle:[self.savedTitle copy]];
} // removeEditor

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark PFPViewTypeDelegate Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

// -----------------------------------------------------------------------------
//  Delegate method from view type that user has changed a setting
// -----------------------------------------------------------------------------
- (void)userSettingsChanged:(NSDictionary *_Nonnull)changeDict payloadCollectionKey:(PFPPayloadCollectionKey *_Nullable)payloadCollectionKey sender:(id _Nonnull)sender {

    // -------------------------------------------------------------------------
    //  Clear current modified identifiers to not update settings that haven't changed
    // -------------------------------------------------------------------------
    [self.modifiedIdentifiers removeAllObjects];

    // -------------------------------------------------------------------------
    //  Ask framework to update saved settings with user changes
    // -------------------------------------------------------------------------
    [self.payloadCollections updatePayloadSettings:self.payloadSettings withUserChangeDict:changeDict payloadCollectionKey:payloadCollectionKey];

    // -------------------------------------------------------------------------
    //  Depending on what view was updated, reload table view or leave as is
    // -------------------------------------------------------------------------
    NSString *notificationEvent = changeDict[PFPUserChangeKeyNotificationEvent];
    if ([notificationEvent hasPrefix:@"controlText"]) {

        // ---------------------------------------------------------------------
        //  If view DisplayName in General settings was updated, also update profile title
        // ---------------------------------------------------------------------
        if ([changeDict[PFPUserChangeKeyCollectionKeyIdentifier] isEqualToString:@"4402B07D-78EA-482F-B4FD-C8352085CE55"]) {
            [self updateTitle:[changeDict[PFPUserChangeKeyValue] copy]];
        }
    } else if (![notificationEvent hasPrefix:@"textDid"]) {
        [self.modifiedIdentifiers addObject:changeDict[PFPUserChangeKeyCollectionKeyIdentifier]];
        if (self.viewDelegate && [self.viewDelegate respondsToSelector:@selector(reloadDataWithForcedReload:)]) {
            [self.viewDelegate reloadDataWithForcedReload:NO];
        }
    }
} // userSettingsChanged:payloadCollectionKey:sender

@end
