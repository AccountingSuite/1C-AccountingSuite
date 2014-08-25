﻿
////////////////////////////////////////////////////////////////////////////////
// Cash sale: Manager module
//------------------------------------------------------------------------------

////////////////////////////////////////////////////////////////////////////////
#Region PUBLIC_INTERFACE

#If Server Or ThickClientOrdinaryApplication Or ExternalConnection Then

//------------------------------------------------------------------------------
// Document posting

// Pre-check, lock, calculate data before write document.
Function PrepareDataBeforeWrite(AdditionalProperties, DocumentParameters, Cancel) Export
	
	// 0.1. Access data without rights checking.
	SetPrivilegedMode(True);
	
	// 0.2. Create list of query tables (according to the list of requested balances).
	PreCheck     = New Structure;
	LocksList    = New Structure;
	BalancesList = New Structure;
	
	// 0.3. Set optional accounting flags.
	InventoryPosting = True; // Post always.
	
	
	// 1.1. Create a query to request data.
	Query = New Query;
	Query.TempTablesManager = New TempTablesManager;
	
	// 1.2. Put supplied DocumentParameters in query parameters and temporary tables.
	For Each Parameter In DocumentParameters Do
		If TypeOf(Parameter.Value) = Type("ValueTable") Then
			DocumentPosting.PutTemporaryTable(Parameter.Value, "Table_"+Parameter.Key, Query.TempTablesManager);
		ElsIf TypeOf(Parameter.Value) = Type("PointInTime") Then
			Query.SetParameter(Parameter.Key, New Boundary(Parameter.Value, BoundaryType.Excluding));
		Else
			Query.SetParameter(Parameter.Key, Parameter.Value);
		EndIf;
	EndDo;
	
	
	// 2.1. Request data for lock in registers before accessing balances.
	Query.Text = "";
	If InventoryPosting Then
		Query.Text = Query.Text +
		             Query_InventoryJournal_Lock(LocksList);
	EndIf;
	
	// 2.2. Proceed with locking the data.
	If Not IsBlankString(Query.Text) Then
		QueryResult = Query.ExecuteBatch();
		For Each LockTable In LocksList Do
			DocumentPosting.LockDataSourceBeforeWrite(StrReplace(LockTable.Key, "_", "."), QueryResult[LockTable.Value], DataLockMode.Exclusive);
		EndDo;
	EndIf;
	
	
	// 3.1. Query for register balances excluding document data (if it already affected to).
	Query.Text = "";
	If InventoryPosting Then
		Query.Text = Query.Text +
		             Query_InventoryJournal_Balance(BalancesList);
		
		// Reuse locked inventory items list.
		DocumentPosting.PutTemporaryTable(QueryResult[LocksList.AccumulationRegister_InventoryJournal].Unload(),
		                                  "Table_InventoryJournal_Lock", Query.TempTablesManager);
	EndIf;
	
	// 3.2. Save balances in posting parameters.
	If Not IsBlankString(Query.Text) Then
		QueryResult = Query.ExecuteBatch();
		For Each BalanceTable In BalancesList Do
			PreCheck.Insert(BalanceTable.Key, QueryResult[BalanceTable.Value].Unload());
		EndDo;
		Query.TempTablesManager.Close();
	EndIf;
	
	// 3.3. Put structure of prechecked registers in additional properties.
	If PreCheck.Count() > 0 Then
		AdditionalProperties.Posting.Insert("PreCheck", PreCheck);
	EndIf;
	
EndFunction

// Collect document data for posting on the server (in terms of document).
Function PrepareDataStructuresForPosting(DocumentRef, AdditionalProperties, RegisterRecords) Export
	Var PreCheck;
	
	//------------------------------------------------------------------------------
	// 1. Prepare structures for querying data.
	
	// Set optional accounting flags.
	InventoryPosting = True; // Post always.
	SalesTaxPosting  = GeneralFunctionsReusable.FunctionalOptionValue("SalesTaxCharging");
	
	// Create list of posting tables (according to the list of registers).
	TablesList = New Structure;
	
	// Create a query to request document data.
	Query = New Query;
	Query.TempTablesManager = New TempTablesManager;
	Query.SetParameter("Ref", DocumentRef);
	
	//------------------------------------------------------------------------------
	// 2. Prepare query text.
	
	// Query for document's tables.
	Query.Text   = "";
	If InventoryPosting Then
		Query.Text = Query.Text +
		             Query_InventoryJournal_LineItems(TablesList) +
		             Query_InventoryJournal_Balance_Quantity(TablesList) +
		             Query_InventoryJournal_Balance_FIFO(TablesList) +
		             Query_InventoryJournal(TablesList);
	EndIf;
				 
	 If SalesTaxPosting Then
		Query.Text = Query.Text +
		             Query_SalesTaxOwed(TablesList) +
		             Query_GeneralJournal_SalesTax(TablesList);
	EndIf;
	
	//------------------------------------------------------------------------------
	// 3. Execute query and fill data structures.
	
	// Execute query, fill temporary tables with postings data.
	If Not IsBlankString(Query.Text) Then
		// Fill data from precheck.
		If AdditionalProperties.Posting.Property("PreCheck", PreCheck) And PreCheck.Count() > 0 Then
			For Each PreCheckTable In PreCheck Do
				DocumentPosting.PutTemporaryTable(PreCheckTable.Value, PreCheckTable.Key, Query.TempTablesManager);
			EndDo;
		EndIf;
		
		// Execute query.
		QueryResult = Query.ExecuteBatch();
		
		// Save documents table in posting parameters.
		For Each DocumentTable In TablesList Do
			ResultTable = QueryResult[DocumentTable.Value].Unload();
			If Not DocumentPosting.IsTemporaryTable(ResultTable) Then
				AdditionalProperties.Posting.PostingTables.Insert(DocumentTable.Key, ResultTable);
			EndIf;
		EndDo;
	EndIf;
	
	//------------------------------------------------------------------------------
	// 4. Final check of posting data correctness (i.e. negative balances and s.o.).
	
	// Clear used temporary tables manager.
	Query.TempTablesManager.Close();
	
	// Fill list of registers to check (non-negative) balances in posting parameters.
	FillRegistersCheckList(AdditionalProperties, RegisterRecords);
	
EndFunction

// Collect document data for posting on the server (in terms of document).
Function PrepareDataStructuresForPostingClearing(DocumentRef, AdditionalProperties, RegisterRecords) Export
	
	// Fill list of registers to check (non-negative) balances in posting parameters.
	FillRegistersCheckList(AdditionalProperties, RegisterRecords);
	
EndFunction

//------------------------------------------------------------------------------
// Document fill check processing

//------------------------------------------------------------------------------
// Document filling

