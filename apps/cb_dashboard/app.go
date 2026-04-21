package main

import (
	"encoding/json"
	"fmt"
	"syscall/js"
)

var activeApp *App

const themeStorageKey = "ironledger.theme"

// DashboardStats represents summary statistics for the dashboard
type DashboardStats struct {
	TotalCustomers int   `json:"total_customers"`
	TotalAccounts  int   `json:"total_accounts"`
	TotalBalance   int64 `json:"total_balance"`
	TodayTxns      int   `json:"today_txns"`
	PendingTxns    int   `json:"pending_txns"`
}

// ActivityItem represents a recent activity feed item
type ActivityItem struct {
	ID          string `json:"id"`
	Type        string `json:"type"`
	Description string `json:"description"`
	Timestamp   int64  `json:"timestamp"`
	Amount      int64  `json:"amount"`
	Currency    string `json:"currency"`
}

// AuthUser represents the authenticated dashboard user.
type AuthUser struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
	Role   string `json:"role"`
	Status string `json:"status"`
}

// App represents the dashboard application state
type App struct {
	CurrentView     string
	Parties         []Party
	Accounts        []Account
	Transactions    []Transaction
	LedgerEntries   []LedgerEntry
	SavingsProducts []SavingsProduct
	LoanProducts    []LoanProduct
	Loans           []Loan
	LoanRepayments  []LoanRepayment
	Holds           []AccountHold
	SelectedParty   *Party
	SelectedAccount *Account
	SelectedLoan    *Loan
	Error           string
	Success         string
	Loading         bool
	Authenticated   bool
	SessionID       string
	CurrentUser     *AuthUser
	DevToolsEnabled bool
	MockImporting   bool

	// Statement view state
	AccountStatement    *AccountStatement
	StatementFromDate   string
	StatementToDate     string
	StatementAccountID  string

	// Dashboard specific
	Stats               DashboardStats
	RecentActivity     []ActivityItem
	SearchQuery        string
	FilterAccountID    string
	FilterStatus       string
	ShowNewCustomerForm bool
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
	EntryID        string `json:"entry_id"`
	TxnID          string `json:"txn_id"`
	AccountID      string `json:"account_id"`
	EntryType      string `json:"entry_type"`
	Amount         int64  `json:"amount"`
	Currency       string `json:"currency"`
	Description    string `json:"description"`
	PostedAt       int64  `json:"posted_at"`
	RunningBalance int64  `json:"running_balance"`
}

// AccountStatement represents a generated account statement
type AccountStatement struct {
	AccountID      string         `json:"account_id"`
	PartyID        string         `json:"party_id"`
	Name           string         `json:"name"`
	Currency       string         `json:"currency"`
	CurrentBalance int64          `json:"current_balance"`
	OpeningBalance int64          `json:"opening_balance"`
	ClosingBalance int64          `json:"closing_balance"`
	Entries        []LedgerEntry  `json:"entries"`
	Total          int            `json:"total"`
	Page           int            `json:"page"`
	PageSize       int            `json:"page_size"`
	From           *int64         `json:"from"`
	To             *int64         `json:"to"`
}

// SavingsProduct represents a savings product definition
type SavingsProduct struct {
	ProductID         string `json:"product_id"`
	Name              string `json:"name"`
	Description       string `json:"description"`
	Currency          string `json:"currency"`
	InterestRateBps   int64  `json:"interest_rate_bps"`
	InterestType      string `json:"interest_type"`
	CompoundingPeriod string `json:"compounding_period"`
	MinimumBalance    int64  `json:"minimum_balance"`
	Status            string `json:"status"`
	CreatedAt         int64  `json:"created_at"`
	UpdatedAt         int64  `json:"updated_at"`
}

// LoanProduct represents a loan product definition
type LoanProduct struct {
	ProductID       string `json:"product_id"`
	Name            string `json:"name"`
	Description     string `json:"description"`
	Currency        string `json:"currency"`
	MinAmount       int64  `json:"min_amount"`
	MaxAmount       int64  `json:"max_amount"`
	MinTermMonths   int64  `json:"min_term_months"`
	MaxTermMonths   int64  `json:"max_term_months"`
	InterestRateBps int64  `json:"interest_rate_bps"`
	InterestType    string `json:"interest_type"`
	Status          string `json:"status"`
	CreatedAt       int64  `json:"created_at"`
	UpdatedAt       int64  `json:"updated_at"`
}

