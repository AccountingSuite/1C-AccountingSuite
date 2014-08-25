﻿
&AtServer
Procedure OnCreateAtServer(Cancel, StandardProcessing)
	
	If Parameters.Property("Company") And Parameters.Company.Customer Then
		Object.Company = Parameters.Company;
	EndIf;

	
	If Object.User = Catalogs.UserList.EmptyRef() Then
		Object.User =  Catalogs.UserList.FindByDescription(GeneralFunctions.GetUserName());

	Endif;
	
	If Object.SalesOrder <> Documents.SalesOrder.EmptyRef() Then
		Items.LinkSalesOrder.Title = "Unlink sales order";
	EndIf;
	
	If Object.Ref.IsEmpty() Then
		Object.DateFrom = CurrentDate();
		Object.Billable = True;
	EndIf;
	
EndProcedure

&AtClient
Procedure TaskOnChange(Item)
	ObjChanged();
	TaskOnChangeAtServer();
EndProcedure

&AtServer
Procedure TaskOnChangeAtServer()
	
	Object.Price = GeneralFunctions.RetailPrice(CurrentDate(),Object.Task,Object.Company);
EndProcedure

&AtClient
Procedure DateToOnChange(Item)
	ObjChanged();
		
EndProcedure


&AtServer
Procedure BeforeWriteAtServer(Cancel, CurrentObject, WriteParameters)
	
	//Period closing
	If PeriodClosingServerCall.DocumentPeriodIsClosed(CurrentObject.Ref, CurrentObject.Date) Then
		PermitWrite = PeriodClosingServerCall.DocumentWritePermitted(WriteParameters);
		CurrentObject.AdditionalProperties.Insert("PermitWrite", PermitWrite);	
	EndIf;	
	
	If Changed = True Then	
		
		If CurrentObject.Billable = False Then
			CurrentObject.InvoiceStatus = Enums.TimeTrackStatus.Unbillable;
		Else
			CurrentObject.InvoiceStatus = Enums.TimeTrackStatus.Unbilled;
		Endif;
		
	Endif;

	
EndProcedure

&AtClient
Procedure ObjChanged()
	//If Changed = False And Object.SalesInvoice.IsEmpty() = False Then
	//	Message("You are changing data in an entry that has a linked invoice. Note that changes here are not carried over to the linked invoice and may cause inconsistency.");
	//Endif;
	
	Changed = True;
EndProcedure


&AtClient
Procedure OnOpen(Cancel)
	
	OnOpenAtServer();
	
	AttachIdleHandler("AfterOpen", 0.1, True);
	
EndProcedure

&AtClient
Procedure AfterOpen()
	
	ThisForm.Activate();
	
	If ThisForm.IsInputAvailable() Then
		///////////////////////////////////////////////
		DetachIdleHandler("AfterOpen");
		
		If  Object.Ref.IsEmpty() And ValueIsFilled(Object.Company) Then
			ObjChanged();	
		EndIf;	
		///////////////////////////////////////////////
	Else 
		AttachIdleHandler("AfterOpen", 0.1, True);
	EndIf;		
	
EndProcedure

&AtServer
Procedure OnOpenAtServer()
		
	If Object.SalesInvoice.IsEmpty() OR Object.Billable = False Then
		Items.SalesInvoice.Visible = False;
	Else
		Items.SalesInvoice.Visible = True;
		Items.UnlinkSalesInvoice.Visible = True;
	EndIf;
	
	If Object.SalesOrder.IsEmpty() = False Then
		Items.SalesOrder.Visible = True;
	EndIf;

	
EndProcedure

&AtClient
Procedure BeforeWrite(Cancel, WriteParameters)
	
	//Closing period
	If PeriodClosingServerCall.DocumentPeriodIsClosed(Object.Ref, Object.Date) Then
		Cancel = Not PeriodClosingServerCall.DocumentWritePermitted(WriteParameters);
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

	
	//If Changed = True And Object.SalesInvoice.IsEmpty() = False Then
		//ShowMessageBox(,"New changes will not change " + Object.SalesInvoice + ". Generating a new invoice for this time entry will link the entry to a new invoice.",,"ChangedEntry"); 
	//EndIf;
	