//------------------------------------------------------------------------------
// Document printing
Procedure Print(Spreadsheet, SheetTitle, Ref, TemplateName = Undefined) Export
	
	SheetTitle = "Cash Sale";
	CustomTemplate = GeneralFunctions.GetCustomTemplate("Document.CashSale", SheetTitle);
	
	If CustomTemplate = Undefined Then
		Template = Documents.CashSale.GetTemplate("New_CashSale_Form");
	Else
		Template = CustomTemplate;
	EndIf;
	
   // Quering necessary data.
   Query = New Query();
   Query.Text =
   "SELECT
   |	CashSale.Ref,
   |	CashSale.DataVersion,
   |	CashSale.DeletionMark,
   |	CashSale.Number,
   |	CashSale.Date,
   |	CashSale.Posted,
   |	CashSale.Company,
   |	CashSale.RefNum,
   |	CashSale.Memo,
   |	CashSale.DepositType,
   |	CashSale.Deposited,
   |	CashSale.Currency,
   |	CashSale.ExchangeRate,
   |	CashSale.Location,
   |	CashSale.BankAccount,
   |	CashSale.PaymentMethod,
   |	CashSale.ShipTo,
   |	CashSale.Project,
   |	CashSale.StripeID,
   |	CashSale.StripeCardName,
   |	CashSale.StripeAmount,
   |	CashSale.StripeCreated,
   |	CashSale.StripeCardType,
   |	CashSale.StripeLast4,
   |	CashSale.NewObject,
   |	CashSale.EmailTo,
   |	CashSale.EmailNote,
   |	CashSale.EmailCC,
   |	CashSale.LastEmail,
   |	CashSale.LineSubtotal,
   |	CashSale.Discount,
   |	CashSale.Subtotal,
   |	CashSale.Shipping,
   |	CashSale.SalesTaxRC,
   |	CashSale.DocumentTotal,
   |	CashSale.DocumentTotalRC,
   |	CashSale.BillTo,
   |	CashSale.DiscountPercent,
   |	CashSale.ManualAdjustment,
   |	CashSale.SalesPerson,
   |	CashSale.SalesTaxRate,
   |	CashSale.DiscountIsTaxable,
   |	CashSale.SalesTax,
   |	CashSale.TaxableSubtotal,
   |	CashSale.SalesTaxAmount,
   |	CashSale.LineItems.(
   |		Ref,
   |		LineNumber,
   |		Product,
   |		ProductDescription,
   |		UnitSet,
   |		QtyUnits,
   |		Unit,
   |		QtyUM,
   |		PriceUnits,
   |		LineTotal,
   |		Project,
   |		Taxable,
   |		TaxableAmount,
   |		Class
   |	),
   |	CashSale.SalesTaxAcrossAgencies.(
   |		Ref,
   |		LineNumber,
   |		Agency,
   |		Rate,
   |		Amount,
   |		SalesTaxRate,
   |		SalesTaxComponent
   |	)
   |FROM
   |	Document.CashSale AS CashSale
   |WHERE
   |	CashSale.Ref IN(&Ref)";
   Query.SetParameter("Ref", Ref);
   Selection = Query.Execute().Select();
  
   Spreadsheet.Clear();
   
    While Selection.Next() Do
	   
	BinaryLogo = GeneralFunctions.GetLogo();
	LogoPicture = New Picture(BinaryLogo);
	DocumentPrinting.FillLogoInDocumentTemplate(Template, LogoPicture); 
	
	Try
		FooterLogo = GeneralFunctions.GetFooterPO("CSfooter1");
		Footer1Pic = New Picture(FooterLogo);
		FooterLogo2 = GeneralFunctions.GetFooterPO("CSfooter2");
		Footer2Pic = New Picture(FooterLogo2);
		FooterLogo3 = GeneralFunctions.GetFooterPO("CSfooter3");
		Footer3Pic = New Picture(FooterLogo3);
	Except
	EndTry;
	
	//Add footer with page count	
	Template.Footer.Enabled = True;
	Template.Footer.RightText = "Page [&PageNumber] of [&PagesTotal]";
   
	TemplateArea = Template.GetArea("Header");
	  		
	UsBill = PrintTemplates.ContactInfoDatasetUs();
	ThemShip = PrintTemplates.ContactInfoDataset(Selection.Company, "ThemShip", Selection.ShipTo);
	ThemBill = PrintTemplates.ContactInfoDataset(Selection.Company, "ThemBill", Selection.BillTo);
	
	TemplateArea.Parameters.Fill(UsBill);
	TemplateArea.Parameters.Fill(ThemShip);
	TemplateArea.Parameters.Fill(ThemBill);
	
	TemplateArea.Parameters.SalesPerson = Selection.SalesPerson;
			
	If Constants.CSShowFullName.Get() = True Then
		TemplateArea.Parameters.ThemFullName = ThemShip.ThemShipSalutation + " " + ThemShip.ThemShipFirstName + " " + ThemShip.ThemShipLastName;
		TempFullName = ThemBill.ThemBillSalutation + " " + ThemBill.ThemBillFirstName + " " + ThemBill.ThemBillLastName;
		If TempFullName = TemplateArea.Parameters.ThemFullName Then
			TemplateArea.Parameters.ThemBillName = "";
		Else
			TemplateArea.Parameters.ThemBillName = TempFullName + Chars.LF;
		EndIf;
		
	EndIf;

	
	TemplateArea.Parameters.Date = Selection.Date;
	TemplateArea.Parameters.Number = Selection.Number;
	If Selection.StripeID <> "" Then
    	TemplateArea.Parameters.RefNum = Selection.StripeID;
    Else
    	TemplateArea.Parameters.RefNum = Selection.RefNum;
	EndIf;
	If Selection.StripeLast4 <> "" Then
		If Selection.StripeCardType = "Visa" Then
			creditPicture = new Picture(Picturelib.visa_logo.GetBinaryData());
			DocumentPrinting.FillPictureInDocumentTemplate(TemplateArea, creditPicture, "CCpic");
			TemplateArea.Parameters.PayMethod = "**** **** **** " + Selection.StripeLast4;
		ElsIf Selection.StripeCardType = "MasterCard" Then
			creditPicture = new Picture(Picturelib.mastercard_logo.GetBinaryData());
			DocumentPrinting.FillPictureInDocumentTemplate(TemplateArea, creditPicture, "CCpic");
			TemplateArea.Parameters.PayMethod = "**** **** **** " + Selection.StripeLast4;
		ElsIf Selection.StripeCardType = "American Express" Then
			creditPicture = new Picture(Picturelib.amex_logo.GetBinaryData());
			DocumentPrinting.FillPictureInDocumentTemplate(TemplateArea, creditPicture, "CCpic");
			TemplateArea.Parameters.PayMethod = "**** ****** * " + Selection.StripeLast4;
		ElsIf Selection.StripeCardType = "Discover" Then
			creditPicture = new Picture(Picturelib.discover_logo.GetBinaryData());
			DocumentPrinting.FillPictureInDocumentTemplate(TemplateArea, creditPicture, "CCpic");
			TemplateArea.Parameters.PayMethod = "**** **** **** " + Selection.StripeLast4;
		ElsIf Selection.StripeCardType = "JCB" Then
			creditPicture = new Picture(Picturelib.jcb_logo.GetBinaryData());
			DocumentPrinting.FillPictureInDocumentTemplate(TemplateArea, creditPicture, "CCpic");
			TemplateArea.Parameters.PayMethod = "**** **** **** " + Selection.StripeLast4;
		ElsIf Selection.StripeCardType = "Diners Club" Then
			creditPicture = new Picture(Picturelib.dinersclub_logo.GetBinaryData());
			DocumentPrinting.FillPictureInDocumentTemplate(TemplateArea, creditPicture, "CCpic");
			TemplateArea.Parameters.PayMethod = "**** **** **" + Selection.StripeLast4;
		Else
		EndIf;		
	Else
		TemplateArea.Parameters.PayMethod = Selection.PaymentMethod;
	EndIf;
			
	//UsBill filling
	If TemplateArea.Parameters.UsBillLine1 <> "" Then
		TemplateArea.Parameters.UsBillLine1 = TemplateArea.Parameters.UsBillLine1 + Chars.LF; 
	EndIf;

	If TemplateArea.Parameters.UsBillLine2 <> "" Then
		TemplateArea.Parameters.UsBillLine2 = TemplateArea.Parameters.UsBillLine2 + Chars.LF; 
	EndIf;
	
	If TemplateArea.Parameters.UsBillCityStateZIP <> "" Then
		TemplateArea.Parameters.UsBillCityStateZIP = TemplateArea.Parameters.UsBillCityStateZIP + Chars.LF; 
	EndIf;
	
	If TemplateArea.Parameters.UsBillPhone <> "" Then
		TemplateArea.Parameters.UsBillPhone = TemplateArea.Parameters.UsBillPhone + Chars.LF; 
	EndIf;
	
	If TemplateArea.Parameters.UsBillEmail <> "" AND Constants.SIShowEmail.Get() = False Then
		TemplateArea.Parameters.UsBillEmail = ""; 
	EndIf;
	
	//ThemBill filling
	If TemplateArea.Parameters.ThemBillLine1 <> "" Then
		TemplateArea.Parameters.ThemBillLine1 = TemplateArea.Parameters.ThemBillLine1 + Chars.LF; 
	Else
		TemplateArea.Parameters.ThemBillLine1 = "";
	EndIf;

	If TemplateArea.Parameters.ThemBillLine2 <> "" Then
		TemplateArea.Parameters.ThemBillLine2 = TemplateArea.Parameters.ThemBillLine2 + Chars.LF; 
	Else
		TemplateArea.Parameters.ThemBillLine2 = "";
	EndIf;
	
	If TemplateArea.Parameters.ThemBillLine3 <> "" Then
		TemplateArea.Parameters.ThemBillLine3 = TemplateArea.Parameters.ThemBillLine3 + Chars.LF; 
	Else
		TemplateArea.Parameters.ThemBillLine3 = "";
	EndIf;
		
	//ThemShip filling
	If TemplateArea.Parameters.ThemShipLine1 <> "" Then
		TemplateArea.Parameters.ThemShipLine1 = TemplateArea.Parameters.ThemShipLine1 + Chars.LF; 
	Else
		TemplateArea.Parameters.ThemShipLine1 = "";
	EndIf;

	If TemplateArea.Parameters.ThemShipLine2 <> "" Then
		TemplateArea.Parameters.ThemShipLine2 = TemplateArea.Parameters.ThemShipLine2 + Chars.LF; 
	Else
		TemplateArea.Parameters.ThemShipLine2 = "";
	EndIf;
	
	If TemplateArea.Parameters.ThemShipLine3 <> "" Then
		TemplateArea.Parameters.ThemShipLine3 = TemplateArea.Parameters.ThemShipLine3 + Chars.LF; 
	Else
		TemplateArea.Parameters.ThemShipLine3 = "";
	EndIf;
		 
	Spreadsheet.Put(TemplateArea);
	 	 
	If Constants.CSShowPhone2.Get() = False Then
		Direction = SpreadsheetDocumentShiftType.Vertical;
		Area = Spreadsheet.Area("MobileArea");
		Spreadsheet.DeleteArea(Area, Direction);
		Spreadsheet.InsertArea(Spreadsheet.Area("R10"), Spreadsheet.Area("R10"), 
        SpreadsheetDocumentShiftType.Vertical);
	EndIf;
	
	If Constants.CSShowWebsite.Get() = False Then
		Direction = SpreadsheetDocumentShiftType.Vertical;
		Area = Spreadsheet.Area("WebsiteArea");
		Spreadsheet.DeleteArea(Area, Direction);
		Spreadsheet.InsertArea(Spreadsheet.Area("R10"), Spreadsheet.Area("R10"), 
		SpreadsheetDocumentShiftType.Vertical);

	EndIf;
	
	If Constants.CSShowFax.Get() = False Then
		Direction = SpreadsheetDocumentShiftType.Vertical;
		Area = Spreadsheet.Area("FaxArea");
		Spreadsheet.DeleteArea(Area, Direction);
		Spreadsheet.InsertArea(Spreadsheet.Area("R10"), Spreadsheet.Area("R10"), 
		SpreadsheetDocumentShiftType.Vertical);

	EndIf;
	
	If Constants.CSShowFedTax.Get() = False Then
		Direction = SpreadsheetDocumentShiftType.Vertical;
		Area = Spreadsheet.Area("FedTaxArea");
		Spreadsheet.DeleteArea(Area, Direction);
		Spreadsheet.InsertArea(Spreadsheet.Area("R10"), Spreadsheet.Area("R10"), 
		SpreadsheetDocumentShiftType.Vertical);

	EndIf;
		
	SelectionLineItems = Selection.LineItems.Select();
	TemplateArea = Template.GetArea("LineItems");
	LineTotalSum = 0;
	LineItemSwitch = False;
	CurrentLineItemIndex = 0;
	QuantityFormat = GeneralFunctionsReusable.DefaultQuantityFormat();
	
	While SelectionLineItems.Next() Do
				 
		TemplateArea.Parameters.Fill(SelectionLineItems);
		CompanyName = Selection.Company.Description;
		CompanyNameLen = StrLen(CompanyName);
		Try
			 If NOT SelectionLineItems.Project = "" Then
				ProjectLen = StrLen(SelectionLineItems.Project);
			 	TemplateArea.Parameters.Project = Right(SelectionLineItems.Project, ProjectLen - CompanyNameLen - 2);
			EndIf;
		Except
		EndTry;
		LineTotal = SelectionLineItems.LineTotal;
		
		TemplateArea.Parameters.Quantity  = Format(SelectionLineItems.QtyUnits, QuantityFormat);
		TemplateArea.Parameters.Price     = Selection.Currency.Symbol + Format(SelectionLineItems.PriceUnits, "NFD=2; NZ=");
		TemplateArea.Parameters.UM        = SelectionLineItems.Unit.Code;
		TemplateArea.Parameters.LineTotal = Selection.Currency.Symbol + Format(SelectionLineItems.LineTotal, "NFD=2; NZ=");
		Spreadsheet.Put(TemplateArea, SelectionLineItems.Level());
				
		If LineItemSwitch = False Then
			TemplateArea = Template.GetArea("LineItems2");
			LineItemSwitch = True;
		Else
			TemplateArea = Template.GetArea("LineItems");
			LineItemSwitch = False;
		EndIf;
		
		// If can't fit next line, place header
		
		Footer = Template.GetArea("Area3");
		RowsToCheck = New Array();
		RowsToCheck.Add(TemplateArea);
		DividerArea = Template.GetArea("DividerArea");
		RowsToCheck.Add(Footer);
		RowsToCheck.Add(DividerArea);
		
		If Spreadsheet.CheckPut(RowsToCheck) = False Then
			
			// Add divider and footer to bottom, break to next page, add header.
			
			Row = Template.GetArea("EmptyRow");
			Spreadsheet.Put(Row);
			
			DividerArea = Template.GetArea("DividerArea");
			Spreadsheet.Put(DividerArea);

			If Constants.CSFoot1Type.Get()= Enums.TextOrImage.Image Then	
				DocumentPrinting.FillPictureInDocumentTemplate(Template, Footer1Pic, "CSfooter1");
				TemplateArea2 = Template.GetArea("FooterField|FooterSection1");	
				Spreadsheet.Put(TemplateArea2);
			Elsif Constants.CSFoot1Type.Get() = Enums.TextOrImage.Text Then
				TemplateArea2 = Template.GetArea("TextField|FooterSection1");
				TemplateArea2.Parameters.FooterTextLeft = Constants.CSFooterTextLeft.Get();
				Spreadsheet.Put(TemplateArea2);
			EndIf;
		
			If Constants.CSFoot2Type.Get()= Enums.TextOrImage.Image Then
				DocumentPrinting.FillPictureInDocumentTemplate(Template, Footer2Pic, "CSfooter2");
				TemplateArea2 = Template.GetArea("FooterField|FooterSection2");	
				Spreadsheet.Join(TemplateArea2);
			
			Elsif Constants.CSFoot2Type.Get() = Enums.TextOrImage.Text Then
				TemplateArea2 = Template.GetArea("TextField|FooterSection2");
				TemplateArea2.Parameters.FooterTextCenter = Constants.CSFooterTextCenter.Get();
				Spreadsheet.Join(TemplateArea2);
			EndIf;
		
			If Constants.CSFoot3Type.Get()= Enums.TextOrImage.Image Then
					DocumentPrinting.FillPictureInDocumentTemplate(Template, Footer3Pic, "CSfooter3");
					TemplateArea2 = Template.GetArea("FooterField|FooterSection3");	
					Spreadsheet.Join(TemplateArea2);
			Elsif Constants.CSFoot3Type.Get() = Enums.TextOrImage.Text Then
					TemplateArea2 = Template.GetArea("TextField|FooterSection3");
					TemplateArea2.Parameters.FooterTextRight = Constants.CSFooterTextRight.Get();
					Spreadsheet.Join(TemplateArea2);
			EndIf;	
			
			Spreadsheet.PutHorizontalPageBreak();
			Header =  Spreadsheet.GetArea("TopHeader");
			
			LineItemsHeader = Template.GetArea("LineItemsHeader");
			EmptySpace = Template.GetArea("EmptyRow");
			Spreadsheet.Put(Header);
			Spreadsheet.Put(EmptySpace);
			If CurrentLineItemIndex < SelectionLineItems.Count() Then
				Spreadsheet.Put(LineItemsHeader);
			EndIf;
		EndIf;
		 
	 EndDo;
	
	TemplateArea = Template.GetArea("EmptySpace");
	Spreadsheet.Put(TemplateArea);
	
	Row = Template.GetArea("EmptyRow");
	DetailArea = Template.GetArea("Area3");
	Compensator = Template.GetArea("Compensator");
	RowsToCheck = New Array();
	RowsToCheck.Add(Row);
	RowsToCheck.Add(DetailArea);
	
	
	// If Area3 does not fit, print to next page and add preceding header
	
	AddHeader = False;
	If Spreadsheet.CheckPut(DetailArea) = False Then
		AddHeader = True;
	EndIf;
		
	While Spreadsheet.CheckPut(RowsToCheck) = False Do
		 Spreadsheet.Put(Row);
	   	 RowsToCheck.Clear();
	  	 RowsToCheck.Add(DetailArea);
		 RowsToCheck.Add(Row);
	EndDo;
		
	If AddHeader = True Then
		HeaderArea = Spreadsheet.GetArea("TopHeader");
		Spreadsheet.Put(HeaderArea);
		Spreadsheet.Put(Row);
	EndIf;

	 
	TemplateArea = Template.GetArea("Area3|Area1");					
	TemplateArea.Parameters.TermAndCond = Selection.EmailNote;
	Spreadsheet.Put(TemplateArea);

	
	TemplateArea = Template.GetArea("Area3|Area2");
	TemplateArea.Parameters.LineSubtotal = Selection.Currency.Symbol + Format(Selection.LineSubtotal, "NFD=2; NZ=");
	TemplateArea.Parameters.Discount = "("+ Selection.Currency.Symbol + Format(Selection.Discount, "NFD=2; NZ=") + ")";
	TemplateArea.Parameters.Subtotal = Selection.Currency.Symbol + Format(Selection.Subtotal, "NFD=2; NZ=");
	TemplateArea.Parameters.Shipping = Selection.Currency.Symbol + Format(Selection.Shipping, "NFD=2; NZ=");
	TemplateArea.Parameters.SalesTax = Selection.Currency.Symbol + Format(Selection.SalesTax, "NFD=2; NZ=");
	TemplateArea.Parameters.Total = Selection.Currency.Symbol + Format(Selection.DocumentTotal, "NFD=2; NZ=");

	Spreadsheet.Join(TemplateArea);
		
	Row = Template.GetArea("EmptyRow");
	Footer = Template.GetArea("FooterField");
	Compensator = Template.GetArea("Compensator");
	RowsToCheck = New Array();
	RowsToCheck.Add(Row);
	RowsToCheck.Add(Footer);
	RowsToCheck.Add(Row);
	
	
	While Spreadsheet.CheckPut(RowsToCheck) Do
		 Spreadsheet.Put(Row);
	   	 RowsToCheck.Clear();
	  	 RowsToCheck.Add(Footer);
		 RowsToCheck.Add(Row);
	 EndDo;
	 
	 While Spreadsheet.CheckPut(RowsToCheck) Do
		 Spreadsheet.Put(Row);
	   	 RowsToCheck.Clear();
	  	 RowsToCheck.Add(Footer);
		 RowsToCheck.Add(Row);
		 RowsToCheck.Add(Row);
		 RowsToCheck.Add(Row);

	EndDo;


	TemplateArea = Template.GetArea("DividerArea");
	Spreadsheet.Put(TemplateArea);
	
	//Final footer
	
	If Constants.CSFoot1Type.Get()= Enums.TextOrImage.Image Then	
			DocumentPrinting.FillPictureInDocumentTemplate(Template, Footer1Pic, "CSfooter1");
			TemplateArea = Template.GetArea("FooterField|FooterSection1");	
			Spreadsheet.Put(TemplateArea);
	Elsif Constants.CSFoot1Type.Get() = Enums.TextOrImage.Text Then
			TemplateArea = Template.GetArea("TextField|FooterSection1");
			TemplateArea.Parameters.FooterTextLeft = Constants.CSFooterTextLeft.Get();
			Spreadsheet.Put(TemplateArea);
	EndIf;
		
	If Constants.CSFoot2Type.Get()= Enums.TextOrImage.Image Then
			DocumentPrinting.FillPictureInDocumentTemplate(Template, Footer2Pic, "CSfooter2");
			TemplateArea = Template.GetArea("FooterField|FooterSection2");	
			Spreadsheet.Join(TemplateArea);		
	Elsif Constants.CSFoot2Type.Get() = Enums.TextOrImage.Text Then
			TemplateArea = Template.GetArea("TextField|FooterSection2");
			TemplateArea.Parameters.FooterTextCenter = Constants.CSFooterTextCenter.Get();
			Spreadsheet.Join(TemplateArea);
	EndIf;
		
	If Constants.CSFoot3Type.Get()= Enums.TextOrImage.Image Then
			DocumentPrinting.FillPictureInDocumentTemplate(Template, Footer3Pic, "CSfooter3");
			TemplateArea = Template.GetArea("FooterField|FooterSection3");	
			Spreadsheet.Join(TemplateArea);
	Elsif Constants.CSFoot3Type.Get() = Enums.TextOrImage.Text Then
			TemplateArea = Template.GetArea("TextField|FooterSection3");
			TemplateArea.Parameters.FooterTextRight = Constants.CSFooterTextRight.Get();
			Spreadsheet.Join(TemplateArea);
	EndIf;
		
	Spreadsheet.PutHorizontalPageBreak(); //.ВывестиГоризонтальныйРазделительСтраниц();
	Spreadsheet.FitToPage  = True;
	
	// Remove footer information if only a page.
	If Spreadsheet.PageCount() = 1 Then
		Spreadsheet.Footer.Enabled = False;
	EndIf;

	EndDo;

