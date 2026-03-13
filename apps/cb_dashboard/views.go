package main

import (
	"syscall/js"
)

// renderPartiesView renders the parties management view
func (a *App) renderPartiesView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "view")

	// Header
	header := doc.Call("createElement", "h2")
	header.Set("textContent", "Parties")
	container.Call("appendChild", header)

	// Create party form
	form := doc.Call("createElement", "div")
	form.Set("className", "form-card")

	formTitle := doc.Call("createElement", "h3")
	formTitle.Set("textContent", "Create New Party")
	form.Call("appendChild", formTitle)

	// Full name input
	nameLabel := doc.Call("createElement", "label")
	nameLabel.Set("textContent", "Full Name:")
	form.Call("appendChild", nameLabel)

	nameInput := doc.Call("createElement", "input")
	nameInput.Set("type", "text")
	nameInput.Set("id", "party-name")
	nameInput.Set("placeholder", "Enter full name")
	form.Call("appendChild", nameInput)

	// Email input
	emailLabel := doc.Call("createElement", "label")
	emailLabel.Set("textContent", "Email:")
	form.Call("appendChild", emailLabel)

	emailInput := doc.Call("createElement", "input")
	emailInput.Set("type", "email")
	emailInput.Set("id", "party-email")
	emailInput.Set("placeholder", "Enter email")
	form.Call("appendChild", emailInput)

	// Create button
	createBtn := doc.Call("createElement", "button")
	createBtn.Set("textContent", "Create Party")
	createBtn.Set("className", "btn btn-primary")
	createBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		name := doc.Call("getElementById", "party-name").Get("value").String()
		email := doc.Call("getElementById", "party-email").Get("value").String()
		if name != "" && email != "" {
			a.CreateParty(js.Value{}, []js.Value{js.ValueOf(name), js.ValueOf(email)})
		}
		return nil
	}))
	form.Call("appendChild", createBtn)

	container.Call("appendChild", form)

	// Parties list
	listTitle := doc.Call("createElement", "h3")
	listTitle.Set("textContent", "All Parties")
	container.Call("appendChild", listTitle)

	// Refresh button
	refreshBtn := doc.Call("createElement", "button")
	refreshBtn.Set("textContent", "Refresh List")
	refreshBtn.Set("className", "btn btn-secondary")
	refreshBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.ListParties(js.Value{}, nil)
		return nil
	}))
	container.Call("appendChild", refreshBtn)

	// Parties table
	table := doc.Call("createElement", "table")
	table.Set("className", "data-table")

	// Table header
	thead := doc.Call("createElement", "thead")
	theadRow := doc.Call("createElement", "tr")
	headers := []string{"Name", "Email", "Status", "Actions"}
	for _, h := range headers {
		th := doc.Call("createElement", "th")
		th.Set("textContent", h)
		theadRow.Call("appendChild", th)
	}
	thead.Call("appendChild", theadRow)
	table.Call("appendChild", thead)

	// Table body
	tbody := doc.Call("createElement", "tbody")
	tbody.Set("id", "parties-tbody")

	for _, party := range a.Parties {
		row := doc.Call("createElement", "tr")

		nameCell := doc.Call("createElement", "td")
		nameCell.Set("textContent", party.FullName)
		row.Call("appendChild", nameCell)

		emailCell := doc.Call("createElement", "td")
		emailCell.Set("textContent", party.Email)
		row.Call("appendChild", emailCell)

		statusCell := doc.Call("createElement", "td")
		statusCell.Set("textContent", party.Status)
		row.Call("appendChild", statusCell)

		actionsCell := doc.Call("createElement", "td")

		if party.Status == "active" {
			suspendBtn := doc.Call("createElement", "button")
			suspendBtn.Set("textContent", "Suspend")
			suspendBtn.Set("className", "btn btn-warning btn-sm")
			partyID := party.PartyID
			suspendBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
				a.SuspendParty(js.Value{}, []js.Value{js.ValueOf(partyID)})
				return nil
			}))
			actionsCell.Call("appendChild", suspendBtn)
		}

		closeBtn := doc.Call("createElement", "button")
		closeBtn.Set("textContent", "Close")
		closeBtn.Set("className", "btn btn-danger btn-sm")
		partyID := party.PartyID
		closeBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.CloseParty(js.Value{}, []js.Value{js.ValueOf(partyID)})
			return nil
		}))
		actionsCell.Call("appendChild", closeBtn)

		selectBtn := doc.Call("createElement", "button")
		selectBtn.Set("textContent", "Select")
		selectBtn.Set("className", "btn btn-info btn-sm")
		p := party
		selectBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.SelectedParty = &p
			a.CurrentView = "accounts"
			a.Render()
			return nil
		}))
		actionsCell.Call("appendChild", selectBtn)

		row.Call("appendChild", actionsCell)
		tbody.Call("appendChild", row)
	}

	table.Call("appendChild", tbody)
	container.Call("appendChild", table)

	return container
}

