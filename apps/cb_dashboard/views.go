package main

import (
	"syscall/js"
	"time"
)

// renderDashboardHome renders the dashboard home view with summary cards
func (a *App) renderDashboardHome() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "dashboard-view")

	// Summary cards row
	cardsRow := doc.Call("createElement", "div")
	cardsRow.Set("className", "summary-cards")

	cards := []struct {
		title      string
		value      string
		icon       string
		colorClass string
		stat       int
	}{
		{"Total Customers", "", "M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z", "blue", a.Stats.TotalCustomers},
		{"Total Accounts", "", "M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z", "green", a.Stats.TotalAccounts},
		{"Total Balance", FormatAmount(a.Stats.TotalBalance, "USD"), "M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z", "purple", 0},
		{"Today's Transactions", "", "M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4", "orange", a.Stats.TodayTxns},
	}

	for _, card := range cards {
		cardEl := doc.Call("createElement", "div")
		cardEl.Set("className", "summary-card")

		cardHeader := doc.Call("createElement", "div")
		cardHeader.Set("className", "card-header")

		iconWrapper := doc.Call("createElement", "div")
		iconWrapper.Set("className", "card-icon "+card.colorClass)

		icon := doc.Call("createElement", "svg")
		icon.Set("className", "icon")
		icon.Call("setAttribute", "fill", "none")
		icon.Call("setAttribute", "viewBox", "0 0 24 24")
		icon.Call("setAttribute", "stroke", "currentColor")
		icon.Call("setAttribute", "stroke-width", "2")

		iconPath := doc.Call("createElement", "path")
		iconPath.Call("setAttribute", "stroke-linecap", "round")
		iconPath.Call("setAttribute", "stroke-linejoin", "round")
		iconPath.Set("d", card.icon)
		icon.Call("appendChild", iconPath)
		iconWrapper.Call("appendChild", icon)

		cardHeader.Call("appendChild", iconWrapper)
		cardEl.Call("appendChild", cardHeader)

		cardContent := doc.Call("createElement", "div")
		cardContent.Set("className", "card-content")

		valueEl := doc.Call("createElement", "div")
		valueEl.Set("className", "card-value")
		if card.stat > 0 && card.value == "" {
			valueEl.Set("textContent", formatNumber(card.stat))
		} else {
			valueEl.Set("textContent", card.value)
		}
		cardContent.Call("appendChild", valueEl)

		titleEl := doc.Call("createElement", "div")
		titleEl.Set("className", "card-title")
		titleEl.Set("textContent", card.title)
		cardContent.Call("appendChild", titleEl)

		cardEl.Call("appendChild", cardContent)
		cardsRow.Call("appendChild", cardEl)
	}

	container.Call("appendChild", cardsRow)

	// Two column layout for activity and quick actions
	twoCol := doc.Call("createElement", "div")
	twoCol.Set("className", "dashboard-two-col")

	// Recent Activity
	activityCol := doc.Call("createElement", "div")
	activityCol.Set("className", "dashboard-card")

	activityHeader := doc.Call("createElement", "div")
	activityHeader.Set("className", "card-header-row")

	activityTitle := doc.Call("createElement", "h3")
	activityTitle.Set("textContent", "Recent Activity")
	activityHeader.Call("appendChild", activityTitle)

	viewAllBtn := doc.Call("createElement", "button")
	viewAllBtn.Set("className", "btn btn-link")
	viewAllBtn.Set("textContent", "View All")
	viewAllBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.CurrentView = "transactions"
		a.ListAllTransactions(js.Value{}, nil)
		a.Render()
		return nil
	}))
	activityHeader.Call("appendChild", viewAllBtn)

	activityCol.Call("appendChild", activityHeader)

	activityList := doc.Call("createElement", "div")
	activityList.Set("className", "activity-list")

	if len(a.RecentActivity) == 0 {
		emptyState := doc.Call("createElement", "div")
		emptyState.Set("className", "empty-state")
		emptyState.Set("textContent", "No recent activity")
		activityList.Call("appendChild", emptyState)
	} else {
		for _, item := range a.RecentActivity {
			activityItem := doc.Call("createElement", "div")
			activityItem.Set("className", "activity-item")

			iconWrap := doc.Call("createElement", "div")
			iconWrap.Set("className", "activity-icon")
			if item.Type == "deposit" || item.Type == "credit" {
				iconWrap.Get("classList").Call("add", "success")
			} else if item.Type == "withdrawal" || item.Type == "debit" {
				iconWrap.Get("classList").Call("add", "warning")
			}

			icon := doc.Call("createElement", "svg")
			icon.Set("className", "icon-sm")
			icon.Call("setAttribute", "fill", "none")
			icon.Call("setAttribute", "viewBox", "0 0 24 24")
			icon.Call("setAttribute", "stroke", "currentColor")
			icon.Call("setAttribute", "stroke-width", "2")

			path := doc.Call("createElement", "path")
			path.Call("setAttribute", "stroke-linecap", "round")
			path.Call("setAttribute", "stroke-linejoin", "round")
			if item.Type == "deposit" || item.Type == "credit" {
				path.Set("d", "M7 11l5-5m0 0l5 5m-5-5v12")
			} else {
				path.Set("d", "M17 13l-5 5m0 0l-5-5m5 5V6")
			}
			icon.Call("appendChild", path)
			iconWrap.Call("appendChild", icon)

			activityItem.Call("appendChild", iconWrap)

			content := doc.Call("createElement", "div")
			content.Set("className", "activity-content")

			desc := doc.Call("createElement", "div")
			desc.Set("className", "activity-desc")
			desc.Set("textContent", item.Description)
			content.Call("appendChild", desc)

			meta := doc.Call("createElement", "div")
			meta.Set("className", "activity-meta")
			meta.Set("textContent", formatTimestamp(item.Timestamp)+" • "+FormatAmount(item.Amount, item.Currency))
			content.Call("appendChild", meta)

			activityItem.Call("appendChild", content)
			activityList.Call("appendChild", activityItem)
		}
	}

	activityCol.Call("appendChild", activityList)
	twoCol.Call("appendChild", activityCol)

	// Quick Actions Card
	quickCol := doc.Call("createElement", "div")
	quickCol.Set("className", "dashboard-card")

	quickTitle := doc.Call("createElement", "h3")
	quickTitle.Set("textContent", "Quick Actions")
	quickCol.Call("appendChild", quickTitle)

	quickActions := []struct {
		label string
		desc  string
		icon  string
		view  string
		color string
	}{
		{"New Customer", "Add a new customer to the system", "M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z", "customers", "primary"},
		{"New Account", "Open a new account for a customer", "M12 6v6m0 0v6m0-6h6m-6 0H6", "accounts", "success"},
		{"Transfer", "Transfer funds between accounts", "M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4", "transfer", "info"},
		{"View Transactions", "Browse all transactions", "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2", "transactions", "warning"},
	}

	quickGrid := doc.Call("createElement", "div")
	quickGrid.Set("className", "quick-actions-grid")

	for _, action := range quickActions {
		actionBtn := doc.Call("createElement", "button")
		actionBtn.Set("className", "quick-action-card")

		actionIcon := doc.Call("createElement", "div")
		actionIcon.Set("className", "action-icon "+action.color)

		iconSvg := doc.Call("createElement", "svg")
		iconSvg.Set("className", "icon")
		iconSvg.Call("setAttribute", "fill", "none")
		iconSvg.Call("setAttribute", "viewBox", "0 0 24 24")
		iconSvg.Call("setAttribute", "stroke", "currentColor")
		iconSvg.Call("setAttribute", "stroke-width", "2")

		iconPath := doc.Call("createElement", "path")
		iconPath.Call("setAttribute", "stroke-linecap", "round")
		iconPath.Call("setAttribute", "stroke-linejoin", "round")
		iconPath.Set("d", action.icon)
		iconSvg.Call("appendChild", iconPath)
		actionIcon.Call("appendChild", iconSvg)

		actionLabel := doc.Call("createElement", "div")
		actionLabel.Set("className", "action-label")
		actionLabel.Set("textContent", action.label)

		actionDesc := doc.Call("createElement", "div")
		actionDesc.Set("className", "action-desc")
		actionDesc.Set("textContent", action.desc)

		actionBtn.Call("appendChild", actionIcon)
		actionBtn.Call("appendChild", actionLabel)
		actionBtn.Call("appendChild", actionDesc)

		viewName := action.view
		actionBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.CurrentView = viewName
			a.Error = ""
			a.Success = ""
			if viewName == "customers" {
				a.ListParties(js.Value{}, nil)
			} else if viewName == "accounts" {
				a.ListAllAccounts(js.Value{}, nil)
			} else if viewName == "transactions" {
				a.ListAllTransactions(js.Value{}, nil)
			}
			a.Render()
			return nil
		}))

		quickGrid.Call("appendChild", actionBtn)
	}

	quickCol.Call("appendChild", quickGrid)
	twoCol.Call("appendChild", quickCol)

	container.Call("appendChild", twoCol)

	return container
}