// Loan represents a loan account
type Loan struct {
	LoanID             string `json:"loan_id"`
	ProductID          string `json:"product_id"`
	PartyID            string `json:"party_id"`
	AccountID          string `json:"account_id"`
	Principal          int64  `json:"principal"`
	Currency           string `json:"currency"`
	InterestRateBps    int64  `json:"interest_rate_bps"`
	TermMonths         int64  `json:"term_months"`
	MonthlyPayment     int64  `json:"monthly_payment"`
	OutstandingBalance int64  `json:"outstanding_balance"`
	Status             string `json:"status"`
	DisbursedAt        int64  `json:"disbursed_at"`
	CreatedAt          int64  `json:"created_at"`
	UpdatedAt          int64  `json:"updated_at"`
}

// LoanRepayment represents a loan repayment record
type LoanRepayment struct {
	RepaymentID      string `json:"repayment_id"`
	LoanID           string `json:"loan_id"`
	Amount           int64  `json:"amount"`
	PrincipalPortion int64  `json:"principal_portion"`
	InterestPortion  int64  `json:"interest_portion"`
	Penalty          int64  `json:"penalty"`
	DueDate          int64  `json:"due_date"`
	PaidAt           int64  `json:"paid_at"`
	Status           string `json:"status"`
	CreatedAt        int64  `json:"created_at"`
}

// BalanceResponse represents a balance response
type BalanceResponse struct {
	AccountID        string `json:"account_id"`
	Currency         string `json:"currency"`
	Balance          int64  `json:"balance"`
	AvailableBalance int64  `json:"available_balance"`
	BalanceFormatted string `json:"balance_formatted"`
}

// AccountHold represents a temporary funds hold on an account
type AccountHold struct {
	HoldID     string `json:"hold_id"`
	AccountID  string `json:"account_id"`
	Amount     int64  `json:"amount"`
	Reason     string `json:"reason"`
	Status     string `json:"status"`
	PlacedAt   int64  `json:"placed_at"`
	ReleasedAt int64  `json:"released_at"`
	ExpiresAt  int64  `json:"expires_at"`
}

// NewApp creates a new App instance
func NewApp() *App {
	app := &App{
		CurrentView:     "dashboard",
		Parties:         []Party{},
		Accounts:        []Account{},
		Transactions:    []Transaction{},
		LedgerEntries:   []LedgerEntry{},
		SavingsProducts: []SavingsProduct{},
		LoanProducts:    []LoanProduct{},
		Loans:           []Loan{},
		LoanRepayments:  []LoanRepayment{},
		Holds:           []AccountHold{},
		RecentActivity:  []ActivityItem{},
		Stats:           DashboardStats{},
	}
	activeApp = app
	app.applyThemePreference()
	return app
}

func (a *App) applyThemePreference() {
	doc := js.Global().Get("document")
	docEl := doc.Get("documentElement")
	storage := js.Global().Get("window").Get("localStorage")

	if storage.IsUndefined() || storage.IsNull() {
		docEl.Call("setAttribute", "data-theme", "light")
		return
	}

	theme := storage.Call("getItem", themeStorageKey)
	if theme.IsUndefined() || theme.IsNull() || theme.String() == "" {
		docEl.Call("setAttribute", "data-theme", "light")
		return
	}

	t := theme.String()
	if t != "dark" {
		t = "light"
	}
	docEl.Call("setAttribute", "data-theme", t)
}

func (a *App) isDarkTheme() bool {
	doc := js.Global().Get("document")
	docEl := doc.Get("documentElement")
	return docEl.Call("getAttribute", "data-theme").String() == "dark"
}

