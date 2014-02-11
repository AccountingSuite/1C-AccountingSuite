﻿&AtServer
// Request order status from database
Procedure FillOrderStatuses()
	 
	// Request order status
	If Not ValueIsFilled(Object.Ref) Then
		// New order has open status
		OrderStatus = Enums.OrderStatuses.Open;
		
	Else
		// Create new query
		Query = New Query;
		Query.SetParameter("Ref", Object.Ref);
		
		Query.Text = 
			"SELECT TOP 1
			|	OrdersStatuses.Status
			|FROM
			|	InformationRegister.OrdersStatuses AS OrdersStatuses
			|WHERE
			|	Order = &Ref
			|ORDER BY
			|	OrdersStatuses.Status.Order Desc";
		Selection = Query.Execute().Choose();
		
		// Fill order status
		If Selection.Next() Then
			OrderStatus = Selection.Status;
		Else
			OrderStatus = Enums.OrderStatuses.Open;
		EndIf;
	EndIf;
	OrderStatusIndex = Enums.OrderStatuses.IndexOf(OrderStatus);
	
	// Build order status presentation (depending of document state)
	If Not ValueIsFilled(Object.Ref) Then
		OrderStatusPresentation = String(Enums.OrderStatuses.New);
		Items.OrderStatusPresentation.TextColor = WebColors.DarkGreen;
	ElsIf Object.DeletionMark Then
		OrderStatusPresentation = String(Enums.OrderStatuses.Deleted);
		Items.OrderStatusPresentation.TextColor = WebColors.DarkGray;
	ElsIf Not Object.Posted Then 
		OrderStatusPresentation = String(Enums.OrderStatuses.Draft);
		Items.OrderStatusPresentation.TextColor = WebColors.DarkGray;
	Else
		OrderStatusPresentation = String(OrderStatus);
		If OrderStatus = Enums.OrderStatuses.Open Then 
			ThisForm.Items.OrderStatusPresentation.TextColor = WebColors.DarkGreen;
		ElsIf OrderStatus = Enums.OrderStatuses.Backordered Then 
			ThisForm.Items.OrderStatusPresentation.TextColor = WebColors.DarkGoldenRod;
		ElsIf OrderStatus = Enums.OrderStatuses.Closed Then
			ThisForm.Items.OrderStatusPresentation.TextColor = WebColors.DarkRed;
		Else
			ThisForm.Items.OrderStatusPresentation.TextColor = WebColors.DarkGray;
		EndIf;
	EndIf;
	
EndProcedure