// renderCustomersView renders the customers list view with search
func (a *App) renderCustomersView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "customers-view")

	// Toolbar
	toolbar := doc.Call("createElement", "div")
	toolbar.Set("className", "view-toolbar")

	// Search
	searchWrapper := doc.Call("createElement", "div")
	searchWrapper.Set("className", "search-wrapper")

	searchIcon := doc.Call("createElement", "svg")
	searchIcon.Set("className", "search-icon")
	searchIcon.Call("setAttribute", "fill", "none")
	searchIcon.Call("setAttribute", "viewBox", "0 0 24 24")
	searchIcon.Call("setAttribute", "stroke", "currentColor")
	searchIcon.Call("setAttribute", "stroke-width", "2")

	searchPath := doc.Call("createElement", "path")
	searchPath.Call("setAttribute", "stroke-linecap", "round")
	searchPath.Call("setAttribute", "stroke-linejoin", "round")
	searchPath.Set("d", "M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z")
	searchIcon.Call("appendChild", searchPath)
	searchWrapper.Call("appendChild", searchIcon)

	searchInput := doc.Call("createElement", "input")
	searchInput.Set("type", "text")
	searchInput.Set("className", "search-input")
	searchInput.Set("placeholder", "Search customers...")
	searchInput.Set("value", a.SearchQuery)
	searchInput.Call("addEventListener", "input", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.SearchQuery = this.Get("value").String()
		a.Render()
		return nil
	}))
	searchWrapper.Call("appendChild", searchInput)

	toolbar.Call("appendChild", searchWrapper)

	// Add customer button
	addBtn := doc.Call("createElement", "button")
	addBtn.Set("className", "btn btn-primary")
	addBtn.Set("textContent", "Add Customer")
	toolbar.Call("appendChild", addBtn)

	container.Call("appendChild", toolbar)

	// Customer form (collapsible)
	formCard := doc.Call("createElement", "div")
	formCard.Set("className", "form-card")

	formTitle := doc.Call("createElement", "h3")
	formTitle.Set("textContent", "New Customer")
	formCard.Call("appendChild", formTitle)

	formGrid := doc.Call("createElement", "div")
	formGrid.Set("className", "form-grid")

	nameInput := doc.Call("createElement", "input")
	nameInput.Set("type", "text")
	nameInput.Set("id", "customer-name")
	nameInput.Set("placeholder", "Full Name")
	nameInput.Set("className", "form-input")
	formGrid.Call("appendChild", nameInput)

	emailInput := doc.Call("createElement", "input")
	emailInput.Set("type", "email")
	emailInput.Set("id", "customer-email")
	emailInput.Set("placeholder", "Email Address")
	emailInput.Set("className", "form-input")
	formGrid.Call("appendChild", emailInput)

	formCard.Call("appendChild", formGrid)

	formActions := doc.Call("createElement", "div")
	formActions.Set("className", "form-actions")

	saveBtn := doc.Call("createElement", "button")
	saveBtn.Set("className", "btn btn-primary")
	saveBtn.Set("textContent", "Create Customer")
	saveBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		name := doc.Call("getElementById", "customer-name").Get("value").String()
		email := doc.Call("getElementById", "customer-email").Get("value").String()
		if name != "" && email != "" {
			a.CreateParty(js.Value{}, []js.Value{js.ValueOf(name), js.ValueOf(email)})
		}
		return nil
	}))
	formActions.Call("appendChild", saveBtn)

	formCard.Call("appendChild", formActions)
	container.Call("appendChild", formCard)

	// Filtered parties
	filteredParties := a.filterParties(a.SearchQuery)

	// Customers table
	table := doc.Call("createElement", "table")
	table.Set("className", "data-table")

	thead := doc.Call("createElement", "thead")
	theadRow := doc.Call("createElement", "tr")
	headers := []string{"Name", "Email", "Status", "Created", "Actions"}
	for _, h := range headers {
		th := doc.Call("createElement", "th")
		th.Set("textContent", h)
		theadRow.Call("appendChild", th)
	}
	thead.Call("appendChild", theadRow)
	table.Call("appendChild", thead)

	tbody := doc.Call("createElement", "tbody")

	for _, party := range filteredParties {
		row := doc.Call("createElement", "tr")

		nameCell := doc.Call("createElement", "td")
		nameCell.Set("className", "cell-primary")
		nameCell.Set("textContent", party.FullName)
		row.Call("appendChild", nameCell)

		emailCell := doc.Call("createElement", "td")
		emailCell.Set("textContent", party.Email)
		row.Call("appendChild", emailCell)

		statusCell := doc.Call("createElement", "td")
		statusBadge := doc.Call("createElement", "span")
		statusBadge.Set("className", "status-badge "+party.Status)
		statusBadge.Set("textContent", capitalize(party.Status))
		statusCell.Call("appendChild", statusBadge)
		row.Call("appendChild", statusCell)

		dateCell := doc.Call("createElement", "td")
		dateCell.Set("textContent", formatDate(party.CreatedAt))
		row.Call("appendChild", dateCell)

		actionsCell := doc.Call("createElement", "td")

		viewBtn := doc.Call("createElement", "button")
		viewBtn.Set("className", "btn btn-sm btn-ghost")
		viewBtn.Set("textContent", "View")
		p := party
		viewBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.SelectedParty = &p
			a.CurrentView = "accounts"
			a.ListAccounts(js.Value{}, []js.Value{js.ValueOf(p.PartyID)})
			a.Render()
			return nil
		}))
		actionsCell.Call("appendChild", viewBtn)

		if party.Status == "active" {
			actionsCell.Call("appendChild", a.createActionButton("Suspend", "warning", func() {
				a.SuspendParty(js.Value{}, []js.Value{js.ValueOf(party.PartyID)})
			}))
		}

		actionsCell.Call("appendChild", a.createActionButton("Close", "danger", func() {
			a.CloseParty(js.Value{}, []js.Value{js.ValueOf(party.PartyID)})
		}))

		row.Call("appendChild", actionsCell)
		tbody.Call("appendChild", row)
	}

	table.Call("appendChild", tbody)
	container.Call("appendChild", table)

	// Empty state
	if len(filteredParties) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state-large")
		empty.Set("textContent", "No customers found")
		container.Call("appendChild", empty)
	}

	return container
}