EndProcedure

#EndIf

#EndRegion

////////////////////////////////////////////////////////////////////////////////
#Region COMMANDS_HANDLERS

#If Server Or ThickClientOrdinaryApplication Or ExternalConnection Then

//------------------------------------------------------------------------------
// Document printing

#EndIf

#EndRegion

////////////////////////////////////////////////////////////////////////////////
#Region PRIVATE_IMPLEMENTATION

#If Server Or ThickClientOrdinaryApplication Or ExternalConnection Then

//------------------------------------------------------------------------------
// Document posting

// Query for document data.
Function Query_InventoryJournal_LineItems(TablesList)
	
	// Add InventoryJournal - requested items table to document structure.
	TablesList.Insert("Table_InventoryJournal_LineItems", TablesList.Count());
	
	// Collect inventory data.
	QueryText =
	"SELECT // FIFO
	// ------------------------------------------------------
	// Dimensions
	|	LineItems.Product.CostingMethod          AS Type,
	|	LineItems.Product                        AS Product,
	|	LineItems.Ref.Location                   AS Location,
	// ------------------------------------------------------
	// Agregates
	|	SUM(LineItems.QtyUM)                     AS QuantityRequested
	// ------------------------------------------------------
	|INTO
	|	Table_InventoryJournal_LineItems
	|FROM
	|	Document.CashSale.LineItems AS LineItems
	|WHERE
	|	    LineItems.Ref                   = &Ref
	|	AND LineItems.Product.Type          = VALUE(Enum.InventoryTypes.Inventory)
	|	AND LineItems.Product.CostingMethod = VALUE(Enum.InventoryCosting.FIFO)
	|GROUP BY
	|	LineItems.Product.CostingMethod,
	|	LineItems.Product,
	|	LineItems.Ref.Location
	|
	|UNION ALL
	|
	|SELECT // WAve for quantity calcualtion
	// ------------------------------------------------------
	// Dimensions
	|	LineItems.Product.CostingMethod          AS Type,
	|	LineItems.Product                        AS Product,
	|	LineItems.Ref.Location                   AS Location,
	// ------------------------------------------------------
	// Agregates
	|	SUM(LineItems.QtyUM)                     AS QuantityRequested
	// ------------------------------------------------------
	|FROM
	|	Document.CashSale.LineItems AS LineItems
	|WHERE
	|	    LineItems.Ref                   = &Ref
	|	AND LineItems.Product.Type          = VALUE(Enum.InventoryTypes.Inventory)
	|	AND LineItems.Product.CostingMethod = VALUE(Enum.InventoryCosting.WeightedAverage)
	|GROUP BY
	|	LineItems.Product.CostingMethod,
	|	LineItems.Product,
	|	LineItems.Ref.Location
	|
	|UNION ALL
	|
	|SELECT // WAve for amount calcualtion
	// ------------------------------------------------------
	// Dimensions
	|	LineItems.Product.CostingMethod          AS Type,
	|	LineItems.Product                        AS Product,
	|	VALUE(Catalog.Locations.EmptyRef)        AS Location,
	// ------------------------------------------------------
	// Agregates
	|	SUM(LineItems.QtyUM)                     AS QuantityRequested
	// ------------------------------------------------------
	|FROM
	|	Document.CashSale.LineItems AS LineItems
	|WHERE
	|	    LineItems.Ref                   = &Ref
	|	AND LineItems.Product.Type          = VALUE(Enum.InventoryTypes.Inventory)
	|	AND LineItems.Product.CostingMethod = VALUE(Enum.InventoryCosting.WeightedAverage)
	|GROUP BY
	|	LineItems.Product.CostingMethod,
	|	LineItems.Product";
	
	Return QueryText + DocumentPosting.GetDelimeterOfBatchQuery();
	
