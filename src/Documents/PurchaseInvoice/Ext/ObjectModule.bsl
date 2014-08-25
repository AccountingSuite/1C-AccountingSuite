﻿
////////////////////////////////////////////////////////////////////////////////
// Purchase invoice: Object module
//------------------------------------------------------------------------------

////////////////////////////////////////////////////////////////////////////////
#Region EVENT_HANDLERS

#If Server Or ThickClientOrdinaryApplication Or ExternalConnection Then

Procedure BeforeWrite(Cancel, WriteMode, PostingMode)
	
	// Document date adjustment patch (tunes the date of drafts like for the new documents).
	If  WriteMode = DocumentWriteMode.Posting And Not Posted // Posting of new or draft (saved but unposted) document.
	And BegOfDay(Date) = BegOfDay(CurrentSessionDate()) Then // Operational posting (by the current date).
		// Shift document time to the time of posting.
		Date = CurrentSessionDate();
	EndIf;
	
	// Save document parameters before posting the document.
	If WriteMode = DocumentWriteMode.Posting
	Or WriteMode = DocumentWriteMode.UndoPosting Then
		
		// Save custom document parameters.
		Orders = LineItems.UnloadColumn("Order");
		GeneralFunctions.NormalizeArray(Orders);
		
		// Common filling of parameters.
		DocumentParameters = New Structure("Ref, Date, IsNew,   Posted, ManualAdjustment, Metadata,   Orders",
		                                    Ref, Date, IsNew(), Posted, ManualAdjustment, Metadata(), Orders);
		DocumentPosting.PrepareDataStructuresBeforeWrite(AdditionalProperties, DocumentParameters, Cancel, WriteMode, PostingMode);
	EndIf;
	
	// Precheck of register balances to complete filling of document posting.
	If WriteMode = DocumentWriteMode.Posting Then
		
		// Precheck of document data, calculation of temporary data, required for document posting.
		If (Not ManualAdjustment) Then
			DocumentParameters = New Structure("Ref, PointInTime,   Company, LineItems",
			                                    Ref, PointInTime(), Company, LineItems.Unload(, "Order, Product, Unit, Location, LocationActual, DeliveryDate, Project, Class, QtyUM"));
			Documents.PurchaseInvoice.PrepareDataBeforeWrite(AdditionalProperties, DocumentParameters, Cancel);
		EndIf;
		
	EndIf;
	
EndProcedure

Procedure FillCheckProcessing(Cancel, CheckedAttributes)
	
	// Create items filter by non-empty orders.
	FilledOrders = GeneralFunctions.InvertCollectionFilter(LineItems, LineItems.FindRows(New Structure("Order", Documents.PurchaseOrder.EmptyRef())));
	
	// Check doubles in items (to be sure of proper orders placement).
	GeneralFunctions.CheckDoubleItems(Ref, LineItems, "Product, Unit, Order, Location, DeliveryDate, Project, Class, LineNumber", FilledOrders, Cancel);
	
	// Check proper closing of order items by the invoice items.
	If Not Cancel Then
		Documents.PurchaseInvoice.CheckOrderQuantity(Ref, Date, Company, LineItems, FilledOrders, Cancel);
	EndIf;
	
EndProcedure