func (a *App) toggleTheme() {
	doc := js.Global().Get("document")
	docEl := doc.Get("documentElement")
	storage := js.Global().Get("window").Get("localStorage")

	next := "dark"
	if a.isDarkTheme() {
		next = "light"
	}
	docEl.Call("setAttribute", "data-theme", next)

	if !storage.IsUndefined() && !storage.IsNull() {
		storage.Call("setItem", themeStorageKey, next)
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

	if !a.Authenticated {
		root.Call("appendChild", a.renderLoginView())
		return
	}

	// Create main layout with sidebar
	layout := doc.Call("createElement", "div")
	layout.Set("className", "app-layout")

	// Render sidebar
	sidebar := a.renderSidebar()
	layout.Call("appendChild", sidebar)

	// Render main content area
	mainContent := doc.Call("createElement", "div")
	mainContent.Set("className", "main-content")

	// Header bar
	header := a.renderHeader()
	mainContent.Call("appendChild", header)

	// Content area
	content := doc.Call("createElement", "div")
	content.Set("className", "content-area")

	// Loading indicator
	if a.Loading {
		loadingDiv := doc.Call("createElement", "div")
		loadingDiv.Set("className", "loading-spinner")
		loadingDiv.Set("textContent", "Loading...")
		loadingDiv.Call("setAttribute", "data-testid", "loading")
		content.Call("appendChild", loadingDiv)
	} else {
		// Render error if any
		if a.Error != "" {
			errorDiv := doc.Call("createElement", "div")
			errorDiv.Set("className", "alert alert-error")
			errorDiv.Set("textContent", a.Error)
			errorDiv.Call("setAttribute", "data-testid", "error-banner")
			content.Call("appendChild", errorDiv)
		}

		// Render success message if any
		if a.Success != "" {
			successDiv := doc.Call("createElement", "div")
			successDiv.Set("className", "alert alert-success")
			successDiv.Set("textContent", a.Success)
			successDiv.Call("setAttribute", "data-testid", "success-banner")
			content.Call("appendChild", successDiv)
		}

		// Render current view
		switch a.CurrentView {
		case "dashboard":
			content.Call("appendChild", a.renderDashboardHome())
		case "customers":
			content.Call("appendChild", a.renderCustomersView())
		case "accounts":
			content.Call("appendChild", a.renderAccountsListView())
		case "account-detail":
			content.Call("appendChild", a.renderAccountDetailView())
		case "transactions":
			content.Call("appendChild", a.renderTransactionsListView())
		case "ledger":
			content.Call("appendChild", a.renderLedgerView())
		case "products":
			content.Call("appendChild", a.renderProductsView())
		case "loans":
			content.Call("appendChild", a.renderLoansView())
		case "settings":
			content.Call("appendChild", a.renderSettingsView())
		case "transfer":
			content.Call("appendChild", a.renderTransferView())
		case "deposit":
			content.Call("appendChild", a.renderDepositView())
		default:
			content.Call("appendChild", a.renderDashboardHome())
		}
	}

	mainContent.Call("appendChild", content)
	layout.Call("appendChild", mainContent)
	root.Call("appendChild", layout)
}

func (a *App) renderSidebar() js.Value {
	doc := js.Global().Get("document")
	sidebar := doc.Call("createElement", "aside")
	sidebar.Set("className", "sidebar")

	// Logo/Brand
	brand := doc.Call("createElement", "div")
	brand.Set("className", "sidebar-brand")
	brandLogo := doc.Call("createElement", "div")
	brandLogo.Set("className", "brand-logo")
	brandMark := doc.Call("createElement", "div")
	brandMark.Set("className", "brand-mark")
	brandMark.Set("textContent", "Fe")
	brandLogo.Call("appendChild", brandMark)
	brandTextWrap := doc.Call("createElement", "div")
	brandTextWrap.Set("className", "brand-text")
	brandText := doc.Call("createElement", "h1")
	brandText.Set("textContent", "IronLedger")
	brandText.Set("className", "brand-title")
	brandTextWrap.Call("appendChild", brandText)
	brandSubtitle := doc.Call("createElement", "span")
	brandSubtitle.Set("textContent", "Core Banking")
	brandSubtitle.Set("className", "brand-subtitle")
	brandTextWrap.Call("appendChild", brandSubtitle)
	brandLogo.Call("appendChild", brandTextWrap)
	brand.Call("appendChild", brandLogo)
	sidebar.Call("appendChild", brand)

	// Navigation items
	navItems := []struct {
		id    string
		label string
		icon  string
	}{
		{"dashboard", "Dashboard", "dashboard"},
		{"customers", "Customers", "group"},
		{"accounts", "Accounts", "account_balance"},
		{"transactions", "Transactions", "swap_horiz"},
		{"ledger", "Ledger", "book"},
		{"products", "Products", "inventory_2"},
		{"loans", "Loans", "request_quote"},
	}

	nav := doc.Call("createElement", "nav")
	nav.Set("className", "sidebar-nav")

	for _, item := range navItems {
		btn := doc.Call("createElement", "button")
		btn.Set("className", "nav-item")
		btn.Call("setAttribute", "data-testid", "nav-"+item.id)
		if a.CurrentView == item.id {
			btn.Get("classList").Call("add", "active")
		}

		icon := createMaterialIcon(doc, item.icon, "nav-icon")

		label := doc.Call("createElement", "span")
		label.Set("textContent", item.label)
		label.Set("className", "nav-label")

		btn.Call("appendChild", icon)
		btn.Call("appendChild", label)

		viewName := item.id
		btn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.CurrentView = viewName
			a.Error = ""
			a.Success = ""
			if viewName == "dashboard" {
				a.FetchDashboardStats(js.Value{}, nil)
			} else if viewName == "customers" {
				a.ListParties(js.Value{}, nil)
			} else if viewName == "accounts" {
				a.ListParties(js.Value{}, nil)
				a.ListAllAccounts(js.Value{}, nil)
			} else if viewName == "transactions" {
				a.ListAllTransactions(js.Value{}, nil)
			} else if viewName == "products" {
				a.ListSavingsProducts(js.Value{}, nil)
				a.ListLoanProducts(js.Value{}, nil)
			} else if viewName == "loans" {
				a.ListParties(js.Value{}, nil)
				a.ListAllAccounts(js.Value{}, nil)
				a.ListLoanProducts(js.Value{}, nil)
				a.ListLoansForSelectedParty()
			}
			a.Render()
			return nil
		}))

		nav.Call("appendChild", btn)
	}

	sidebar.Call("appendChild", nav)

	// Divider + Operations section
	divider := doc.Call("createElement", "div")
	divider.Set("className", "nav-divider")
	sidebar.Call("appendChild", divider)

	opsLabel := doc.Call("createElement", "div")
	opsLabel.Set("className", "sidebar-section-label")
	opsLabel.Set("textContent", "Operations")
	sidebar.Call("appendChild", opsLabel)

	opsNav := doc.Call("createElement", "nav")
	opsNav.Set("className", "sidebar-nav")
	opsNav.Set("style", "flex: 0; padding-top: 0;")

	opsItems := []struct {
		id    string
		label string
		icon  string
	}{
		{"transfer", "Transfer Funds", "swap_horiz"},
		{"deposit", "Deposit / Withdraw", "payments"},
		{"settings", "Settings", "settings"},
	}
	for _, item := range opsItems {
		btn := doc.Call("createElement", "button")
		btn.Set("className", "nav-item")
		btn.Call("setAttribute", "data-testid", "nav-"+item.id)
		if a.CurrentView == item.id {
			btn.Get("classList").Call("add", "active")
		}
		icon := createMaterialIcon(doc, item.icon, "nav-icon")
		label := doc.Call("createElement", "span")
		label.Set("textContent", item.label)
		label.Set("className", "nav-label")
		btn.Call("appendChild", icon)
		btn.Call("appendChild", label)
		viewName := item.id
		btn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.CurrentView = viewName
			a.Error = ""
			a.Success = ""
			a.Render()
			return nil
		}))
		opsNav.Call("appendChild", btn)
	}
	sidebar.Call("appendChild", opsNav)

	// Sidebar footer
	footer := doc.Call("createElement", "div")
	footer.Set("className", "sidebar-footer")
	footerText := doc.Call("createElement", "div")
	footerText.Set("style", "font-size: 0.72rem; color: var(--color-text-muted);")
	footerText.Set("textContent", "IronLedger v0.1")
	footer.Call("appendChild", footerText)
	sidebar.Call("appendChild", footer)

	return sidebar
}