EndFunction

// Query for document data.
Function Query_InventoryJournal_Balance_Quantity(TablesList)
	
	// Add InventoryJournal - items balance table to document structure.
	TablesList.Insert("Table_InventoryJournal_Balance_Quantity", TablesList.Count());
	
	// Collect inventory data.
	QueryText =
	"SELECT // FIFO
	// ------------------------------------------------------
	// Dimensions
	|	InventoryJournalBalance.Type             AS Type,
	|	InventoryJournalBalance.Product          AS Product,
	|	InventoryJournalBalance.Location         AS Location,
	// ------------------------------------------------------
	// Agregates
	|	SUM(InventoryJournalBalance.Quantity)    AS Quantity,
	|	0                                        AS Amount
	// ------------------------------------------------------
	|INTO
	|	Table_InventoryJournal_Balance_Quantity
	|FROM
	|	Table_InventoryJournal_Balance AS InventoryJournalBalance
	|WHERE
	|	InventoryJournalBalance.Type = VALUE(Enum.InventoryCosting.FIFO)
	|GROUP BY
	|	InventoryJournalBalance.Type,
	|	InventoryJournalBalance.Product,
	|	InventoryJournalBalance.Location
	|
	|UNION ALL
	|
	|SELECT // WAve for quantity calcualtion
	// ------------------------------------------------------
	// Dimensions
	|	InventoryJournalBalance.Type             AS Type,
	|	InventoryJournalBalance.Product          AS Product,
	|	InventoryJournalBalance.Location         AS Location,
	// ------------------------------------------------------
	// Agregates
	|	SUM(InventoryJournalBalance.Quantity)    AS Quantity,
	|	0                                        AS Amount
	// ------------------------------------------------------
	|FROM
	|	Table_InventoryJournal_Balance AS InventoryJournalBalance
	|WHERE
	|	    InventoryJournalBalance.Type      = VALUE(Enum.InventoryCosting.WeightedAverage)
	|	AND InventoryJournalBalance.Location <> VALUE(Catalog.Locations.EmptyRef)
	|GROUP BY
	|	InventoryJournalBalance.Type,
	|	InventoryJournalBalance.Product,
	|	InventoryJournalBalance.Location
	|
	|UNION ALL
	|
	|SELECT // WAve for amount calcualtion
	// ------------------------------------------------------
	// Dimensions
	|	InventoryJournalBalance.Type             AS Type,
	|	InventoryJournalBalance.Product          AS Product,
	|	VALUE(Catalog.Locations.EmptyRef)        AS Location,
	// ------------------------------------------------------
	// Agregates
	|	SUM(InventoryJournalBalance.Quantity)    AS Quantity,
	|	SUM(InventoryJournalBalance.Amount)      AS Amount
	// ------------------------------------------------------
	|FROM
	|	Table_InventoryJournal_Balance AS InventoryJournalBalance
	|WHERE
	|	InventoryJournalBalance.Type = VALUE(Enum.InventoryCosting.WeightedAverage)
	|GROUP BY
	|	InventoryJournalBalance.Type,
	|	InventoryJournalBalance.Product";
	
	Return QueryText + DocumentPosting.GetDelimeterOfBatchQuery();
	