Procedure Filling(FillingData, StandardProcessing)
	
	// Filling new document or filling on the base of another document.
	If FillingData = Undefined Then
		// Filling of the new created document with default values.
		Currency         = Constants.DefaultCurrency.Get();
		ExchangeRate     = GeneralFunctions.GetExchangeRate(Date, Currency);
		APAccount        = Currency.DefaultAPAccount;
		LocationActual   = Catalogs.Locations.MainWarehouse;
		
	Else
		// Generate on the base of Purchase order & Item receipt.
		Cancel = False; TabularSectionData = Undefined;
		
		// 0. Custom check of purchase order for interactive generate of purchase invoice on the base of purchase order.
		If (TypeOf(FillingData) = Type("DocumentRef.PurchaseOrder"))
		And Not Documents.PurchaseInvoice.CheckStatusOfPurchaseOrder(Ref, FillingData) Then
			Cancel = True;
			Return;
		EndIf;
		
		// 1. Common filling of parameters.
		DocumentParameters = New Structure("Ref, Date, Metadata",
		                                    Ref, ?(ValueIsFilled(Date), Date, CurrentSessionDate()), Metadata());
		DocumentFilling.PrepareDataStructuresBeforeFilling(AdditionalProperties, DocumentParameters, FillingData, Cancel);
		
		// 2. Cancel filling on failed data.
		If Cancel Then
			Return;
		EndIf;
		
		// 3. Collect document data, available for filling, and fill created structure.
		Documents.PurchaseInvoice.PrepareDataStructuresForFilling(Ref, AdditionalProperties);
		
		// 4. Check collected data.
		DocumentFilling.CheckDataStructuresOnFilling(AdditionalProperties, Cancel);
		
		// 5. Fill document fields.
		If Not Cancel Then
			// Fill "draft" values to attributes (all including non-critical fields will be filled).
			FillPropertyValues(ThisObject, AdditionalProperties.Filling.FillingTables.Table_Attributes[0]);
			
			// Fill checked unique values to attributes (critical fields will be filled).
			FillPropertyValues(ThisObject, AdditionalProperties.Filling.FillingTables.Table_Check[0]);
			
			// Fill line items.
			For Each TabularSection In AdditionalProperties.Metadata.TabularSections Do
				If AdditionalProperties.Filling.FillingTables.Property("Table_" + TabularSection.Name, TabularSectionData) Then
					ThisObject[TabularSection.Name].Load(TabularSectionData);
				EndIf;
			EndDo;
		EndIf;
		
		// 6. Clear used temporary document data.
		DocumentFilling.ClearDataStructuresAfterFilling(AdditionalProperties);
		
	EndIf;
	
EndProcedure

Procedure OnCopy(CopiedObject)
	
	// Clear manual adjustment attribute.
	ManualAdjustment = False;
	
EndProcedure