// renderAccountsListView renders the accounts list view
func (a *App) renderAccountsListView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "accounts-view")

	// Toolbar
	toolbar := doc.Call("createElement", "div")
	toolbar.Set("className", "view-toolbar")

	searchWrapper := doc.Call("createElement", "div")
	searchWrapper.Set("className", "search-wrapper")

	searchIcon := doc.Call("createElement", "svg")
	searchIcon.Set("className", "search-icon")
	searchIcon.Call("setAttribute", "fill", "none")
	searchIcon.Call("setAttribute", "viewBox", "0 0 24 24")
	searchIcon.Call("setAttribute", "stroke", "currentColor")
	searchIcon.Call("setAttribute", "stroke-width", "2")
	searchPath := doc.Call("createElement", "path")
	searchPath.Call("setAttribute", "stroke-linecap", "round")
	searchPath.Call("setAttribute", "stroke-linejoin", "round")
	searchPath.Set("d", "M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z")
	searchIcon.Call("appendChild", searchPath)
	searchWrapper.Call("appendChild", searchIcon)

	searchInput := doc.Call("createElement", "input")
	searchInput.Set("type", "text")
	searchInput.Set("className", "search-input")
	searchInput.Set("placeholder", "Search accounts...")
	searchInput.Set("value", a.SearchQuery)
	searchInput.Call("addEventListener", "input", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.SearchQuery = this.Get("value").String()
		a.Render()
		return nil
	}))
	searchWrapper.Call("appendChild", searchInput)
	toolbar.Call("appendChild", searchWrapper)

	container.Call("appendChild", toolbar)

	// Filter by status
	filterBar := doc.Call("createElement", "div")
	filterBar.Set("className", "filter-bar")

	statusFilters := []string{"all", "active", "frozen", "closed"}
	for _, status := range statusFilters {
		filterBtn := doc.Call("createElement", "button")
		filterBtn.Set("className", "filter-btn")
		if a.FilterStatus == status || (status == "all" && a.FilterStatus == "") {
			filterBtn.Get("classList").Call("add", "active")
		}
		filterBtn.Set("textContent", capitalize(status))
		filterStatus := status
		filterBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			if filterStatus == "all" {
				a.FilterStatus = ""
			} else {
				a.FilterStatus = filterStatus
			}
			a.Render()
			return nil
		}))
		filterBar.Call("appendChild", filterBtn)
	}

	container.Call("appendChild", filterBar)

	// Filtered accounts
	filteredAccounts := a.filterAccounts(a.SearchQuery, a.FilterStatus)

	// Accounts table
	table := doc.Call("createElement", "table")
	table.Set("className", "data-table")

	thead := doc.Call("createElement", "thead")
	theadRow := doc.Call("createElement", "tr")
	headers := []string{"Account ID", "Name", "Currency", "Balance", "Status", "Actions"}
	for _, h := range headers {
		th := doc.Call("createElement", "th")
		th.Set("textContent", h)
		theadRow.Call("appendChild", th)
	}
	thead.Call("appendChild", theadRow)
	table.Call("appendChild", thead)

	tbody := doc.Call("createElement", "tbody")

	for _, account := range filteredAccounts {
		row := doc.Call("createElement", "tr")

		idCell := doc.Call("createElement", "td")
		idCell.Set("className", "cell-mono")
		idCell.Set("textContent", truncateID(account.AccountID))
		row.Call("appendChild", idCell)

		nameCell := doc.Call("createElement", "td")
		nameCell.Set("className", "cell-primary")
		nameCell.Set("textContent", account.Name)
		row.Call("appendChild", nameCell)

		currencyCell := doc.Call("createElement", "td")
		currencyCell.Set("textContent", account.Currency)
		row.Call("appendChild", currencyCell)

		balanceCell := doc.Call("createElement", "td")
		balanceCell.Set("className", "cell-balance")
		balanceCell.Set("textContent", FormatAmount(account.Balance, account.Currency))
		row.Call("appendChild", balanceCell)

		statusCell := doc.Call("createElement", "td")
		statusBadge := doc.Call("createElement", "span")
		statusBadge.Set("className", "status-badge "+account.Status)
		statusBadge.Set("textContent", capitalize(account.Status))
		statusCell.Call("appendChild", statusBadge)
		row.Call("appendChild", statusCell)

		actionsCell := doc.Call("createElement", "td")

		viewBtn := doc.Call("createElement", "button")
		viewBtn.Set("className", "btn btn-sm btn-primary")
		viewBtn.Set("textContent", "View")
		acc := account
		viewBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.SelectedAccount = &acc
			a.CurrentView = "account-detail"
			a.GetAccountDetails(js.Value{}, []js.Value{js.ValueOf(acc.AccountID)})
			a.Render()
			return nil
		}))
		actionsCell.Call("appendChild", viewBtn)

		row.Call("appendChild", actionsCell)
		tbody.Call("appendChild", row)
	}

	table.Call("appendChild", tbody)
	container.Call("appendChild", table)

	if len(filteredAccounts) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state-large")
		empty.Set("textContent", "No accounts found")
		container.Call("appendChild", empty)
	}

	return container
}

