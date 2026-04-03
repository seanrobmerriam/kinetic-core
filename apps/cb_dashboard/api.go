package main

import (
	"encoding/json"
	"fmt"
	"syscall/js"
)

var apiBaseURL = resolveAPIBaseURL()
var authSessionID string

const sessionStorageKey = "ironledger.session_id"

func resolveAPIBaseURL() string {
	location := js.Global().Get("window").Get("location")
	protocol := location.Get("protocol").String()
	hostname := location.Get("hostname").String()
	if protocol == "" {
		protocol = "http:"
	}
	if hostname == "" {
		hostname = "127.0.0.1"
	}
	return fmt.Sprintf("%s//%s:8081/api/v1", protocol, hostname)
}

// StatsResponse represents the dashboard stats response
type StatsResponse struct {
	TotalCustomers int   `json:"total_customers"`
	TotalAccounts  int   `json:"total_accounts"`
	TotalBalance   int64 `json:"total_balance"`
	TodayTxns      int   `json:"today_txns"`
	PendingTxns    int   `json:"pending_txns"`
}

// fetch makes an HTTP request using the browser's fetch API
func fetch(method, url string, body interface{}) (js.Value, error) {
	// Create request options
	opts := js.Global().Get("Object").New()
	opts.Set("method", method)
	headers := map[string]interface{}{
		"Content-Type": "application/json",
	}
	if authSessionID != "" {
		headers["Authorization"] = "Bearer " + authSessionID
	}
	opts.Set("headers", js.ValueOf(headers))

	if body != nil {
		jsonBody, err := json.Marshal(body)
		if err != nil {
			return js.Value{}, err
		}
		opts.Set("body", string(jsonBody))
	}

	// Make the fetch call
	fetchPromise := js.Global().Call("fetch", url, opts)

	// Create channels for result
	resultCh := make(chan js.Value)
	errCh := make(chan error)

	// Handle success
	thenFunc := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		response := args[0]
		status := response.Get("status").Int()
		if status == 204 {
			resultCh <- js.Null()
			return nil
		}
		if !response.Get("ok").Bool() {
			// Read error response
			var errJsonFunc js.Func
			errJsonFunc = js.FuncOf(func(this js.Value, args []js.Value) interface{} {
				defer errJsonFunc.Release()
				if status == 401 && authSessionID != "" && !isLoginURL(url) && activeApp != nil {
					activeApp.handleUnauthorized("Session expired. Please sign in again.")
				}
				errCh <- fmt.Errorf("API error: %s", args[0].Get("message").String())
				return nil
			})
			response.Call("json").Call("then", errJsonFunc)
			return nil
		}
		var okJsonFunc js.Func
		okJsonFunc = js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			defer okJsonFunc.Release()
			resultCh <- args[0]
			return nil
		})
		response.Call("json").Call("then", okJsonFunc)
		return nil
	})
	defer thenFunc.Release()

	// Handle error
	catchFunc := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		errCh <- fmt.Errorf("fetch error: %s", args[0].Get("message").String())
		return nil
	})
	defer catchFunc.Release()

	fetchPromise.Call("then", thenFunc).Call("catch", catchFunc)

	// Wait for result
	select {
	case result := <-resultCh:
		return result, nil
	case err := <-errCh:
		return js.Value{}, err
	}
}

func loadStoredSessionID() string {
	storage := js.Global().Get("window").Get("localStorage")
	if storage.IsUndefined() || storage.IsNull() {
		return ""
	}
	value := storage.Call("getItem", sessionStorageKey)
	if value.IsNull() || value.IsUndefined() {
		return ""
	}
	return value.String()
}

func persistSessionID(sessionID string) {
	storage := js.Global().Get("window").Get("localStorage")
	if storage.IsUndefined() || storage.IsNull() {
		return
	}
	storage.Call("setItem", sessionStorageKey, sessionID)
}

func clearStoredSessionID() {
	storage := js.Global().Get("window").Get("localStorage")
	if storage.IsUndefined() || storage.IsNull() {
		return
	}
	storage.Call("removeItem", sessionStorageKey)
}

func setSessionID(sessionID string) {
	authSessionID = sessionID
}

