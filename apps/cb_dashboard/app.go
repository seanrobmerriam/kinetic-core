package main

import (
	"encoding/json"
	"fmt"
	"syscall/js"
)

// App represents the dashboard application state
type App struct {
	CurrentView     string
	Parties         []Party
	Accounts        []Account
	Transactions    []Transaction
	SelectedParty   *Party
	SelectedAccount *Account
	Error           string
}

// Party represents a customer/party
type Party struct {
	PartyID   string `json:"party_id"`
	FullName  string `json:"full_name"`
	Email     string `json:"email"`
	Status    string `json:"status"`
	CreatedAt int64  `json:"created_at"`
	UpdatedAt int64  `json:"updated_at"`
}

// Account represents a bank account
type Account struct {
	AccountID string `json:"account_id"`
	PartyID   string `json:"party_id"`
	Name      string `json:"name"`
	Currency  string `json:"currency"`
	Balance   int64  `json:"balance"`
	Status    string `json:"status"`
	CreatedAt int64  `json:"created_at"`
	UpdatedAt int64  `json:"updated_at"`
}

// Transaction represents a financial transaction
type Transaction struct {
	TxnID           string `json:"txn_id"`
	IdempotencyKey  string `json:"idempotency_key"`
	TxnType         string `json:"txn_type"`
	Status          string `json:"status"`
	Amount          int64  `json:"amount"`
	Currency        string `json:"currency"`
	SourceAccountID string `json:"source_account_id"`
	DestAccountID   string `json:"dest_account_id"`
	Description     string `json:"description"`
	CreatedAt       int64  `json:"created_at"`
	PostedAt        int64  `json:"posted_at"`
}

// LedgerEntry represents a ledger entry
type LedgerEntry struct {
	EntryID     string `json:"entry_id"`
	TxnID       string `json:"txn_id"`
	AccountID   string `json:"account_id"`
	EntryType   string `json:"entry_type"`
	Amount      int64  `json:"amount"`
	Currency    string `json:"currency"`
	Description string `json:"description"`
	PostedAt    int64  `json:"posted_at"`
}

// BalanceResponse represents a balance response
type BalanceResponse struct {
	AccountID        string `json:"account_id"`
	Currency         string `json:"currency"`
	Balance          int64  `json:"balance"`
	BalanceFormatted string `json:"balance_formatted"`
}

// NewApp creates a new App instance
func NewApp() *App {
	return &App{
		CurrentView:  "parties",
		Parties:      []Party{},
		Accounts:     []Account{},
		Transactions: []Transaction{},
	}
}

// Navigate changes the current view
func (a *App) Navigate(this js.Value, args []js.Value) interface{} {
	if len(args) > 0 {
		a.CurrentView = args[0].String()
		a.Render()
	}
	return nil
}

// Render renders the current view to the DOM
func (a *App) Render() {
	doc := js.Global().Get("document")
	root := doc.Call("getElementById", "root")

	if root.IsNull() {
		fmt.Println("Root element not found")
		return
	}

	// Clear root
	root.Set("innerHTML", "")

	// Render navigation
	nav := a.renderNav()
	root.Call("appendChild", nav)

	// Render main content
	content := doc.Call("createElement", "main")
	content.Set("className", "container")

	// Render error if any
	if a.Error != "" {
		errorDiv := doc.Call("createElement", "div")
		errorDiv.Set("className", "alert alert-danger")
		errorDiv.Set("textContent", a.Error)
		content.Call("appendChild", errorDiv)
	}

	// Render current view
	switch a.CurrentView {
	case "parties":
		content.Call("appendChild", a.renderPartiesView())
	case "accounts":
		content.Call("appendChild", a.renderAccountsView())
	case "transfer":
		content.Call("appendChild", a.renderTransferView())
	case "deposit":
		content.Call("appendChild", a.renderDepositView())
	case "transactions":
		content.Call("appendChild", a.renderTransactionsView())
	default:
		content.Call("appendChild", a.renderPartiesView())
	}

	root.Call("appendChild", content)
}

func (a *App) renderNav() js.Value {
	doc := js.Global().Get("document")
	nav := doc.Call("createElement", "nav")
	nav.Set("className", "navbar")

	title := doc.Call("createElement", "h1")
	title.Set("textContent", "IronLedger Dashboard")
	nav.Call("appendChild", title)

	links := doc.Call("createElement", "div")
	links.Set("className", "nav-links")

	views := []string{"parties", "accounts", "transfer", "deposit", "transactions"}
	for _, view := range views {
		link := doc.Call("createElement", "button")
		link.Set("textContent", capitalize(view))
		link.Set("className", "nav-btn")
		if a.CurrentView == view {
			link.Get("classList").Call("add", "active")
		}
		viewName := view // capture for closure
		link.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.CurrentView = viewName
			a.Render()
			return nil
		}))
		links.Call("appendChild", link)
	}

	nav.Call("appendChild", links)
	return nav
}

func capitalize(s string) string {
	if len(s) == 0 {
		return s
	}
	return string(s[0]-32) + s[1:]
}

// fetch makes an HTTP request to the API
func (a *App) fetch(method, url string, body interface{}, result interface{}) error {
	// This will be implemented using syscall/js fetch
	return fmt.Errorf("fetch not implemented")
}

// FormatAmount formats an amount for display
func FormatAmount(amount int64, currency string) string {
	switch currency {
	case "JPY":
		return fmt.Sprintf("¥%d", amount)
	case "USD":
		return fmt.Sprintf("$%.2f", float64(amount)/100)
	case "EUR":
		return fmt.Sprintf("€%.2f", float64(amount)/100)
	case "GBP":
		return fmt.Sprintf("£%.2f", float64(amount)/100)
	case "CHF":
		return fmt.Sprintf("CHF %.2f", float64(amount)/100)
	default:
		return fmt.Sprintf("%d", amount)
	}
}

// ParseAmount parses a decimal string to minor units
func ParseAmount(amountStr string) (int64, error) {
	var dollars, cents int64
	_, err := fmt.Sscanf(amountStr, "%d.%d", &dollars, &cents)
	if err != nil {
		// Try without cents
		_, err = fmt.Sscanf(amountStr, "%d", &dollars)
		if err != nil {
			return 0, err
		}
		cents = 0
	}
	return dollars*100 + cents, nil
}

// ToJSObject converts a Go value to a JavaScript object
func ToJSObject(v interface{}) js.Value {
	jsonBytes, _ := json.Marshal(v)
	return js.Global().Get("JSON").Call("parse", string(jsonBytes))
}