// renderAccountDetailView renders the account detail view
func (a *App) renderAccountDetailView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "account-detail-view")

	if a.SelectedAccount == nil {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state-large")
		empty.Set("textContent", "No account selected")
		container.Call("appendChild", empty)
		return container
	}

	account := *a.SelectedAccount

	// Back button
	backBtn := doc.Call("createElement", "button")
	backBtn.Set("className", "btn btn-ghost back-btn")
	backBtn.Set("textContent", "← Back to Accounts")
	backBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.CurrentView = "accounts"
		a.SelectedAccount = nil
		a.Render()
		return nil
	}))
	container.Call("appendChild", backBtn)

	// Account header card
	headerCard := doc.Call("createElement", "div")
	headerCard.Set("className", "account-header-card")

	headerTop := doc.Call("createElement", "div")
	headerTop.Set("className", "account-header-top")

	accountName := doc.Call("createElement", "h2")
	accountName.Set("className", "account-name")
	accountName.Set("textContent", account.Name)
	headerTop.Call("appendChild", accountName)

	statusBadge := doc.Call("createElement", "span")
	statusBadge.Set("className", "status-badge-lg "+account.Status)
	statusBadge.Set("textContent", capitalize(account.Status))
	headerTop.Call("appendChild", statusBadge)

	headerCard.Call("appendChild", headerTop)

	accountID := doc.Call("createElement", "div")
	accountID.Set("className", "account-id")
	accountID.Set("textContent", "Account ID: "+account.AccountID)
	headerCard.Call("appendChild", accountID)

	headerCard.Call("appendChild", container)

	// Stats row
	statsRow := doc.Call("createElement", "div")
	statsRow.Set("className", "detail-stats")

	balanceStat := doc.Call("createElement", "div")
	balanceStat.Set("className", "detail-stat")
	balanceLabel := doc.Call("createElement", "div")
	balanceLabel.Set("className", "stat-label")
	balanceLabel.Set("textContent", "Current Balance")
	balanceStat.Call("appendChild", balanceLabel)
	balanceValue := doc.Call("createElement", "div")
	balanceValue.Set("className", "stat-value-lg")
	balanceValue.Set("textContent", FormatAmount(account.Balance, account.Currency))
	balanceStat.Call("appendChild", balanceValue)
	statsRow.Call("appendChild", balanceStat)

	currencyStat := doc.Call("createElement", "div")
	currencyStat.Set("className", "detail-stat")
	currencyLabel := doc.Call("createElement", "div")
	currencyLabel.Set("className", "stat-label")
	currencyLabel.Set("textContent", "Currency")
	currencyStat.Call("appendChild", currencyLabel)
	currencyValue := doc.Call("createElement", "div")
	currencyValue.Set("className", "stat-value")
	currencyValue.Set("textContent", account.Currency)
	currencyStat.Call("appendChild", currencyValue)
	statsRow.Call("appendChild", currencyStat)

	createdStat := doc.Call("createElement", "div")
	createdStat.Set("className", "detail-stat")
	createdLabel := doc.Call("createElement", "div")
	createdLabel.Set("className", "stat-label")
	createdLabel.Set("textContent", "Created")
	createdStat.Call("appendChild", createdLabel)
	createdValue := doc.Call("createElement", "div")
	createdValue.Set("className", "stat-value")
	createdValue.Set("textContent", formatDate(account.CreatedAt))
	createdStat.Call("appendChild", createdValue)
	statsRow.Call("appendChild", createdStat)

	container.Call("appendChild", statsRow)

	// Action buttons
	actionsRow := doc.Call("createElement", "div")
	actionsRow.Set("className", "account-actions")

	if account.Status == "active" {
		freezeBtn := doc.Call("createElement", "button")
		freezeBtn.Set("className", "btn btn-warning")
		freezeBtn.Set("textContent", "Freeze Account")
		freezeBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.FreezeAccount(js.Value{}, []js.Value{js.ValueOf(account.AccountID)})
			return nil
		}))
		actionsRow.Call("appendChild", freezeBtn)
	}

	if account.Status == "frozen" {
		unfreezeBtn := doc.Call("createElement", "button")
		unfreezeBtn.Set("className", "btn btn-success")
		unfreezeBtn.Set("textContent", "Unfreeze Account")
		unfreezeBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.UnfreezeAccount(js.Value{}, []js.Value{js.ValueOf(account.AccountID)})
			return nil
		}))
		actionsRow.Call("appendChild", unfreezeBtn)
	}

	closeBtn := doc.Call("createElement", "button")
	closeBtn.Set("className", "btn btn-danger")
	closeBtn.Set("textContent", "Close Account")
	closeBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.CloseAccount(js.Value{}, []js.Value{js.ValueOf(account.AccountID)})
		return nil
	}))
	actionsRow.Call("appendChild", closeBtn)

	container.Call("appendChild", actionsRow)

	// Recent Transactions
	txnSection := doc.Call("createElement", "div")
	txnSection.Set("className", "detail-section")

	txnTitle := doc.Call("createElement", "h3")
	txnTitle.Set("textContent", "Recent Transactions")
	txnSection.Call("appendChild", txnTitle)

	if len(a.Transactions) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state")
		empty.Set("textContent", "No transactions yet")
		txnSection.Call("appendChild", empty)
	} else {
		txnTable := doc.Call("createElement", "table")
		txnTable.Set("className", "data-table")

		txnThead := doc.Call("createElement", "thead")
		txnTheadRow := doc.Call("createElement", "tr")
		txnHeaders := []string{"Date", "Type", "Description", "Amount", "Status"}
		for _, h := range txnHeaders {
			th := doc.Call("createElement", "th")
			th.Set("textContent", h)
			txnTheadRow.Call("appendChild", th)
		}
		txnThead.Call("appendChild", txnTheadRow)
		txnTable.Call("appendChild", txnThead)

		txnTbody := doc.Call("createElement", "tbody")

		for _, txn := range a.Transactions {
			txnRow := doc.Call("createElement", "tr")

			dateCell := doc.Call("createElement", "td")
			dateCell.Set("textContent", formatTimestamp(txn.CreatedAt))
			txnRow.Call("appendChild", dateCell)

			typeCell := doc.Call("createElement", "td")
			typeBadge := doc.Call("createElement", "span")
			typeBadge.Set("className", "type-badge "+txn.TxnType)
			typeBadge.Set("textContent", capitalize(txn.TxnType))
			typeCell.Call("appendChild", typeBadge)
			txnRow.Call("appendChild", typeCell)

			descCell := doc.Call("createElement", "td")
			descCell.Set("textContent", txn.Description)
			txnRow.Call("appendChild", descCell)

			amountCell := doc.Call("createElement", "td")
			amountCell.Set("className", "cell-balance")
			amountCell.Set("textContent", FormatAmount(txn.Amount, txn.Currency))
			txnRow.Call("appendChild", amountCell)

			statusCell := doc.Call("createElement", "td")
			statusBadge := doc.Call("createElement", "span")
			statusBadge.Set("className", "status-badge "+txn.Status)
			statusBadge.Set("textContent", capitalize(txn.Status))
			statusCell.Call("appendChild", statusBadge)
			txnRow.Call("appendChild", statusCell)

			txnTbody.Call("appendChild", txnRow)
		}

		txnTable.Call("appendChild", txnTbody)
		txnSection.Call("appendChild", txnTable)
	}

	container.Call("appendChild", txnSection)

	return container
}

