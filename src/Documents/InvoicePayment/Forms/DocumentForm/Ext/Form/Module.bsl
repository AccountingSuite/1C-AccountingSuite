﻿
&AtServer
// The procedure selects all vendor invoices and customer returns having an unpaid balance
// and fills in line items of an invoice payment.
//
Procedure FillDocumentList(Company)
		
	Object.LineItems.Clear();
	
	Query = New Query;
	Query.Text = "SELECT
	             |	GeneralJournalBalance.AmountBalance * -1 AS AmountBalance,
	             |	GeneralJournalBalance.AmountRCBalance * -1 AS AmountRCBalance,
	             |	GeneralJournalBalance.ExtDimension2.Ref AS Ref,
				 |  GeneralJournalBalance.ExtDimension2.Date
	             |FROM
	             |	AccountingRegister.GeneralJournal.Balance AS GeneralJournalBalance
	             |WHERE
	             |	GeneralJournalBalance.AmountBalance <> 0
	             |	AND (GeneralJournalBalance.ExtDimension2 REFS Document.PurchaseInvoice OR
	             |       GeneralJournalBalance.ExtDimension2 REFS Document.SalesReturn)
	             |	AND GeneralJournalBalance.ExtDimension1 = &Company
				 |ORDER BY
				 |	GeneralJournalBalance.ExtDimension2.Date";
				 
	Query.SetParameter("Company", Company);
	
	Result = Query.Execute().Choose();
	
	While Result.Next() Do
		// Skip credit memos. Due to high load on subdimensions in query and small quantity of returns - do this in loop
		If TypeOf(Result.Ref) = Type("DocumentRef.SalesReturn") AND Result.Ref.ReturnType = Enums.ReturnTypes.CreditMemo Then
			Continue;
		EndIf;
		
		DataLine = Object.LineItems.Add();
		
		DataLine.Document = Result.Ref;
		DataLine.Currency = Result.Ref.Currency;
		Dataline.BalanceFCY = Result.AmountBalance;
		Dataline.Balance = Result.AmountRCBalance;
		DataLine.Payment = 0;
		
	EndDo;	
	
EndProcedure

&AtClient
// CompanyOnChange UI event handler. The procedure repopulates line items upon a company change.
//
Procedure CompanyOnChange(Item)
	
	Object.CompanyCode = CommonUse.GetAttributeValue(Object.Company, "Code");
	FillDocumentList(Object.Company);
	LineItemsPaymentOnChange(Items.LineItemsPayment);
	
EndProcedure


&AtClient
// The procedure notifies all related dynamic lists that the changes in data have occured.
//
Procedure AfterWrite(WriteParameters)
	
	For Each DocumentLine in Object.LineItems Do
		
		RepresentDataChange(DocumentLine.Document, DataChangeType.Update);
		
	EndDo;
		
EndProcedure

&AtClient
// The procedure deletes all line items which are
// not paid by this invoice payment
//
Procedure BeforeWrite(Cancel, WriteParameters)
	
	If Object.LineItems.Count() = 0 Then
		Message("Invoice Payment can not have empty lines. The system automatically shows unpaid documents to the selected company in the line items");
		Cancel = True;
		Return;
	EndIf;
	
	NumberOfLines = Object.LineItems.Count() - 1;
	
	While NumberOfLines >=0 Do
		
		If Object.LineItems[NumberOfLines].Payment = 0 Then
			Object.LineItems.Delete(NumberOfLines);
		Else
		EndIf;
		
		NumberOfLines = NumberOfLines - 1;
		
	EndDo;
	
	Object.Currency = Object.LineItems[0].Currency;
	NumberOfRows = Object.LineItems.Count() - 1;
		
	While NumberOfRows >= 0 Do
		
		If NOT Object.LineItems[NumberOfRows].Currency = Object.Currency Then
			Message("All documents in the line items need to have the same currency");
			Cancel = True;
			Return;
	    EndIf;
		
		NumberOfRows = NumberOfRows - 1;
		
	EndDo
	
EndProcedure