EndFunction

// Query for document data.
Function Query_InventoryJournal_Balance_FIFO(TablesList)
	
	// Add InventoryJournal balance table to document structure.
	TablesList.Insert("Table_InventoryJournal_Balance_FIFO", TablesList.Count());
	
	// Collect inventory data.
	QueryText =
	"SELECT
	// ------------------------------------------------------
	// Dimensions
	|	InventoryJournalBalance.Product          AS Product,
	|	InventoryJournalBalance.Location         AS Location,
	|	InventoryJournalBalance.Layer            AS Layer,
	// ------------------------------------------------------
	// Resources
	|	InventoryJournalBalance.Quantity         AS Quantity,
	|	InventoryJournalBalance.Amount           AS Amount,
	// ------------------------------------------------------
	// Agregates
	|	SUM(InventoryJournalCumulative.Quantity) AS QuantityCumulative
	// ------------------------------------------------------
	|INTO
	|	Table_InventoryJournal_Balance_FIFO
	|FROM
	|	Table_InventoryJournal_Balance AS InventoryJournalBalance
	|	LEFT JOIN Table_InventoryJournal_Balance AS InventoryJournalCumulative
	|		ON  InventoryJournalBalance.Product =  InventoryJournalCumulative.Product
	|		AND InventoryJournalBalance.Location = InventoryJournalCumulative.Location
	|		AND InventoryJournalBalance.Layer.PointInTime >= InventoryJournalCumulative.Layer.PointInTime
	|WHERE
	|	InventoryJournalBalance.Type = VALUE(Enum.InventoryCosting.FIFO)
	|GROUP BY
	|	InventoryJournalBalance.Product,
	|	InventoryJournalBalance.Location,
	|	InventoryJournalBalance.Layer,
	|	InventoryJournalBalance.Quantity,
	|	InventoryJournalBalance.Amount";
	
	Return QueryText + DocumentPosting.GetDelimeterOfBatchQuery();
	