// renderTransactionsListView renders the transactions list view
func (a *App) renderTransactionsListView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "transactions-view")

	// Toolbar
	toolbar := doc.Call("createElement", "div")
	toolbar.Set("className", "view-toolbar")

	searchWrapper := doc.Call("createElement", "div")
	searchWrapper.Set("className", "search-wrapper")

	searchIcon := doc.Call("createElement", "svg")
	searchIcon.Set("className", "search-icon")
	searchIcon.Call("setAttribute", "fill", "none")
	searchIcon.Call("setAttribute", "viewBox", "0 0 24 24")
	searchIcon.Call("setAttribute", "stroke", "currentColor")
	searchIcon.Call("setAttribute", "stroke-width", "2")
	searchPath := doc.Call("createElement", "path")
	searchPath.Call("setAttribute", "stroke-linecap", "round")
	searchPath.Call("setAttribute", "stroke-linejoin", "round")
	searchPath.Set("d", "M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z")
	searchIcon.Call("appendChild", searchPath)
	searchWrapper.Call("appendChild", searchIcon)

	searchInput := doc.Call("createElement", "input")
	searchInput.Set("type", "text")
	searchInput.Set("className", "search-input")
	searchInput.Set("placeholder", "Search transactions...")
	searchInput.Set("value", a.SearchQuery)
	searchInput.Call("addEventListener", "input", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.SearchQuery = this.Get("value").String()
		a.Render()
		return nil
	}))
	searchWrapper.Call("appendChild", searchInput)
	toolbar.Call("appendChild", searchWrapper)

	container.Call("appendChild", toolbar)

	// Filter by status
	filterBar := doc.Call("createElement", "div")
	filterBar.Set("className", "filter-bar")

	statusFilters := []string{"all", "pending", "posted", "failed"}
	for _, status := range statusFilters {
		filterBtn := doc.Call("createElement", "button")
		filterBtn.Set("className", "filter-btn")
		if a.FilterStatus == status || (status == "all" && a.FilterStatus == "") {
			filterBtn.Get("classList").Call("add", "active")
		}
		filterBtn.Set("textContent", capitalize(status))
		filterStatus := status
		filterBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			if filterStatus == "all" {
				a.FilterStatus = ""
			} else {
				a.FilterStatus = filterStatus
			}
			a.Render()
			return nil
		}))
		filterBar.Call("appendChild", filterBtn)
	}

	container.Call("appendChild", filterBar)

	// Transactions table
	table := doc.Call("createElement", "table")
	table.Set("className", "data-table")

	thead := doc.Call("createElement", "thead")
	theadRow := doc.Call("createElement", "tr")
	headers := []string{"ID", "Date", "Type", "Description", "Amount", "Status", "Actions"}
	for _, h := range headers {
		th := doc.Call("createElement", "th")
		th.Set("textContent", h)
		theadRow.Call("appendChild", th)
	}
	thead.Call("appendChild", theadRow)
	table.Call("appendChild", thead)

	filteredTxns := a.filterTransactions(a.SearchQuery, a.FilterStatus)

	tbody := doc.Call("createElement", "tbody")

	for _, txn := range filteredTxns {
		row := doc.Call("createElement", "tr")

		idCell := doc.Call("createElement", "td")
		idCell.Set("className", "cell-mono")
		idCell.Set("textContent", truncateID(txn.TxnID))
		row.Call("appendChild", idCell)

		dateCell := doc.Call("createElement", "td")
		dateCell.Set("textContent", formatTimestamp(txn.CreatedAt))
		row.Call("appendChild", dateCell)

		typeCell := doc.Call("createElement", "td")
		typeBadge := doc.Call("createElement", "span")
		typeBadge.Set("className", "type-badge "+txn.TxnType)
		typeBadge.Set("textContent", capitalize(txn.TxnType))
		typeCell.Call("appendChild", typeBadge)
		row.Call("appendChild", typeCell)

		descCell := doc.Call("createElement", "td")
		descCell.Set("textContent", txn.Description)
		row.Call("appendChild", descCell)

		amountCell := doc.Call("createElement", "td")
		amountCell.Set("className", "cell-balance")
		amountCell.Set("textContent", FormatAmount(txn.Amount, txn.Currency))
		row.Call("appendChild", amountCell)

		statusCell := doc.Call("createElement", "td")
		statusBadge := doc.Call("createElement", "span")
		statusBadge.Set("className", "status-badge "+txn.Status)
		statusBadge.Set("textContent", capitalize(txn.Status))
		statusCell.Call("appendChild", statusBadge)
		row.Call("appendChild", statusCell)

		actionsCell := doc.Call("createElement", "td")

		if txn.Status == "posted" {
			reverseBtn := doc.Call("createElement", "button")
			reverseBtn.Set("className", "btn btn-sm btn-warning")
			reverseBtn.Set("textContent", "Reverse")
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

	if len(filteredTxns) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state-large")
		empty.Set("textContent", "No transactions found")
		container.Call("appendChild", empty)
	}

	return container
}