func clearSessionID() {
	authSessionID = ""
}

func isLoginURL(url string) bool {
	return url == apiBaseURL+"/auth/login"
}

// CreateParty creates a new party
func (a *App) CreateParty(this js.Value, args []js.Value) interface{} {
	if len(args) < 2 {
		a.Error = "Name and email required"
		a.Render()
		return nil
	}

	name := args[0].String()
	email := args[1].String()

	body := map[string]string{
		"full_name": name,
		"email":     email,
	}

	go func() {
		logMsg(INFO, "API request", map[string]interface{}{"method": "POST", "url": apiBaseURL + "/parties"})
		_, err := fetch("POST", apiBaseURL+"/parties", body)
		if err != nil {
			logMsg(ERROR, "API request failed", map[string]interface{}{"error": err.Error()})
			a.Error = err.Error()
			a.Success = ""
		} else {
			logMsg(INFO, "API request succeeded", map[string]interface{}{"action": "createParty"})
			a.Error = ""
			a.Success = "Customer created"
			a.ListParties(js.Value{}, nil)
		}
		a.Render()
	}()

	return nil
}

// ListParties fetches all parties
func (a *App) ListParties(this js.Value, args []js.Value) interface{} {
	go func() {
		logMsg(INFO, "API request", map[string]interface{}{"method": "GET", "url": apiBaseURL + "/parties"})
		result, err := fetch("GET", apiBaseURL+"/parties", nil)
		if err != nil {
			logMsg(ERROR, "API request failed", map[string]interface{}{"error": err.Error()})
			a.Error = err.Error()
		} else {
			a.Error = ""
			// Parse result using JSON.stringify to properly convert JS array to JSON
			itemsJSON := js.Global().Get("JSON").Call("stringify", result.Get("items")).String()
			json.Unmarshal([]byte(itemsJSON), &a.Parties)
			if a.SelectedParty == nil && len(a.Parties) > 0 {
				party := a.Parties[0]
				a.SelectedParty = &party
				if a.CurrentView == "loans" {
					a.ListLoansForSelectedParty()
				}
			}
			logMsg(INFO, "API request succeeded", map[string]interface{}{"action": "listParties", "count": len(a.Parties)})
		}
		a.Render()
	}()

	return nil
}

// SuspendParty suspends a party
func (a *App) SuspendParty(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	partyID := args[0].String()

	go func() {
		_, err := fetch("POST", apiBaseURL+"/parties/"+partyID+"/suspend", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			a.ListParties(js.Value{}, nil)
		}
		a.Render()
	}()

	return nil
}

// CloseParty closes a party
func (a *App) CloseParty(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	partyID := args[0].String()

	go func() {
		_, err := fetch("POST", apiBaseURL+"/parties/"+partyID+"/close", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			a.ListParties(js.Value{}, nil)
		}
		a.Render()
	}()

	return nil
}

// CreateAccount creates a new account
func (a *App) CreateAccount(this js.Value, args []js.Value) interface{} {
	if len(args) < 3 {
		return nil
	}

	partyID := args[0].String()
	name := args[1].String()
	currency := args[2].String()

	body := map[string]string{
		"party_id": partyID,
		"name":     name,
		"currency": currency,
	}

	go func() {
		_, err := fetch("POST", apiBaseURL+"/accounts", body)
		if err != nil {
			a.Error = err.Error()
			a.Success = ""
		} else {
			a.Error = ""
			a.Success = "Account created"
			a.ListParties(js.Value{}, nil)
			a.ListAllAccounts(js.Value{}, nil)
		}
		a.Render()
	}()

	return nil
}

// ListAccounts fetches accounts for a party
func (a *App) ListAccounts(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	partyID := args[0].String()

	go func() {
		result, err := fetch("GET", apiBaseURL+"/parties/"+partyID+"/accounts", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			itemsJSON := js.Global().Get("JSON").Call("stringify", result.Get("items")).String()
			json.Unmarshal([]byte(itemsJSON), &a.Accounts)
		}
		a.Render()
	}()

	return nil
}