func (a *App) renderHeader() js.Value {
	doc := js.Global().Get("document")
	header := doc.Call("createElement", "header")
	header.Set("className", "main-header")

	// Page title
	title := doc.Call("createElement", "div")
	title.Set("className", "header-title")

	pageTitle := doc.Call("createElement", "h2")
	pageTitle.Set("textContent", a.getPageTitle())
	pageTitle.Set("className", "page-title")
	title.Call("appendChild", pageTitle)

	header.Call("appendChild", title)

	// Header actions
	headerActions := doc.Call("createElement", "div")
	headerActions.Set("className", "header-actions")

	if a.CurrentUser != nil {
		// User avatar pill
		userPill := doc.Call("createElement", "div")
		userPill.Set("className", "user-pill")
		userPill.Call("setAttribute", "data-testid", "current-user")

		avatar := doc.Call("createElement", "div")
		avatar.Set("className", "user-avatar")
		// Get initials from email
		initials := "U"
		if len(a.CurrentUser.Email) > 0 {
			initials = string([]rune(a.CurrentUser.Email)[0:1])
		}
		avatar.Set("textContent", initials)
		userPill.Call("appendChild", avatar)

		nameEl := doc.Call("createElement", "span")
		nameEl.Set("textContent", a.CurrentUser.Email)
		nameEl.Set("style", "max-width: 160px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;")
		userPill.Call("appendChild", nameEl)

		roleEl := doc.Call("createElement", "span")
		roleEl.Set("style", "color: var(--color-text-muted); font-size: 0.75rem;")
		roleEl.Set("textContent", capitalize(a.CurrentUser.Role))
		userPill.Call("appendChild", roleEl)

		headerActions.Call("appendChild", userPill)
	}

	if a.DevToolsEnabled {
		mockBtn := doc.Call("createElement", "button")
		mockBtn.Set("className", "header-btn")
		mockBtn.Call("setAttribute", "title", "Import mock data")
		mockBtn.Call("setAttribute", "data-testid", "mock-import-button")
		iconName := "upload"
		if a.MockImporting {
			iconName = "hourglass_top"
		}
		mockBtn.Call("appendChild", createMaterialIcon(doc, iconName, "header-icon"))
		if a.MockImporting {
			mockBtn.Call("setAttribute", "disabled", "true")
		}
		mockBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.ImportMockData(js.Value{}, nil)
			return nil
		}))
		headerActions.Call("appendChild", mockBtn)
	}

	// Theme toggle
	themeBtn := doc.Call("createElement", "button")
	themeBtn.Set("className", "header-btn")
	themeBtn.Call("setAttribute", "title", "Toggle theme")
	themeBtn.Call("setAttribute", "data-testid", "theme-toggle")
	themeIconName := "dark_mode"
	if a.isDarkTheme() {
		themeIconName = "light_mode"
	}
	themeBtn.Call("appendChild", createMaterialIcon(doc, themeIconName, "header-icon"))
	themeBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.toggleTheme()
		a.Render()
		return nil
	}))
	headerActions.Call("appendChild", themeBtn)

	// Refresh button
	refreshBtn := doc.Call("createElement", "button")
	refreshBtn.Set("className", "header-btn")
	refreshBtn.Call("setAttribute", "title", "Refresh")

	refreshIcon := createMaterialIcon(doc, "autorenew", "header-icon")
	refreshBtn.Call("appendChild", refreshIcon)

	refreshBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.RefreshCurrentView()
		return nil
	}))

	headerActions.Call("appendChild", refreshBtn)

	logoutBtn := doc.Call("createElement", "button")
	logoutBtn.Set("className", "header-btn")
	logoutBtn.Call("setAttribute", "title", "Sign out")
	logoutBtn.Call("setAttribute", "data-testid", "logout-button")
	logoutBtn.Call("appendChild", createMaterialIcon(doc, "logout", "header-icon"))
	logoutBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.Logout(js.Value{}, nil)
		return nil
	}))
	headerActions.Call("appendChild", logoutBtn)

	header.Call("appendChild", headerActions)

	return header
}

