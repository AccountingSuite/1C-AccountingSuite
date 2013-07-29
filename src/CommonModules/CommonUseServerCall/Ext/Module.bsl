﻿
////////////////////////////////////////////////////////////////////////////////
// Base functionality subsystem.
//------------------------------------------------------------------------------
// Server interface procedures and functions of common use for working with:
// - saving/reading/deleting settings to/from storages.
//

////////////////////////////////////////////////////////////////////////////////
#Region PUBLIC_INTERFACE

// Set default value of setting defined for the passed user.
// Use common settings storage for saving of user settings.
//
// Parameters:
//  Setting   - String    - Setting name.
//  Value     - Arbitrary - Value of setting.
//  User      - String    - User defining setting (current user by default).
//
Procedure SetValueAsDefault(Setting, Value, User = Undefined) Export 

	// Get current setting value.
	CurrentValueByDefault = GetValueByDefault(Setting,, User);
	
	// Check value type and compare old and new value.
	If TypeOf(Value) <> TypeOf(CurrentValueByDefault)
	Or Value <> CurrentValueByDefault Then
		
		// Save new value of setting.
		CommonSettingsStorage.Save(Upper(Setting),, Value,, User);
		
	EndIf;

EndProcedure

// Get default value of setting defined for the passed user.
// Use common settings storage for saving of user settings.
//
// Parameters:
//  Setting   - String    - Setting name.
//  Default   - Arbitrary - Default (or empty) value of the same type as expected.
//                          or Undefined to skip value checking.
//  User      - String    - User for which setting was defined (current user by default).
//
// Returns:
//  Value     - Arbitrary - Value of setting.
//
Function GetValueByDefault(Setting, Default = Undefined, User = Undefined) Export
	
	// Get value from common storage.
	Value = CommonSettingsStorage.Load(Upper(Setting),,, User);
	
	// Check value is properly filled
	If  Default = Undefined Then
		// No value for compare provided: skip value checking.
		Return Value;
		
	ElsIf Value = Undefined                // No value defined for this setting.
	   Or TypeOf(Value) <> TypeOf(Default) // Value defined, but other type than expected.
	Then // Only default value defined.
		
		// Try to use the existing value in the database if only one defined.
		If CommonUse.IsReference(TypeOf(Default)) Then
			
			// Check presence of only one ref othis kind in database.
			OnlyOneRef = CommonUse.RefIfOnlyOne(TypeOf(Default));
			If OnlyOneRef <> Undefined Then
				
				// Save currently found value for the later use.
				CommonSettingsStorage.Save(Upper(Setting),, OnlyOneRef,, User);
				
				// Return set value.
				Return OnlyOneRef;
			EndIf;
		EndIf;
		
		// No proper value found.
		Return Default;
		
	// Both Value and Default are defined.
	ElsIf (Value <> Default) // This is not default (or empty) value (prevents empty search).
	  And (CommonUse.IsReference(TypeOf(Value)))   // This is value of reference type
	  And (Not CommonUse.RefExists(Value)) // And reference actually don't exist.
	Then // Value of proper type saved, but no more exists in the database.
		
		// Broken link found.
		CommonSettingsStorage.Delete(Upper(Setting),, User);
		
		// Try to get value once again.
		Return GetValueByDefault(Setting, Default, User);
		
	Else
		// Value of proper type.
		Return Value;
	EndIf;
	
EndFunction

#EndRegion