// FreezeAccount freezes an account
func (a *App) FreezeAccount(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	accountID := args[0].String()

	go func() {
		_, err := fetch("POST", apiBaseURL+"/accounts/"+accountID+"/freeze", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			if a.SelectedParty != nil {
				a.ListAccounts(js.Value{}, []js.Value{js.ValueOf(a.SelectedParty.PartyID)})
			}
		}
		a.Render()
	}()

	return nil
}

// UnfreezeAccount unfreezes an account
func (a *App) UnfreezeAccount(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	accountID := args[0].String()

	go func() {
		_, err := fetch("POST", apiBaseURL+"/accounts/"+accountID+"/unfreeze", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			if a.SelectedParty != nil {
				a.ListAccounts(js.Value{}, []js.Value{js.ValueOf(a.SelectedParty.PartyID)})
			}
		}
		a.Render()
	}()

	return nil
}

// CloseAccount closes an account
func (a *App) CloseAccount(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	accountID := args[0].String()

	go func() {
		_, err := fetch("POST", apiBaseURL+"/accounts/"+accountID+"/close", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			if a.SelectedParty != nil {
				a.ListAccounts(js.Value{}, []js.Value{js.ValueOf(a.SelectedParty.PartyID)})
			}
		}
		a.Render()
	}()

	return nil
}

// GetBalance fetches account balance
func (a *App) GetBalance(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	accountID := args[0].String()

	go func() {
		result, err := fetch("GET", apiBaseURL+"/accounts/"+accountID+"/balance", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			var balance BalanceResponse
			resultJSON := js.Global().Get("JSON").Call("stringify", result).String()
			json.Unmarshal([]byte(resultJSON), &balance)
			// Show balance alert
			js.Global().Call("alert", fmt.Sprintf("Balance: %s (%d %s)",
				balance.BalanceFormatted, balance.Balance, balance.Currency))
		}
		a.Render()
	}()

	return nil
}

// Transfer performs a transfer between accounts
func (a *App) Transfer(this js.Value, args []js.Value) interface{} {
	if len(args) < 5 {
		return nil
	}

	sourceID := args[0].String()
	destID := args[1].String()
	amount := args[2].Int()
	currency := args[3].String()
	description := args[4].String()

	idempotencyKey := fmt.Sprintf("wasm-%d", js.Global().Get("Date").Call("now").Int())

	body := map[string]interface{}{
		"idempotency_key":   idempotencyKey,
		"source_account_id": sourceID,
		"dest_account_id":   destID,
		"amount":            amount,
		"currency":          currency,
		"description":       description,
	}

	go func() {
		_, err := fetch("POST", apiBaseURL+"/transactions/transfer", body)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			js.Global().Call("alert", "Transfer successful!")
		}
		a.Render()
	}()

	return nil
}

// Deposit performs a deposit to an account
func (a *App) Deposit(this js.Value, args []js.Value) interface{} {
	if len(args) < 4 {
		return nil
	}

	accountID := args[0].String()
	amount := args[1].Int()
	currency := args[2].String()
	description := args[3].String()

	idempotencyKey := fmt.Sprintf("wasm-%d", js.Global().Get("Date").Call("now").Int())

	body := map[string]interface{}{
		"idempotency_key": idempotencyKey,
		"dest_account_id": accountID,
		"amount":          amount,
		"currency":        currency,
		"description":     description,
	}

	go func() {
		_, err := fetch("POST", apiBaseURL+"/transactions/deposit", body)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			js.Global().Call("alert", "Deposit successful!")
		}
		a.Render()
	}()

	return nil
}

// Withdraw performs a withdrawal from an account
func (a *App) Withdraw(this js.Value, args []js.Value) interface{} {
	if len(args) < 4 {
		return nil
	}

	accountID := args[0].String()
	amount := args[1].Int()
	currency := args[2].String()
	description := args[3].String()

	idempotencyKey := fmt.Sprintf("wasm-%d", js.Global().Get("Date").Call("now").Int())

	body := map[string]interface{}{
		"idempotency_key":   idempotencyKey,
		"source_account_id": accountID,
		"amount":            amount,
		"currency":          currency,
		"description":       description,
	}

	go func() {
		_, err := fetch("POST", apiBaseURL+"/transactions/withdraw", body)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			js.Global().Call("alert", "Withdrawal successful!")
		}
		a.Render()
	}()

	return nil
}