EndFunction

// Query for document data.
Function Query_InventoryJournal(TablesList)
	
	// Add InventoryJournal table to document structure.
	TablesList.Insert("Table_InventoryJournal", TablesList.Count());
	
	// Collect inventory data.
	QueryText =
	"SELECT // FIFO normal balances
	// ------------------------------------------------------
	// Standard attributes
	|	CashSale.Ref                          AS Recorder,
	|	CashSale.Date                         AS Period,
	|	0                                     AS LineNumber,
	|	VALUE(AccumulationRecordType.Expense) AS RecordType,
	|	True                                  AS Active,
	// ------------------------------------------------------
	// Dimensions
	|	Balance_FIFO.Product                  AS Product,
	|	Balance_FIFO.Location                 AS Location,
	|	Balance_FIFO.Layer                    AS Layer,
	// ------------------------------------------------------
	// Resources
	|	CASE
	|		WHEN Balance_FIFO.QuantityCumulative <= LineItems_FIFO.QuantityRequested
	|		// The layer written off completely.
	|		THEN Balance_FIFO.Quantity
	|		// The layer written partially or left off.
	|		ELSE CASE
	|			WHEN Balance_FIFO.Quantity + LineItems_FIFO.QuantityRequested - Balance_FIFO.QuantityCumulative > 0
	|			// The layer written off partially.
	|			THEN Balance_FIFO.Quantity + LineItems_FIFO.QuantityRequested - Balance_FIFO.QuantityCumulative
	|			// The layer is not requested and left off.
	|			ELSE 0
	|		END
	|	END                                   AS Quantity,
	|	CASE
	|		WHEN Balance_FIFO.QuantityCumulative <= LineItems_FIFO.QuantityRequested
	|		// The layer written off completely.
	|		THEN Balance_FIFO.Amount
	|		// The layer written partially or left off.
	|		ELSE CASE
	|			WHEN Balance_FIFO.Quantity + LineItems_FIFO.QuantityRequested - Balance_FIFO.QuantityCumulative > 0
	|			// The layer written off partially.
	|			THEN CAST ( // Format(Amount * QuantityExpense / Quantity, ""ND=15; NFD=2"")
	|				 Balance_FIFO.Amount * 
	|				(Balance_FIFO.Quantity + LineItems_FIFO.QuantityRequested - Balance_FIFO.QuantityCumulative) /
	|				 Balance_FIFO.Quantity
	|				 AS NUMBER (15, 2))
	|			// The layer is not requested and left off.
	|			ELSE 0
	|		END
	|	END                                   AS Amount
	// ------------------------------------------------------
	// Attributes
	// ------------------------------------------------------
	|FROM
	|	Table_InventoryJournal_Balance_FIFO AS Balance_FIFO
	|	LEFT JOIN Table_InventoryJournal_LineItems AS LineItems_FIFO
	|		ON  Balance_FIFO.Product  = LineItems_FIFO.Product
	|		AND Balance_FIFO.Location = LineItems_FIFO.Location
	|	LEFT JOIN Document.CashSale AS CashSale
	|		ON True
	|WHERE
	|	CashSale.Ref = &Ref
	|	AND LineItems_FIFO.Type = VALUE(Enum.InventoryCosting.FIFO)
	|	AND // Quantity > 0
	|	CASE
	|		WHEN Balance_FIFO.QuantityCumulative <= LineItems_FIFO.QuantityRequested
	|		// The layer written off completely.
	|		THEN Balance_FIFO.Quantity
	|		// The layer written partially or left off.
	|		ELSE CASE
	|			WHEN Balance_FIFO.Quantity + LineItems_FIFO.QuantityRequested - Balance_FIFO.QuantityCumulative > 0
	|			// The layer written off partially.
	|			THEN Balance_FIFO.Quantity + LineItems_FIFO.QuantityRequested - Balance_FIFO.QuantityCumulative
	|			// The layer is not requested and left off.
	|			ELSE 0
	|		END
	|	END > 0
	|
	|UNION ALL
	|
	|SELECT // FIFO negative balances
	// ------------------------------------------------------
	// Standard attributes
	|	CashSale.Ref                          AS Recorder,
	|	CashSale.Date                         AS Period,
	|	0                                     AS LineNumber,
	|	VALUE(AccumulationRecordType.Expense) AS RecordType,
	|	True                                  AS Active,
	// ------------------------------------------------------
	// Dimensions
	|	LineItems_FIFO.Product                AS Product,
	|	LineItems_FIFO.Location               AS Location,
	|	NULL                                  AS Layer,
	// ------------------------------------------------------
	// Resources
	|	CASE
	|		WHEN LineItems_FIFO.QuantityRequested > ISNULL(Balance_FIFO.Quantity, 0)
	|		// The balance became negative.
	|		THEN LineItems_FIFO.QuantityRequested - ISNULL(Balance_FIFO.Quantity, 0)
	|		// The balance still positive or zeroed.
	|		ELSE 0
	|	END                                   AS Quantity,
	|	0                                     AS Amount
	// ------------------------------------------------------
	// Attributes
	// ------------------------------------------------------
	|FROM
	|	Table_InventoryJournal_LineItems AS LineItems_FIFO
	|	LEFT JOIN Table_InventoryJournal_Balance_Quantity AS Balance_FIFO
	|		ON  Balance_FIFO.Product  = LineItems_FIFO.Product
	|		AND Balance_FIFO.Location = LineItems_FIFO.Location
	|	LEFT JOIN Document.CashSale AS CashSale
	|		ON True
	|WHERE
	|	CashSale.Ref = &Ref
	|	AND LineItems_FIFO.Type = VALUE(Enum.InventoryCosting.FIFO)
	|	AND // Quantity > 0
	|	CASE
	|		WHEN LineItems_FIFO.QuantityRequested > ISNULL(Balance_FIFO.Quantity, 0)
	|		// The balance became negative.
	|		THEN LineItems_FIFO.QuantityRequested - ISNULL(Balance_FIFO.Quantity, 0)
	|		// The balance still positive or zeroed.
	|		ELSE 0
	|	END > 0
	|
	|UNION ALL
	|
	|SELECT // WeightedAverage by quantity
	// ------------------------------------------------------
	// Standard attributes
	|	CashSale.Ref                          AS Recorder,
	|	CashSale.Date                         AS Period,
	|	0                                     AS LineNumber,
	|	VALUE(AccumulationRecordType.Expense) AS RecordType,
	|	True                                  AS Active,
	// ------------------------------------------------------
	// Dimensions
	|	LineItems_WAve.Product                AS Product,
	|	LineItems_WAve.Location               AS Location,
	|	NULL                                  AS Layer,
	// ------------------------------------------------------
	// Resources
	|	LineItems_WAve.QuantityRequested      AS Quantity,
	|	0                                     AS Amount
	// ------------------------------------------------------
	// Attributes
	// ------------------------------------------------------
	|FROM
	|	Table_InventoryJournal_LineItems AS LineItems_WAve
	|	LEFT JOIN Document.CashSale AS CashSale
	|		ON True
	|WHERE
	|	CashSale.Ref = &Ref
	|	AND LineItems_WAve.Type      = VALUE(Enum.InventoryCosting.WeightedAverage)
	|	AND LineItems_WAve.Location <> VALUE(Catalog.Locations.EmptyRef)
	|	AND LineItems_WAve.QuantityRequested > 0
	|
	|UNION ALL
	|
	|SELECT // WeightedAverage by amount
	// ------------------------------------------------------
	// Standard attributes
	|	CashSale.Ref                          AS Recorder,
	|	CashSale.Date                         AS Period,
	|	0                                     AS LineNumber,
	|	VALUE(AccumulationRecordType.Expense) AS RecordType,
	|	True                                  AS Active,
	// ------------------------------------------------------
	// Dimensions
	|	LineItems_WAve.Product                AS Product,
	|	VALUE(Catalog.Locations.EmptyRef)     AS Location,
	|	NULL                                  AS Layer,
	// ------------------------------------------------------
	// Resources
	|	0                                     AS Quantity,
	|	CASE
	|		WHEN ISNULL(Balance_WAve.Quantity, 0) <= LineItems_WAve.QuantityRequested
	|		// The product written off completely.
	|		THEN ISNULL(Balance_WAve.Amount, 0)
	|		// The product written off partially.
	|		ELSE CAST ( // Format(Amount / QuantityExpense / Quantity, ""ND=15; NFD=2"")
	|			 Balance_WAve.Amount * LineItems_WAve.QuantityRequested / Balance_WAve.Quantity
	|			 AS NUMBER (15, 2))
	|	END                                   AS Amount
	// ------------------------------------------------------
	// Attributes
	// ------------------------------------------------------
	|FROM
	|	Table_InventoryJournal_LineItems AS LineItems_WAve
	|	LEFT JOIN Table_InventoryJournal_Balance_Quantity AS Balance_WAve
	|		ON  Balance_WAve.Product  = LineItems_WAve.Product
	|		AND Balance_WAve.Location = VALUE(Catalog.Locations.EmptyRef)
	|	LEFT JOIN Document.CashSale AS CashSale
	|		ON True
	|WHERE
	|	CashSale.Ref = &Ref
	|	AND LineItems_WAve.Type     = VALUE(Enum.InventoryCosting.WeightedAverage)
	|	AND LineItems_WAve.Location = VALUE(Catalog.Locations.EmptyRef)
	|	AND // Amount > 0
	|	CASE
	|		WHEN ISNULL(Balance_WAve.Quantity, 0) <= LineItems_WAve.QuantityRequested
	|		// The product written off completely.
	|		THEN ISNULL(Balance_WAve.Amount, 0)
	|		// The product written off partially.
	|		ELSE CAST ( // Format(Amount / QuantityExpense / Quantity, ""ND=15; NFD=2"")
	|			 Balance_WAve.Amount * LineItems_WAve.QuantityRequested / Balance_WAve.Quantity
	|			 AS NUMBER (15, 2))
	|	END > 0";
	
	Return QueryText + DocumentPosting.GetDelimeterOfBatchQuery();
	