&AtServer
// Request demanded order items from database
Procedure FillOrdersRegistered()
	
	// Request ordered items quantities
	If ValueIsFilled(Object.Ref) Then
		
		// Create new query
		Query = New Query;
		Query.SetParameter("Ref", Object.Ref);
		Query.SetParameter("OrderStatus", OrderStatus);
		
		Query.Text = 
			"SELECT
			|	OrdersRegistered.LineNumber              AS LineNumber,
			|	OrdersRegisteredBalance.Product          AS Product,                                                            // ---------------------------------------
			|	OrdersRegisteredBalance.QuantityBalance  AS Quantity,                                                           // Backorder quantity calculation
			|	CASE                                                                                                            // ---------------------------------------
			|		WHEN &OrderStatus = VALUE(Enum.OrderStatuses.Open)        THEN 0                                            // Order status = Open:
			|		WHEN &OrderStatus = VALUE(Enum.OrderStatuses.Backordered) THEN                                              //   Backorder = 0
			|			CASE                                                                                                    // Order status = Backorder:
			|				WHEN OrdersRegisteredBalance.Product.Type = VALUE(Enum.InventoryTypes.Inventory) THEN               //   Inventory:
			|					CASE                                                                                            //     Backorder = Ordered - Shipped >= 0
			|						WHEN OrdersRegisteredBalance.QuantityBalance > OrdersRegisteredBalance.ShippedBalance THEN  //     |
			|							 OrdersRegisteredBalance.QuantityBalance - OrdersRegisteredBalance.ShippedBalance       //     |
			|						ELSE 0 END                                                                                  //     |
			|				ELSE                                                                                                //   Non-inventory:
			|					CASE                                                                                            //     Backorder = Ordered - Invoiced >= 0
			|						WHEN OrdersRegisteredBalance.QuantityBalance > OrdersRegisteredBalance.InvoicedBalance THEN //     |
			|							 OrdersRegisteredBalance.QuantityBalance - OrdersRegisteredBalance.InvoicedBalance      //     |
			|						ELSE 0 END                                                                                  //     |
			|				END                                                                                                 //     |
			|		WHEN &OrderStatus = VALUE(Enum.OrderStatuses.Closed)      THEN 0                                            // Order status = Closed:
			|		END AS Backorder,                                                                                           //   Backorder = 0
			|	OrdersRegisteredBalance.ShippedBalance   AS Shipped,
			|	OrdersRegisteredBalance.InvoicedBalance  AS Invoiced
			|FROM
			|	AccumulationRegister.OrdersRegistered.Balance(,
			|		(Company, Order, Product) IN
			|			(SELECT
			|				LineItems.Ref.Company,
			|				LineItems.Ref,
			|				LineItems.Product
			|			FROM
			|				Document.SalesOrder.LineItems AS LineItems
			|			WHERE
			|				LineItems.Ref = &Ref)) AS OrdersRegisteredBalance
			|	LEFT JOIN AccumulationRegister.OrdersRegistered AS OrdersRegistered
			|		ON    ( OrdersRegistered.Recorder = &Ref
			|			AND OrdersRegistered.Company  = OrdersRegisteredBalance.Company
			|			AND OrdersRegistered.Order    = OrdersRegisteredBalance.Order
			|			AND OrdersRegistered.Product  = OrdersRegisteredBalance.Product
			|			AND OrdersRegistered.Quantity = OrdersRegisteredBalance.QuantityBalance)
			|ORDER BY
			|	OrdersRegistered.LineNumber";
		Selection = Query.Execute().Choose();
		
		// Fill ordered items quantities
		SearchRec = New Structure("LineNumber, Product, Quantity");
		While Selection.Next() Do
			
			// Search for appropriate line in tabular section of order
			FillPropertyValues(SearchRec, Selection);
			FoundLineItems = Object.LineItems.FindRows(SearchRec);
			
			// Fill quantities in tabular section
			If FoundLineItems.Count() > 0 Then
				FillPropertyValues(FoundLineItems[0], Selection, "Backorder, Shipped, Invoiced");
			EndIf;
			
		EndDo;
		
	EndIf;
	
EndProcedure

&AtServer
// Request and fill indexes of product type (required to calculate bacorder property)
Procedure FillProductTypes()
	
	// Fill line item's product types
	If ValueIsFilled(Object.Ref) Then
		
		// Create new query
		Query = New Query;
		Query.SetParameter("Ref", Object.Ref);
		
		Query.Text =
		"SELECT
		|	SalesOrderLineItems.LineNumber         AS LineNumber,
		|	SalesOrderLineItems.Product.Type.Order AS ProductTypeIndex
		|FROM
		|	Document.SalesOrder.LineItems AS SalesOrderLineItems
		|WHERE
		|	SalesOrderLineItems.Ref = &Ref
		|ORDER BY
		|	LineNumber";
		Selection = Query.Execute().Choose();
		
		// Fill ordered items quantities
		While Selection.Next() Do
			
			// Search for appropriate line in tabular section of order
			LineItem = Object.LineItems.Get(Selection.LineNumber-1);
			If LineItem <> Undefined Then
				LineItem.ProductTypeIndex = Selection.ProductTypeIndex;
			EndIf;
		EndDo;
		
	EndIf;
EndProcedure

&AtClient
// ProductOnChange UI event handler.
// The procedure clears quantities, line total, and taxable amount in the line item,
// selects price for the new product from the price-list, divides the price by the document
// exchange rate, selects a default unit of measure for the product, and
// selects a product's sales tax type.
// 
Procedure LineItemsProductOnChange(Item)
	
	TabularPartRow = Items.LineItems.CurrentData;
	
	DataArray = GetDataOnServer(TabularPartRow.Product, Object.Company);
	
	//ProductProperties = CommonUse.GetAttributeValues(TabularPartRow.Product, "Description, SalesVATCode");  // mt_change Type.Order,
	//TabularPartRow.ProductDescription = ProductProperties.Description;
	TabularPartRow.ProductDescription = DataArray[0];
	TabularPartRow.ProductTypeIndex   = DataArray[3]; // TypeOrder(TabularPartRow.Product);
	
	TabularPartRow.Quantity = 0;
	TabularPartRow.Backorder = 0;
	TabularPartRow.Shipped = 0;
	TabularPartRow.Invoiced = 0;
	TabularPartRow.LineTotal = 0;
	//TabularPartRow.TaxableAmount = 0;
	TabularPartRow.Price = 0;
	TabularPartRow.Taxable = DataArray[2];
    //TabularPartRow.VAT = 0;
	
	Price = DataArray[1]; //GeneralFunctions.RetailPrice(CurrentDate(), TabularPartRow.Product, Object.Company);
	TabularPartRow.Price = Price / Object.ExchangeRate;

	//TabularPartRow.SalesTaxType = DataArray[3]; // US_FL.GetSalesTaxType(TabularPartRow.Product);	
	
	//TabularPartRow.VATCode = DataArray[2];   // ProductProperties.SalesVATCode;
	
	RecalcTotal();
	