// renderLedgerView renders the ledger view
func (a *App) renderLedgerView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "ledger-view")

	header := doc.Call("createElement", "div")
	header.Set("className", "section-header")

	title := doc.Call("createElement", "h3")
	title.Set("textContent", "Ledger Entries")
	header.Call("appendChild", title)

	container.Call("appendChild", header)

	// Filter
	filterCard := doc.Call("createElement", "div")
	filterCard.Set("className", "filter-card")

	filterLabel := doc.Call("createElement", "label")
	filterLabel.Set("textContent", "Filter by Account ID:")
	filterCard.Call("appendChild", filterLabel)

	filterInput := doc.Call("createElement", "input")
	filterInput.Set("type", "text")
	filterInput.Set("id", "ledger-account-filter")
	filterInput.Set("className", "form-input")
	filterInput.Set("placeholder", "Enter account ID")
	filterInput.Set("value", a.FilterAccountID)
	filterCard.Call("appendChild", filterInput)

	filterBtn := doc.Call("createElement", "button")
	filterBtn.Set("className", "btn btn-primary")
	filterBtn.Set("textContent", "Filter")
	filterBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		accountID := doc.Call("getElementById", "ledger-account-filter").Get("value").String()
		a.FilterAccountID = accountID
		if accountID != "" {
			a.GetLedgerEntries(js.Value{}, []js.Value{js.ValueOf(accountID)})
		}
		a.Render()
		return nil
	}))
	filterCard.Call("appendChild", filterBtn)

	container.Call("appendChild", filterCard)

	// Ledger entries table
	if len(a.LedgerEntries) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state-large")
		empty.Set("textContent", "Select an account to view ledger entries")
		container.Call("appendChild", empty)
	} else {
		table := doc.Call("createElement", "table")
		table.Set("className", "data-table")

		thead := doc.Call("createElement", "thead")
		theadRow := doc.Call("createElement", "tr")
		headers := []string{"Entry ID", "Transaction ID", "Account ID", "Type", "Amount", "Description", "Posted At"}
		for _, h := range headers {
			th := doc.Call("createElement", "th")
			th.Set("textContent", h)
			theadRow.Call("appendChild", th)
		}
		thead.Call("appendChild", theadRow)
		table.Call("appendChild", thead)

		tbody := doc.Call("createElement", "tbody")

		for _, entry := range a.LedgerEntries {
			row := doc.Call("createElement", "tr")

			entryCell := doc.Call("createElement", "td")
			entryCell.Set("className", "cell-mono")
			entryCell.Set("textContent", truncateID(entry.EntryID))
			row.Call("appendChild", entryCell)

			txnCell := doc.Call("createElement", "td")
			txnCell.Set("className", "cell-mono")
			txnCell.Set("textContent", truncateID(entry.TxnID))
			row.Call("appendChild", txnCell)

			accountCell := doc.Call("createElement", "td")
			accountCell.Set("className", "cell-mono")
			accountCell.Set("textContent", truncateID(entry.AccountID))
			row.Call("appendChild", accountCell)

			typeCell := doc.Call("createElement", "td")
			typeBadge := doc.Call("createElement", "span")
			typeBadge.Set("className", "type-badge "+entry.EntryType)
			typeBadge.Set("textContent", capitalize(entry.EntryType))
			typeCell.Call("appendChild", typeBadge)
			row.Call("appendChild", typeCell)

			amountCell := doc.Call("createElement", "td")
			amountCell.Set("className", "cell-balance")
			amountCell.Set("textContent", FormatAmount(entry.Amount, entry.Currency))
			row.Call("appendChild", amountCell)

			descCell := doc.Call("createElement", "td")
			descCell.Set("textContent", entry.Description)
			row.Call("appendChild", descCell)

			dateCell := doc.Call("createElement", "td")
			dateCell.Set("textContent", formatTimestamp(entry.PostedAt))
			row.Call("appendChild", dateCell)

			tbody.Call("appendChild", row)
		}

		table.Call("appendChild", tbody)
		container.Call("appendChild", table)
	}

	return container
}

// renderSettingsView renders the settings view
func (a *App) renderSettingsView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "settings-view")

	title := doc.Call("createElement", "h2")
	title.Set("textContent", "Settings")
	container.Call("appendChild", title)

	settingsCard := doc.Call("createElement", "div")
	settingsCard.Set("className", "settings-card")

	settingItem := doc.Call("createElement", "div")
	settingItem.Set("className", "setting-item")

	settingLabel := doc.Call("createElement", "div")
	settingLabel.Set("className", "setting-label")
	labelTitle := doc.Call("createElement", "h4")
	labelTitle.Set("textContent", "API Endpoint")
	settingLabel.Call("appendChild", labelTitle)
	labelDesc := doc.Call("createElement", "p")
	labelDesc.Set("textContent", "The backend API URL")
	settingLabel.Call("appendChild", labelDesc)
	settingItem.Call("appendChild", settingLabel)

	settingValue := doc.Call("createElement", "div")
	settingValue.Set("className", "setting-value")
	endpoint := doc.Call("createElement", "code")
	endpoint.Set("textContent", apiBaseURL)
	settingValue.Call("appendChild", endpoint)
	settingItem.Call("appendChild", settingValue)

	settingsCard.Call("appendChild", settingItem)

	settingItem2 := doc.Call("createElement", "div")
	settingItem2.Set("className", "setting-item")

	settingLabel2 := doc.Call("createElement", "div")
	settingLabel2.Set("className", "setting-label")
	labelTitle2 := doc.Call("createElement", "h4")
	labelTitle2.Set("textContent", "Application Version")
	settingLabel2.Call("appendChild", labelTitle2)
	labelDesc2 := doc.Call("createElement", "p")
	labelDesc2.Set("textContent", "Current dashboard version")
	settingLabel2.Call("appendChild", labelDesc2)
	settingItem2.Call("appendChild", settingLabel2)

	settingValue2 := doc.Call("createElement", "div")
	settingValue2.Set("className", "setting-value")
	version := doc.Call("createElement", "span")
	version.Set("textContent", "1.0.0")
	settingValue2.Call("appendChild", version)
	settingItem2.Call("appendChild", settingValue2)

	settingsCard.Call("appendChild", settingItem2)

	container.Call("appendChild", settingsCard)

	return container
}