// GetTransaction fetches a transaction by ID
func (a *App) GetTransaction(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	txnID := args[0].String()

	go func() {
		_, err := fetch("GET", apiBaseURL+"/transactions/"+txnID, nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
		}
		a.Render()
	}()

	return nil
}

// ListTransactions fetches transactions for an account
func (a *App) ListTransactions(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	accountID := args[0].String()

	go func() {
		result, err := fetch("GET", apiBaseURL+"/accounts/"+accountID+"/transactions", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			itemsJSON := result.Get("items").String()
			json.Unmarshal([]byte(itemsJSON), &a.Transactions)
		}
		a.Render()
	}()

	return nil
}

// ReverseTransaction reverses a transaction
func (a *App) ReverseTransaction(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	txnID := args[0].String()

	go func() {
		_, err := fetch("POST", apiBaseURL+"/transactions/"+txnID+"/reverse", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			js.Global().Call("alert", "Transaction reversed!")
		}
		a.Render()
	}()

	return nil
}

// GetLedgerEntries fetches ledger entries for an account
func (a *App) GetLedgerEntries(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	accountID := args[0].String()

	go func() {
		result, err := fetch("GET", apiBaseURL+"/accounts/"+accountID+"/entries", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			itemsJSON := js.Global().Get("JSON").Call("stringify", result.Get("items")).String()
			json.Unmarshal([]byte(itemsJSON), &a.LedgerEntries)
		}
		a.Render()
	}()

	return nil
}

// FetchDashboardStats fetches dashboard statistics
func (a *App) FetchDashboardStats(this js.Value, args []js.Value) interface{} {
	a.Loading = true
	a.Render()

	go func() {
		// Fetch all parties to count customers
		partiesResult, partiesErr := fetch("GET", apiBaseURL+"/parties", nil)
		if partiesErr == nil {
			itemsJSON := js.Global().Get("JSON").Call("stringify", partiesResult.Get("items")).String()
			var parties []Party
			json.Unmarshal([]byte(itemsJSON), &parties)
			a.Stats.TotalCustomers = len(parties)
		}

		// Fetch all accounts - we'll need to iterate through parties
		partiesResult2, partiesErr2 := fetch("GET", apiBaseURL+"/parties", nil)
		if partiesErr2 != nil {
			a.Stats = DashboardStats{}
			a.Loading = false
			a.Render()
			return
		}

		var allAccounts []Account
		if partiesResult2.Get("items").Truthy() {
			itemsJSON := js.Global().Get("JSON").Call("stringify", partiesResult2.Get("items")).String()
			var parties []Party
			json.Unmarshal([]byte(itemsJSON), &parties)

			for _, party := range parties {
				accResult, accErr := fetch("GET", apiBaseURL+"/parties/"+party.PartyID+"/accounts", nil)
				if accErr != nil || !accResult.Get("items").Truthy() {
					continue
				}
				accItemsJSON := js.Global().Get("JSON").Call("stringify", accResult.Get("items")).String()
				var accounts []Account
				json.Unmarshal([]byte(accItemsJSON), &accounts)
				allAccounts = append(allAccounts, accounts...)
			}
		}
		a.Stats.TotalAccounts = len(allAccounts)

		// Calculate total balance
		var totalBalance int64
		for _, acc := range allAccounts {
			totalBalance += acc.Balance
		}
		a.Stats.TotalBalance = totalBalance

		// For now, set today's transactions to a placeholder
		// In production, this would come from an API endpoint
		a.Stats.TodayTxns = 0

		// Fetch recent transactions for activity feed
		a.RecentActivity = []ActivityItem{}
		if len(allAccounts) > 0 {
			txnResult, txnErr := fetch("GET", apiBaseURL+"/accounts/"+allAccounts[0].AccountID+"/transactions", nil)
			if txnErr == nil && txnResult.Get("items").Truthy() {
				itemsJSON := js.Global().Get("JSON").Call("stringify", txnResult.Get("items")).String()
				var txns []Transaction
				json.Unmarshal([]byte(itemsJSON), &txns)

				// Take first 5 as recent activity
				if len(txns) > 5 {
					txns = txns[:5]
				}

				for _, txn := range txns {
					activity := ActivityItem{
						ID:          txn.TxnID,
						Type:        txn.TxnType,
						Description: txn.Description,
						Timestamp:   txn.CreatedAt,
						Amount:      txn.Amount,
						Currency:    txn.Currency,
					}
					a.RecentActivity = append(a.RecentActivity, activity)
				}
			}
		}

		a.Loading = false
		a.Render()
	}()

	return nil
}