EndProcedure

&AtServer
Function GetDataOnServer(Product, Company)
	
	 ReturnArray = New Array(5);
	 ReturnArray[0] = Product.Description;
	 ReturnArray[1] = GeneralFunctions.RetailPrice(CurrentDate(), Product, Company);
	 ReturnArray[2] = Product.Taxable;
	 
	 If Product.Type = Enums.InventoryTypes.Inventory Then
		ReturnArray[3] = 0;
	 Else
		ReturnArray[3] = 1;
	 EndIf;
	 
	 Return ReturnArray;
	 
EndFunction


// mt_change
//Function TypeOrder(Product) Export
//	
//	If Product.Type = Enums.InventoryTypes.Inventory Then
//		Return 0;
//	Else
//		Return 1;
//	EndIf;
//	
//EndFunction


//&AtClient
// The procedure recalculates the document's total.
// DocumentTotal - document's currency in FCY (foreign currency).
// DocumentTotalRC - company's reporting currency.
//
&AtServer
Procedure RecalcTotal()
	
	
	Object.LineSubtotalRC = Object.LineItems.Total("LineTotal");
	Object.SubTotalRC = Object.LineItems.Total("LineTotal") + Object.DiscountRC;
	
	DocTotal = Object.LineSubtotalRC + Object.DiscountRC + Object.ShippingRC + Object.SalesTaxRC;
	Object.DocumentTotal = DocTotal;
	Object.DocumentTotalRC = DocTotal * Object.ExchangeRate;

	
EndProcedure


&AtClient
// CustomerOnChange UI event handler.
// Selects default currency for the customer, determines an exchange rate, and
// recalculates the document's sales tax and total amounts.
// 
Procedure CompanyOnChange(Item)
	
	CompanyOnChangeServer();
	
EndProcedure

&AtServer
Procedure CompanyOnChangeServer()
	
	//Object.CompanyCode = CommonUse.GetAttributeValue(Object.Company, "Code");
	Object.ShipTo = GeneralFunctions.GetShipToAddress(Object.Company);
	Object.BillTo = GeneralFunctions.GetBillToAddress(Object.Company);
	Object.Currency = CommonUse.GetAttributeValue(Object.Company, "DefaultCurrency");
	Object.ExchangeRate = GeneralFunctions.GetExchangeRate(Object.Date, Object.Currency);
	Items.ExchangeRate.Title = GeneralFunctionsReusable.DefaultCurrencySymbol() + "/1" + CommonUse.GetAttributeValue(Object.Currency, "Symbol");
	Items.FCYCurrency.Title = CommonUse.GetAttributeValue(Object.Currency, "Symbol");
	//RecalcSalesTax();
	RecalcTotal();
	//RecalcSalesTaxAndTotal();

EndProcedure

&AtClient
// PriceOnChange UI event handler.
// Calculates line total by multiplying a price by a quantity in either the selected
// unit of measure (U/M) or in the base U/M, and recalculates the line's taxable amount and total.
// 
Procedure LineItemsPriceOnChange(Item)
	
	TabularPartRow = Items.LineItems.CurrentData;
	
	TabularPartRow.LineTotal = TabularPartRow.Quantity * TabularPartRow.Price;
	
	//RecalcTaxableAmount();
	//RecalcSalesTax();
	RecalcTotal();
	//RecalcSalesTaxAndTotal();

EndProcedure


&AtClient
// DateOnChange UI event handler.
// Determines an exchange rate on the new date, and recalculates the document's
// sales tax and total.
//
Procedure DateOnChange(Item)
	
	If GeneralFunctionsReusable.FunctionalOptionValue("MultiCurrency") Then
		Object.ExchangeRate = GeneralFunctions.GetExchangeRate(Object.Date, Object.Currency);
	Else
		Object.ExchangeRate = 1;
	EndIf;
	//RecalcSalesTax();
	RecalcTotal();
	//RecalcSalesTaxAndTotal();
	