&AtClient
// LineItemsPaymentOnChange UI event handler.
// The procedure calculates a document total in the foreign currency (DocumentTotal) and in the
// reporting currency (DocumentTotalRC).
//
Procedure LineItemsPaymentOnChange(Item)
	
	DefaultCurrency = GeneralFunctionsReusable.DefaultCurrency();
	
	DocumentTotalRC = 0;
	For Each Row In Object.LineItems Do
		If Row.Currency = DefaultCurrency Then
			DocumentTotalRC = DocumentTotalRC + Row.Payment;
		Else
			ExchangeRate = GeneralFunctions.GetExchangeRate(Object.Date, Row.Currency);
			DocumentTotalRC = DocumentTotalRC + Round(Row.Payment * ExchangeRate, 2);
		EndIf;
	EndDo;
	Object.DocumentTotal = Object.LineItems.Total("Payment");
	Object.DocumentTotalRC = DocumentTotalRC;
	
EndProcedure

&AtClient
// Retrieves the account's description
//
Procedure BankAccountOnChange(Item)
	
	Items.BankAccountLabel.Title =
		CommonUse.GetAttributeValue(Object.BankAccount, "Description");

EndProcedure

&AtServer
Procedure OnCreateAtServer(Cancel, StandardProcessing)
	
	//Title = "Payment " + Object.Number + " " + Format(Object.Date, "DLF=D");
	
	Items.Company.Title = GeneralFunctionsReusable.GetVendorName();
	
	If Object.BankAccount.IsEmpty() Then
		Object.BankAccount = Constants.BankAccount.Get();
	Else
	EndIf; 

	Items.BankAccountLabel.Title =
		CommonUse.GetAttributeValue(Object.BankAccount, "Description");
	
	If GeneralFunctionsReusable.FunctionalOptionValue("MultiCurrency") Then	
		Items.LineItemsPayment.Title = "Payment FCY";	
	EndIf;
	
EndProcedure

&AtServer
Procedure BeforeWriteAtServer(Cancel, CurrentObject, WriteParameters)
	
	If Object.PaymentMethod = Catalogs.PaymentMethods.Check Then
		
		If CurrentObject.Ref.IsEmpty() Then
		
			LastNumber = GeneralFunctions.LastCheckNumber(Object.BankAccount);
			
			LastNumberString = "";
			If LastNumber < 10000 Then
				LastNumberString = Left(String(LastNumber+1),1) + Right(String(LastNumber+1),3)
			Else
				LastNumberString = Left(String(LastNumber+1),2) + Right(String(LastNumber+1),3)
			EndIf;
			
			CurrentObject.Number = LastNumberString;
			CurrentObject.PhysicalCheckNum = LastNumber + 1;
			
		Else
			CurrentObject.PhysicalCheckNum = Number(CurrentObject.Number);		
		EndIf;
	Endif;
	

EndProcedure

&AtClient
Procedure PaymentMethodOnChange(Item)
	If Object.PaymentMethod = CheckPaymentMethod() Then
		Object.Number = "auto";
		Items.Number.ReadOnly = True;
	Else
		Object.Number = "";
		Items.Number.ReadOnly = False;
	EndIf;
EndProcedure

&AtServer
Function CheckPaymentMethod()
	
	Return Catalogs.PaymentMethods.Check;
	
EndFunction


&AtServer
Procedure FillCheckProcessingAtServer(Cancel, CheckedAttributes)
	
	If NOT Object.Ref.IsEmpty() And Object.PaymentMethod = CheckPaymentMethod() Then
	
	Try
		If Number(Object.Number) <= 0 OR Number(Object.Number) >= 100000 Then
			Cancel = True;
			Message = New UserMessage();
			Message.Text=NStr("en='Enter a check number from 0 to 9999 (99999)'");
			Message.Field = "Object.Number";
			Message.Message();
		EndIf;
	Except
			Cancel = True;
			Message = New UserMessage();
			Message.Text=NStr("en='Enter a check number from 0 to 9999 (99999)'");
			Message.Field = "Object.Number";
			Message.Message();
	EndTry;
		
	Endif;

EndProcedure