// renderTransferView renders the transfer form
func (a *App) renderTransferView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "transfer-view")

	backBtn := doc.Call("createElement", "button")
	backBtn.Set("className", "btn btn-ghost back-btn")
	backBtn.Set("textContent", "← Back")
	backBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.CurrentView = "dashboard"
		a.Render()
		return nil
	}))
	container.Call("appendChild", backBtn)

	header := doc.Call("createElement", "h2")
	header.Set("textContent", "Transfer Funds")
	container.Call("appendChild", header)

	form := doc.Call("createElement", "div")
	form.Set("className", "form-card")

	formGrid := doc.Call("createElement", "div")
	formGrid.Set("className", "form-grid")

	sourceLabel := doc.Call("createElement", "label")
	sourceLabel.Set("textContent", "Source Account ID")
	formGrid.Call("appendChild", sourceLabel)

	sourceInput := doc.Call("createElement", "input")
	sourceInput.Set("type", "text")
	sourceInput.Set("id", "transfer-source")
	sourceInput.Set("className", "form-input")
	sourceInput.Set("placeholder", "Enter source account ID")
	formGrid.Call("appendChild", sourceInput)

	destLabel := doc.Call("createElement", "label")
	destLabel.Set("textContent", "Destination Account ID")
	formGrid.Call("appendChild", destLabel)

	destInput := doc.Call("createElement", "input")
	destInput.Set("type", "text")
	destInput.Set("id", "transfer-dest")
	destInput.Set("className", "form-input")
	destInput.Set("placeholder", "Enter destination account ID")
	formGrid.Call("appendChild", destInput)

	amountLabel := doc.Call("createElement", "label")
	amountLabel.Set("textContent", "Amount")
	formGrid.Call("appendChild", amountLabel)

	amountInput := doc.Call("createElement", "input")
	amountInput.Set("type", "text")
	amountInput.Set("id", "transfer-amount")
	amountInput.Set("className", "form-input")
	amountInput.Set("placeholder", "Enter amount (e.g., 100.00)")
	formGrid.Call("appendChild", amountInput)

	currencyLabel := doc.Call("createElement", "label")
	currencyLabel.Set("textContent", "Currency")
	formGrid.Call("appendChild", currencyLabel)

	currencySelect := doc.Call("createElement", "select")
	currencySelect.Set("id", "transfer-currency")
	currencySelect.Set("className", "form-select")
	currencies := []string{"USD", "EUR", "GBP", "JPY", "CHF"}
	for _, c := range currencies {
		option := doc.Call("createElement", "option")
		option.Set("value", c)
		option.Set("textContent", c)
		currencySelect.Call("appendChild", option)
	}
	formGrid.Call("appendChild", currencySelect)

	descLabel := doc.Call("createElement", "label")
	descLabel.Set("textContent", "Description")
	formGrid.Call("appendChild", descLabel)

	descInput := doc.Call("createElement", "input")
	descInput.Set("type", "text")
	descInput.Set("id", "transfer-desc")
	descInput.Set("className", "form-input")
	descInput.Set("placeholder", "Enter description")
	formGrid.Call("appendChild", descInput)

	form.Call("appendChild", formGrid)

	submitBtn := doc.Call("createElement", "button")
	submitBtn.Set("className", "btn btn-primary btn-lg")
	submitBtn.Set("textContent", "Transfer Funds")
	submitBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
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
	form.Call("appendChild", submitBtn)

	container.Call("appendChild", form)
	return container
}