func (a *App) renderLoginView() js.Value {
	doc := js.Global().Get("document")

	container := doc.Call("createElement", "div")
	container.Set("className", "app-layout")

	mainContent := doc.Call("createElement", "div")
	mainContent.Set("className", "main-content")

	content := doc.Call("createElement", "div")
	content.Set("className", "content-area login-shell")

	hero := doc.Call("createElement", "div")
	hero.Set("className", "login-hero")

	heroTitle := doc.Call("createElement", "h1")
	heroTitle.Set("className", "login-hero-title")
	heroTitle.Set("textContent", "IronLedger Dashboard")
	hero.Call("appendChild", heroTitle)

	heroSubtitle := doc.Call("createElement", "p")
	heroSubtitle.Set("className", "login-hero-subtitle")
	heroSubtitle.Set("textContent", "Modern core banking operations with real-time visibility and controls.")
	hero.Call("appendChild", heroSubtitle)

	heroMeta := doc.Call("createElement", "div")
	heroMeta.Set("className", "login-hero-meta")
	heroMeta.Set("textContent", "Secure operator access")
	hero.Call("appendChild", heroMeta)

	authWrap := doc.Call("createElement", "div")
	authWrap.Set("className", "login-auth")

	card := doc.Call("createElement", "div")
	card.Set("className", "dashboard-card login-card")
	card.Call("setAttribute", "data-testid", "login-form")

	title := doc.Call("createElement", "h2")
	title.Set("className", "page-title")
	title.Set("textContent", "Dashboard Sign In")
	card.Call("appendChild", title)

	subtitle := doc.Call("createElement", "p")
	subtitle.Set("textContent", "Use the configured IronLedger operator credentials to continue.")
	card.Call("appendChild", subtitle)

	if a.Error != "" {
		errorDiv := doc.Call("createElement", "div")
		errorDiv.Set("className", "alert alert-error")
		errorDiv.Set("textContent", a.Error)
		errorDiv.Call("setAttribute", "data-testid", "error-banner")
		card.Call("appendChild", errorDiv)
	}

	if a.Loading {
		loadingDiv := doc.Call("createElement", "div")
		loadingDiv.Set("className", "loading-spinner")
		loadingDiv.Set("textContent", "Signing in...")
		loadingDiv.Call("setAttribute", "data-testid", "loading")
		card.Call("appendChild", loadingDiv)
	}

	form := doc.Call("createElement", "form")
	form.Set("className", "login-form")

	emailLabel := doc.Call("createElement", "label")
	emailLabel.Set("className", "form-label")
	emailLabel.Set("textContent", "Email")
	form.Call("appendChild", emailLabel)

	emailInput := doc.Call("createElement", "input")
	emailInput.Set("className", "form-input")
	emailInput.Set("id", "login-email")
	emailInput.Set("type", "email")
	emailInput.Set("placeholder", "admin@example.com")
	emailInput.Set("required", true)
	form.Call("appendChild", emailInput)

	passwordLabel := doc.Call("createElement", "label")
	passwordLabel.Set("className", "form-label")
	passwordLabel.Set("textContent", "Password")
	form.Call("appendChild", passwordLabel)

	passwordInput := doc.Call("createElement", "input")
	passwordInput.Set("className", "form-input")
	passwordInput.Set("id", "login-password")
	passwordInput.Set("type", "password")
	passwordInput.Set("required", true)
	form.Call("appendChild", passwordInput)

	submitBtn := doc.Call("createElement", "button")
	submitBtn.Set("id", "login-submit")
	submitBtn.Set("className", "btn btn-primary")
	submitBtn.Set("textContent", "Sign In")
	submitBtn.Set("type", "submit")
	form.Call("appendChild", submitBtn)

	form.Call("addEventListener", "submit", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		if len(args) > 0 {
			args[0].Call("preventDefault")
		}
		a.Login(emailInput.Get("value").String(), passwordInput.Get("value").String())
		return nil
	}))

	card.Call("appendChild", form)
	authWrap.Call("appendChild", card)
	content.Call("appendChild", hero)
	content.Call("appendChild", authWrap)
	mainContent.Call("appendChild", content)
	container.Call("appendChild", mainContent)

	return container
}