// ListAllAccounts fetches all accounts across all parties
func (a *App) ListAllAccounts(this js.Value, args []js.Value) interface{} {
	a.Loading = true
	a.Render()

	go func() {
		partiesResult, err := fetch("GET", apiBaseURL+"/parties", nil)
		if err != nil {
			a.Error = err.Error()
			a.Loading = false
			a.Render()
			return
		}

		itemsJSON := js.Global().Get("JSON").Call("stringify", partiesResult.Get("items")).String()
		var parties []Party
		json.Unmarshal([]byte(itemsJSON), &parties)

		var allAccounts []Account
		for _, party := range parties {
			accResult, _ := fetch("GET", apiBaseURL+"/parties/"+party.PartyID+"/accounts", nil)
			if accResult.Get("items").Truthy() {
				accItemsJSON := js.Global().Get("JSON").Call("stringify", accResult.Get("items")).String()
				var accounts []Account
				json.Unmarshal([]byte(accItemsJSON), &accounts)
				allAccounts = append(allAccounts, accounts...)
			}
		}

		a.Accounts = allAccounts
		a.Loading = false
		a.Render()
	}()

	return nil
}

// ListAllTransactions fetches all transactions
func (a *App) ListAllTransactions(this js.Value, args []js.Value) interface{} {
	a.Loading = true
	a.Render()

	go func() {
		// First get all accounts
		partiesResult, err := fetch("GET", apiBaseURL+"/parties", nil)
		if err != nil {
			a.Error = err.Error()
			a.Loading = false
			a.Render()
			return
		}

		itemsJSON := js.Global().Get("JSON").Call("stringify", partiesResult.Get("items")).String()
		var parties []Party
		json.Unmarshal([]byte(itemsJSON), &parties)

		var allAccounts []Account
		for _, party := range parties {
			accResult, _ := fetch("GET", apiBaseURL+"/parties/"+party.PartyID+"/accounts", nil)
			if accResult.Get("items").Truthy() {
				accItemsJSON := js.Global().Get("JSON").Call("stringify", accResult.Get("items")).String()
				var accounts []Account
				json.Unmarshal([]byte(accItemsJSON), &accounts)
				allAccounts = append(allAccounts, accounts...)
			}
		}

		// Now get transactions for each account
		var allTxns []Transaction
		seen := make(map[string]bool)
		for _, account := range allAccounts {
			txnResult, _ := fetch("GET", apiBaseURL+"/accounts/"+account.AccountID+"/transactions", nil)
			if txnResult.Get("items").Truthy() {
				txnItemsJSON := js.Global().Get("JSON").Call("stringify", txnResult.Get("items")).String()
				var txns []Transaction
				json.Unmarshal([]byte(txnItemsJSON), &txns)
				for _, txn := range txns {
					if !seen[txn.TxnID] {
						seen[txn.TxnID] = true
						allTxns = append(allTxns, txn)
					}
				}
			}
		}

		a.Transactions = allTxns
		a.Loading = false
		a.Render()
	}()

	return nil
}