EndProcedure

&AtClient
// CurrencyOnChange UI event handler.
// Determines an exchange rate for the new currency, and recalculates the document's
// sales tax and total.
//
Procedure CurrencyOnChange(Item)
	
	Object.ExchangeRate = GeneralFunctions.GetExchangeRate(Object.Date, Object.Currency);
	Items.ExchangeRate.Title = GeneralFunctionsReusable.DefaultCurrencySymbol() + "/1" + CommonUse.GetAttributeValue(Object.Currency, "Symbol");
	Items.FCYCurrency.Title = CommonUse.GetAttributeValue(Object.Currency, "Symbol");
	//RecalcSalesTax();
	RecalcTotal();
	//RecalcSalesTaxAndTotal();
	
EndProcedure

&AtClient
// LineItemsAfterDeleteRow UI event handler.
// 
Procedure LineItemsAfterDeleteRow(Item)
	
	//RecalcSalesTax();
	RecalcTotal();
	//RecalcSalesTaxAndTotal();
	
EndProcedure

&AtClient
// LineItemsQuantityOnChange UI event handler.
// This procedure is used when the units of measure (U/M) functional option is turned off
// and base quantities are used instead of U/M quantities.
// The procedure recalculates line total, line taxable amount, and a document's sales tax and total.
// 
Procedure LineItemsQuantityOnChange(Item)
	
	// Request current string
	TabularPartRow = Items.LineItems.CurrentData;
	
	// Calculate sum and taxes by line
	TabularPartRow.LineTotal = TabularPartRow.Quantity * TabularPartRow.Price;
	
	//If GeneralFunctionsReusable.FunctionalOptionValue("VATFinLocalization") Then
	//	TabularPartRow.VAT = VAT_FL.VATLine(TabularPartRow.LineTotal, TabularPartRow.VATCode, "Sales", Object.PriceIncludesVAT);
	//Else	
	//	TabularPartRow.VAT = 0;
	//EndIf;
	
	// Update backorder quantity based on document status
	If    OrderStatusIndex = 0 Then // OrderStatus = Enums.OrderStatuses.Open
		TabularPartRow.Backorder = 0;
	ElsIf OrderStatusIndex = 1 Then // OrderStatus = Enums.OrderStatuses.Backordered
		If TabularPartRow.ProductTypeIndex = 0 Then // Product.Type = Enums.InventoryTypes.Inventory
			TabularPartRow.Backorder = Max(TabularPartRow.Quantity - TabularPartRow.Shipped, 0);
		Else 
			TabularPartRow.Backorder = Max(TabularPartRow.Quantity - TabularPartRow.Invoiced, 0);
		EndIf;
	ElsIf OrderStatusIndex = 2 Then // OrderStatus = Enums.OrderStatuses.Closed
		TabularPartRow.Backorder = 0;
	Else
		TabularPartRow.Backorder = 0;
	EndIf;
	
	// Calculate totals
	//RecalcTaxableAmount();
	//RecalcSalesTax();
	RecalcTotal();
	//RecalcSalesTaxAndTotal();

EndProcedure