func (a *App) getPageTitle() string {
	switch a.CurrentView {
	case "dashboard":
		return "Dashboard"
	case "customers":
		return "Customers"
	case "accounts":
		return "Accounts"
	case "account-detail":
		return "Account Details"
	case "transactions":
		return "Transactions"
	case "ledger":
		return "Ledger"
	case "products":
		return "Products"
	case "loans":
		return "Loans"
	case "settings":
		return "Settings"
	case "transfer":
		return "Transfer Funds"
	case "deposit":
		return "Deposit / Withdraw"
	default:
		return "Dashboard"
	}
}

func (a *App) RefreshCurrentView() {
	switch a.CurrentView {
	case "dashboard":
		a.FetchDashboardStats(js.Value{}, nil)
	case "customers":
		a.ListParties(js.Value{}, nil)
	case "accounts":
		a.ListParties(js.Value{}, nil)
		a.ListAllAccounts(js.Value{}, nil)
	case "transactions":
		a.ListAllTransactions(js.Value{}, nil)
	case "products":
		a.ListSavingsProducts(js.Value{}, nil)
		a.ListLoanProducts(js.Value{}, nil)
	case "loans":
		a.ListParties(js.Value{}, nil)
		a.ListAllAccounts(js.Value{}, nil)
		a.ListLoanProducts(js.Value{}, nil)
		a.ListLoansForSelectedParty()
	case "account-detail":
		if a.SelectedAccount != nil {
			a.GetAccountDetails(js.Value{}, []js.Value{js.ValueOf(a.SelectedAccount.AccountID)})
		}
	}
	a.Render()
}

