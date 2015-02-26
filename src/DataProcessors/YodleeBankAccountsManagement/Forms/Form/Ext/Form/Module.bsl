﻿////////////////////////////////////////////////////////////////////////////////
// Online Bank accounts management form
//------------------------------------------------------------------------------
// Available on:
// - Client (managed application)
//

#REGION FORM_SERVER_FUNCTIONS
////////////////////////////////////////////////////////////////////////////////
// FORM SERVER FUNCTIONS

&AtServer
Procedure OnCreateAtServer(Cancel, StandardProcessing)
	
	If (Not Constants.ServiceDB.Get()) And (Not Parameters.PerformAddAccount) And (Not Parameters.PerformAssignAccount) Then
		Cancel = True;
		return;
	EndIf;
	
	//When working in the non-serviceDB then allow adding only offline accounts 
	If Parameters.PerformAddAccount And (Not Constants.ServiceDB.Get()) Then
		Items.OnlineAccount.ReadOnly = True;
		OnlineAccount = "Offline";
		Items.AccountDescription.Visible 	= True;
		Items.BankDetails.Visible			= False;
	Else
		OnlineAccount = "Online";
	EndIf;

	BankAccounts.Parameters.SetParameterValue("Bank", Catalogs.Banks.EmptyRef());
	Items.ProgressGroup.Visible = False;
	CurrentBankAccount = Parameters.RefreshAccount;
	PerformRefreshingAccount = Parameters.PerformRefreshingAccount;
	UploadTransactionsFrom = Parameters.UploadTransactionsFrom;
	UploadTransactionsTo = Parameters.UploadTransactionsTo;
	PerformAddAccount = Parameters.PerformAddAccount;
	PerformEditAccount = Parameters.PerformEditAccount;
	PerformAssignAccount = Parameters.PerformAssignAccount;
	If Parameters.PerformAddAccount OR Parameters.PerformEditAccount OR Parameters.PerformRefreshingAccount Or Parameters.PerformAssignAccount Then
		CalledForSingleOperation = True;
	EndIf;
	If PerformRefreshingAccount Then		
		Items.AccountsRefreshPage.Visible = False;
		Items.AccountAssignTypePage.Visible = False;
		Items.AccountEditPage.Visible = False;
		Items.AccountsAddPage.Visible = False;
		Items.AccountRefreshPage.Visible = True;
		//Delete white spaces to the right and to the left
		Items.RefreshLeftTab.Visible = False;
		Items.RefreshRightTab.Visible = False;
		Items.RefreshLowerTab.Visible = False;
		Items.GotoAssigningPage.Visible = False;
	EndIf;
	If PerformAddAccount Then
		Items.AccountsRefreshPage.Visible = False;
		Items.AccountEditPage.Visible = False;
		Items.AccountAssignTypePage.Visible = True;
		Items.AccountsAddPage.Visible = True;
		Items.AccountRefreshPage.Visible = True;
		//Delete white spaces to the right and to the left
		Items.AddLeftTab.Visible = False;
		Items.AddRightTab.Visible = False;
		
		Items.AssignLeftTab.Visible = False;
		Items.AssignRightTab.Visible = False;
		
		Items.RefreshLeftTab.Visible = False;
		Items.RefreshRightTab.Visible = False;
		Items.RefreshLowerTab.Visible = False;
		Items.GotoAssigningPage.Visible = False;
		
		//In the Demo mode adding new accounts is unavailable
		If Constants.PublicDemo.Get() Then
			Items.DemoConfigurationGroup.Visible = True;
			Items.AddAccounts.Enabled = False;
		EndIf;
	EndIf;
	If PerformEditAccount Then
		Items.AccountsRefreshPage.Visible = False;
		Items.AccountAssignTypePage.Visible = False;
		Items.AccountsAddPage.Visible = False;
		Items.AccountEditPage.Visible = True;
		Items.AccountRefreshPage.Visible = True;
		//Edit page. Delete white spaces to the right and to the left
		Items.EditLeftTab.Visible = False;
		Items.EditRightTab.Visible = False;
		Items.EditLowerTab.Visible =  False;
		//Refresh page. Delete white spaces to the right and to the left
		Items.RefreshLeftTab.Visible = False;
		Items.RefreshRightTab.Visible = False;
		Items.RefreshLowerTab.Visible = False;
		Items.GotoAssigningPage.Visible = False;
	EndIf;
	If PerformAssignAccount Then
		Items.AccountsRefreshPage.Visible = False;
		Items.AccountEditPage.Visible = False;
		Items.AccountAssignTypePage.Visible = True;
		Items.AccountsAddPage.Visible = False;
		Items.AccountRefreshPage.Visible = False;
		//Assign page. Delete white spaces to the right and to the left
		Items.AssignLeftTab.Visible = False;
		Items.AssignLeftTab.Visible = False;

		Items.Pages.CurrentPage = Items.AccountAssignTypePage;
		Items.AssigningSuccessGroup.BackColor = Items.Group13.BackColor;
		Items.AssigningSuccessPicture.Picture = New Picture();
		Items.AssigningSuccessReason.Title = "";
		If PerformAssignAccount Then
			Items.AssigningAccountTypeConnect.Visible = False;
		Else
			Items.AssigningAccountTypeConnect.Visible = True;
		EndIf;
		FillAssigningTable();
		FillAvailableAccounts(ThisForm);
		ApplyConditionalAppearance();
	EndIf;
	
	If Items.AccountAssignTypePage.Visible Then
		ApplyConditionalAppearance();
	EndIf;
EndProcedure

&AtServer
Procedure ApplyConditionalAppearance()
	
	CA = ThisForm.ConditionalAppearance; 
 	CA.Items.Clear(); 
	
	//Highlighting Account type column with pink back-color
	ElementCA = CA.Items.Add(); 
	
	FieldAppearance = ElementCA.Fields.Items.Add(); 
	FieldAppearance.Field = New DataCompositionField("AssigningAccountTypeAccountType"); 
 	FieldAppearance.Use = True; 

	FilterElement = ElementCA.Filter.Items.Add(Type("DataCompositionFilterItem")); // current row filter 
	FilterElement.LeftValue 		= New DataCompositionField("AssigningAccountType.AssigningFailed"); 
	FilterElement.ComparisonType 	= DataCompositionComparisonType.Equal; 
	FilterElement.RightValue 		= True; 
	FilterElement.Use				= True;
	
	ElementCA.Appearance.SetParameterValue("BackColor", WebColors.MistyRose);
	
	//Inform the user about the creation of a new G/L account
	ElementCA = CA.Items.Add(); 
	
	FieldAppearance = ElementCA.Fields.Items.Add(); 
	FieldAppearance.Field = New DataCompositionField("AssigningAccountTypeAccountType"); 
	FieldAppearance.Use = True; 

	FilterElement = ElementCA.Filter.Items.Add(Type("DataCompositionFilterItem")); // current row filter 
	FilterElement.LeftValue 		= New DataCompositionField("AssigningAccountType.AccountType"); 
	FilterElement.ComparisonType 	= DataCompositionComparisonType.Equal; 
	FilterElement.RightValue 		= ChartsOfAccounts.ChartOfAccounts.EmptyRef(); 
	FilterElement.Use				= True;
		
	ElementCA.Appearance.SetParameterValue("Text", "Create new or map to existing...");
	ElementCA.Appearance.SetParameterValue("TextColor", WebColors.Green);
	ElementCA.Appearance.SetParameterValue("MarkIncomplete", True);
		
	ElementCA = CA.Items.Add(); 
	
	FieldAppearance = ElementCA.Fields.Items.Add(); 
	FieldAppearance.Field = New DataCompositionField("AssigningAccountTypeAccountType"); 
	FieldAppearance.Use = True; 

	FilterElement = ElementCA.Filter.Items.Add(Type("DataCompositionFilterItem")); // current row filter 
	FilterElement.LeftValue 		= New DataCompositionField("AssigningAccountType.AccountType"); 
	FilterElement.ComparisonType 	= DataCompositionComparisonType.Equal; 
	FilterElement.RightValue 		= Undefined; 
	FilterElement.Use				= True;
		
	ElementCA.Appearance.SetParameterValue("Text", "Create new or map to existing...");
	ElementCA.Appearance.SetParameterValue("TextColor", WebColors.Green);
	ElementCA.Appearance.SetParameterValue("MarkIncomplete", True);

		
	ElementCA = CA.Items.Add();
		
	FieldAppearance = ElementCA.Fields.Items.Add(); 
	FieldAppearance.Field = New DataCompositionField("AssigningAccountTypeAccountType"); 
	FieldAppearance.Use = True; 

	FilterElement = ElementCA.Filter.Items.Add(Type("DataCompositionFilterItem")); // current row filter 
	FilterElement.LeftValue 		= New DataCompositionField("AssigningAccountType.AccountType"); 
	FilterElement.ComparisonType 	= DataCompositionComparisonType.Equal; 
	FilterElement.RightValue 		= 1; 
	FilterElement.Use				= True;
					
	ElementCA.Appearance.SetParameterValue("Text", "Create new G/L account...");