// GetAccountDetails fetches account details including transactions
func (a *App) GetAccountDetails(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	accountID := args[0].String()
	a.Loading = true
	a.Render()

	go func() {
		// Get balance
		balanceResult, err := fetch("GET", apiBaseURL+"/accounts/"+accountID+"/balance", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			var balance BalanceResponse
			resultJSON := js.Global().Get("JSON").Call("stringify", balanceResult).String()
			json.Unmarshal([]byte(resultJSON), &balance)
			if a.SelectedAccount != nil {
				a.SelectedAccount.Balance = balance.Balance
			}
		}

		// Get transactions
		txnResult, err := fetch("GET", apiBaseURL+"/accounts/"+accountID+"/transactions", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			itemsJSON := js.Global().Get("JSON").Call("stringify", txnResult.Get("items")).String()
			json.Unmarshal([]byte(itemsJSON), &a.Transactions)
		}

		// Get ledger entries
		ledgerResult, err := fetch("GET", apiBaseURL+"/accounts/"+accountID+"/entries", nil)
		if err == nil {
			itemsJSON := js.Global().Get("JSON").Call("stringify", ledgerResult.Get("items")).String()
			json.Unmarshal([]byte(itemsJSON), &a.LedgerEntries)
		}

		a.Loading = false
		a.Render()
	}()

	return nil
}

// ListSavingsProducts fetches all savings products
func (a *App) ListSavingsProducts(this js.Value, args []js.Value) interface{} {
	go func() {
		result, err := fetch("GET", apiBaseURL+"/savings-products", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			itemsJSON := js.Global().Get("JSON").Call("stringify", result.Get("items")).String()
			json.Unmarshal([]byte(itemsJSON), &a.SavingsProducts)
		}
		a.Render()
	}()

	return nil
}

// CreateSavingsProduct creates a new savings product
func (a *App) CreateSavingsProduct(this js.Value, args []js.Value) interface{} {
	if len(args) < 7 {
		return nil
	}

	body := map[string]interface{}{
		"name":               args[0].String(),
		"description":        args[1].String(),
		"currency":           args[2].String(),
		"interest_rate_bps":  args[3].Int(),
		"interest_type":      args[4].String(),
		"compounding_period": args[5].String(),
		"minimum_balance":    args[6].Int(),
	}

	go func() {
		_, err := fetch("POST", apiBaseURL+"/savings-products", body)
		if err != nil {
			a.Error = err.Error()
			a.Success = ""
		} else {
			a.Error = ""
			a.Success = "Savings product created"
			a.ListSavingsProducts(js.Value{}, nil)
		}
		a.Render()
	}()

	return nil
}

// ListLoanProducts fetches all loan products
func (a *App) ListLoanProducts(this js.Value, args []js.Value) interface{} {
	go func() {
		result, err := fetch("GET", apiBaseURL+"/loan-products", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			itemsJSON := js.Global().Get("JSON").Call("stringify", result.Get("items")).String()
			json.Unmarshal([]byte(itemsJSON), &a.LoanProducts)
		}
		a.Render()
	}()

	return nil
}

// CreateLoanProduct creates a new loan product
func (a *App) CreateLoanProduct(this js.Value, args []js.Value) interface{} {
	if len(args) < 9 {
		return nil
	}

	body := map[string]interface{}{
		"name":              args[0].String(),
		"description":       args[1].String(),
		"currency":          args[2].String(),
		"min_amount":        args[3].Int(),
		"max_amount":        args[4].Int(),
		"min_term_months":   args[5].Int(),
		"max_term_months":   args[6].Int(),
		"interest_rate_bps": args[7].Int(),
		"interest_type":     args[8].String(),
	}

	go func() {
		_, err := fetch("POST", apiBaseURL+"/loan-products", body)
		if err != nil {
			a.Error = err.Error()
			a.Success = ""
		} else {
			a.Error = ""
			a.Success = "Loan product created"
			a.ListLoanProducts(js.Value{}, nil)
		}
		a.Render()
	}()

	return nil
}

// ListLoans fetches loans for a specific party
func (a *App) ListLoans(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	partyID := args[0].String()

	go func() {
		result, err := fetch("GET", apiBaseURL+"/loans?party_id="+partyID, nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			itemsJSON := js.Global().Get("JSON").Call("stringify", result.Get("items")).String()
			json.Unmarshal([]byte(itemsJSON), &a.Loans)
		}
		a.Render()
	}()

	return nil
}

// ListLoansForSelectedParty refreshes loans for the selected party when present
func (a *App) ListLoansForSelectedParty() {
	if a.SelectedParty != nil {
		a.ListLoans(js.Value{}, []js.Value{js.ValueOf(a.SelectedParty.PartyID)})
	}
}