// renderAccountsView renders the accounts management view
func (a *App) renderAccountsView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "view")

	// Header
	header := doc.Call("createElement", "h2")
	if a.SelectedParty != nil {
		header.Set("textContent", "Accounts for "+a.SelectedParty.FullName)
	} else {
		header.Set("textContent", "Accounts")
	}
	container.Call("appendChild", header)

	if a.SelectedParty == nil {
		msg := doc.Call("createElement", "p")
		msg.Set("textContent", "Please select a party from the Parties view first.")
		container.Call("appendChild", msg)
		return container
	}

	// Create account form
	form := doc.Call("createElement", "div")
	form.Set("className", "form-card")

	formTitle := doc.Call("createElement", "h3")
	formTitle.Set("textContent", "Create New Account")
	form.Call("appendChild", formTitle)

	// Name input
	nameLabel := doc.Call("createElement", "label")
	nameLabel.Set("textContent", "Account Name:")
	form.Call("appendChild", nameLabel)

	nameInput := doc.Call("createElement", "input")
	nameInput.Set("type", "text")
	nameInput.Set("id", "account-name")
	nameInput.Set("placeholder", "Enter account name")
	form.Call("appendChild", nameInput)

	// Currency select
	currencyLabel := doc.Call("createElement", "label")
	currencyLabel.Set("textContent", "Currency:")
	form.Call("appendChild", currencyLabel)

	currencySelect := doc.Call("createElement", "select")
	currencySelect.Set("id", "account-currency")
	currencies := []string{"USD", "EUR", "GBP", "JPY", "CHF"}
	for _, c := range currencies {
		option := doc.Call("createElement", "option")
		option.Set("value", c)
		option.Set("textContent", c)
		currencySelect.Call("appendChild", option)
	}
	form.Call("appendChild", currencySelect)

	// Create button
	createBtn := doc.Call("createElement", "button")
	createBtn.Set("textContent", "Create Account")
	createBtn.Set("className", "btn btn-primary")
	partyID := a.SelectedParty.PartyID
	createBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		name := doc.Call("getElementById", "account-name").Get("value").String()
		currency := doc.Call("getElementById", "account-currency").Get("value").String()
		if name != "" {
			a.CreateAccount(js.Value{}, []js.Value{js.ValueOf(partyID), js.ValueOf(name), js.ValueOf(currency)})
		}
		return nil
	}))
	form.Call("appendChild", createBtn)

	container.Call("appendChild", form)

	// Accounts list
	listTitle := doc.Call("createElement", "h3")
	listTitle.Set("textContent", "Accounts")
	container.Call("appendChild", listTitle)

	// Refresh button
	refreshBtn := doc.Call("createElement", "button")
	refreshBtn.Set("textContent", "Refresh List")
	refreshBtn.Set("className", "btn btn-secondary")
	refreshBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.ListAccounts(js.Value{}, []js.Value{js.ValueOf(partyID)})
		return nil
	}))
	container.Call("appendChild", refreshBtn)

	// Accounts table
	table := doc.Call("createElement", "table")
	table.Set("className", "data-table")

	// Table header
	thead := doc.Call("createElement", "thead")
	theadRow := doc.Call("createElement", "tr")
	headers := []string{"Name", "Currency", "Balance", "Status", "Actions"}
	for _, h := range headers {
		th := doc.Call("createElement", "th")
		th.Set("textContent", h)
		theadRow.Call("appendChild", th)
	}
	thead.Call("appendChild", theadRow)
	table.Call("appendChild", thead)

	// Table body
	tbody := doc.Call("createElement", "tbody")

	for _, account := range a.Accounts {
		row := doc.Call("createElement", "tr")

		nameCell := doc.Call("createElement", "td")
		nameCell.Set("textContent", account.Name)
		row.Call("appendChild", nameCell)

		currencyCell := doc.Call("createElement", "td")
		currencyCell.Set("textContent", account.Currency)
		row.Call("appendChild", currencyCell)

		balanceCell := doc.Call("createElement", "td")
		balanceCell.Set("textContent", FormatAmount(account.Balance, account.Currency))
		row.Call("appendChild", balanceCell)

		statusCell := doc.Call("createElement", "td")
		statusCell.Set("textContent", account.Status)
		row.Call("appendChild", statusCell)

		actionsCell := doc.Call("createElement", "td")

		if account.Status == "active" {
			freezeBtn := doc.Call("createElement", "button")
			freezeBtn.Set("textContent", "Freeze")
			freezeBtn.Set("className", "btn btn-warning btn-sm")
			accountID := account.AccountID
			freezeBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
				a.FreezeAccount(js.Value{}, []js.Value{js.ValueOf(accountID)})
				return nil
			}))
			actionsCell.Call("appendChild", freezeBtn)
		}

		if account.Status == "frozen" {
			unfreezeBtn := doc.Call("createElement", "button")
			unfreezeBtn.Set("textContent", "Unfreeze")
			unfreezeBtn.Set("className", "btn btn-success btn-sm")
			accountID := account.AccountID
			unfreezeBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
				a.UnfreezeAccount(js.Value{}, []js.Value{js.ValueOf(accountID)})
				return nil
			}))
			actionsCell.Call("appendChild", unfreezeBtn)
		}

		closeBtn := doc.Call("createElement", "button")
		closeBtn.Set("textContent", "Close")
		closeBtn.Set("className", "btn btn-danger btn-sm")
		accountID := account.AccountID
		closeBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.CloseAccount(js.Value{}, []js.Value{js.ValueOf(accountID)})
			return nil
		}))
		actionsCell.Call("appendChild", closeBtn)

		selectBtn := doc.Call("createElement", "button")
		selectBtn.Set("textContent", "Select")
		selectBtn.Set("className", "btn btn-info btn-sm")
		acc := account
		selectBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.SelectedAccount = &acc
			a.GetBalance(js.Value{}, []js.Value{js.ValueOf(acc.AccountID)})
			return nil
		}))
		actionsCell.Call("appendChild", selectBtn)

		row.Call("appendChild", actionsCell)
		tbody.Call("appendChild", row)
	}

	table.Call("appendChild", tbody)
	container.Call("appendChild", table)

	return container
}

