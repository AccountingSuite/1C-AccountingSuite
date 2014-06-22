﻿
&AtServer
Procedure OnCreateAtServer(Cancel, StandardProcessing)
	
	If Parameters.Property("Product") Then
		
		If Parameters.Product.Type = Enums.InventoryTypes.NonInventory Then
			Items.QtyOnHand.Visible               = False;
			Items.VTQtyOnHand.Visible			  = False;
			Items.QtyAvailableToPromise.Visible   = False;
			Items.VTQtyAvailableToPromise.Visible = False;
		EndIf;
		
		ThisForm.Title = Parameters.Product.Description; 
		
		QtyOnPO = Parameters.QtyOnPO;
		QtyOnSO = Parameters.QtyOnSO;
		QtyOnHand = Parameters.QtyOnHand;
		QtyAvailableToPromise = Parameters.QtyAvailableToPromise;
		
		Query = New Query;
		
		Query.SetParameter("Product", Parameters.Product);
		
		Query.Text = "SELECT
		             |	OrdersDispatchedBalance.Product AS Product,
		             |	OrdersDispatchedBalance.Location AS Location,
		             |	CASE
		             |		WHEN OrdersDispatchedBalance.Product.Type = VALUE(Enum.InventoryTypes.Inventory)
		             |			THEN CASE
		             |					WHEN OrdersDispatchedBalance.QuantityBalance - OrdersDispatchedBalance.ReceivedBalance > 0
		             |						THEN OrdersDispatchedBalance.QuantityBalance - OrdersDispatchedBalance.ReceivedBalance
		             |					ELSE 0
		             |				END
		             |		WHEN OrdersDispatchedBalance.Product.Type = VALUE(Enum.InventoryTypes.NonInventory)
		             |			THEN CASE
		             |					WHEN OrdersDispatchedBalance.QuantityBalance - OrdersDispatchedBalance.InvoicedBalance > 0
		             |						THEN OrdersDispatchedBalance.QuantityBalance - OrdersDispatchedBalance.InvoicedBalance
		             |					ELSE 0
		             |				END
		             |		ELSE 0
		             |	END AS QtyOnPO,
		             |	0 AS QtyOnSO,
		             |	0 AS QtyOnHand
		             |INTO Table_OrdersDispatched_OrdersRegistered_InventoryJournal
		             |FROM
		             |	AccumulationRegister.OrdersDispatched.Balance(, Product = &Product) AS OrdersDispatchedBalance
		             |
		             |UNION ALL
		             |
		             |SELECT
		             |	OrdersRegisteredBalance.Product,
		             |	OrdersRegisteredBalance.Location,
		             |	0,
		             |	CASE
		             |		WHEN OrdersRegisteredBalance.Product.Type = VALUE(Enum.InventoryTypes.Inventory)
		             |			THEN CASE
		             |					WHEN OrdersRegisteredBalance.QuantityBalance - OrdersRegisteredBalance.ShippedBalance > 0
		             |						THEN OrdersRegisteredBalance.QuantityBalance - OrdersRegisteredBalance.ShippedBalance
		             |					ELSE 0
		             |				END
		             |		WHEN OrdersRegisteredBalance.Product.Type = VALUE(Enum.InventoryTypes.NonInventory)
		             |			THEN CASE
		             |					WHEN OrdersRegisteredBalance.QuantityBalance - OrdersRegisteredBalance.InvoicedBalance > 0
		             |						THEN OrdersRegisteredBalance.QuantityBalance - OrdersRegisteredBalance.InvoicedBalance
		             |					ELSE 0
		             |				END
		             |		ELSE 0
		             |	END,
		             |	0
		             |FROM
		             |	AccumulationRegister.OrdersRegistered.Balance(, Product = &Product) AS OrdersRegisteredBalance
		             |
		             |UNION ALL
		             |
		             |SELECT
		             |	InventoryJournalBalance.Product,
		             |	InventoryJournalBalance.Location,
		             |	0,
		             |	0,
		             |	CASE
		             |		WHEN InventoryJournalBalance.Product.Type = VALUE(Enum.InventoryTypes.Inventory)
		             |			THEN InventoryJournalBalance.QuantityBalance
		             |		WHEN InventoryJournalBalance.Product.Type = VALUE(Enum.InventoryTypes.NonInventory)
		             |			THEN 0
		             |		ELSE 0
		             |	END
		             |FROM
		             |	AccumulationRegister.InventoryJournal.Balance(, Product = &Product) AS InventoryJournalBalance
		             |;
		             |
		             |////////////////////////////////////////////////////////////////////////////////
		             |SELECT
		             |	TableBalances.Location,
		             |	SUM(ISNULL(TableBalances.QtyOnPO, 0)) AS QtyOnPO,
		             |	SUM(ISNULL(TableBalances.QtyOnSO, 0)) AS QtyOnSO,
		             |	SUM(ISNULL(TableBalances.QtyOnHand, 0)) AS QtyOnHand,
		             |	CASE
		             |		WHEN TableBalances.Product.Type = VALUE(Enum.InventoryTypes.Inventory)
		             |			THEN SUM(ISNULL(TableBalances.QtyOnHand, 0)) + SUM(ISNULL(TableBalances.QtyOnPO, 0)) - SUM(ISNULL(TableBalances.QtyOnSO, 0))
		             |		WHEN TableBalances.Product.Type = VALUE(Enum.InventoryTypes.NonInventory)
		             |			THEN 0
		             |		ELSE 0
		             |	END AS QtyAvailableToPromise
		             |INTO TotalTable
		             |FROM
		             |	Table_OrdersDispatched_OrdersRegistered_InventoryJournal AS TableBalances
		             |
		             |GROUP BY
		             |	TableBalances.Location,
		             |	TableBalances.Product.Type
		             |;
		             |
		             |////////////////////////////////////////////////////////////////////////////////
		             |SELECT
		             |	TotalTable.Location,
		             |	TotalTable.QtyOnPO,
		             |	TotalTable.QtyOnSO,
		             |	TotalTable.QtyOnHand,
		             |	TotalTable.QtyAvailableToPromise
		             |FROM
		             |	TotalTable AS TotalTable
		             |WHERE
		             |	(TotalTable.QtyOnPO <> 0
		             |			OR TotalTable.QtyOnSO <> 0
		             |			OR TotalTable.QtyOnHand <> 0
		             |			OR TotalTable.QtyAvailableToPromise <> 0)";
		
		ValueToFormData(Query.Execute().Unload(), VT);
		
	EndIf;
	
EndProcedure