// renderDepositView renders the deposit/withdrawal form
func (a *App) renderDepositView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "deposit-view")

	backBtn := doc.Call("createElement", "button")
	backBtn.Set("className", "btn btn-ghost back-btn")
	backBtn.Set("textContent", "← Back")
	backBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.CurrentView = "dashboard"
		a.Render()
		return nil
	}))
	container.Call("appendChild", backBtn)

	header := doc.Call("createElement", "h2")
	header.Set("textContent", "Deposit / Withdraw")
	container.Call("appendChild", header)

	twoCol := doc.Call("createElement", "div")
	twoCol.Set("className", "two-col-forms")

	// Deposit form
	depositCard := doc.Call("createElement", "div")
	depositCard.Set("className", "form-card")

	depositTitle := doc.Call("createElement", "h3")
	depositTitle.Set("textContent", "Deposit")
	depositCard.Call("appendChild", depositTitle)

	depositForm := doc.Call("createElement", "div")
	depositForm.Set("className", "form-stack")

	accountLabel1 := doc.Call("createElement", "label")
	accountLabel1.Set("textContent", "Account ID")
	depositForm.Call("appendChild", accountLabel1)

	accountInput1 := doc.Call("createElement", "input")
	accountInput1.Set("type", "text")
	accountInput1.Set("id", "deposit-account")
	accountInput1.Set("className", "form-input")
	accountInput1.Set("placeholder", "Enter account ID")
	depositForm.Call("appendChild", accountInput1)

	amountLabel1 := doc.Call("createElement", "label")
	amountLabel1.Set("textContent", "Amount")
	depositForm.Call("appendChild", amountLabel1)

	amountInput1 := doc.Call("createElement", "input")
	amountInput1.Set("type", "text")
	amountInput1.Set("id", "deposit-amount")
	amountInput1.Set("className", "form-input")
	amountInput1.Set("placeholder", "Enter amount")
	depositForm.Call("appendChild", amountInput1)

	currencyLabel1 := doc.Call("createElement", "label")
	currencyLabel1.Set("textContent", "Currency")
	depositForm.Call("appendChild", currencyLabel1)

	currencySelect1 := doc.Call("createElement", "select")
	currencySelect1.Set("id", "deposit-currency")
	currencySelect1.Set("className", "form-select")
	for _, c := range []string{"USD", "EUR", "GBP", "JPY", "CHF"} {
		option := doc.Call("createElement", "option")
		option.Set("value", c)
		option.Set("textContent", c)
		currencySelect1.Call("appendChild", option)
	}
	depositForm.Call("appendChild", currencySelect1)

	descLabel1 := doc.Call("createElement", "label")
	descLabel1.Set("textContent", "Description")
	depositForm.Call("appendChild", descLabel1)

	descInput1 := doc.Call("createElement", "input")
	descInput1.Set("type", "text")
	descInput1.Set("id", "deposit-desc")
	descInput1.Set("className", "form-input")
	descInput1.Set("placeholder", "Enter description")
	depositForm.Call("appendChild", descInput1)

	depositBtn := doc.Call("createElement", "button")
	depositBtn.Set("className", "btn btn-success btn-lg")
	depositBtn.Set("textContent", "Deposit")
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
	depositForm.Call("appendChild", depositBtn)

	depositCard.Call("appendChild", depositForm)
	twoCol.Call("appendChild", depositCard)

	// Withdrawal form
	withdrawCard := doc.Call("createElement", "div")
	withdrawCard.Set("className", "form-card")

	withdrawTitle := doc.Call("createElement", "h3")
	withdrawTitle.Set("textContent", "Withdraw")
	withdrawCard.Call("appendChild", withdrawTitle)

	withdrawForm := doc.Call("createElement", "div")
	withdrawForm.Set("className", "form-stack")

	accountLabel2 := doc.Call("createElement", "label")
	accountLabel2.Set("textContent", "Account ID")
	withdrawForm.Call("appendChild", accountLabel2)

	accountInput2 := doc.Call("createElement", "input")
	accountInput2.Set("type", "text")
	accountInput2.Set("id", "withdraw-account")
	accountInput2.Set("className", "form-input")
	accountInput2.Set("placeholder", "Enter account ID")
	withdrawForm.Call("appendChild", accountInput2)

	amountLabel2 := doc.Call("createElement", "label")
	amountLabel2.Set("textContent", "Amount")
	withdrawForm.Call("appendChild", amountLabel2)

	amountInput2 := doc.Call("createElement", "input")
	amountInput2.Set("type", "text")
	amountInput2.Set("id", "withdraw-amount")
	amountInput2.Set("className", "form-input")
	amountInput2.Set("placeholder", "Enter amount")
	withdrawForm.Call("appendChild", amountInput2)

	currencyLabel2 := doc.Call("createElement", "label")
	currencyLabel2.Set("textContent", "Currency")
	withdrawForm.Call("appendChild", currencyLabel2)

	currencySelect2 := doc.Call("createElement", "select")
	currencySelect2.Set("id", "withdraw-currency")
	currencySelect2.Set("className", "form-select")
	for _, c := range []string{"USD", "EUR", "GBP", "JPY", "CHF"} {
		option := doc.Call("createElement", "option")
		option.Set("value", c)
		option.Set("textContent", c)
		currencySelect2.Call("appendChild", option)
	}
	withdrawForm.Call("appendChild", currencySelect2)

	descLabel2 := doc.Call("createElement", "label")
	descLabel2.Set("textContent", "Description")
	withdrawForm.Call("appendChild", descLabel2)

	descInput2 := doc.Call("createElement", "input")
	descInput2.Set("type", "text")
	descInput2.Set("id", "withdraw-desc")
	descInput2.Set("className", "form-input")
	descInput2.Set("placeholder", "Enter description")
	withdrawForm.Call("appendChild", descInput2)

	withdrawBtn := doc.Call("createElement", "button")
	withdrawBtn.Set("className", "btn btn-warning btn-lg")
	withdrawBtn.Set("textContent", "Withdraw")
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
	withdrawForm.Call("appendChild", withdrawBtn)

	withdrawCard.Call("appendChild", withdrawForm)
	twoCol.Call("appendChild", withdrawCard)

	container.Call("appendChild", twoCol)

	return container
}

// Helper functions
func (a *App) createActionButton(label string, color string, action func()) js.Value {
	doc := js.Global().Get("document")
	btn := doc.Call("createElement", "button")
	btn.Set("className", "btn btn-sm btn-"+color)
	btn.Set("textContent", label)
	btn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		action()
		return nil
	}))
	return btn
}

func (a *App) filterParties(query string) []Party {
	if query == "" {
		return a.Parties
	}
	var filtered []Party
	lowerQuery := toLower(query)
	for _, p := range a.Parties {
		if contains(toLower(p.FullName), lowerQuery) || contains(toLower(p.Email), lowerQuery) {
			filtered = append(filtered, p)
		}
	}
	return filtered
}

func (a *App) filterAccounts(query string, status string) []Account {
	var filtered []Account
	for _, acc := range a.Accounts {
		if status != "" && acc.Status != status {
			continue
		}
		if query == "" {
			filtered = append(filtered, acc)
		} else {
			lowerQuery := toLower(query)
			if contains(toLower(acc.Name), lowerQuery) || contains(acc.AccountID, lowerQuery) {
				filtered = append(filtered, acc)
			}
		}
	}
	return filtered
}

func (a *App) filterTransactions(query string, status string) []Transaction {
	var filtered []Transaction
	for _, txn := range a.Transactions {
		if status != "" && txn.Status != status {
			continue
		}
		if query == "" {
			filtered = append(filtered, txn)
		} else {
			lowerQuery := toLower(query)
			if contains(toLower(txn.TxnType), lowerQuery) || contains(toLower(txn.Description), lowerQuery) || contains(txn.TxnID, lowerQuery) {
				filtered = append(filtered, txn)
			}
		}
	}
	return filtered
}

func toLower(s string) string {
	result := make([]byte, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 32
		}
		result[i] = c
	}
	return string(result)
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func truncateID(id string) string {
	if len(id) > 12 {
		return id[:8] + "..." + id[len(id)-4:]
	}
	return id
}

func formatNumber(n int) string {
	if n == 0 {
		return "0"
	}
	var result string
	for n > 0 {
		digit := n % 10
		result = string('0'+digit) + result
		n /= 10
	}
	return result
}

func formatTimestamp(ts int64) string {
	if ts == 0 {
		return "-"
	}
	t := time.Unix(ts/1000, 0)
	return t.Format("2006-01-02 15:04:05")
}

func formatDate(ts int64) string {
	if ts == 0 {
		return "-"
	}
	t := time.Unix(ts/1000, 0)
	return t.Format("2006-01-02")
}
