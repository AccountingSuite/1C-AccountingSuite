﻿
////////////////////////////////////////////////////////////////////////////////
// Shipment: Object module
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
			Documents.Shipment.PrepareDataBeforeWrite(AdditionalProperties, DocumentParameters, Cancel);
		EndIf;
				
	EndIf;
	
EndProcedure

Procedure FillCheckProcessing(Cancel, CheckedAttributes)
	
	// Check positive discounts.
	If Discount > 0 Then
		MessageText = StringFunctionsClientServer.SubstituteParametersInString(NStr("en = 'Specified discount: %1. A discount should be negative number.'"), Format(Discount, "NFD=2; NZ="));
		CommonUseClientServer.MessageToUser(MessageText, Ref,,, Cancel);
	EndIf;
	
	// Check sales tax rate filling
	If GeneralFunctionsReusable.FunctionalOptionValue("SalesTaxCharging") And Not UseAvatax Then
		If Not ValueIsFilled(SalesTaxRate) Then
			CommonUseClientServer.MessageToUser(NStr("en = 'Field ""Sales tax rate"" is empty'"), Ref, "SalesTaxRate",, Cancel);
		EndIf;
	EndIf;
	
	// Check proper filling of lots.
	LotsSerialNumbers.CheckLotsFilling(Ref, LineItems, Cancel);
	
	// Check proper filling of serial numbers.
	LotsSerialNumbers.CheckSerialNumbersFilling(Ref, PointInTime(), LineItems, SerialNumbers, 1, "", Cancel);
	
	// Check doubles in items (to be sure of proper orders placement).
	GeneralFunctions.CheckDoubleItems(Ref, LineItems, "Product, Unit, Order, Location, DeliveryDate, Project, Class, LineNumber",, Cancel);
	
	// Check proper closing of order items by the shipment items.
	If Not Cancel Then
		Documents.Shipment.CheckOrderQuantity(Ref, Date, Company, LineItems, Cancel);
	EndIf;
	
EndProcedure

Procedure Filling(FillingData, StandardProcessing)
	
	// Forced assign the new document number.
	If ThisObject.IsNew() And Not ValueIsFilled(ThisObject.Number) Then ThisObject.SetNewNumber(); EndIf;
	
	// Filling new document or filling on the base of another document.
	If FillingData = Undefined Then
		// Filling of the new created document with default values.
		Currency         = Constants.DefaultCurrency.Get();
		ExchangeRate     = GeneralFunctions.GetExchangeRate(Date, Currency);
		LocationActual   = GeneralFunctions.GetDefaultLocation();
		
	Else
		// Generate on the base of Sales order & Shipment.
		Cancel = False; TabularSectionData = Undefined;
		
		// 0. Custom check of sales order for interactive generate of Shipment on the base of sales order.
		If (TypeOf(FillingData) = Type("DocumentRef.SalesOrder"))
		And ((Not Documents.Shipment.CheckStatusOfSalesOrder(Ref, FillingData)) Or (Not Documents.Shipment.CheckUseShipmentOfSalesOrder(Ref, FillingData))) Then
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
		Documents.Shipment.PrepareDataStructuresForFilling(Ref, AdditionalProperties);
		
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
		
		// 7 Custom filling of UUIDs.
		For Each Row In LineItems Do
			Row.LineID = New UUID();
		EndDo;
	EndIf;
	
EndProcedure

Procedure OnCopy(CopiedObject)
	
	If ThisObject.IsNew() Then ThisObject.SetNewNumber(); EndIf;
	
	// Clear manual adjustment attribute.
	ManualAdjustment = False;
	
EndProcedure

Procedure OnSetNewNumber(StandardProcessing, Prefix)
	
	StandardProcessing = False;
	
	Numerator = Catalogs.DocumentNumbering.Shipment;
	NextNumber = GeneralFunctions.Increment(Numerator.Number);
	
	While Documents.Shipment.FindByNumber(NextNumber) <> Documents.Shipment.EmptyRef() And NextNumber <> "" Do
		ObjectNumerator = Numerator.GetObject();
		ObjectNumerator.Number = NextNumber;
		ObjectNumerator.Write();
		
		NextNumber = GeneralFunctions.Increment(NextNumber);
	EndDo;
	
	ThisObject.Number = NextNumber; 

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
	Documents.Shipment.PrepareDataStructuresForPosting(Ref, AdditionalProperties, RegisterRecords);
	
	// 5. Fill register records with document's postings.
	DocumentPosting.FillRecordSets(AdditionalProperties, RegisterRecords, Cancel);
	
	// 6. Write document postings to register.
	DocumentPosting.WriteRecordSets(AdditionalProperties, RegisterRecords);
	
	// 7. Check register blanaces according to document's changes.
	DocumentPosting.CheckPostingResults(AdditionalProperties, RegisterRecords, Cancel);
	
	// 8. Clear used temporary document data.
	DocumentPosting.ClearDataStructuresAfterPosting(AdditionalProperties);
	
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
	Documents.Shipment.PrepareDataStructuresForPostingClearing(Ref, AdditionalProperties, RegisterRecords);
	
	// 5. Write document postings to register.
	DocumentPosting.WriteRecordSets(AdditionalProperties, RegisterRecords);
	
	// 6. Check register blanaces according to document's changes.
	DocumentPosting.CheckPostingResults(AdditionalProperties, RegisterRecords, Cancel);
	
	// 7. Clear used temporary document data.
	DocumentPosting.ClearDataStructuresAfterPosting(AdditionalProperties);
	
EndProcedure

#EndIf

#EndRegion