&AtServer
// Procedure fills in default values, used mostly when the corresponding functional
// options are turned off.
// The following defaults are filled in - warehouse location, and currency.
// 
Procedure OnCreateAtServer(Cancel, StandardProcessing)
	
	//ConstantSaleOrder = Constants.SalesOrderLastNumber.Get();
	//If Object.Ref.IsEmpty() Then		
	//	
	//	Object.Number = Constants.SalesOrderLastNumber.Get();
	//Endif;

	
	tempstor = PutToTempStorage(Object.Company,Object.Ref);
	
	Items.LineItemsQuantity.EditFormat = "NFD=" + Constants.QtyPrecision.Get();
	Items.LineItemsQuantity.Format = "NFD=" + Constants.QtyPrecision.Get();
	
	Items.LineItemsBackorder.EditFormat = "NFD=" + Constants.QtyPrecision.Get();
	Items.LineItemsBackorder.Format = "NFD=" + Constants.QtyPrecision.Get();

	Items.LineItemsShipped.EditFormat = "NFD=" + Constants.QtyPrecision.Get();
	Items.LineItemsShipped.Format = "NFD=" + Constants.QtyPrecision.Get();

	Items.LineItemsInvoiced.EditFormat = "NFD=" + Constants.QtyPrecision.Get();
	Items.LineItemsInvoiced.Format = "NFD=" + Constants.QtyPrecision.Get();

	Items.Company.Title = GeneralFunctionsReusable.GetCustomerName();
	
	//Title = "Sales Order " + Object.Number + " " + Format(Object.Date, "DLF=D");
	
	//If Object.Ref.IsEmpty() Then
	//	Object.PriceIncludesVAT = GeneralFunctionsReusable.PriceIncludesVAT();
	//EndIf;
	
	//If NOT GeneralFunctionsReusable.FunctionalOptionValue("VATFinLocalization") Then
	//	Items.VATGroup.Visible = False;
	//EndIf;
	
	If NOT GeneralFunctionsReusable.FunctionalOptionValue("MultiCurrency") Then
		Items.FCYCurrency.Visible = False;
		Items.RCCurrency.Visible = False;
	EndIf;
	
	//If GeneralFunctionsReusable.FunctionalOptionValue("MultiLocation") Then
	//Else
		If Object.Location.IsEmpty() Then
			Object.Location = Catalogs.Locations.MainWarehouse;
		EndIf;
	//EndIf;

	If Object.Currency.IsEmpty() Then
		Object.Currency = Constants.DefaultCurrency.Get();
		Object.ExchangeRate = 1;	
	Else
	EndIf; 
	
	Items.ExchangeRate.Title = GeneralFunctionsReusable.DefaultCurrencySymbol() + "/1" + Object.Currency.Symbol;
	//Items.VATCurrency.Title = GeneralFunctionsReusable.DefaultCurrencySymbol();
	Items.RCCurrency.Title = GeneralFunctionsReusable.DefaultCurrencySymbol();
	Items.FCYCurrency.Title = CommonUse.GetAttributeValue(Object.Currency, "Symbol");

	// Request and fill order status
	FillOrderStatuses();

	// Request and fill ordered items from database
	FillOrdersRegistered();
	
	// Request and fill indexes of product type (required to calculate bacorder property)
	FillProductTypes();
	
EndProcedure

//&AtClient
// Calculates a VAT amount for the document line
//
//Procedure LineItemsVATCodeOnChange(Item)
//	
//	TabularPartRow = Items.LineItems.CurrentData;
//	TabularPartRow.VAT = VAT_FL.VATLine(TabularPartRow.LineTotal, TabularPartRow.VATCode, "Sales", Object.PriceIncludesVAT);
//	RecalcTotal();

//EndProcedure

&AtServer
Procedure AfterWriteAtServer(CurrentObject, WriteParameters)
	
	// Request and fill order status from database
	FillOrderStatuses();
	
	// Request and fill ordered items from database
	FillOrdersRegistered();
	
	// Request and fill indexes of product type (required to calculate bacorder property)
	FillProductTypes();
		
EndProcedure

&AtClient
Procedure LineItemsOnChange(Item)
	
	If NewRow = true Then
		CurrentData = Item.CurrentData;
		//CurrentData.Project = Object.Project;
		NewRow = false;
	Endif;

EndProcedure

&AtClient
Procedure LineItemsBeforeAddRow(Item, Cancel, Clone, Parent, Folder)
	NewRow = true;
EndProcedure

&AtServer
Function Increment(NumberToInc)
	
	//Last = Constants.SalesInvoiceLastNumber.Get();
	Last = NumberToInc;
	//Last = "AAAAA";
	LastCount = StrLen(Last);
	Digits = new Array();
	For i = 1 to LastCount Do	
		Digits.Add(Mid(Last,i,1));

	EndDo;
	
	NumPos = 9999;
	lengthcount = 0;
	firstnum = false;
	j = 0;
	While j < LastCount Do
		If NumCheck(Digits[LastCount - 1 - j]) Then
			if firstnum = false then //first number encountered, remember position
				firstnum = true;
				NumPos = LastCount - 1 - j;
				lengthcount = lengthcount + 1;
			Else
				If firstnum = true Then
					If NumCheck(Digits[LastCount - j]) Then //if the previous char is a number
						lengthcount = lengthcount + 1;  //next numbers, add to length.
					Else
						break;
					Endif;
				Endif;
			Endif;
						
		Endif;
		j = j + 1;
	EndDo;
	
	NewString = "";
	
	If lengthcount > 0 Then //if there are numbers in the string
		changenumber = Mid(Last,(NumPos - lengthcount + 2),lengthcount);
		NumVal = Number(changenumber);
		NumVal = NumVal + 1;
		StringVal = String(NumVal);
		StringVal = StrReplace(StringVal,",","");
		
		StringValLen = StrLen(StringVal);
		changenumberlen = StrLen(changenumber);
		LeadingZeros = Left(changenumber,(changenumberlen - StringValLen));

		LeftSide = Left(Last,(NumPos - lengthcount + 1));
		RightSide = Right(Last,(LastCount - NumPos - 1));
		NewString = LeftSide + LeadingZeros + StringVal + RightSide; //left side + incremented number + right side
		
	Endif;
	
	Next = NewString;

	return NewString;
	