EndFunction

// Query for dimensions lock data.
Function Query_InventoryJournal_Lock(TablesList)
	
	// Add InventoryJournal - Lock table to locks structure.
	TablesList.Insert("AccumulationRegister_InventoryJournal", TablesList.Count());
	
	// Collect dimensions for inventory journal locking.
	QueryText =
	"SELECT DISTINCT // FIFO & WAve by quantity
	// ------------------------------------------------------
	// Dimensions
	|	LineItems.Product                     AS Product,
	|	&Location                             AS Location
	// ------------------------------------------------------
	|FROM
	|	Table_LineItems AS LineItems
	|WHERE
	|	LineItems.Product.Type = VALUE(Enum.InventoryTypes.Inventory)
	|
	|UNION ALL
	|
	|SELECT DISTINCT // WAve by amount
	// ------------------------------------------------------
	// Dimensions
	|	LineItems.Product                     AS Product,
	|	VALUE(Catalog.Locations.EmptyRef)     AS Location
	// ------------------------------------------------------
	|FROM
	|	Table_LineItems AS LineItems
	|WHERE
	|	    LineItems.Product.Type = VALUE(Enum.InventoryTypes.Inventory)
	|	AND LineItems.Product.CostingMethod = VALUE(Enum.InventoryCosting.WeightedAverage)";
	
	Return QueryText + DocumentPosting.GetDelimeterOfBatchQuery();
	