// renderTransferView renders the transfer form
func (a *App) renderTransferView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "view")

	header := doc.Call("createElement", "h2")
	header.Set("textContent", "Transfer Funds")
	container.Call("appendChild", header)

	form := doc.Call("createElement", "div")
	form.Set("className", "form-card")

	// Source account
	sourceLabel := doc.Call("createElement", "label")
	sourceLabel.Set("textContent", "Source Account ID:")
	form.Call("appendChild", sourceLabel)

	sourceInput := doc.Call("createElement", "input")
	sourceInput.Set("type", "text")
	sourceInput.Set("id", "transfer-source")
	sourceInput.Set("placeholder", "Enter source account ID")
	form.Call("appendChild", sourceInput)

	// Destination account
	destLabel := doc.Call("createElement", "label")
	destLabel.Set("textContent", "Destination Account ID:")
	form.Call("appendChild", destLabel)

	destInput := doc.Call("createElement", "input")
	destInput.Set("type", "text")
	destInput.Set("id", "transfer-dest")
	destInput.Set("placeholder", "Enter destination account ID")
	form.Call("appendChild", destInput)

	// Amount
	amountLabel := doc.Call("createElement", "label")
	amountLabel.Set("textContent", "Amount (e.g., 10.50 for $10.50):")
	form.Call("appendChild", amountLabel)

	amountInput := doc.Call("createElement", "input")
	amountInput.Set("type", "text")
	amountInput.Set("id", "transfer-amount")
	amountInput.Set("placeholder", "Enter amount")
	form.Call("appendChild", amountInput)

	// Currency
	currencyLabel := doc.Call("createElement", "label")
	currencyLabel.Set("textContent", "Currency:")
	form.Call("appendChild", currencyLabel)

	currencySelect := doc.Call("createElement", "select")
	currencySelect.Set("id", "transfer-currency")
	currencies := []string{"USD", "EUR", "GBP", "JPY", "CHF"}
	for _, c := range currencies {
		option := doc.Call("createElement", "option")
		option.Set("value", c)
		option.Set("textContent", c)
		currencySelect.Call("appendChild", option)
	}
	form.Call("appendChild", currencySelect)

	// Description
	descLabel := doc.Call("createElement", "label")
	descLabel.Set("textContent", "Description:")
	form.Call("appendChild", descLabel)

	descInput := doc.Call("createElement", "input")
	descInput.Set("type", "text")
	descInput.Set("id", "transfer-desc")
	descInput.Set("placeholder", "Enter description")
	form.Call("appendChild", descInput)

	// Transfer button
	transferBtn := doc.Call("createElement", "button")
	transferBtn.Set("textContent", "Transfer")
	transferBtn.Set("className", "btn btn-primary")
	transferBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		source := doc.Call("getElementById", "transfer-source").Get("value").String()
		dest := doc.Call("getElementById", "transfer-dest").Get("value").String()
		amountStr := doc.Call("getElementById", "transfer-amount").Get("value").String()
		currency := doc.Call("getElementById", "transfer-currency").Get("value").String()
		desc := doc.Call("getElementById", "transfer-desc").Get("value").String()

		amount, err := ParseAmount(amountStr)
		if err != nil {
			a.Error = "Invalid amount format"
			a.Render()
			return nil
		}

		a.Transfer(js.Value{}, []js.Value{
			js.ValueOf(source),
			js.ValueOf(dest),
			js.ValueOf(amount),
			js.ValueOf(currency),
			js.ValueOf(desc),
		})
		return nil
	}))
	form.Call("appendChild", transferBtn)

	container.Call("appendChild", form)
	return container
}