EndProcedure

&AtServerNoContext
Procedure AddItemsAtServer(Bank, ProgrammaticElems, YodleeStorage, TempStorageAddress)
	//Prepare data for background execution
	ProcParameters = New Array;
 	ProcParameters.Add(Bank.ServiceID);
	ProcParameters.Add(ProgrammaticElems);
	ProcParameters.Add(YodleeStorage);
 	ProcParameters.Add(TempStorageAddress);
	
	//Performing background operation
	JobTitle = NStr("en = 'Adding an account at Yodlee server'");
	Job = BackgroundJobs.Execute("Yodlee.AddItem_AddItem", ProcParameters, , JobTitle);

EndProcedure

&AtServerNoContext
Procedure UpdateItemsCredentialsAtServer(BankAccount, ProgrammaticElems, YodleeStorage, TempStorageAddress)
	//Prepare data for background execution
	ProcParameters = New Array;
 	ProcParameters.Add(BankAccount.ItemID);
	ProcParameters.Add(ProgrammaticElems);
	ProcParameters.Add(YodleeStorage);
 	ProcParameters.Add(TempStorageAddress);
	
	//Performing background operation
	JobTitle = NStr("en = 'Updating account credentials at Yodlee server'");
	Job = BackgroundJobs.Execute("Yodlee.EditItem_UpdateEditedItem", ProcParameters, , JobTitle);
EndProcedure
	