// CreateLoan creates a new loan application
func (a *App) CreateLoan(this js.Value, args []js.Value) interface{} {
	if len(args) < 5 {
		return nil
	}

	partyID := args[0].String()
	body := map[string]interface{}{
		"party_id":    partyID,
		"product_id":  args[1].String(),
		"account_id":  args[2].String(),
		"principal":   args[3].Int(),
		"term_months": args[4].Int(),
	}

	go func() {
		_, err := fetch("POST", apiBaseURL+"/loans", body)
		if err != nil {
			a.Error = err.Error()
			a.Success = ""
		} else {
			a.Error = ""
			a.Success = "Loan created"
			a.ListLoans(js.Value{}, []js.Value{js.ValueOf(partyID)})
		}
		a.Render()
	}()

	return nil
}

// ApproveLoan approves a pending loan
func (a *App) ApproveLoan(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	loanID := args[0].String()

	go func() {
		_, err := fetch("POST", apiBaseURL+"/loans/"+loanID+"/approve", nil)
		if err != nil {
			a.Error = err.Error()
			a.Success = ""
		} else {
			a.Error = ""
			a.Success = "Loan approved"
			a.ListLoansForSelectedParty()
			if a.SelectedLoan != nil && a.SelectedLoan.LoanID == loanID {
				a.GetLoan(js.Value{}, []js.Value{js.ValueOf(loanID)})
			}
		}
		a.Render()
	}()

	return nil
}

// DisburseLoan disburses an approved loan
func (a *App) DisburseLoan(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	loanID := args[0].String()

	go func() {
		_, err := fetch("POST", apiBaseURL+"/loans/"+loanID+"/disburse", nil)
		if err != nil {
			a.Error = err.Error()
			a.Success = ""
		} else {
			a.Error = ""
			a.Success = "Loan disbursed"
			a.ListLoansForSelectedParty()
			if a.SelectedLoan != nil && a.SelectedLoan.LoanID == loanID {
				a.GetLoan(js.Value{}, []js.Value{js.ValueOf(loanID)})
			}
		}
		a.Render()
	}()

	return nil
}

// GetLoan fetches a single loan and marks it as selected
func (a *App) GetLoan(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	loanID := args[0].String()

	go func() {
		result, err := fetch("GET", apiBaseURL+"/loans/"+loanID, nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			var loan Loan
			resultJSON := js.Global().Get("JSON").Call("stringify", result).String()
			json.Unmarshal([]byte(resultJSON), &loan)
			a.SelectedLoan = &loan
			a.ListLoanRepayments(js.Value{}, []js.Value{js.ValueOf(loanID)})
		}
		a.Render()
	}()

	return nil
}

// ListLoanRepayments fetches repayments for a loan
func (a *App) ListLoanRepayments(this js.Value, args []js.Value) interface{} {
	if len(args) < 1 {
		return nil
	}

	loanID := args[0].String()

	go func() {
		result, err := fetch("GET", apiBaseURL+"/loans/"+loanID+"/repayments", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			itemsJSON := js.Global().Get("JSON").Call("stringify", result.Get("items")).String()
			json.Unmarshal([]byte(itemsJSON), &a.LoanRepayments)
		}
		a.Render()
	}()

	return nil
}

// RecordLoanRepayment posts a repayment for a loan
func (a *App) RecordLoanRepayment(this js.Value, args []js.Value) interface{} {
	if len(args) < 3 {
		return nil
	}

	loanID := args[0].String()
	body := map[string]interface{}{
		"amount":       args[1].Int(),
		"payment_type": args[2].String(),
	}

	go func() {
		_, err := fetch("POST", apiBaseURL+"/loans/"+loanID+"/repayments", body)
		if err != nil {
			a.Error = err.Error()
			a.Success = ""
		} else {
			a.Error = ""
			a.Success = "Repayment recorded"
			a.ListLoansForSelectedParty()
			a.GetLoan(js.Value{}, []js.Value{js.ValueOf(loanID)})
		}
		a.Render()
	}()

	return nil
}