Procedure Posting(Cancel, PostingMode)
	
	// 1. Common postings clearing / reactivate manual ajusted postings.
	DocumentPosting.PrepareRecordSetsForPosting(AdditionalProperties, RegisterRecords);
	
	// 2. Skip manually adjusted documents.
	If ManualAdjustment Then
		Return;
	EndIf;
	
	// 3. Create structures with document data to pass it on the server.
	DocumentPosting.PrepareDataStructuresBeforePosting(AdditionalProperties);
	
	// 4. Collect document data, available for posing, and fill created structure.
	Documents.PurchaseInvoice.PrepareDataStructuresForPosting(Ref, AdditionalProperties, RegisterRecords);
	
	// 5. Fill register records with document's postings.
	DocumentPosting.FillRecordSets(AdditionalProperties, RegisterRecords, Cancel);
	
	// 6. Write document postings to register.
	DocumentPosting.WriteRecordSets(AdditionalProperties, RegisterRecords);
	
	// 7. Check register blanaces according to document's changes.
	DocumentPosting.CheckPostingResults(AdditionalProperties, RegisterRecords, Cancel);
	
	// 8. Clear used temporary document data.
	DocumentPosting.ClearDataStructuresAfterPosting(AdditionalProperties);
	
	
	// -> CODE REVIEW
		
	PostingDataset = New ValueTable();
	PostingDataset.Columns.Add("Account");
	PostingDataset.Columns.Add("AmountRC");
	
	CalculateByPlannedCosting = False;
	//PurchaseVarianceAccount = Constants.PurchaseVarianceAccount.Get();
	
	RegisterRecords.CashFlowData.Write = True;
	
	For Each CurRowLineItems in LineItems Do
		
		Record = RegisterRecords.CashFlowData.Add();
		Record.RecordType = AccumulationRecordType.Receipt;
		Record.Period = Date;
		Record.Company = Company;
		Record.Document = Ref;
		If CurRowLineItems.Product.Type = Enums.InventoryTypes.Inventory Then
			Record.Account = CurRowLineItems.Product.COGSAccount;
		Else
			Record.Account = CurRowLineItems.Product.InventoryOrExpenseAccount;
		EndIf;
		//Record.Account = CurRowLineItems.Product.InventoryOrExpenseAccount;
		//Record.CashFlowSection = CurRowLineItems.Product.InventoryOrExpenseAccount.CashFlowSection;
		Record.AmountRC = CurRowLineItems.LineTotal * ExchangeRate;
		//Record.PaymentMethod = PaymentMethod;

		
		// Detect inventory item in table part
		IsInventoryPosting = (Not CurRowLineItems.Product.IsEmpty()) And (CurRowLineItems.Product.Type = Enums.InventoryTypes.Inventory);
		
		PostingLine = PostingDataset.Add();       
		If CalculateByPlannedCosting And IsInventoryPosting Then
			//PostingLine.Account = AccruedPurchasesAccount;
		Else
			PostingLine.Account = CurRowLineItems.Product.InventoryOrExpenseAccount;
		EndIf;
		PostingLine.AmountRC = CurRowLineItems.LineTotal * ExchangeRate;
		
		// Calculating diference between ordered cost and invoiced cost of inventory items.
		//If CalculateByPlannedCosting And IsInventoryPosting Then
		//	// Calculate difference in ordered and invoiced sum
		//	OrderCostDiff = CurRowLineItems.Quantity * (CurRowLineItems.OrderPrice - CurRowLineItems.Price);
		//	// Book found difference
		//	If OrderCostDiff <> 0 Then
		//		// Increase/Decrease booked value by ordering cost
		//		PostingLine.AmountRC = PostingLine.AmountRC + OrderCostDiff;
		//		// Found difference will be booked to the Purchased Variance account
		//		PostingLine = PostingDataset.Add();       
		//		PostingLine.Account = PurchaseVarianceAccount;
		//		PostingLine.AmountRC = - OrderCostDiff;
		//	EndIf;
		//EndIf;
		
	EndDo;
	
	For Each CurRowAccount in Accounts Do
		
		Record = RegisterRecords.CashFlowData.Add();
		Record.RecordType = AccumulationRecordType.Receipt;
		Record.Period = Date;
		Record.Company = Company;
		Record.Document = Ref;
		Record.Account = CurRowAccount.Account;
		//Record.CashFlowSection = CurRowAccount.Account.CashFlowSection;
		Record.AmountRC = CurRowAccount.Amount * ExchangeRate;
		//Record.PaymentMethod = PaymentMethod;

		
		PostingLine = PostingDataset.Add();
		PostingLine.Account = CurRowAccount.Account;
		PostingLine.AmountRC = CurRowAccount.Amount * ExchangeRate;
	EndDo;
	
	PostingDataset.GroupBy("Account", "AmountRC");
	
	NoOfPostingRows = PostingDataset.Count();
	
	// GL posting
	RegisterRecords.GeneralJournal.Write = True;	
	
	For i = 0 To NoOfPostingRows - 1 Do
		
		If PostingDataset[i][1] > 0 Then // Dr: Amount > 0
			Record = RegisterRecords.GeneralJournal.AddDebit();
			Record.Account = PostingDataset[i][0];
			Record.Period = Date;
			Record.AmountRC = PostingDataset[i][1];
			
		ElsIf PostingDataset[i][1] < 0 Then // Cr: Amount < 0
			Record = RegisterRecords.GeneralJournal.AddCredit();
			Record.Account = PostingDataset[i][0];
			Record.Period = Date;
			Record.AmountRC = -PostingDataset[i][1];
			
		EndIf;
	EndDo;
	
	Record = RegisterRecords.GeneralJournal.AddCredit();
	Record.Account = APAccount;
	Record.Period = Date;
	Record.Amount = DocumentTotal;
	Record.Currency = Currency;
	Record.AmountRC = DocumentTotal * ExchangeRate;
	Record.ExtDimensions[ChartsOfCharacteristicTypes.Dimensions.Company] = Company;
	Record.ExtDimensions[ChartsOfCharacteristicTypes.Dimensions.Document] = Ref;
	
	RegisterRecords.ProjectData.Write = True;
	RegisterRecords.ClassData.Write	=True;
	For Each CurRowLineItems In LineItems Do
		
		If CurRowLineItems.Product.Type = Enums.InventoryTypes.NonInventory Then
		//	ProductAccountType = CurRowLineItems.Product.COGSAccount.AccountType;
		//Else
			ProductAccountType = CurRowLineItems.Product.InventoryOrExpenseAccount.AccountType;
		//EndIf;
			If (ProductAccountType = Enums.AccountTypes.Expense) OR
				(ProductAccountType = Enums.AccountTypes.OtherExpense) OR
				(ProductAccountType = Enums.AccountTypes.CostOfSales) OR
				(ProductAccountType = Enums.AccountTypes.IncomeTaxExpense) OR
				(ProductAccountType = Enums.AccountTypes.Income) OR
				(ProductAccountType = Enums.AccountTypes.OtherIncome) Then
				
				//ClassData
				Record = RegisterRecords.ClassData.Add();
				Record.RecordType = AccumulationRecordType.Expense;
				Record.Period = Date;
				//If CurRowLineItems.Product.Type = Enums.InventoryTypes.Inventory Then
					//Record.Account = CurRowLineItems.Product.COGSAccount;
				//Else
				Record.Account = CurRowLineItems.Product.InventoryOrExpenseAccount;
				//EndIf;
				Record.Class = CurRowLineItems.Class;
				Record.Amount = CurRowLineItems.LineTotal;	
				
				//ProjectData
				Record = RegisterRecords.ProjectData.Add();
				Record.RecordType = AccumulationRecordType.Expense;
				Record.Period = Date;
				Record.Account = CurRowLineItems.Product.InventoryOrExpenseAccount;
				Record.Project = CurRowLineItems.Project;
				Record.Amount = CurRowLineItems.LineTotal;
				
			EndIf;
		EndIf;
	EndDo;
	
	For Each CurRowAccount In Accounts Do
		
		If (CurRowAccount.Account.AccountType = Enums.AccountTypes.Expense) OR
			(CurRowAccount.Account.AccountType = Enums.AccountTypes.OtherExpense) OR
			(CurRowAccount.Account.AccountType = Enums.AccountTypes.CostOfSales) OR
			(CurRowAccount.Account.AccountType = Enums.AccountTypes.IncomeTaxExpense) OR
			(CurRowAccount.Account.AccountType = Enums.AccountTypes.Income) OR
			(CurRowAccount.Account.AccountType = Enums.AccountTypes.OtherIncome) Then

			//ClassData
			Record = RegisterRecords.ClassData.Add();
			Record.RecordType = AccumulationRecordType.Expense;
			Record.Period = Date;
			Record.Account = CurRowAccount.Account;
			Record.Class = CurRowAccount.Class;
			Record.Amount = CurRowAccount.Amount;
			
			//ProjectData
			Record = RegisterRecords.ProjectData.Add();
			Record.RecordType = AccumulationRecordType.Expense;
			Record.Period = Date;
			Record.Account = CurRowAccount.Account;
			Record.Project = CurRowAccount.Project;
			Record.Amount = CurRowAccount.Amount;
			
		EndIf;
		
	EndDo;
	// <- CODE REVIEW
	
EndProcedure

Procedure UndoPosting(Cancel)
	
	// 1. Common posting clearing / deactivate manual ajusted postings.
	DocumentPosting.PrepareRecordSetsForPostingClearing(AdditionalProperties, RegisterRecords);
	
	// 2. Skip manually adjusted documents.
	If ManualAdjustment Then
		Return;
	EndIf;
	
	// 3. Create structures with document data to pass it on the server.
	DocumentPosting.PrepareDataStructuresBeforePosting(AdditionalProperties);
	
	// 4. Collect document data, required for posing clearing, and fill created structure.
	Documents.PurchaseInvoice.PrepareDataStructuresForPostingClearing(Ref, AdditionalProperties, RegisterRecords);
	
	// 5. Write document postings to register.
	DocumentPosting.WriteRecordSets(AdditionalProperties, RegisterRecords);
	
	// 6. Check register blanaces according to document's changes.
	DocumentPosting.CheckPostingResults(AdditionalProperties, RegisterRecords, Cancel);
	
	// 7. Clear used temporary document data.
	DocumentPosting.ClearDataStructuresAfterPosting(AdditionalProperties);
	
EndProcedure

#EndIf

#EndRegion