func (a *App) BootstrapSession() {
	sessionID := loadStoredSessionID()
	if sessionID == "" {
		a.Loading = false
		a.Authenticated = false
		a.SessionID = ""
		a.CurrentUser = nil
		a.Error = ""
		a.Render()
		return
	}

	a.Loading = true
	a.Error = ""
	a.Render()
	setSessionID(sessionID)

	go func() {
		result, err := fetch("GET", apiBaseURL+"/auth/me", nil)
		if err != nil {
			a.handleUnauthorized("Session expired. Please sign in again.")
			return
		}

		userJSON := js.Global().Get("JSON").Call("stringify", result.Get("user")).String()
		var user AuthUser
		if err := json.Unmarshal([]byte(userJSON), &user); err != nil {
			a.handleUnauthorized("Session expired. Please sign in again.")
			return
		}

		a.finishLogin(sessionID, user)
	}()
}

func (a *App) Login(email string, password string) {
	if email == "" || password == "" {
		a.Error = "Email and password are required"
		a.Render()
		return
	}

	a.Loading = true
	a.Error = ""
	a.Success = ""
	a.Render()

	go func() {
		result, err := fetch("POST", apiBaseURL+"/auth/login", map[string]string{
			"email":    email,
			"password": password,
		})
		if err != nil {
			a.Loading = false
			a.Error = err.Error()
			a.Render()
			return
		}

		sessionID := result.Get("session_id").String()
		userJSON := js.Global().Get("JSON").Call("stringify", result.Get("user")).String()
		var user AuthUser
		if err := json.Unmarshal([]byte(userJSON), &user); err != nil {
			a.Loading = false
			a.Error = "Invalid login response"
			a.Render()
			return
		}

		a.finishLogin(sessionID, user)
	}()
}

func (a *App) Logout(this js.Value, args []js.Value) interface{} {
	go func() {
		_, _ = fetch("POST", apiBaseURL+"/auth/logout", nil)
		a.handleUnauthorized("")
	}()
	return nil
}

func (a *App) finishLogin(sessionID string, user AuthUser) {
	persistSessionID(sessionID)
	setSessionID(sessionID)
	a.Authenticated = true
	a.SessionID = sessionID
	a.CurrentUser = &user
	a.DevToolsEnabled = false
	a.MockImporting = false
	a.CurrentView = "dashboard"
	a.Error = ""
	a.Success = ""
	a.Loading = false
	a.Render()
	a.LoadDevToolsCapability()
	a.FetchDashboardStats(js.Value{}, nil)
}

func (a *App) handleUnauthorized(message string) {
	clearStoredSessionID()
	clearSessionID()
	a.Authenticated = false
	a.SessionID = ""
	a.CurrentUser = nil
	a.DevToolsEnabled = false
	a.MockImporting = false
	a.Loading = false
	a.Success = ""
	a.Error = message
	a.Render()
}

func capitalize(s string) string {
	if len(s) == 0 {
		return s
	}
	runes := []rune(s)
	runes[0] = rune(s[0] - 32)
	return string(runes)
}

func createMaterialIcon(doc js.Value, name string, className string) js.Value {
	icon := doc.Call("createElement", "span")
	icon.Set("className", className+" material-symbols-outlined")
	icon.Set("textContent", name)
	icon.Call("setAttribute", "aria-hidden", "true")
	return icon
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