// renderDepositView renders the deposit/withdrawal form
func (a *App) renderDepositView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "view")

	header := doc.Call("createElement", "h2")
	header.Set("textContent", "Deposit / Withdraw")
	container.Call("appendChild", header)

	// Deposit section
	depositSection := doc.Call("createElement", "div")
	depositSection.Set("className", "form-card")

	depositTitle := doc.Call("createElement", "h3")
	depositTitle.Set("textContent", "Deposit")
	depositSection.Call("appendChild", depositTitle)

	// Account ID
	depAccountLabel := doc.Call("createElement", "label")
	depAccountLabel.Set("textContent", "Account ID:")
	depositSection.Call("appendChild", depAccountLabel)

	depAccountInput := doc.Call("createElement", "input")
	depAccountInput.Set("type", "text")
	depAccountInput.Set("id", "deposit-account")
	depAccountInput.Set("placeholder", "Enter account ID")
	depositSection.Call("appendChild", depAccountInput)

	// Amount
	depAmountLabel := doc.Call("createElement", "label")
	depAmountLabel.Set("textContent", "Amount:")
	depositSection.Call("appendChild", depAmountLabel)

	depAmountInput := doc.Call("createElement", "input")
	depAmountInput.Set("type", "text")
	depAmountInput.Set("id", "deposit-amount")
	depAmountInput.Set("placeholder", "Enter amount")
	depositSection.Call("appendChild", depAmountInput)

	// Currency
	depCurrencyLabel := doc.Call("createElement", "label")
	depCurrencyLabel.Set("textContent", "Currency:")
	depositSection.Call("appendChild", depCurrencyLabel)

	depCurrencySelect := doc.Call("createElement", "select")
	depCurrencySelect.Set("id", "deposit-currency")
	for _, c := range []string{"USD", "EUR", "GBP", "JPY", "CHF"} {
		option := doc.Call("createElement", "option")
		option.Set("value", c)
		option.Set("textContent", c)
		depCurrencySelect.Call("appendChild", option)
	}
	depositSection.Call("appendChild", depCurrencySelect)

	// Description
	depDescLabel := doc.Call("createElement", "label")
	depDescLabel.Set("textContent", "Description:")
	depositSection.Call("appendChild", depDescLabel)

	depDescInput := doc.Call("createElement", "input")
	depDescInput.Set("type", "text")
	depDescInput.Set("id", "deposit-desc")
	depDescInput.Set("placeholder", "Enter description")
	depositSection.Call("appendChild", depDescInput)

	// Deposit button
	depositBtn := doc.Call("createElement", "button")
	depositBtn.Set("textContent", "Deposit")
	depositBtn.Set("className", "btn btn-primary")
	depositBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		account := doc.Call("getElementById", "deposit-account").Get("value").String()
		amountStr := doc.Call("getElementById", "deposit-amount").Get("value").String()
		currency := doc.Call("getElementById", "deposit-currency").Get("value").String()
		desc := doc.Call("getElementById", "deposit-desc").Get("value").String()

		amount, err := ParseAmount(amountStr)
		if err != nil {
			a.Error = "Invalid amount format"
			a.Render()
			return nil
		}

		a.Deposit(js.Value{}, []js.Value{
			js.ValueOf(account),
			js.ValueOf(amount),
			js.ValueOf(currency),
			js.ValueOf(desc),
		})
		return nil
	}))
	depositSection.Call("appendChild", depositBtn)

	container.Call("appendChild", depositSection)

	// Withdrawal section
	withdrawSection := doc.Call("createElement", "div")
	withdrawSection.Set("className", "form-card")

	withdrawTitle := doc.Call("createElement", "h3")
	withdrawTitle.Set("textContent", "Withdraw")
	withdrawSection.Call("appendChild", withdrawTitle)

	// Account ID
	wdAccountLabel := doc.Call("createElement", "label")
	wdAccountLabel.Set("textContent", "Account ID:")
	withdrawSection.Call("appendChild", wdAccountLabel)

	wdAccountInput := doc.Call("createElement", "input")
	wdAccountInput.Set("type", "text")
	wdAccountInput.Set("id", "withdraw-account")
	wdAccountInput.Set("placeholder", "Enter account ID")
	withdrawSection.Call("appendChild", wdAccountInput)

	// Amount
	wdAmountLabel := doc.Call("createElement", "label")
	wdAmountLabel.Set("textContent", "Amount:")
	withdrawSection.Call("appendChild", wdAmountLabel)

	wdAmountInput := doc.Call("createElement", "input")
	wdAmountInput.Set("type", "text")
	wdAmountInput.Set("id", "withdraw-amount")
	wdAmountInput.Set("placeholder", "Enter amount")
	withdrawSection.Call("appendChild", wdAmountInput)

	// Currency
	wdCurrencyLabel := doc.Call("createElement", "label")
	wdCurrencyLabel.Set("textContent", "Currency:")
	withdrawSection.Call("appendChild", wdCurrencyLabel)

	wdCurrencySelect := doc.Call("createElement", "select")
	wdCurrencySelect.Set("id", "withdraw-currency")
	for _, c := range []string{"USD", "EUR", "GBP", "JPY", "CHF"} {
		option := doc.Call("createElement", "option")
		option.Set("value", c)
		option.Set("textContent", c)
		wdCurrencySelect.Call("appendChild", option)
	}
	withdrawSection.Call("appendChild", wdCurrencySelect)

	// Description
	wdDescLabel := doc.Call("createElement", "label")
	wdDescLabel.Set("textContent", "Description:")
	withdrawSection.Call("appendChild", wdDescLabel)

	wdDescInput := doc.Call("createElement", "input")
	wdDescInput.Set("type", "text")
	wdDescInput.Set("id", "withdraw-desc")
	wdDescInput.Set("placeholder", "Enter description")
	withdrawSection.Call("appendChild", wdDescInput)

	// Withdraw button
	withdrawBtn := doc.Call("createElement", "button")
	withdrawBtn.Set("textContent", "Withdraw")
	withdrawBtn.Set("className", "btn btn-primary")
	withdrawBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		account := doc.Call("getElementById", "withdraw-account").Get("value").String()
		amountStr := doc.Call("getElementById", "withdraw-amount").Get("value").String()
		currency := doc.Call("getElementById", "withdraw-currency").Get("value").String()
		desc := doc.Call("getElementById", "withdraw-desc").Get("value").String()

		amount, err := ParseAmount(amountStr)
		if err != nil {
			a.Error = "Invalid amount format"
			a.Render()
			return nil
		}

		a.Withdraw(js.Value{}, []js.Value{
			js.ValueOf(account),
			js.ValueOf(amount),
			js.ValueOf(currency),
			js.ValueOf(desc),
		})
		return nil
	}))
	withdrawSection.Call("appendChild", withdrawBtn)

	container.Call("appendChild", withdrawSection)

	return container
}