EndProcedure


&AtClient
Procedure LinkSalesOrder(Command)
	
	If LinkSalesOrderAtServer() = False Then
	
		If (Not Object.Company.IsEmpty()) And (HasNonClosedOrders(Object.Company)) Then
			

			FormParameters = New Structure();
			FormParameters.Insert("ChoiceMode", True);
			FormParameters.Insert("MultipleChoice", True);
			

			FltrParameters = New Structure();
			FltrParameters.Insert("Company", Object.Company); 
			FltrParameters.Insert("OrderStatus", GetNonClosedOrderStatuses());
			FormParameters.Insert("Filter", FltrParameters);
			
			NotifyDescription = New NotifyDescription("OrderSelection", ThisForm);
			OpenForm("Document.SalesOrder.ChoiceForm", FormParameters,,,,,NotifyDescription)
			
		EndIf;	
	EndIf;

EndProcedure
	
&AtClient
Procedure OrderSelection(Result, Parameters) Export
	
	If Not Result = Undefined Then
		object.SalesOrder = Result[0];
		Items.SalesOrder.Visible = True;
		Items.LinkSalesOrder.Title = "Unlink sales order";
		Changed = True;
	EndIf;
	
EndProcedure




&AtServer
Function LinkSalesOrderAtServer()
	
	If Object.SalesOrder <> Documents.SalesOrder.EmptyRef() Then
		Object.SalesOrder = Documents.SalesOrder.EmptyRef();
		Items.LinkSalesOrder.Title = "Link sales order";
		Return True;
	EndIf;
	
	Return False
	
EndFunction

&AtServer
Function HasNonClosedOrders(Company)
	
	// Create new query
	Query = New Query;
	Query.SetParameter("Company", Company);
	
	QueryText = 
		"SELECT
		|	SalesOrder.Ref
		|FROM
		|	Document.SalesOrder AS SalesOrder
		|	LEFT JOIN InformationRegister.OrdersStatuses.SliceLast AS OrdersStatuses
		|		ON SalesOrder.Ref = OrdersStatuses.Order
		|WHERE
		|	SalesOrder.Company = &Company
		|AND
		|	CASE
		|		WHEN SalesOrder.DeletionMark THEN
		|			 VALUE(Enum.OrderStatuses.Deleted)
		|		WHEN NOT SalesOrder.Posted THEN
		|			 VALUE(Enum.OrderStatuses.Draft)
		|		WHEN OrdersStatuses.Status IS NULL THEN
		|			 VALUE(Enum.OrderStatuses.Open)
		|		WHEN OrdersStatuses.Status = VALUE(Enum.OrderStatuses.EmptyRef) THEN
		|			 VALUE(Enum.OrderStatuses.Open)
		|		ELSE
		|			 OrdersStatuses.Status
		|	END IN (VALUE(Enum.OrderStatuses.Open), VALUE(Enum.OrderStatuses.Backordered))";
	Query.Text  = QueryText;
	
	// Returns true if there are open or backordered orders
	Return Not Query.Execute().IsEmpty();
	
EndFunction

&AtServer
// Returns array of Order Statuses indicating non-closed orders
Function GetNonClosedOrderStatuses()
	
	// Define all non-closed statuses array
	OrderStatuses  = New Array;
	OrderStatuses.Add(Enums.OrderStatuses.Open);
	OrderStatuses.Add(Enums.OrderStatuses.Backordered);
	
	// Return filled array
	Return OrderStatuses;
	
EndFunction

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
Procedure UnlinkSalesInvoice(Command)
	UnlinkSalesInvoiceAtServer();
EndProcedure

&AtServer
Procedure UnlinkSalesInvoiceAtServer()

	Object.SalesInvoice = Documents.SalesInvoice.EmptyRef();
	Items.SalesInvoice.Visible = False;
	Items.UnlinkSalesInvoice.Visible = False;
	Object.InvoiceStatus = Enums.TimeTrackStatus.Unbilled;
	Modified = True;
	
EndProcedure




