﻿
#Region PUBLIC_INTERFACE

//Categorization mechanism

//Updates transaction categorization library
//Used in scheduled background job
Procedure UpdateTransactionCategorizationLibrary() Export
	//Select all accepted (falling in 2-monthes interval) but not yet processed transactions
	
	TransactionsRequest = New Query("SELECT
	                                |	AcceptedTransactions.BankAccount,
	                                |	AcceptedTransactions.ID,
	                                |	AcceptedTransactions.Description,
	                                |	AcceptedTransactions.Company,
	                                |	AcceptedTransactions.Category,
	                                |	AcceptedTransactions.CategoryID,
	                                |	AcceptedTransactions.TransactionDate
	                                |INTO NewlyAcceptedTransactions
	                                |FROM
	                                |	(SELECT
	                                |		BankTransactions.BankAccount AS BankAccount,
	                                |		BankTransactions.ID AS ID,
	                                |		BankTransactions.Description AS Description,
	                                |		BankTransactions.Company AS Company,
	                                |		BankTransactions.Category AS Category,
	                                |		BankTransactions.CategoryID AS CategoryID,
	                                |		BankTransactions.TransactionDate AS TransactionDate
	                                |	FROM
	                                |		InformationRegister.BankTransactions AS BankTransactions
	                                |	WHERE
	                                |		BankTransactions.TransactionDate >= &RelevancePeriod
	                                |		AND BankTransactions.Accepted = TRUE) AS AcceptedTransactions
	                                |		LEFT JOIN InformationRegister.BankTransactionCategorization AS BankTransactionCategorization
	                                |		ON AcceptedTransactions.ID = BankTransactionCategorization.TransactionID
	                                |			AND AcceptedTransactions.Company = BankTransactionCategorization.Customer
	                                |			AND AcceptedTransactions.Category = BankTransactionCategorization.Category
	                                |WHERE
	                                |	BankTransactionCategorization.TransactionID IS NULL 
	                                |;
	                                |
	                                |////////////////////////////////////////////////////////////////////////////////
	                                |SELECT
	                                |	NewlyAcceptedTransactions.BankAccount,
	                                |	NewlyAcceptedTransactions.ID,
	                                |	NewlyAcceptedTransactions.Description,
	                                |	NewlyAcceptedTransactions.Company,
	                                |	NewlyAcceptedTransactions.Category,
	                                |	ISNULL(BankTransactionCategories.Account, VALUE(Catalog.BankTransactionCategories.EmptyRef)) AS YodleeCategory,
	                                |	NewlyAcceptedTransactions.TransactionDate AS TransactionDate
	                                |FROM
	                                |	NewlyAcceptedTransactions AS NewlyAcceptedTransactions
	                                |		LEFT JOIN Catalog.BankTransactionCategories AS BankTransactionCategories
	                                |		ON NewlyAcceptedTransactions.CategoryID = BankTransactionCategories.Code
	                                |
	                                |ORDER BY
	                                |	TransactionDate");
									
	RelevancePeriod = AddMonth(CurrentDate(), -3);
	RelevancePeriod = BegOfDay(RelevancePeriod);
	TransactionsRequest.SetParameter("RelevancePeriod", RelevancePeriod);
	Res = TransactionsRequest.Execute();
	Tab = Res.Unload();
	For Each TabRow In Tab Do
		ProcessTransactionForCategorization(TabRow);
	EndDo;
	
	//Delete old and cancelled records
	TransactionsRequest = New Query("SELECT DISTINCT
	                                |	TransactionsToDelete.ID
	                                |FROM
	                                |	(SELECT
	                                |		UnacceptedTransactions.ID AS ID
	                                |	FROM
	                                |		(SELECT
	                                |			BankTransactions.ID AS ID
	                                |		FROM
	                                |			InformationRegister.BankTransactions AS BankTransactions
	                                |		WHERE
	                                |			BankTransactions.Accepted = FALSE) AS UnacceptedTransactions
	                                |			INNER JOIN InformationRegister.BankTransactionCategorization AS BankTransactionCategorization
	                                |			ON UnacceptedTransactions.ID = BankTransactionCategorization.TransactionID
	                                |	
	                                |	UNION ALL
	                                |	
	                                |	SELECT
	                                |		BankTransactionCategorization.TransactionID
	                                |	FROM
	                                |		InformationRegister.BankTransactionCategorization AS BankTransactionCategorization
	                                |			INNER JOIN InformationRegister.BankTransactions AS BankTransactions
	                                |			ON BankTransactionCategorization.TransactionID = BankTransactions.ID
	                                |				AND (BankTransactions.TransactionDate < &RelevancePeriod)) AS TransactionsToDelete");
	TransactionsRequest.SetParameter("RelevancePeriod", RelevancePeriod);
	Tab = TransactionsRequest.Execute().Unload();
	RecordSet = InformationRegisters.BankTransactionCategorization.CreateRecordSet();
	IDFilter = RecordSet.Filter.TransactionID;
	IDFilter.Use = True;
	IDFilter.ComparisonType = ComparisonType.Equal;
	For Each TabRow In Tab Do
		IDFilter.Value = TabRow.ID;
		RecordSet.Write(True);
	EndDo;

EndProcedure

//Function categorizes transactions
// 
//Parameters:
//Transactions - Array of structures - transactions to be processed
// Description - String - Transaction description
// ID - UUID - Transaction ID
//Result:
//Transactions - Array of structures - transactions processed with the results
// Description - String - Transaction description
// ID - UUID - Transaction ID
// Company - CatalogRef.Companies
// Category - ChartOfAccountsRef.ChartOfAccounts
//
Function CategorizeTransactions(Transactions) Export
	
	UpdateTransactionCategorizationLibrary();
	
	//Convert an array into a Value Table
	TranTab = New ValueTable;
	QS = New StringQualifiers(50);
	TypeDescriptionString = New TypeDescription("String",,QS);
	TypeID = New TypeDescription("Number");
	TypeBankAccount = New TypeDescription("CatalogRef.BankAccounts");
	TranTab.Columns.Add("BankAccount", TypeBankAccount);
	TranTab.Columns.Add("lexem", TypeDescriptionString); 
	TranTab.Columns.Add("TranID", TypeID);
	IDCounter = 0;
	While IDCounter < Transactions.Count() Do
		Transaction = Transactions[IDCounter];
		Transaction.Insert("TranID", IDCounter + 1);
		Description = Transaction.Description;
		lexemes = StringFunctionsClientServer.SplitStringIntoSubstringArray(Description, " ");
		lexemes.Add(Description);
		//delete 1- to 2- letter words
		i = 0;
		While i < lexemes.Count() Do
			If StrLen(lexemes[i]) < 3 Then
				lexemes.Delete(i);
			Else
				i = i + 1;
			EndIf;
		EndDo;
		For Each lexem In lexemes Do
			NewRow = TranTab.Add();
			NewRow.BankAccount = Transaction.BankAccount;
			NewRow.lexem = lexem;
			NewRow.TranID = Transaction.TranID;
		EndDo;
		IDCounter = IDCounter + 1;		
	EndDo;
	Request = New Query("SELECT
	                    |	NewTransactions.BankAccount AS BankAccount,
	                    |	NewTransactions.lexem AS lexem,
	                    |	NewTransactions.TranID AS TranID
	                    |INTO NewTransactions
	                    |FROM
	                    |	&NewTransactions AS NewTransactions
	                    |
	                    |INDEX BY
	                    |	BankAccount,
	                    |	lexem
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT
	                    |	NewTransactions.BankAccount,
	                    |	NewTransactions.TranID,
	                    |	NewTransactions.lexem,
	                    |	BankTransactionCategorization.Customer,
	                    |	BankTransactionCategorization.Category,
	                    |	BankTransactionCategorization.FullDescription
	                    |INTO FoundCoincidents
	                    |FROM
	                    |	NewTransactions AS NewTransactions
	                    |		INNER JOIN InformationRegister.BankTransactionCategorization AS BankTransactionCategorization
	                    |		ON NewTransactions.BankAccount = BankTransactionCategorization.BankAccount
	                    |			AND NewTransactions.lexem = BankTransactionCategorization.Lexem
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT DISTINCT
	                    |	FoundCoincidents.TranID,
	                    |	FoundCoincidents.Customer,
	                    |	FoundCoincidents.Category,
	                    |	1000000 AS Priority
	                    |INTO FullCoincidents
	                    |FROM
	                    |	FoundCoincidents AS FoundCoincidents
	                    |WHERE
	                    |	FoundCoincidents.FullDescription = TRUE
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT DISTINCT
	                    |	FoundCoincidents.BankAccount,
	                    |	FoundCoincidents.lexem
	                    |INTO UsedLexems
	                    |FROM
	                    |	FoundCoincidents AS FoundCoincidents
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT DISTINCT
	                    |	UsedLexems.lexem,
	                    |	UsedLexems.BankAccount,
	                    |	BankTransactionCategorization.Customer,
	                    |	BankTransactionCategorization.Category
	                    |INTO CustomersAndCategoriesForLexem
	                    |FROM
	                    |	UsedLexems AS UsedLexems
	                    |		INNER JOIN InformationRegister.BankTransactionCategorization AS BankTransactionCategorization
	                    |		ON UsedLexems.lexem = BankTransactionCategorization.Lexem
	                    |			AND UsedLexems.BankAccount = BankTransactionCategorization.BankAccount
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT
	                    |	CustomersAndCategoriesForLexem.BankAccount,
	                    |	CustomersAndCategoriesForLexem.lexem,
	                    |	COUNT(DISTINCT CustomersAndCategoriesForLexem.Customer) AS Priority
	                    |INTO LexemPriorityForCustomer
	                    |FROM
	                    |	CustomersAndCategoriesForLexem AS CustomersAndCategoriesForLexem
	                    |
	                    |GROUP BY
	                    |	CustomersAndCategoriesForLexem.lexem,
	                    |	CustomersAndCategoriesForLexem.BankAccount
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT
	                    |	CustomersAndCategoriesForLexem.BankAccount,
	                    |	CustomersAndCategoriesForLexem.lexem,
	                    |	COUNT(DISTINCT CustomersAndCategoriesForLexem.Category) AS Priority
	                    |INTO LexemPriorityForCategory
	                    |FROM
	                    |	CustomersAndCategoriesForLexem AS CustomersAndCategoriesForLexem
	                    |
	                    |GROUP BY
	                    |	CustomersAndCategoriesForLexem.BankAccount,
	                    |	CustomersAndCategoriesForLexem.lexem
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT DISTINCT
	                    |	FoundCoincidents.TranID,
	                    |	FoundCoincidents.lexem,
	                    |	FoundCoincidents.Customer,
	                    |	10000 / LexemPriorityForCustomer.Priority / LexemPriorityForCustomer.Priority AS Priority
	                    |INTO LexemsCustomers
	                    |FROM
	                    |	FoundCoincidents AS FoundCoincidents
	                    |		INNER JOIN LexemPriorityForCustomer AS LexemPriorityForCustomer
	                    |		ON FoundCoincidents.BankAccount = LexemPriorityForCustomer.BankAccount
	                    |			AND FoundCoincidents.lexem = LexemPriorityForCustomer.lexem
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT DISTINCT
	                    |	FoundCoincidents.TranID,
	                    |	FoundCoincidents.lexem,
	                    |	FoundCoincidents.Category,
	                    |	10000 / LexemPriorityForCategory.Priority / LexemPriorityForCategory.Priority AS Priority
	                    |INTO LexemsCategories
	                    |FROM
	                    |	FoundCoincidents AS FoundCoincidents
	                    |		INNER JOIN LexemPriorityForCategory AS LexemPriorityForCategory
	                    |		ON FoundCoincidents.BankAccount = LexemPriorityForCategory.BankAccount
	                    |			AND FoundCoincidents.lexem = LexemPriorityForCategory.lexem
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT
	                    |	LexemsCustomers.TranID,
	                    |	LexemsCustomers.Customer,
	                    |	SUM(LexemsCustomers.Priority) AS Priority
	                    |INTO CustomerPriorityByNumberOfLexems
	                    |FROM
	                    |	LexemsCustomers AS LexemsCustomers
	                    |
	                    |GROUP BY
	                    |	LexemsCustomers.TranID,
	                    |	LexemsCustomers.Customer
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT
	                    |	LexemsCategories.TranID,
	                    |	LexemsCategories.Category,
	                    |	SUM(LexemsCategories.Priority) AS Priority
	                    |INTO CategoryPriorityByNumberOfLexems
	                    |FROM
	                    |	LexemsCategories AS LexemsCategories
	                    |
	                    |GROUP BY
	                    |	LexemsCategories.TranID,
	                    |	LexemsCategories.Category
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT
	                    |	FoundCoincidents.TranID,
	                    |	FoundCoincidents.Customer,
	                    |	SUM(50 / LexemPriorityForCustomer.Priority) AS Priority
	                    |INTO CustomerPriorityByNumberofCoincidents
	                    |FROM
	                    |	FoundCoincidents AS FoundCoincidents
	                    |		INNER JOIN LexemPriorityForCustomer AS LexemPriorityForCustomer
	                    |		ON FoundCoincidents.BankAccount = LexemPriorityForCustomer.BankAccount
	                    |			AND FoundCoincidents.lexem = LexemPriorityForCustomer.lexem
	                    |
	                    |GROUP BY
	                    |	FoundCoincidents.TranID,
	                    |	FoundCoincidents.Customer
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT
	                    |	FoundCoincidents.TranID,
	                    |	FoundCoincidents.Category,
	                    |	SUM(50 / LexemPriorityForCategory.Priority) AS Priority
	                    |INTO CategoryPriorityByNumberOfCoincidents
	                    |FROM
	                    |	FoundCoincidents AS FoundCoincidents
	                    |		INNER JOIN LexemPriorityForCategory AS LexemPriorityForCategory
	                    |		ON FoundCoincidents.BankAccount = LexemPriorityForCategory.BankAccount
	                    |			AND FoundCoincidents.lexem = LexemPriorityForCategory.lexem
	                    |
	                    |GROUP BY
	                    |	FoundCoincidents.TranID,
	                    |	FoundCoincidents.Category
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT
	                    |	NestedSelect.TranID,
	                    |	NestedSelect.Customer,
	                    |	SUM(NestedSelect.Priority) AS Priority
	                    |INTO Customers_Semifinal
	                    |FROM
	                    |	(SELECT
	                    |		FullCoincidents.TranID AS TranID,
	                    |		FullCoincidents.Customer AS Customer,
	                    |		FullCoincidents.Priority AS Priority
	                    |	FROM
	                    |		FullCoincidents AS FullCoincidents
	                    |	
	                    |	UNION ALL
	                    |	
	                    |	SELECT
	                    |		CustomerPriorityByNumberOfLexems.TranID,
	                    |		CustomerPriorityByNumberOfLexems.Customer,
	                    |		CustomerPriorityByNumberOfLexems.Priority
	                    |	FROM
	                    |		CustomerPriorityByNumberOfLexems AS CustomerPriorityByNumberOfLexems
	                    |	
	                    |	UNION ALL
	                    |	
	                    |	SELECT
	                    |		CustomerPriorityByNumberofCoincidents.TranID,
	                    |		CustomerPriorityByNumberofCoincidents.Customer,
	                    |		CustomerPriorityByNumberofCoincidents.Priority
	                    |	FROM
	                    |		CustomerPriorityByNumberofCoincidents AS CustomerPriorityByNumberofCoincidents) AS NestedSelect
	                    |
	                    |GROUP BY
	                    |	NestedSelect.TranID,
	                    |	NestedSelect.Customer
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT
	                    |	NestedSelect.TranID,
	                    |	NestedSelect.Category,
	                    |	SUM(NestedSelect.Priority) AS Priority
	                    |INTO Categories_Semifinal
	                    |FROM
	                    |	(SELECT
	                    |		FullCoincidents.TranID AS TranID,
	                    |		FullCoincidents.Category AS Category,
	                    |		FullCoincidents.Priority AS Priority
	                    |	FROM
	                    |		FullCoincidents AS FullCoincidents
	                    |	
	                    |	UNION ALL
	                    |	
	                    |	SELECT
	                    |		CategoryPriorityByNumberOfLexems.TranID,
	                    |		CategoryPriorityByNumberOfLexems.Category,
	                    |		CategoryPriorityByNumberOfLexems.Priority
	                    |	FROM
	                    |		CategoryPriorityByNumberOfLexems AS CategoryPriorityByNumberOfLexems
	                    |	
	                    |	UNION ALL
	                    |	
	                    |	SELECT
	                    |		CategoryPriorityByNumberOfCoincidents.TranID,
	                    |		CategoryPriorityByNumberOfCoincidents.Category,
	                    |		CategoryPriorityByNumberOfCoincidents.Priority
	                    |	FROM
	                    |		CategoryPriorityByNumberOfCoincidents AS CategoryPriorityByNumberOfCoincidents) AS NestedSelect
	                    |
	                    |GROUP BY
	                    |	NestedSelect.TranID,
	                    |	NestedSelect.Category
	                    |;
	                    |
	                    |////////////////////////////////////////////////////////////////////////////////
	                    |SELECT
	                    |	ISNULL(CustomerResult.TranID, CategoryResult.TranID) AS TranID,
	                    |	ISNULL(CustomerResult.Priority, 0) AS CustomerPriority,
	                    |	ISNULL(CustomerResult.Customer, VALUE(Catalog.Companies.EmptyRef)) AS Customer,
	                    |	ISNULL(CategoryResult.Priority, 0) AS CategoryPriority,
	                    |	ISNULL(CategoryResult.Category, VALUE(Catalog.BankTransactionCategories.EmptyRef)) AS Category
	                    |FROM
	                    |	(SELECT
	                    |		CustomerMaxPriority.TranID AS TranID,
	                    |		CustomerMaxPriority.Priority AS Priority,
	                    |		Customers_Semifinal.Customer AS Customer
	                    |	FROM
	                    |		(SELECT
	                    |			Customers_Semifinal.TranID AS TranID,
	                    |			MAX(Customers_Semifinal.Priority) AS Priority
	                    |		FROM
	                    |			Customers_Semifinal AS Customers_Semifinal
	                    |		
	                    |		GROUP BY
	                    |			Customers_Semifinal.TranID) AS CustomerMaxPriority
	                    |			INNER JOIN Customers_Semifinal AS Customers_Semifinal
	                    |			ON CustomerMaxPriority.TranID = Customers_Semifinal.TranID
	                    |				AND CustomerMaxPriority.Priority = Customers_Semifinal.Priority) AS CustomerResult
	                    |		FULL JOIN (SELECT
	                    |			CategoryMaxPriority.TranID AS TranID,
	                    |			CategoryMaxPriority.Priority AS Priority,
	                    |			Categories_Semifinal.Category AS Category
	                    |		FROM
	                    |			(SELECT
	                    |				Categories_Semifinal.TranID AS TranID,
	                    |				MAX(Categories_Semifinal.Priority) AS Priority
	                    |			FROM
	                    |				Categories_Semifinal AS Categories_Semifinal
	                    |			
	                    |			GROUP BY
	                    |				Categories_Semifinal.TranID) AS CategoryMaxPriority
	                    |				INNER JOIN Categories_Semifinal AS Categories_Semifinal
	                    |				ON CategoryMaxPriority.TranID = Categories_Semifinal.TranID
	                    |					AND CategoryMaxPriority.Priority = Categories_Semifinal.Priority) AS CategoryResult
	                    |		ON CustomerResult.TranID = CategoryResult.TranID
	                    |
	                    |ORDER BY
	                    |	TranID,
	                    |	CustomerPriority DESC,
	                    |	CategoryPriority DESC");
	Request.SetParameter("NewTransactions", TranTab);
	CategorizedTrans = Request.Execute().Unload();
	
	TransIDs = CategorizedTrans.Copy();
	ResultTable = CategorizedTrans.CopyColumns();
	TransIDs.GroupBy("TranID");
	For Each TranID IN TransIDs Do
		//Process the current transaction
		//Define if there are several options for customer or category
		//Ignore results with several options
		CompanyForFilling = Catalogs.Companies.EmptyRef();
		CategoryForFilling = ChartsOfAccounts.ChartOfAccounts.EmptyRef();
		//If Priorities < 10000, then ignore the result
		PriorityForCompany = 0;
		PriorityForCategory = 0;
		
		FoundRows = CategorizedTrans.FindRows(New Structure("TranID", TranID.TranID));
		If FoundRows.Count() > 1 Then
			TableForIDCustomer = CategorizedTrans.Copy(FoundRows);
			TableForIDCategory = TableForIDCustomer.Copy();
			TableForIDCustomer.GroupBy("Customer, CustomerPriority");
			If TableForIDCustomer.Count() = 1 Then
				CompanyForFilling = TableForIDCustomer[0]["Customer"];
				PriorityForCompany = TableForIDCustomer[0]["CustomerPriority"];
			EndIf;
			TableForIDCategory.GroupBy("Category, CategoryPriority");
			If TableForIDCategory.Count() = 1 Then
				CategoryForFilling = TableForIDCategory[0]["Category"];
				PriorityForCategory = TableForIDCategory[0]["CategoryPriority"];
			EndIf;
		Else
			CompanyForFilling = FoundRows[0].Customer;
			PriorityForCompany = FoundRows[0].CustomerPriority;
			CategoryForFilling = FoundRows[0].Category;
			PriorityForCategory = FoundRows[0].CategoryPriority;
		EndIf;
		
		If (PriorityForCompany < 10100) And (PriorityForCategory < 10100) Then
			Continue;
		EndIf;
				
		NewResultRow = ResultTable.Add();
		FillPropertyValues(NewResultRow, FoundRows[0]);
		NewResultRow.Customer = ?(PriorityForCompany >= 10100, CompanyForFilling, Catalogs.Companies.EmptyRef());
		NewResultRow.Category = ?(PriorityForCategory >= 10100, CategoryForFilling, ChartsOfAccounts.ChartOfAccounts.EmptyRef());
	EndDo;		

	ReturnArray = New Array();
	For Each CategorizedTran In ResultTable Do
		ReturnArray.Add(New Structure("BankAccount, Description, ID, RowID, CustomerPriority, Customer, CategoryPriority, Category", Transactions[CategorizedTran.TranID-1].BankAccount,
		Transactions[CategorizedTran.TranID-1].Description, Transactions[CategorizedTran.TranID-1].ID, Transactions[CategorizedTran.TranID-1].RowID, CategorizedTran.CustomerPriority, CategorizedTran.Customer,
		CategorizedTran.CategoryPriority, CategorizedTran.Category));
	EndDo;
	return ReturnArray;
EndFunction

Procedure CategorizeTransactionsAtServer(BankAccount, TempStorageAddress = Undefined) Export
	Try
		SetPrivilegedMode(True);
		BeginTransaction(DataLockControlMode.Managed);
		//Select all required transactions
		Request = New Query("SELECT
		                    |	BankTransactions.TransactionDate,
		                    |	BankTransactions.BankAccount,
		                    |	BankTransactions.Company,
		                    |	BankTransactions.ID,
		                    |	BankTransactions.Description,
		                    |	BankTransactions.Amount,
		                    |	BankTransactions.Category,
		                    |	BankTransactions.Document,
		                    |	BankTransactions.Accepted,
		                    |	BankTransactions.Hidden,
		                    |	BankTransactions.OriginalID,
		                    |	BankTransactions.YodleeTransactionID,
		                    |	BankTransactions.PostDate,
		                    |	BankTransactions.Price,
		                    |	BankTransactions.Quantity,
		                    |	BankTransactions.RunningBalance,
		                    |	BankTransactions.CurrencyCode,
		                    |	BankTransactions.CategoryID,
		                    |	BankTransactions.Type,
		                    |	BankTransactions.CategorizedCompanyNotAccepted,
		                    |	BankTransactions.CategorizedCategoryNotAccepted,
		                    |	ISNULL(BankTransactionCategories.Account, VALUE(ChartOfAccounts.ChartOfAccounts.EmptyRef)) AS CategoryAccount
		                    |FROM
		                    |	InformationRegister.BankTransactions AS BankTransactions
		                    |		LEFT JOIN Catalog.BankTransactionCategories AS BankTransactionCategories
		                    |		ON BankTransactions.CategoryID = BankTransactionCategories.Code
		                    |WHERE
		                    |	BankTransactions.BankAccount = &BankAccount
		                    |	AND BankTransactions.Accepted = FALSE
		                    |	AND BankTransactions.Hidden = FALSE");
		Request.SetParameter("BankAccount", BankAccount);
		UnacceptedTransactions = Request.Execute().Unload();
		//Lock records being processed
		DataLock = New DataLock();
		BT_DataLock = DataLock.Add("InformationRegister.BankTransactions");
		BT_DataLock.Mode = DataLockMode.Exclusive;
		BT_DataLock.DataSource = UnacceptedTransactions;
		BT_DataLock.UseFromDataSource("ID", "ID");
		DataLock.Lock();
		
		Transactions = UnacceptedTransactions.Copy(, "BankAccount, ID, Description");
		Transactions.Columns.Add("RowID", New TypeDescription("Number"));
		i = 0;
		ArrayOfTransactions = New Array();
		While i < Transactions.Count() Do
			Transactions[i].RowID = i;
			ArrayOfTransactions.Add(New Structure("BankAccount, ID, Description, RowID", Transactions[i].BankAccount, Transactions[i].ID, Transactions[i].Description, Transactions[i].RowID));
			i = i + 1;
		EndDo;
		ReturnArray = CategorizeTransactions(ArrayOfTransactions);
		AffectedRows = New Array();
		
		ProcessedArray = New Array();
		For Each CategorizedTran IN ReturnArray Do
			CompanyFilled = False;
			CategoryFilled = False;
			ProcessedArray.Add(CategorizedTran.RowID);
			BTUnaccepted = UnacceptedTransactions[CategorizedTran.RowID];
			//Apply categorized company if it is not filled
			If (Not ValueIsFilled(BTUnaccepted.Company)) Or (BTUnaccepted.CategorizedCompanyNotAccepted) Then 
				BTUnaccepted.Company = CategorizedTran.Customer;
				BTUnaccepted.CategorizedCompanyNotAccepted = True;
				CompanyFilled = True;
			EndIf;
			If (Not ValueIsFilled(BTUnaccepted.Category)) Or (BTUnaccepted.CategorizedCategoryNotAccepted) Then 
				If (BTUnaccepted.CategoryAccount <> CategorizedTran.Category) Then
					BTUnaccepted.Category = CategorizedTran.Category;
					BTUnaccepted.CategorizedCategoryNotAccepted = True;
					CategoryFilled = True;
				EndIf;
			EndIf;
			If CompanyFilled OR CategoryFilled Then
				RecordTransactionToTheDatabase(BTUnaccepted);
				NewAffectedRow = New Structure("ID, Company, CategorizedCompanyNotAccepted, Category, CategorizedCategoryNotAccepted");
				FillPropertyValues(NewAffectedRow, BTUnaccepted);
				AffectedRows.Add(NewAffectedRow);
			EndIf;
		EndDo;
		//Clear previously categorized transactions, which are absent this time
		i = 0;
		EmptyCompany = Catalogs.Companies.EmptyRef();
		EmptyCategory = ChartsOfAccounts.ChartOfAccounts.EmptyRef();
		While i < UnacceptedTransactions.Count() Do
			If ProcessedArray.Find(i) <> Undefined Then
				i = i + 1;
				Continue;
			EndIf;
			CompanyWasCleared = False;
			CategoryWasCleared = False;
			BTUnaccepted = UnacceptedTransactions[i];
			If (ValueIsFilled(BTUnaccepted.Company)) And (BTUnaccepted.CategorizedCompanyNotAccepted) Then
				BTUnaccepted.Company = EmptyCompany;
				BTUnaccepted.CategorizedCompanyNotAccepted = False;
				CompanyWasCleared =True;
			EndIf;
			If (ValueIsFilled(BTUnaccepted.Category)) And (BTUnaccepted.CategorizedCategoryNotAccepted) Then
				BTUnaccepted.Category = EmptyCategory;
				BTUnaccepted.CategorizedCategoryNotAccepted = False;
				CategoryWasCleared = True;
			EndIf;
			i = i + 1;
			If CompanyWasCleared OR CategoryWasCleared Then
				RecordTransactionToTheDatabase(BTUnaccepted);
				NewAffectedRow = New Structure("ID, Company, CategorizedCompanyNotAccepted, Category, CategorizedCategoryNotAccepted");
				FillPropertyValues(NewAffectedRow, BTUnaccepted);
				AffectedRows.Add(NewAffectedRow);
			EndIf;
		EndDo;
		CommitTransaction();
		If TempStorageAddress <> Undefined Then
			PutToTempStorage(New Structure("CurrentStatus, ErrorDescription, AffectedRows", True, "", AffectedRows), TempStorageAddress);
		EndIf;
	Except
		ErrorDescription = ErrorDescription();
		If TempStorageAddress <> Undefined Then
			PutToTempStorage(New Structure("CurrentStatus, ErrorDescription", False, ErrorDescription), TempStorageAddress);
		EndIf;
		WriteLogEvent("DownloadedTransactions.TransactionCategorization", EventLogLevel.Error,,, ErrorDescription());	
		RollbackTransaction();
	EndTry;			
	
EndProcedure

#EndRegion

#Region PRIVATE_IMPLEMENTATION

//Processes accepted transaction
//Fills categorization library
//
//Parameters:
// TabRow - row of value table
// Columns:
// ID - the UUID of the transaction
// Description - String - the description of the transaction
// Company - CatalogRef.Companies - assigned company
// Category - ChartOfAccountsRef.ChartOfAccounts - assigned category
// YodleeCategory - ChartOfAccountsRef.ChartOfAccounts - assigned category by Yodlee
// TransactionDate - Date - the date of the transaction

Procedure ProcessTransactionForCategorization(TabRow)
	Description = TabRow.Description;
	lexemes = StringFunctionsClientServer.SplitStringIntoSubstringArray(Description, " ");
	//delete 1- to 2- letter words
	i = 0;
	While i < lexemes.Count() Do
		If StrLen(lexemes[i]) < 3 Then
			lexemes.Delete(i);
		Else
			i = i + 1;
		EndIf;
	EndDo;
	RecordSet = InformationRegisters.BankTransactionCategorization.CreateRecordSet();
	IDFilter = RecordSet.Filter.TransactionID;
	IDFilter.Use = True;
	IDFilter.ComparisonType = ComparisonType.Equal;
	IDFilter.Value 			= TabRow.ID;
	
	For Each lexem In lexemes Do
		NewRecord = RecordSet.Add();
		NewRecord.BankAccount = TabRow.BankAccount;
		NewRecord.Lexem = lexem;
		NewRecord.TransactionID = TabRow.ID;
		NewRecord.Customer = TabRow.Company;
		NewRecord.Category = ?(TabRow.Category = TabRow.YodleeCategory, ChartsOfAccounts.ChartOfAccounts.EmptyRef(), TabRow.Category);
	EndDo;	
	//Add the record with the full description
	NewRecord = RecordSet.Add();
	NewRecord.BankAccount = TabRow.BankAccount;
	NewRecord.Lexem = Description;
	NewRecord.TransactionID = TabRow.ID;
	NewRecord.Customer = TabRow.Company;
	NewRecord.Category = TabRow.Category;
	NewRecord.FullDescription = True;
	RecordSet.Write(True);	
EndProcedure

Function RecordTransactionToTheDatabase(Tran)
	Try
		BeginTransaction();
		BTRecordset = InformationRegisters.BankTransactions.CreateRecordSet();
		//Add (save) current row to a information register
		If NOT ValueIsFilled(Tran.ID) then
			Tran.ID = New UUID();
		EndIf;
		BTRecordset.Filter.ID.Set(Tran.ID);
		BTRecordset.Write(True);

		BTRecordset.Clear();
		BTRecordset.Filter.TransactionDate.Set(Tran.TransactionDate);
		BTRecordset.Filter.BankAccount.Set(Tran.BankAccount);
		BTRecordset.Filter.Company.Set(Tran.Company);
		BTRecordset.Filter.ID.Set(Tran.ID);
		NewRecord = BTRecordset.Add();
		FillPropertyValues(NewRecord, Tran);
		BTRecordset.Write(True);
		CommitTransaction();
	Except
		ErrDesc = ErrorDescription();
		If TransactionActive() Then
			RollbackTransaction();
		EndIf;
		Raise ErrDesc;
	EndTry;
EndFunction

#EndRegion