EndFunction

// Query for balances data.
Function Query_InventoryJournal_Balance(TablesList)
	
	// Add InventoryJournal - Balances table to balances structure.
	TablesList.Insert("Table_InventoryJournal_Balance", TablesList.Count());
	
	// Collect inventory journal balances.
	QueryText =
	"SELECT // FIFO
	// ------------------------------------------------------
	// Dimensions
	|	InventoryJournalBalance.Product.CostingMethod
	|	                                         AS Type,
	|	InventoryJournalBalance.Product          AS Product,
	|	InventoryJournalBalance.Location         AS Location,
	|	InventoryJournalBalance.Layer            AS Layer,
	// ------------------------------------------------------
	// Resources
	|	InventoryJournalBalance.QuantityBalance  AS Quantity,
	|	InventoryJournalBalance.AmountBalance    AS Amount
	// ------------------------------------------------------
	|FROM
	|	AccumulationRegister.InventoryJournal.Balance(&PointInTime,
	|		(Product, Location) IN
	|		(SELECT DISTINCT Product, Location FROM Table_InventoryJournal_Lock WHERE Product.CostingMethod = VALUE(Enum.InventoryCosting.FIFO)))
	|		                                     AS InventoryJournalBalance
	|
	|UNION ALL
	|
	|SELECT // WAve by quantity and amount
	// ------------------------------------------------------
	// Dimensions
	|	InventoryJournalBalance.Product.CostingMethod
	|	                                         AS Type,
	|	InventoryJournalBalance.Product          AS Product,
	|	InventoryJournalBalance.Location         AS Location,
	|	NULL                                     AS Layer,
	// ------------------------------------------------------
	// Resources
	|	InventoryJournalBalance.QuantityBalance  AS Quantity,
	|	InventoryJournalBalance.AmountBalance    AS Amount
	// ------------------------------------------------------
	|FROM
	|	AccumulationRegister.InventoryJournal.Balance(&PointInTime,
	|		(Product) IN
	|		(SELECT DISTINCT Product FROM Table_InventoryJournal_Lock WHERE Product.CostingMethod = VALUE(Enum.InventoryCosting.WeightedAverage)))
	|		                                     AS InventoryJournalBalance";
	
	Return QueryText + DocumentPosting.GetDelimeterOfBatchQuery();
	
EndFunction

Function Query_SalesTaxOwed(TablesList)
	// Add SalesTaxOwed table to document structure.
	TablesList.Insert("Table_SalesTaxOwed", TablesList.Count());
	
	// Collect sales tax data
	QueryText1 ="SELECT
				// Standard
	           |	CashSale.Ref AS Recorder,
	           |	CashSale.Ref.Date AS Period,
	           |	0 AS LineNumber,
	           |	VALUE(AccumulationRecordType.Receipt) AS RecordType,
	           |	TRUE AS Active,
			    // Dimensions
	           |	AccountingMethod.Ref AS ChargeType,
	           |	CashSale.Agency AS Agency,
	           |	CashSale.Rate AS TaxRate,
			   |	CashSale.SalesTaxComponent as SalesTaxComponent,
			    // Resources
	           |	CashSale.Ref.DocumentTotalRC - CashSale.Ref.SalesTax AS GrossSale,
	           |	CashSale.Ref.TaxableSubtotal AS TaxableSale,
	           |	CashSale.Amount AS TaxPayable
	           |FROM
	           |	Document.CashSale.SalesTaxAcrossAgencies AS CashSale,
			   |    Enum.AccountingMethod AS AccountingMethod
	           |WHERE
	           |	CashSale.Ref = &Ref";
			   
	Return QueryText1 + DocumentPosting.GetDelimeterOfBatchQuery();
	
EndFunction

// Query for sales tax to be posted in General Journal
Function Query_GeneralJournal_SalesTax(TablesList)
	
	// Add General Journal table to document structure.
	TablesList.Insert("Table_GeneralJournal", TablesList.Count());
	
	// Collect sales tax data.
	QueryText = "SELECT
	            |	CashSale.Ref AS Recorder,
	            |	CashSale.Date AS Period,
	            |	0 AS LineNumber,
	            |	VALUE(AccountingRecordType.Credit) AS RecordType,
	            |	TRUE AS Active,
	            |	TaxPayableAccount.Value AS Account,
	            |	NULL AS ExtDimensionTypeDr1,
	            |	NULL AS ExtDimensionTypeDr2,
	            |	NULL AS ExtDimensionDr1,
	            |	NULL AS ExtDimensionDr2,
	            |	VALUE(Catalog.Currencies.EmptyRef) AS Currency,
	            |	0 AS Amount,
	            |	CashSale.SalesTax AS AmountRC,
	            |	"""" AS Memo
	            |FROM
	            |	Document.CashSale AS CashSale,
	            |	Constant.TaxPayableAccount AS TaxPayableAccount
	            |WHERE
	            |	CashSale.Ref = &Ref";
	
	Return QueryText + DocumentPosting.GetDelimeterOfBatchQuery();
	
EndFunction

// Put structure of registers, which balance should be checked during posting.
Procedure FillRegistersCheckList(AdditionalProperties, RegisterRecords)
	
	// Create structure of registers and its resources to check balances.
	BalanceCheck = New Structure;
	
	// Fill structure depending on document write mode.
	If AdditionalProperties.Posting.WriteMode = DocumentWriteMode.Posting Then
		
		// Add resources for check changes in recordset.
		CheckPostings = New Array;
		CheckPostings.Add("{Table}.Quantity{Posting}, <, 0"); // Check decreasing quantity.
		
		// Add resources for check register balances.
		CheckBalances = New Array;
		CheckBalances.Add("{Table}.Quantity{Balance}, <, 0"); // Check negative inventory balance.
		
		// Add messages for different error situations.
		CheckMessages = New Array;
		CheckMessages.Add(NStr("en = '{Product}?{Layer}:
		                             |There is an insufficient balance of {-Quantity} at the {Location}.|Layer = "" of {Layer}""'"));
		
		// Add register to check it's recordset changes and balances during posting.
		BalanceCheck.Insert("InventoryJournal", New Structure("CheckPostings, CheckBalances, CheckMessages", CheckPostings, CheckBalances, CheckMessages));
		
	ElsIf AdditionalProperties.Posting.WriteMode = DocumentWriteMode.UndoPosting Then
		
		// No checks performed while unposting, it does not lead to decreasing the balance.
	EndIf;
	
	// Return structure of registers to check.
	If BalanceCheck.Count() > 0 Then
		AdditionalProperties.Posting.Insert("BalanceCheck", BalanceCheck);
	EndIf;
	
EndProcedure

//------------------------------------------------------------------------------
// Document filling

//------------------------------------------------------------------------------
// Document printing

#EndIf

#EndRegion