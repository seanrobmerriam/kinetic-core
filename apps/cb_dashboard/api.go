package main

import (
	"encoding/json"
	"fmt"
	"syscall/js"
)

const apiBaseURL = "http://localhost:8081/api/v1"

// fetch makes an HTTP request using the browser's fetch API
func fetch(method, url string, body interface{}) (js.Value, error) {
	// Create request options
	opts := js.Global().Get("Object").New()
	opts.Set("method", method)
	opts.Set("headers", js.ValueOf(map[string]interface{}{
		"Content-Type": "application/json",
	}))

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
		if !response.Get("ok").Bool() {
			// Read error response
			response.Call("json").Call("then", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
				errCh <- fmt.Errorf("API error: %s", args[0].Get("message").String())
				return nil
			}))
			return nil
		}
		response.Call("json").Call("then", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			resultCh <- args[0]
			return nil
		}))
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
		_, err := fetch("POST", apiBaseURL+"/parties", body)
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

// ListParties fetches all parties
func (a *App) ListParties(this js.Value, args []js.Value) interface{} {
	go func() {
		result, err := fetch("GET", apiBaseURL+"/parties", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
			// Parse result
			itemsJSON := result.Get("items").String()
			json.Unmarshal([]byte(itemsJSON), &a.Parties)
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
		} else {
			a.Error = ""
			a.ListAccounts(js.Value{}, []js.Value{js.ValueOf(partyID)})
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
			itemsJSON := result.Get("items").String()
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
			resultJSON := result.String()
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
		_, err := fetch("GET", apiBaseURL+"/accounts/"+accountID+"/entries", nil)
		if err != nil {
			a.Error = err.Error()
		} else {
			a.Error = ""
		}
		a.Render()
	}()

	return nil
}