EndFunction

&AtServer
Function NumCheck(CheckValue)
	 
	For i = 0 to  9 Do
		If CheckValue = String(i) Then
			Return True;
		Endif;
	EndDo;
		
	Return False;
		
EndFunction


&AtServer
Procedure BeforeWriteAtServer(Cancel, CurrentObject, WriteParameters)
	
	//Period closing
	If DocumentPosting.DocumentPeriodIsClosed(CurrentObject.Ref, CurrentObject.Date) Then
		PermitWrite = DocumentPosting.DocumentWritePermitted(WriteParameters);
		CurrentObject.AdditionalProperties.Insert("PermitWrite", PermitWrite);	
	EndIf;

	
	//If Object.Ref.IsEmpty() Then
	//
	//	MatchVal = Increment(Constants.SalesOrderLastNumber.Get());
	//	If Object.Number = MatchVal Then
	//		Constants.SalesOrderLastNumber.Set(MatchVal);
	//	Else
	//		If Increment(Object.Number) = "" Then
	//		Else
	//			If StrLen(Increment(Object.Number)) > 20 Then
	//				 Constants.SalesOrderLastNumber.Set("");
	//			Else
	//				Constants.SalesOrderLastNumber.Set(Increment(Object.Number));
	//			Endif;

	//		Endif;
	//	Endif;
	//Endif;
EndProcedure


&AtClient
Procedure BeforeWrite(Cancel, WriteParameters)
	
	//Closing period
	If DocumentPosting.DocumentPeriodIsClosed(Object.Ref, Object.Date) Then
		Cancel = Not DocumentPosting.DocumentWritePermitted(WriteParameters);
		If Cancel Then
			If WriteParameters.Property("PeriodClosingPassword") And WriteParameters.Property("Password") Then
				If WriteParameters.Password = TRUE Then //Writing the document requires a password
					ShowMessageBox(, "Invalid password!",, "Closed period notification");
				EndIf;
			Else
				Notify = New NotifyDescription("ProcessUserResponseOnDocumentPeriodClosed", ThisObject, WriteParameters);
				Password = "";
				OpenForm("CommonForm.ClosedPeriodNotification", New Structure, ThisForm,,,, Notify, FormWindowOpeningMode.LockOwnerWindow);
			EndIf;
			return;
		EndIf;
	EndIf;

EndProcedure

//Closing period
&AtClient
Procedure ProcessUserResponseOnDocumentPeriodClosed(Result, Parameters) Export
	If (TypeOf(Result) = Type("String")) Then //Inserted password
		Parameters.Insert("PeriodClosingPassword", Result);
		Parameters.Insert("Password", TRUE);
		Write(Parameters);
	ElsIf (TypeOf(Result) = Type("DialogReturnCode")) Then //Yes, No or Cancel
		If Result = DialogReturnCode.Yes Then
			Parameters.Insert("PeriodClosingPassword", "Yes");
			Parameters.Insert("Password", FALSE);
			Write(Parameters);
		EndIf;
	EndIf;	
EndProcedure

&AtClient
Procedure DiscountRCOnChange(Item)
	RecalcTotal();
EndProcedure

&AtClient
Procedure ShippingRCOnChange(Item)
	RecalcTotal();
EndProcedure

&AtClient
Procedure SalesTaxOnChange(Item)
	RecalcTotal();
EndProcedure

&AtClient
Procedure DiscountPercentOnChange(Item)
	
	Object.DiscountRC = (-1 * Object.LineSubtotalRC * Object.DiscountPercent ) / 100;
	RecalcTotal();

EndProcedure

&AtClient
Procedure Transactions(Command)
	
	FormParameters = New Structure();
	
	FltrParameters = New Structure();
	FltrParameters.Insert("Order", Object.Ref);
	FormParameters.Insert("Filter", FltrParameters);
	OpenForm("CommonForm.OrderTransactions",FormParameters, Object.Ref);

EndProcedure