&AtServerNoContext
Function GetBankAccountByItemID(newItemID)
	Request = New Query("SELECT ALLOWED
	                    |	BankAccounts.Ref
	                    |FROM
	                    |	Catalog.BankAccounts AS BankAccounts
	                    |WHERE
	                    |	BankAccounts.ItemID = &ItemID");
	Request.SetParameter("ItemID", newItemID);
	Result = Request.Execute();
	If Result.IsEmpty() Then
		return Catalogs.BankAccounts.EmptyRef();
	Else
		Sel = Result.Select();
		Sel.Next();
		return Sel.Ref;
	EndIf;
EndFunction

&AtServerNoContext
Procedure GetMFAFormFieldsAtServer(Bank, TempStorageAddress)
	
	//Prepare data for background execution
	ProcParameters = New Array;
 	ProcParameters.Add(Bank.ServiceID);
 	ProcParameters.Add(TempStorageAddress);
	
	//Performing background operation
	JobTitle = NStr("en = 'Obtaining MFA fields from Yodlee'");
	Job = BackgroundJobs.Execute("Yodlee.AddItem_GetFormFields", ProcParameters, , JobTitle);

EndProcedure

&AtServerNoContext
Procedure UpdateBankAccountsAtServer(DeleteUninitializedAccounts = False, CurrentBankAccount, TempStorageAddress)
	Params = New Array();
	If DeleteUninitializedAccounts Then
		Params.Add(Undefined);
		Params.Add(True);
		Params.Add(CurrentBankAccount);
		Params.Add(TempStorageAddress);
	EndIf;
	LongActions.ExecuteInBackground("Yodlee.YodleeUpdateBankAccounts", Params);
EndProcedure

&AtServerNoContext
Function ContinueMFARefreshAtServer(ProgrammaticElems, Params, TempStorageAddress)
	//Prepare data for background execution
	ProcParameters = New Array;
 	ProcParameters.Add(ProgrammaticElems);
	ProcParameters.Add(Params);
	ProcParameters.Add(TempStorageAddress);
 		
	//Performing background operation
	JobTitle = NStr("en = 'Processing user response in the refresh bank account process'");
	Job = BackgroundJobs.Execute("Yodlee.ContinueMFARefresh", ProcParameters, , JobTitle);

EndFunction

//Starts the refresh procedure on an account with ItemID
&AtServerNoContext
Procedure RefreshItemAtServer(ItemID, TempStorageAddress)
	//Prepare data for background execution
	ProcParameters = New Array;
 	ProcParameters.Add(ItemID);
	ProcParameters.Add(Undefined);
	ProcParameters.Add(Undefined);
 	ProcParameters.Add(TempStorageAddress);
	
	//Performing background operation
	JobTitle = NStr("en = 'Starting the refresh bank account process'");
	Job = BackgroundJobs.Execute("Yodlee.RefreshItem", ProcParameters, , JobTitle);
EndProcedure

&AtServerNoContext
Procedure EditAccountAtServer(ItemID, TempStorageAddress)
	//Prepare data for background execution
	ProcParameters = New Array;
 	ProcParameters.Add(ItemID);
	ProcParameters.Add(TempStorageAddress);
	
	//Performing background operation
	JobTitle = NStr("en = 'Starting the editing bank account process'");
	Job = BackgroundJobs.Execute("Yodlee.EditItem_GetFormFields", ProcParameters, , JobTitle);
		
EndProcedure

&AtServerNoContext
Procedure RefreshTransactionsAtServer(CurrentBankAccount, TempStorageAddress, UploadTransactionsFrom, UploadTransactionsTo, YodleeStorage = Undefined)
	//Prepare data for background execution
	ProcParameters = New Array;
 	ProcParameters.Add(CurrentBankAccount);
	ProcParameters.Add(TempStorageAddress);
	ProcParameters.Add(YodleeStorage);
	ProcParameters.Add(UploadTransactionsFrom);
	ProcParameters.Add(UploadTransactionsTo);	
	
	//Performing background operation
	JobTitle = NStr("en = 'Refreshing transactions of the bank account'");
	//Job = BackgroundJobs.Execute("Yodlee.ViewTransactions", ProcParameters, , JobTitle);
	Job = BackgroundJobs.Execute("Yodlee.RefreshTransactionsOfGroupOfAccounts", ProcParameters, , JobTitle);
EndProcedure

&AtServerNoContext
Function RemoveAccountAtServer(ItemID)
	ReturnStruct = Yodlee.RemoveItem(ItemID);
	If (ReturnStruct.ReturnValue) OR (Find(ReturnStruct.Status, "InvalidItemExceptionFaultMessage")) Then
		//Mark bank account as non-Yodlee
		AccRequest = New Query("SELECT
		                         |	BankAccounts.Ref
		                         |FROM
		                         |	Catalog.BankAccounts AS BankAccounts
		                         |WHERE
		                         |	BankAccounts.ItemID = &ItemID");
		AccRequest.SetParameter("ItemID", ItemID);
		AccSelection = AccRequest.Execute().Select();
		While AccSelection.Next() Do
			Try
				AccObject = AccSelection.Ref.GetObject();
				AccObject.YodleeAccount = False;
				AccObject.Write();
			Except
			EndTry;				
		EndDo;
	EndIf;
	return ReturnStruct;
EndFunction

&AtServerNoContext
Procedure RefreshListAtServer()
	Yodlee.YodleeUpdateBankAccounts(, True);
EndProcedure

&AtServerNoContext
Function GetLogotypeAddress(Bank)
	If ValueIsFilled(Bank.Logotype.Get()) Then
		LogotypeAddress = GetURL(Bank, "Logotype");
	ElsIf ValueIsFilled(Bank.Icon.Get()) Then
		LogotypeAddress = GetURL(Bank, "Icon");
	Else		
		LogotypeAddress = "";
	EndIf;
	return LogotypeAddress;
EndFunction

&AtServerNoContext
Function GetAccountsForAssigning(CurrentBankAccount)
	ItemID = CurrentBankAccount.ItemID;
	Request = New Query("SELECT ALLOWED
	                    |	BankAccounts.Ref AS BankAccount,
	                    |	BankAccounts.Description AS BankAccountDescription,
	                    |	BankAccounts.AccountType AS Type,
	                    |	BankAccounts.CurrentBalance,
	                    |	BankAccounts.AccountingAccount AS AccountType,
	                    |	CASE
	                    |		WHEN BankAccounts.DeletionMark = TRUE
	                    |			THEN FALSE
	                    |		ELSE TRUE
	                    |	END AS Connect,
	                    |	CASE
	                    |		WHEN BankAccount.Value = VALUE(ChartOfAccounts.ChartOfAccounts.EmptyRef)
	                    |			THEN FALSE
	                    |		ELSE TRUE
	                    |	END AS DefaultBankAccountFilled
	                    |FROM
	                    |	Catalog.BankAccounts AS BankAccounts,
	                    |	Constant.BankAccount AS BankAccount
	                    |WHERE
	                    |	(BankAccounts.ItemID = &ItemID
	                    |				AND BankAccounts.ItemID <> 0
	                    |			OR BankAccounts.Ref = &CurrentBankAccount)");
	Request.SetParameter("ItemID", ItemID);
	Request.SetParameter("CurrentBankAccount", CurrentBankAccount);
	Sel = Request.Execute().Select();
	AvailableList = New Array();
	While Sel.Next() Do
		AvailableList.Add(New Structure("BankAccount, BankAccountDescription, Type, CurrentBalance, AccountType, Connect, DefaultBankAccountFilled"));
		FillPropertyValues(AvailableList[AvailableList.Count()-1], Sel);
	EndDo;
	return AvailableList;
EndFunction

&AtServerNoContext
Function GetAvailableListOfAccounts(CurrentAccountType = Undefined, CurrentBankAccount = Undefined)
	Request = New Query("SELECT ALLOWED
	                    |	ChartOfAccounts.Ref,
	                    |	ChartOfAccounts.AccountType,
	                    |	ChartOfAccounts.Code,
	                    |	ChartOfAccounts.Description
	                    |FROM
	                    |	ChartOfAccounts.ChartOfAccounts AS ChartOfAccounts
	                    |		LEFT JOIN Catalog.BankAccounts AS BankAccounts
	                    |		ON (BankAccounts.AccountingAccount = ChartOfAccounts.Ref)
	                    |WHERE
	                    |	BankAccounts.Ref IS NULL 
	                    |	AND ChartOfAccounts.AccountType IN(&ListOfAvailableTypes)");
	ListOfAvailableTypes = New ValueList();
	ListOfAvailableTypes.Add(Enums.AccountTypes.Bank);
	ListOfAvailableTypes.Add(Enums.AccountTypes.OtherCurrentAsset);
	ListOfAvailableTypes.Add(Enums.AccountTypes.OtherCurrentLiability);
	Request.SetParameter("ListOfAvailableTypes", ListOfAvailableTypes);
	RequestRes = Request.Execute();
	AvailableList = New ValueList();
	If Not RequestRes.IsEmpty() Then
		Sel = RequestRes.Select();
		While Sel.Next() Do
			//AvailableList.Add(Sel.Ref, String(Sel.AccountType) + " (" + String(Sel.Code) + "-" + TrimAll(Sel.Description) + ")");
			AvailableList.Add(Sel.Ref, String(Sel.Code) + "-" + TrimAll(Sel.Description));
		EndDo;
	EndIf;
	If (CurrentAccountType <> Undefined) And (CurrentAccountType <> 1) Then
		If AvailableList.FindByValue(CurrentAccountType) = Undefined Then
			//AvailableList.Add(CurrentAccountType, String(CurrentAccountType.AccountType) + " (" + String(CurrentAccountType.Code) + "-" + TrimAll(CurrentAccountType.Description) + ")");
			AvailableList.Add(CurrentAccountType, String(CurrentAccountType.Code) + "-" + TrimAll(CurrentAccountType.Description));
		EndIf;
	EndIf;
	If (CurrentBankAccount <> Undefined) Then
		BankAA = CurrentBankAccount.AccountingAccount;
		If ValueIsFilled(CurrentBankAccount.AccountingAccount) And (BankAA <> CurrentAccountType) Then
			//AvailableList.Add(BankAA, String(BankAA.AccountType) + " (" + String(BankAA.Code) + "-" + TrimAll(BankAA.Description) + ")");	
			AvailableList.Add(BankAA, String(BankAA.Code) + "-" + TrimAll(BankAA.Description));	
		EndIf;
	EndIf;
	return AvailableList;
EndFunction

&AtServerNoContext
Function AssignAccountTypeAtServer(Val CurrentBankAccount, Val BankAccountType, Val Connect = True, Val SetAsDefault = False)
	ReturnStructure = New Structure("ReturnValue, ErrorMessage", True, "");
	If (CurrentBankAccount.AccountingAccount = BankAccountType) And (ValueIsFilled(CurrentBankAccount.AccountingAccount)) Then
		ReturnStructure.ReturnValue = True;
		return ReturnStructure;
	EndIf;
	BeginTransaction(DataLockControlMode.Managed);
	
	//Set DataLock on ChartOfAccounts
	GLLock = New DataLock();
	LockItem = GLLock.Add("ChartOfAccounts.ChartOfAccounts");
	LockItem.Mode = DataLockMode.Exclusive;
	GLLock.Lock();
	
	Try
		If Connect Then
			BAObject = CurrentBankAccount.GetObject();
			//Create appropriate G/L account 
			If (Not ValueIsFilled(BankAccountType)) Or (BankAccountType = 1) Then
				NewGLAccount = ChartsOfAccounts.ChartOfAccounts.CreateAccount();
				NewGLAccount.Description = CurrentBankAccount.Description;
				If CurrentBankAccount.Owner.ContainerType = Enums.YodleeContainerTypes.Bank Then
					NewGLAccount.AccountType = Enums.AccountTypes.Bank;
					NewGLAccount.Currency = GeneralFunctionsReusable.DefaultCurrency(); // KZ 11/19/14
					StartCode = "1000";
					EndCode = "2000";
					NewCode = GeneralFunctions.FindVacantCode(StartCode, EndCode, Enums.AccountTypes.Bank);
				Else
					NewGLAccount.AccountType 	= Enums.AccountTypes.OtherCurrentLiability;
					NewGLAccount.CreditCard		= True;
					StartCode = "2100";
					EndCode = "3000";
					NewCode = GeneralFunctions.FindVacantCode(StartCode, EndCode, Enums.AccountTypes.OtherCurrentLiability);
				EndIf;
				If Not ValueIsFilled(NewCode) Then
					UM = GetUserMessages(True);
					If UM.Count()>0 Then
						ReturnStructure.ErrorMessage = UM[0].Text;
					Else
						ReturnStructure.ErrorMessage = "Couldn't create the new G/L account """ + CurrentBankAccount.Description + """"
						+ " for no vacant code found between " + StartCode + " and " + EndCode;
					EndIf;
					ReturnStructure.ReturnValue = False;
					return ReturnStructure;
				EndIf;
				NewGLAccount.Code = NewCode;
				NewGLAccount.Order = NewCode;
				NewGLAccount.Write();
				BAObject.AccountingAccount = NewGLAccount.Ref;
				ReturnStructure.Insert("NewGLAccount", NewGLAccount.Ref);
			Else
				BAObject.AccountingAccount = BankAccountType;
			EndIf;
			GetUserMessages(True);
		Else
			BAObject = CurrentBankAccount.GetObject();
			//BAObject.DeletionMark = True;
			GetUserMessages(True);
		EndIf;

		If Connect Then
			BAObject.Write();
		Else
			//Reflect this in Register
			RecordSet = InformationRegisters.DisconnectedBankAccounts.CreateRecordSet();
			ItemIdFilter = RecordSet.Filter.ItemID;
			ItemAccountIDFilter = RecordSet.Filter.ItemAccountID;
			ItemIDFilter.Use = True;
			ItemIDFilter.ComparisonType = ComparisonType.Equal;
			ItemIDFilter.Value = CurrentBankAccount.ItemID;
			ItemAccountIDFilter.Use = True;
			ItemAccountIDFilter.ComparisonType = ComparisonType.Equal;
			ItemAccountIDFilter.Value = CurrentBankAccount.ItemAccountID;
			NewRecord = RecordSet.Add();
			NewRecord.Active =  True;
			NewRecord.ItemID = CurrentBankAccount.ItemID;
			NewRecord.ItemAccountID = CurrentBankAccount.ItemAccountID;
			RecordSet.Write(True);
			BAObject.Delete();
		EndIf;
		If SetAsDefault Then
			Constants.BankAccount.Set(BankAccountType);
		EndIf;
		CommitTransaction();
	Except
		ErrorDesc = ErrorDescription();
		If TransactionActive() Then
			RollbackTransaction();
		EndIf;
		UM = GetUserMessages(True);
		If UM.Count()>0 Then
			ReturnStructure.ErrorMessage = UM[0].Text;
		Else
			ReturnStructure.ErrorMessage = ErrorDesc;
		EndIf;
		ReturnStructure.ReturnValue = False;	
	EndTry;
	return ReturnStructure;
EndFunction

&AtServerNoContext
Function CreateNewOfflineBankAccount(Bank, Description)
	
	If Bank = Catalogs.Banks.EmptyRef() Then
		//Try to find the Offline bank, if not found then create the new one
		Request = New Query("SELECT
		                    |	Banks.Ref
		                    |FROM
		                    |	Catalog.Banks AS Banks
		                    |WHERE
		                    |	Banks.Code = ""000000000""");
		Res = Request.Execute();
		If Res.IsEmpty() Then
			SetPrivilegedMode(True);
			OfflineBank = Catalogs.Banks.CreateItem();
			OfflineBank.Code 		= "000000000";
			OfflineBank.Description = "Offline bank";
			OfflineBank.Write();
			SetPrivilegedMode(False);
			Bank = OfflineBank.Ref;
		Else
			Sel = Res.Select();
			Sel.Next();
			Bank = Sel.Ref;
		EndIf;
	EndIf;
	NewAccount = Catalogs.BankAccounts.CreateItem();
	NewAccount.Owner = Bank;
	NewAccount.Description = Description;
	NewAccount.Write();
	return NewAccount.Ref;
	
EndFunction

&AtServerNoContext
Function RemoveBankAccountAtServer(AccountForDeletionIfCancelled, RemoveFromYodlee = True)
	return Yodlee.RemoveBankAccountAtServer(AccountForDeletionIfCancelled, RemoveFromYodlee);
EndFunction

#ENDREGION

#REGION FORM_COMMAND_HANDLERS 
////////////////////////////////////////////////////////////////////////////////
// FORM COMMAND HANDLERS

&AtClient
Procedure OnOpen(Cancel)
	If PerformRefreshingAccount Then
		ItemID = CommonUse.GetAttributeValue(CurrentBankAccount, "ItemID");
		RefreshBankAccount(ItemID);
	EndIf;
	If PerformAddAccount Then
		GotoAddAccountsPage(Undefined);
	EndIf;		
	If PerformEditAccount Then
		ItemID = CommonUse.GetAttributeValue(CurrentBankAccount, "ItemID");
		EditAccountCredentials(ItemID);		
	EndIf;
EndProcedure

&AtClient
Procedure OnClose()
	// Remove newly added bank account(s) if operation cancelled
	If ValueIsFilled(AccountForDeletionIfCancelled) Then
		RemoveBankAccountAtServer(AccountForDeletionIfCancelled, False);
	EndIf;
EndProcedure

&AtClient
Procedure OnlineAccountOnChange(Item)
	If OnlineAccount = "Online" Then
		Items.AccountDescription.Visible = False;
	ElsIf OnlineAccount = "Offline" Then
		Items.AccountDescription.Visible = True;
	EndIf;
EndProcedure

&AtClient
Procedure GotoAssigningPage(Command)
	Items.Pages.CurrentPage = Items.AccountAssignTypePage;
	//Items.AssigningSuccessGroup.Visible = False;
	Items.AssigningSuccessGroup.BackColor = Items.Group13.BackColor;
	Items.AssigningSuccessPicture.Picture = New Picture();
	Items.AssigningSuccessReason.Title = "";
	If PerformAssignAccount Then
		Items.AssigningAccountTypeConnect.Visible = False;
	Else
		Items.AssigningAccountTypeConnect.Visible = True;
	EndIf;
	GotoAssigningPageAtServer();
EndProcedure

&AtServer
Procedure GotoAssigningPageAtServer()
	FillAssigningTable();
	FillAvailableAccounts(ThisForm);
	ApplyConditionalAppearance();
EndProcedure

&AtClient
Procedure AddAccounts(Command)
	
	If OnlineAccount = "Online" Then
		//Put progress description to temp storage
		Progress = New Structure("Params, CurrentStatus, Step",, "Obtaining authorization fields from server...", 1);
		TempStorageAddress = PutToTempStorage(Progress, ThisForm.UUID);
		GetMFAFormFieldsAtServer(Bank, TempStorageAddress);
	
		//Show the ProgressGroup, Attach idle handler
	
		Items.AddingAccountProgress.Title = "Obtaining authorization fields from server...";
		Items.BankDetails.Visible = False;
		Items.ProgressGroup.Visible = True;
		AttachIdleHandler("DispatchAddAccount", 0.1, True);
		
	ElsIf OnlineAccount = "Offline" Then //Creating "manual" bank account just in database
		
		CurrentBankAccount = CreateNewOfflineBankAccount(Bank, AccountDescription);
		
		AccountForDeletionIfCancelled = CurrentBankAccount;
		
		GotoAssigningPage(Undefined);
		
	EndIf;
	
EndProcedure

&AtClient
Procedure GotoRefreshPage(Command)
	If CalledForSingleOperation Then //Called from other forms for specific operations
		ReturnArray = New Array();
		If (AssigningAccountType.Count() > 0) And (Not ValueIsFilled(AccountForDeletionIfCancelled)) Then
			For Each AAT In AssigningAccountType Do
				If AAT.Connect Then
					ReturnArray.Add(AAT.BankAccount);
				EndIf;
			EndDo;
		EndIf;
		Close(ReturnArray);
	Else
		Items.BankAccounts.Refresh();
		Items.Pages.CurrentPage = Items.AccountsRefreshPage;
	EndIf;
EndProcedure

&AtClient
Procedure RefreshAccount(Command)
	PerformRefreshingAccount = True;
	CurrentBankAccount = Items.BankAccounts.CurrentRow;
	CurData = Items.BankAccounts.CurrentData;
	If CurData = Undefined Then 
		return;
	EndIf;
	ItemID = CurData.ItemID;  
	RefreshBankAccount(ItemID);		
EndProcedure

&AtClient
Procedure RemoveAccount(Command)
	CurrentLine = Items.BankAccounts.CurrentData;
	If CurrentLine <> Undefined Then
		ReturnStruct = RemoveAccountAtServer(CurrentLine.ItemID);
		If ReturnStruct.returnValue Then
			ShowMessageBox(, ReturnStruct.Status,,"Removing bank account");
		Else
			If Find(ReturnStruct.Status, "InvalidItemExceptionFaultMessage") Then
				ShowMessageBox(, "Account not found.",,"Removing bank account");
			Else
				ShowMessageBox(, ReturnStruct.Status,,"Removing bank account");
			EndIf;
		EndIf;
	EndIf;
	UpdateBankAccounts();
EndProcedure

&AtClient
Procedure RefreshList(Command)
	RefreshListAtServer();
	Items.BankAccounts.Refresh();
EndProcedure

&AtClient
Procedure GotoAddAccountsPage(Command)
	Items.Pages.CurrentPage = Items.AccountsAddPage;
EndProcedure

&AtClient
Procedure EditAccount(Command)
	CurrentBankAccount = Items.BankAccounts.CurrentRow;
	CurData = Items.BankAccounts.CurrentData;
	If CurData = Undefined Then 
		return;
	EndIf;
	ItemID = CurData.ItemID; 
	EditAccountCredentials(ItemID);
EndProcedure

&AtClient
Procedure BankOnChange(Item)
	FillDetailsAtServer();
EndProcedure

&AtClient
Procedure AssignAccountType(Command)
	If Not CheckDataFill() Then
		return;
	EndIf;
	FailReason = "";
	i = 1;
	For Each Str In AssigningAccountType Do
		ReturnStructure = AssignAccountTypeAtServer(Str.BankAccount, Str.AccountType, Str.Connect, Str.SetDefault);
		If Not ReturnStructure.ReturnValue Then
			CurrentFailReason = "Row #" + String(i) + ". Assigning failed. Reason: " + ReturnStructure.ErrorMessage + " Please, choose an account type once again.";
			FailReason = FailReason + ?(StrLen(FailReason)>0, Chars.CR + Chars.LF, "") + CurrentFailReason;
			Str.AssigningFailed = True;
			CurAccountType = CommonUse.GetAttributeValue(Str.BankAccount, "AccountingAccount");
			If Str.AccountType <> CurAccountType Then
				Str.AccountType = CurAccountType;
			EndIf;
		Else
			Str.AssigningFailed = False;	
			If (Not ValueIsFilled(Str.AccountType)) And (ReturnStructure.Property("NewGLAccount")) Then
				Str.AccountType = ReturnStructure.NewGLAccount;
			EndIf;
		EndIf;
		i = i + 1;
	EndDo;
	If ValueIsFilled(FailReason) Then // If an error occured
		Items.AssigningSuccessReason.Title = FailReason;
		Items.AssigningSuccessPicture.Picture = PictureLib.Warning32;
		Items.AssigningSuccessGroup.BackColor = Items.TooltipBackground.BackColor;
		FillAvailableAccounts(ThisForm);
	Else // If successful
		Items.AssigningSuccessReason.Title = "Account " + ?(AssigningAccountType.Count()>1, "types were", "type was") + " successfully assigned";
		Items.AssigningSuccessPicture.Picture = PictureLib.Information32;
		Items.AssigningSuccessGroup.BackColor = Items.TooltipBackground.BackColor;
		AccountForDeletionIfCancelled = PredefinedValue("Catalog.BankAccounts.EmptyRef");
	EndIf;
	NotifyChanged(Type("CatalogRef.BankAccounts"));
	If Not ValueIsFilled(FailReason) Then
		GotoRefreshPage(Undefined);//Finish
	EndIf;
EndProcedure

&AtClient
Procedure BankAccountTypeCreating(Item, StandardProcessing)
	StandardProcessing = False;
	Notify = New NotifyDescription("RefreshAvailableAccounts", ThisObject, New Structure("CurrentRow", Items.AssigningAccountType.CurrentRow));
	OpenForm("ChartOfAccounts.ChartOfAccounts.ObjectForm", New Structure(), ThisForm,,,,Notify,FormWindowOpeningMode.LockOwnerWindow);
EndProcedure

&AtClient
Procedure RefreshAvailableAccounts(NewAccount, Parameters) Export
	FillAvailableAccounts(ThisForm);
	ChoicesCount = Items.AssigningAccountTypeAccountType.ChoiceList.Count();
	If Parameters.Property("CurrentRow") And (ChoicesCount = 1) Then
		Items.AssigningAccountType.CurrentRow = Parameters.CurrentRow;
		Items.AssigningAccountType.CurrentData.AccountType = Items.AssigningAccountTypeAccountType.ChoiceList[0].Value;
	EndIf;
EndProcedure

&AtClient
Procedure GotoAssigningPageFromList(Command)
	CurrentBankAccount = Items.BankAccounts.CurrentRow;
	PerformAssignAccount = True;
	GotoAssigningPage(Command);
	PerformAssignAccount = False;
EndProcedure

&AtClient
Procedure AssigningAccountTypeOnActivateRow(Item)
	FillAvailableAccounts(ThisForm);
EndProcedure

#ENDREGION

#REGION OTHER_FUNCTIONS
////////////////////////////////////////////////////////////////////////////////
// OTHER FUNCTIONS

&AtClient
Function CheckDataFill()
	Result = True;
	i = 0;
	While i < AssigningAccountType.Count() Do
		CurAccount = AssigningAccountType[i];
		If Not CurAccount.Connect Then
			i = i + 1;
			Continue;
		EndIf;
		If CurAccount.AccountType = PredefinedValue("ChartOfAccounts.ChartOfAccounts.EmptyRef") Then
			Result = False;
			MessOnError = New UserMessage();
			MessOnError.Field = "AssigningAccountType[" + String(i) + "]." + "AccountType";
			MessOnError.Text  = "Please, choose whether to create a new G/L account or map to an existing one";
			MessOnError.Message();
		EndIf;
		//If Not ValueIsFilled(CurAccount.AccountType) Then
		//	Result = False;
		//	MessOnError = New UserMessage();
		//	//MessOnError.SetData(Object);
		//	MessOnError.Field = "AssigningAccountType[" + String(i) + "]." + "AccountType";
		//	MessOnError.Text  = "Field """ + "G/L account" + """ in row №" + String(i+1) + " is not filled";
		//	MessOnError.Message();
		//EndIf;
		i = i + 1;
	EndDo;
	Return Result;
EndFunction

&AtClient
Procedure GetMFAFields(ProgrammaticElems, Params) Export
	If TypeOf(ProgrammaticElems) <> Type("Array") Then
		ShowMessageBox(,"Operation failed. Try to repeat the operation",,"Adding bank accounts");
		Items.ProgressGroup.Visible = False;
		Items.BankDetails.Visible = True;
		return;
	EndIf;
	
	//Adding items at server
	//Put progress description to temp storage
	Progress = New Structure("Params, CurrentStatus, Step",, "Adding accounts at server...", 2);
	TempStorageAddress = PutToTempStorage(Progress, ThisForm.UUID);
	
	Items.AddingAccountProgress.Title = "Sending authorization reply to server...";
	Items.ProgressGroup.Visible = True;
	AttachIdleHandler("DispatchAddAccount", 0.1, True);
	
	AddItemsAtServer(Params.Bank, ProgrammaticElems, Params.YodleeStorage, TempStorageAddress);
	
EndProcedure

&AtClient
Procedure DispatchAddAccount() Export
	//Get current status from temp storage
	Progress = GetFromTempStorage(TempStorageAddress);
	If TypeOf(Progress) <> Type("Structure") Then
		Items.ProgressGroup.Visible = False;
		Items.BankDetails.Visible = True;
		ShowMessageBox(, "An error occured while adding an account",, "Adding bank account");
		return;
	EndIf;
	
	Items.AddingAccountProgress.Title = Progress.CurrentStatus;
	If TypeOf(Progress.Params) <> Type("Structure") Then
		AttachIdleHandler("DispatchAddAccount", 0.1, True);
		return;
	EndIf;
	
	Params = Progress.Params;
	
	If Progress.Step = 1 Then //Obtaining MFA fields
		
		If Not Params.ReturnValue Then
			ShowMessageBox(,"Operation failed. Try to repeat the operation",,"Adding bank accounts");
			Items.ProgressGroup.Visible = False;
			Items.BankDetails.Visible = True;
			return;
		EndIf;
		
		Params.Insert("FormTitle", "Adding account");
		Notify 	= New NotifyDescription("GetMFAFields", ThisObject, New Structure("YodleeStorage, Bank", Params.YodleeStorage, Bank));
		OpenForm("DataProcessor.YodleeBankAccountsManagement.Form.MFA", Params, ThisForm,,,,Notify,FormWindowOpeningMode.LockOwnerWindow);
		
	ElsIf Progress.Step = 2 Then //Adding a bank account at server
		
		If Params.NewItemID <> 0 Then
			AttachIdleHandler("DispatchAddAccount", 0.1, True);
			return;
		Else
			ShowCustomMessageBox(ThisForm, "Adding bank accounts","Operation failed. Try to repeat the operation", PredefinedValue("Enum.MessageStatus.Warning"));
			Items.ProgressGroup.Visible = False;
			Items.BankDetails.Visible = True;
		EndIf;	
	ElsIf Progress.Step = 3 Then
		CurrentBankAccount = GetBankAccountByItemID(Params.NewItemID);
		AccountForDeletionIfCancelled = CurrentBankAccount;
		RefreshBankAccount(Params.NewItemID);
		Items.ProgressGroup.Visible = False;
	EndIf;
	
EndProcedure

&AtClient 
Procedure UpdateAccountCredentials(ProgrammaticElems, Params) Export
	
	If TypeOf(ProgrammaticElems) <> Type("Array") Then
		ShowMessageBox(,"Operation failed. Try to repeat the operation",,"Updating bank accounts credentials");
		Items.ProgressGroup.Visible = False;
		return;
	EndIf;
	
	//Adding items at server
	//Put progress description to temp storage
	Progress = New Structure("Params, CurrentStatus, Step",, "Updating account credentials at server...", 2);
	TempStorageAddress = PutToTempStorage(Progress, ThisForm.UUID);
	
	Items.AddingAccountProgress.Title = "Sending authorization reply to server...";
	Items.ProgressGroup.Visible = True;
	AttachIdleHandler("DispatchEditAccount", 0.1, True);
	
	UpdateItemsCredentialsAtServer(Params.BankAccount, ProgrammaticElems, Params.YodleeStorage, TempStorageAddress);
	
EndProcedure

&AtClient
Procedure DispatchEditAccount() Export
	//Get current status from temp storage
	Progress = GetFromTempStorage(TempStorageAddress);
	If TypeOf(Progress) <> Type("Structure") Then
		Items.EditGroup.Visible = False;
		ShowMessageBox(, "An error occured while editing an account",, "Editing bank account");
		return;
	EndIf;
	
	Items.EditingAccountProgress.Title = Progress.CurrentStatus;
	If TypeOf(Progress.Params) <> Type("Structure") Then
		AttachIdleHandler("DispatchEditAccount", 0.1, True);
		return;
	EndIf;
	
	Params = Progress.Params;
	
	If Progress.Step = 1 Then //Obtaining MFA fields
		
		If Not Params.ReturnValue Then
			ShowMessageBox(,"Operation failed. Try to repeat the operation",,"Editing bank accounts");
			Items.EditGroup.Visible = False;
			return;
		EndIf;
		
		Params.Insert("FormTitle", "Editing account");
		Notify 	= New NotifyDescription("UpdateAccountCredentials", ThisObject, New Structure("YodleeStorage, BankAccount", Params.YodleeStorage, CurrentBankAccount));
		OpenForm("DataProcessor.YodleeBankAccountsManagement.Form.MFA", Params, ThisForm,,,,Notify,FormWindowOpeningMode.LockOwnerWindow);
		
	ElsIf Progress.Step = 2 Then //Adding a bank account at server
		
		If Params.Result = True Then
			RefreshBankAccount(Params.ItemID);
			Items.EditGroup.Visible = False;
			return;
		Else
			ShowCustomMessageBox(ThisForm, "Editing bank account","Operation failed. Try to repeat the operation", PredefinedValue("Enum.MessageStatus.Warning"));
			Items.EditGroup.Visible = False;
		EndIf;	
	EndIf;
	
EndProcedure

&AtClient
Procedure RefreshBankAccount(ItemID)
	//Put progress description to temp storage
	Progress = New Structure("Params, CurrentStatus, Step",, "Starting the refresh process...", 1);
	TempStorageAddress = PutToTempStorage(Progress, ThisForm.UUID);
	RefreshItemAtServer(ItemID, TempStorageAddress);
	
	//Show the ProgressGroup, Attach idle handler
	
	Items.RefreshingAccountProgress.Title = "Starting the refresh process...";
	HideMessageToTheUser();
	ShowProgress();
	AttachIdleHandler("DispatchRefreshAccount", 0.1, True);
		
	Items.Pages.CurrentPage = Items.AccountRefreshPage;
		
	Items.GotoAssigningPage.Visible = False;
EndProcedure

&AtClient 
Procedure EditAccountCredentials(ItemID)
	
	Progress = New Structure("Params, CurrentStatus, Step",, "Obtaining authorization fields from server...", 1);
	TempStorageAddress = PutToTempStorage(Progress, ThisForm.UUID);
	EditAccountAtServer(ItemID, TempStorageAddress);
		
	//Show the ProgressGroup, Attach idle handler
	Items.EditingAccountProgress.Title = "Obtaining authorization fields from server...";
	Items.EditGroup.Visible = True;
	AttachIdleHandler("DispatchEditAccount", 0.1, True);
	
	Items.Pages.CurrentPage = Items.AccountEditPage;

EndProcedure

&AtClient
Procedure OutputMessagesToTheUser()
	i = 0;
	While i < MessagesToTheUser.Count() Do
		Row = MessagesToTheUser.Get(i);
		If Row.Status = "SUCCESS" Then
			pict = PictureLib.Information32;
		ElsIf Row.Status = "FAIL" Then
			pict = PictureLib.Warning32;
		Else
			pict = New Picture();
		EndIf;
		If i = 0 Then //Output to SuccessGroup
			Items.RefreshSuccessIcon.Picture = pict;
			Items.DecorationSuccessReason.Title = Row.Message;
			Items.DecorationSuccessReason.Border = New Border(ControlBorderType.Overline);
			Items.RefreshSuccessGroup.BackColor = Items.Group7.BackColor;
		ElsIf i = 1 Then //Output to FailGroup
			Items.RefreshFailIcon.Picture = pict;		
			Items.DecorationFailReason.Title = Row.Message;
			Items.DecorationFailReason.Border = New Border(ControlBorderType.Overline);
			Items.RefreshFailGroup.BackColor = Items.Group7.BackColor;
		EndIf;
		i = i + 1;
	EndDo;
	If MessagesToTheUser.Count() < 2 Then
		Items.RefreshFailIcon.Picture = New Picture();		
		Items.DecorationFailReason.Title = "";
		Items.DecorationFailReason.Border = New Border(ControlBorderType.WithoutBorder);
		Items.RefreshFailGroup.BackColor = Items.AccountRefreshPage.BackColor;
	EndIf;
	If MessagesToTheUser.Count() < 1 Then
		Items.RefreshSuccessIcon.Picture = New Picture();
		Items.DecorationSuccessReason.Title = "";
		Items.DecorationSuccessReason.Border = New Border(ControlBorderType.WithoutBorder);
		Items.RefreshSuccessGroup.BackColor = Items.AccountRefreshPage.BackColor;
	EndIf;
	
EndProcedure

//
//MessageStatus = 0 - Information; 1 - Warning
//
&AtClient
Procedure ShowMessageToTheUser(MessageStatus, MessageText)
	AddMessageToTheUser(MessageStatus, MessageText);
	OutputMessagesToTheUser();
EndProcedure

//
//MessageStatus = 0 - Information; 1 - Warning
//
&AtClient
Procedure HideMessageToTheUser(MessageStatus = Undefined)
	AddMessageToTheUser(MessageStatus, "");
	OutputMessagesToTheUser();
EndProcedure

&AtClient
Procedure AddMessageToTheUser(MessageStatus, Message)
	i = 0;
	MessageIsSet =False;
	MessageStatus = Upper(MessageStatus);
	If (MessageStatus <> "SUCCESS") AND (MessageStatus <> "FAIL") Then
		return;
	EndIf;
	For Each Row In MessagesToTheUser Do
		If Row.Status = MessageStatus Then
			If ValueIsFilled(Message) Then
				Row.Message = Message;
			Else
				MessagesToTheUser.Delete(i);
			EndIf;
			MessageIsSet = True;
		EndIf;
		i  = i + 1;
	EndDo;
	If (Not MessageIsSet) And ValueIsFilled(Message) Then
		NewRow = MessagesToTheUser.Add();
		NewRow.Status = MessageStatus;
		NewRow.Message = Message;
	EndIf;
EndProcedure

&AtClient
Procedure ShowProgress()
	Items.RefreshProgressIcon.Picture = PictureLib.LongAction48;
EndProcedure

&AtClient
Procedure HideProgress(SuccessOrFail, Message = "")
	If SuccessOrFail Then //success
		Items.RefreshProgressIcon.Picture = PictureLib.TaskComplete;
		Items.RefreshingAccountProgress.Title = ?(Message = "", "Done!", Message);
	Else  //fail
		Items.RefreshProgressIcon.Picture = PictureLib.Questionnaire;
		Items.RefreshingAccountProgress.Title = ?(Message = "", "Error occured!", Message);
	EndIf;
EndProcedure

&AtClient
Procedure DispatchRefreshAccount() Export
	
	//Get current status from temp storage
	Progress = GetFromTempStorage(TempStorageAddress);
	If TypeOf(Progress) <> Type("Structure") Then
		HideProgress(False, "An error occured while refreshing an account");
		return;
	EndIf;
	
	Items.RefreshingAccountProgress.Title = Progress.CurrentStatus;
	If TypeOf(Progress.Params) <> Type("Structure") Then
		AttachIdleHandler("DispatchRefreshAccount", 0.1, True);
		return;
	EndIf;
	
	Params = Progress.Params;
	
	If Not Params.ReturnValue Then //An error occured during the refresh
		HideProgress(false);
		If Params.Property("Status") Then
			If ValueIsFilled(Params.Status) Then
				FailTitle = Params.Status;
				FailTitle = FailTitle + ?(Right(TrimAll(FailTitle),1)=".", "", ".") + ?(Find(Params.Status, "repeat") > 0, "", Chars.CR + "Try to repeat the operation after a while.");
			EndIf;
		EndIf;
		ShowMessageToTheUser("fail", FailTitle);
	EndIf;

	FinishedRefresh = False;
	If Progress.Step = 1 Then //Starting the refresh
		
		If Not Params.ReturnValue Then
			FinishedRefresh = True;						
		Else                       			
			AttachIdleHandler("DispatchRefreshAccount", 0.1, True);			
		EndIf;
						
	ElsIf Progress.Step = 2 Then //Started the refresh (for non-MFA sites) or obtaining MFA fields (for MFA)
		
		If Not Params.ReturnValue Then
			FinishedRefresh = True;
		Else
			AttachIdleHandler("DispatchRefreshAccount", 0.1, True);	
		EndIf;
		
	ElsIf Progress.Step = 3 Then //Finished the refresh (for non-MFA sites)
		If Params.ReturnValue Then
			ShowMessageToTheUser("Success", "Bank account was successfully refreshed");
		EndIf;
		
		FinishedRefresh = True;
		
	ElsIf Progress.Step = 4 Then //Processing MFA 
		If Params.ReturnValue Then
			If Params.isMFA Then
				//Open MFA form
				NotifyParams = New Structure("ItemId", Params.ItemID);
				NotifyParams.Insert("YodleeStorage", Params.YodleeStorage);
				Params.Insert("FormTitle", "Refreshing account");
				Notify 	= New NotifyDescription("ContinueMFARefresh", ThisObject, NotifyParams);
				OpenForm("DataProcessor.YodleeBankAccountsManagement.Form.MFA", Params, ThisForm,,,,Notify,FormWindowOpeningMode.LockOwnerWindow);
			EndIf;
		Else
			FinishedRefresh = True;
		EndIf;

	ElsIf Progress.Step = 5 Then //Polling refresh status. Finishing the refresh for MFA sites
		If Params.ReturnValue Then
			If Params.IsMFA Then //Wait for polling to finish
				AttachIdleHandler("DispatchRefreshAccount", 0.1, True);
			Else  //Successfully finished the refresh
				If Params.ReturnValue Then
					ShowMessageToTheUser("success", "Bank account was successfully refreshed");
				EndIf;
				FinishedRefresh = True;
			EndIf;
		Else
			FinishedRefresh = True;
		EndIf;
	ElsIf Progress.Step = 6 Then //Started uploading transactions
		If Params.ReturnValue Then
			AttachIdleHandler("DispatchRefreshAccount", 0.1, True);
		EndIf;
	ElsIf Progress.Step = 7 Then //Transactions upload is complete
		If Params.ReturnValue Then
			ShowMessageToTheUser("success", Progress.CurrentStatus);
		EndIf;
		UpdateBankAccounts(True, TempStorageAddress); //Final update of the accounts
		AttachIdleHandler("DispatchRefreshAccount", 0.1, True);
	ElsIf Progress.Step = 8 Then //Refreshing bank accounts requisites
		If Not Params.ReturnValue Then
			HideProgress(false);
		Else
			AttachIdleHandler("DispatchRefreshAccount", 0.1, True);
		EndIf;
	ElsIf Progress.Step = 9 Then //Refreshing bank accounts requisites has finished
		If Not PerformRefreshingAccount AND Not PerformEditAccount Then
			ItemAccountID = CommonUse.GetAttributeValue(CurrentBankAccount, "ItemAccountID");
			//Items.GotoAssigningPage.Visible = ValueIsFilled(ItemAccountID);	
			If ValueIsFilled(ItemAccountID) Then
				GotoAssigningPage(Undefined);
			Else
				If PerformAddAccount Then
					HideProgress(False, "An error occured. Account was not added!");
				Else
					HideProgress(False);
				EndIf;
				HideMessageToTheUser("success");
				CurrentBankAccount = PredefinedValue("Catalog.BankAccounts.EmptyRef");
			EndIf;
		Else
			HideProgress(true);
			If Not CalledForSingleOperation Then //Called from inside of this data processor
				PerformRefreshingAccount = False;
				PerformEditAccount = False;
			EndIf;
		EndIf;
		NotifyChanged(Type("CatalogRef.BankAccounts"));
	EndIf;
	
	//If the refresh process is complete - perform some actions
	If FinishedRefresh Then
		
		//If refreshing from Downloaded Transactions - need to refresh transactions
		ShowProgress();
		YodleeStorage = ?(Progress.Property("YodleeStorage"), Progress.YodleeStorage, Undefined);
		PutToTempStorage(New Structure("Params, CurrentStatus, Step", Undefined, "Started selecting transactions...", 6), TempStorageAddress);
		RefreshTransactionsAtServer(CurrentBankAccount, TempStorageAddress, UploadTransactionsFrom, UploadTransactionsTo, YodleeStorage);
		AttachIdleHandler("DispatchRefreshAccount", 0.1, True);
	EndIf;
	
EndProcedure

&AtClient
Procedure UpdateBankAccounts(DeleteUninitializedAccounts = False, TempStorageAddress = Undefined)
	UpdateBankAccountsAtServer(DeleteUninitializedAccounts, CurrentBankAccount, TempStorageAddress);
	//AttachIdleHandler("RefreshAccountsList", 0.2, True);
	//AttachIdleHandler("RefreshAccountsList", 3, True);
EndProcedure

&AtClient
Procedure RefreshAccountsList() Export
	Items.BankAccounts.Refresh();
EndProcedure

&AtClient
Procedure ContinueMFARefresh(ProgrammaticElems, Params) Export
	//Put progress description to temp storage
	Progress = New Structure("Params, CurrentStatus, Step",, "Sending user response to the server...", 4);
	PutToTempStorage(Progress, TempStorageAddress);

	Params = ContinueMFARefreshAtServer(ProgrammaticElems, Params, TempStorageAddress);
	
	AttachIdleHandler("DispatchRefreshAccount", 0.1, True);
	
	return;
	
	If TypeOf(Params) <> Type("Structure") Then
		return;
	EndIf;
	If Not Params.ReturnValue Then
		Items.BankAccounts.CurrentData.Status = Params.Status; 
		ShowMessageBox(,Params.Status,,"Refreshing bank accounts");
		UpdateBankAccounts();
		return;
	EndIf;
	If Params.isMFA Then
		//Open MFA form
		NotifyParams = New Structure("ItemId", Params.ItemID);
		NotifyParams.Insert("YodleeStorage", Params.YodleeStorage);
		Params.Insert("FormTitle", "Refreshing account");
		Notify 	= New NotifyDescription("ContinueMFARefresh", ThisObject, NotifyParams);
		OpenForm("DataProcessor.YodleeBankAccountsManagement.Form.MFA", Params, ThisForm,,,,Notify,FormWindowOpeningMode.LockOwnerWindow);
	Else
		UpdateBankAccounts();
		Items.BankAccounts.CurrentData.Status = Params.Status;
	EndIf;	
EndProcedure

&AtClient
Procedure ShowCustomMessageBox(FormOwner, Title = "", Message, MessageStatus = Undefined)
	If MessageStatus = Undefined Then 
		MessageStatus = PredefinedValue("Enum.MessageStatus.NoStatus");
	EndIf;
	If Not ValueIsFilled(Title) Then
		Title = "Message";
	EndIf;
	Params = New Structure("Title, Message, MessageStatus", Title, Message, MessageStatus);
	OpenForm("CommonForm.MessageBox", Params, FormOwner,,,,, FormWindowOpeningMode.LockOwnerWindow); 
EndProcedure

&AtServer
Procedure FillAssigningTable()
	AvailableList = GetAccountsForAssigning(CurrentBankAccount);
	AssigningAccountType.Clear();
	For Each AL IN AvailableList Do
		//After connecting bank accounts, show only undeleted items
		If (PerformAssignAccount = True) And (Not AL.Connect) Then
			Continue;
		EndIf;
		NewRow = AssigningAccountType.Add();
		FillPropertyValues(NewRow, AL);
		If AssigningAccountType.Count() = 1 And NOT AL.DefaultBankAccountFilled Then
			NewRow.SetDefault = True;
		EndIf;
		AvailableAccounts = GetAvailableListOfAccounts(, NewRow.BankAccount);
		//Exclude items already used
		For Each Str In AssigningAccountType Do
			If Str = NewRow Then
				Continue;
			EndIf;
			FoundItem = AvailableAccounts.FindByValue(Str.AccountType);
			If FoundItem <> Undefined Then
				AvailableAccounts.Delete(FoundItem);
			EndIf;
		EndDo;
		For Each AvailableAccount In AvailableAccounts Do
			Presentation = AvailableAccount.Presentation;
			Pos = Find(Presentation, NewRow.BankAccountDescription);
			If (Pos > 1) And Mid(Presentation, Pos-1, 1) = "-" Then
				NewRow.AccountType = AvailableAccount.Value;
				Break;
			EndIf;
		EndDo;
	EndDo;
EndProcedure

&AtClientAtServerNoContext 
Procedure FillAvailableAccounts(ThisForm)
	Items = ThisForm.Items;
	#If Client Then
	CurrentData = Items.AssigningAccountType.CurrentData;
	#EndIf
	#If Server Then
	CurrentData = Undefined;
	#EndIf
	If CurrentData <> Undefined Then
		If ValueIsFilled(CurrentData.AccountType) Then
			AvailableList = GetAvailableListOfAccounts(CurrentData.AccountType, CurrentData.BankAccount);
		Else
			AvailableList = GetAvailableListOfAccounts(, CurrentData.BankAccount);
		EndIf;
	Else
		AvailableList = GetAvailableListOfAccounts();	
	EndIf;
	
	AppropriateGLAccountFound = False;
	ChoiceList = Items.AssigningAccountTypeAccountType.ChoiceList;
	ChoiceList.Clear();
	For Each El IN AvailableList Do
		ChoiceList.Add(El.Value, El.Presentation);
		If CurrentData <> Undefined Then
			If Find(El.Presentation, CurrentData.BankAccountDescription) > 0 Then
				AppropriateGLAccountFound = True;
			EndIf;
		EndIf;
	EndDo;
	//Exclude items already used
	For Each Str In ThisForm.AssigningAccountType Do
		If Str = CurrentData Then
			Continue;
		EndIf;
		FoundItem = ChoiceList.FindByValue(Str.AccountType);
		If FoundItem <> Undefined Then
			ChoiceList.Delete(FoundItem);
		EndIf;
	EndDo;
	//If an account with the same name as bank account is absent then add one
	If Not AppropriateGLAccountFound And (CurrentData <> Undefined) Then
		//ChoiceList.Add(PredefinedValue("ChartOfAccounts.ChartOfAccounts.EmptyRef"), CurrentData.BankAccountDescription);
		//ChoiceList.Add(PredefinedValue("ChartOfAccounts.ChartOfAccounts.EmptyRef"), "Create new or map to existing...");
		ChoiceList.Add(1, "Create new G/L account...");
	EndIf;
EndProcedure

&AtClient
Procedure ChooseWellsFargo(Command)
	ChooseBankAtServer(5);
EndProcedure

&AtServer
Procedure ChooseBankAtServer(ServiceID)
	Request = New Query("SELECT
	                    |	Banks.Ref
	                    |FROM
	                    |	Catalog.Banks AS Banks
	                    |WHERE
	                    |	Banks.ServiceID = &ServiceID");
	Request.SetParameter("ServiceID", ServiceID);
	
	Result = Request.Execute();
	If Not Result.IsEmpty() Then
		BankTab = Result.Unload();
		Bank = BankTab[0].Ref;
		LogotypeAddress = GetLogotypeAddress(Bank);
		Items.ServiceURL.Title = Bank.ServiceURL;
	EndIf;	
EndProcedure

&AtServer
Procedure FillDetailsAtServer()
	LogotypeAddress = GetLogotypeAddress(Bank);
	Items.ServiceURL.Title = Bank.ServiceURL;
EndProcedure

&AtClient
Procedure ChooseAmericanExpressCreditCard(Command)
	ChooseBankAtServer(12);
EndProcedure

&AtClient
Procedure ChooseBankOfAmerica(Command)
	ChooseBankAtServer(2931);
EndProcedure

&AtClient
Procedure ChooseChaseBank(Command)
	ChooseBankAtServer(663);
EndProcedure

&AtClient
Procedure ChooseJPMorganChaseBank(Command)
	ChooseBankAtServer(663);
EndProcedure

&AtClient
Procedure ChoosePayPalBank(Command)
	ChooseBankAtServer(10817);
EndProcedure

&AtClient
Procedure ChooseUSBank(Command)
	ChooseBankAtServer(545);
EndProcedure

&AtClient
Procedure ChooseCapitalOneCreditCard(Command)
	ChooseBankAtServer(2935);
EndProcedure

&AtClient
Procedure ChooseSunTrustBank(Command)
	ChooseBankAtServer(12729);
EndProcedure

&AtClient
Procedure ChoosePNCBank(Command)
	ChooseBankAtServer(2199);
EndProcedure

&AtClient
Procedure ServiceURLURLProcessing(Item, URL, StandardProcessing)
	EndProcedure

&AtClient
Procedure ServiceURLClick(Item)
	StandardProcessing = false;
	If ValueIsFilled(Item.Title) Then
		GotoUrl(Item.Title);
	EndIf;
EndProcedure

&AtClient
Procedure AssigningAccountTypeSetDefaultOnChange(Item)
	// Only one bank account can be set as default
	CurrentData = Items.AssigningAccountType.CurrentData;
	If Not CurrentData.SetDefault Then
		return;
	EndIf;
	For Each Row In AssigningAccountType Do
		If Row.GetID() = Items.AssigningAccountType.CurrentRow Then
			Continue;
		EndIf;
		If Row.SetDefault Then
			Row.SetDefault = False;
		EndIf;
	EndDo;
	
EndProcedure

#ENDREGION