// renderTransactionsView renders the transactions view
func (a *App) renderTransactionsView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "view")

	header := doc.Call("createElement", "h2")
	header.Set("textContent", "Transactions")
	container.Call("appendChild", header)

	// Account filter
	filterLabel := doc.Call("createElement", "label")
	filterLabel.Set("textContent", "Filter by Account ID (optional):")
	container.Call("appendChild", filterLabel)

	filterInput := doc.Call("createElement", "input")
	filterInput.Set("type", "text")
	filterInput.Set("id", "txn-filter")
	filterInput.Set("placeholder", "Enter account ID to filter")
	container.Call("appendChild", filterInput)

	// Refresh button
	refreshBtn := doc.Call("createElement", "button")
	refreshBtn.Set("textContent", "Refresh")
	refreshBtn.Set("className", "btn btn-secondary")
	refreshBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		accountID := doc.Call("getElementById", "txn-filter").Get("value").String()
		if accountID != "" {
			a.ListTransactions(js.Value{}, []js.Value{js.ValueOf(accountID)})
		}
		return nil
	}))
	container.Call("appendChild", refreshBtn)

	// Transactions table
	table := doc.Call("createElement", "table")
	table.Set("className", "data-table")

	// Table header
	thead := doc.Call("createElement", "thead")
	theadRow := doc.Call("createElement", "tr")
	headers := []string{"Type", "Amount", "Currency", "Status", "Description", "Actions"}
	for _, h := range headers {
		th := doc.Call("createElement", "th")
		th.Set("textContent", h)
		theadRow.Call("appendChild", th)
	}
	thead.Call("appendChild", theadRow)
	table.Call("appendChild", thead)

	// Table body
	tbody := doc.Call("createElement", "tbody")

	for _, txn := range a.Transactions {
		row := doc.Call("createElement", "tr")

		typeCell := doc.Call("createElement", "td")
		typeCell.Set("textContent", txn.TxnType)
		row.Call("appendChild", typeCell)

		amountCell := doc.Call("createElement", "td")
		amountCell.Set("textContent", FormatAmount(txn.Amount, txn.Currency))
		row.Call("appendChild", amountCell)

		currencyCell := doc.Call("createElement", "td")
		currencyCell.Set("textContent", txn.Currency)
		row.Call("appendChild", currencyCell)

		statusCell := doc.Call("createElement", "td")
		statusCell.Set("textContent", txn.Status)
		row.Call("appendChild", statusCell)

		descCell := doc.Call("createElement", "td")
		descCell.Set("textContent", txn.Description)
		row.Call("appendChild", descCell)

		actionsCell := doc.Call("createElement", "td")

		if txn.Status == "posted" {
			reverseBtn := doc.Call("createElement", "button")
			reverseBtn.Set("textContent", "Reverse")
			reverseBtn.Set("className", "btn btn-warning btn-sm")
			txnID := txn.TxnID
			reverseBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
				a.ReverseTransaction(js.Value{}, []js.Value{js.ValueOf(txnID)})
				return nil
			}))
			actionsCell.Call("appendChild", reverseBtn)
		}

		row.Call("appendChild", actionsCell)
		tbody.Call("appendChild", row)
	}

	table.Call("appendChild", tbody)
	container.Call("appendChild", table)

	return container
}
