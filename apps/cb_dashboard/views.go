package main

import (
	"fmt"
	"strconv"
	"syscall/js"
	"time"
)

// renderDashboardHome renders the dashboard home view (Baseella-inspired layout)
func (a *App) renderDashboardHome() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "dashboard-view")

	// ── Stat strip: 4 slim metric cards ──────────────────────────────
	strip := doc.Call("createElement", "div")
	strip.Set("className", "stat-strip")

	type statCard struct {
		label string
		value string
		icon  string
		color string
	}
	statsData := []statCard{
		{"Total Customers", formatNumber(a.Stats.TotalCustomers), "group", "blue"},
		{"Total Accounts", formatNumber(a.Stats.TotalAccounts), "account_balance", "green"},
		{"Portfolio Balance", FormatAmount(a.Stats.TotalBalance, "USD"), "payments", "orange"},
		{"Today's Transactions", formatNumber(a.Stats.TodayTxns), "receipt_long", "amber"},
	}

	for _, s := range statsData {
		card := doc.Call("createElement", "div")
		card.Set("className", "stat-strip-card")

		iconWrap := doc.Call("createElement", "div")
		iconWrap.Set("className", "stat-strip-icon "+s.color)
		iconWrap.Call("appendChild", createMaterialIcon(doc, s.icon, "icon"))
		card.Call("appendChild", iconWrap)

		body := doc.Call("createElement", "div")
		body.Set("className", "stat-strip-body")

		valEl := doc.Call("createElement", "div")
		valEl.Set("className", "stat-strip-value")
		valEl.Set("textContent", s.value)
		body.Call("appendChild", valEl)

		lblEl := doc.Call("createElement", "div")
		lblEl.Set("className", "stat-strip-label")
		lblEl.Set("textContent", s.label)
		body.Call("appendChild", lblEl)

		card.Call("appendChild", body)
		strip.Call("appendChild", card)
	}
	container.Call("appendChild", strip)

	// ── Two-column section grid ───────────────────────────────────────
	grid := doc.Call("createElement", "div")
	grid.Set("className", "dashboard-section-grid")

	// ── Left: Recent Activity ─────────────────────────────────────────
	activitySection := doc.Call("createElement", "div")
	activitySection.Set("className", "metric-section")

	actHdr := doc.Call("createElement", "div")
	actHdr.Set("className", "section-header")

	actHdrLeft := doc.Call("createElement", "div")
	actHdrLeft.Set("className", "section-header-left")
	actIcon := doc.Call("createElement", "div")
	actIcon.Set("className", "section-icon")
	actIcon.Call("appendChild", createMaterialIcon(doc, "receipt_long", ""))
	actIcon.Get("firstChild").Set("style", "font-size:14px; line-height:30px;")
	actHdrLeft.Call("appendChild", actIcon)
	actTitle := doc.Call("createElement", "h3")
	actTitle.Set("className", "section-title")
	actTitle.Set("textContent", "Recent Activity")
	actHdrLeft.Call("appendChild", actTitle)
	actHdr.Call("appendChild", actHdrLeft)

	viewAllBtn := doc.Call("createElement", "button")
	viewAllBtn.Set("className", "section-link")
	viewAllBtn.Set("textContent", "View all ↗")
	viewAllBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.CurrentView = "transactions"
		a.ListAllTransactions(js.Value{}, nil)
		a.Render()
		return nil
	}))
	actHdr.Call("appendChild", viewAllBtn)
	activitySection.Call("appendChild", actHdr)

	actList := doc.Call("createElement", "div")
	if len(a.RecentActivity) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state")
		empty.Set("textContent", "No recent activity")
		actList.Call("appendChild", empty)
	} else {
		for _, item := range a.RecentActivity {
			row := doc.Call("createElement", "div")
			row.Set("className", "activity-row")

			isCredit := item.Type == "deposit" || item.Type == "credit"
			dotClass := "neutral"
			amtClass := ""
			if isCredit {
				dotClass = "credit"
				amtClass = "credit"
			} else if item.Type == "withdrawal" || item.Type == "debit" {
				dotClass = "debit"
				amtClass = "debit"
			}

			dot := doc.Call("createElement", "div")
			dot.Set("className", "activity-dot "+dotClass)
			row.Call("appendChild", dot)

			desc := doc.Call("createElement", "div")
			desc.Set("className", "activity-row-desc")
			desc.Set("textContent", item.Description)
			row.Call("appendChild", desc)

			meta := doc.Call("createElement", "div")
			meta.Set("className", "activity-row-meta")
			meta.Set("textContent", formatTimestamp(item.Timestamp))
			row.Call("appendChild", meta)

			amt := doc.Call("createElement", "div")
			amt.Set("className", "activity-row-amount "+amtClass)
			prefix := ""
			if isCredit {
				prefix = "+"
			}
			amt.Set("textContent", prefix+FormatAmount(item.Amount, item.Currency))
			row.Call("appendChild", amt)

			actList.Call("appendChild", row)
		}
	}
	activitySection.Call("appendChild", actList)
	grid.Call("appendChild", activitySection)

	// ── Right: Overview metrics + quick-navigate ──────────────────────
	overviewSection := doc.Call("createElement", "div")
	overviewSection.Set("className", "metric-section")

	ovHdr := doc.Call("createElement", "div")
	ovHdr.Set("className", "section-header")
	ovHdrLeft := doc.Call("createElement", "div")
	ovHdrLeft.Set("className", "section-header-left")
	ovIcon := doc.Call("createElement", "div")
	ovIcon.Set("className", "section-icon")
	ovIcon.Call("appendChild", createMaterialIcon(doc, "bar_chart", ""))
	ovIcon.Get("firstChild").Set("style", "font-size:14px; line-height:30px;")
	ovHdrLeft.Call("appendChild", ovIcon)
	ovTitle := doc.Call("createElement", "h3")
	ovTitle.Set("className", "section-title")
	ovTitle.Set("textContent", "Overview")
	ovHdrLeft.Call("appendChild", ovTitle)
	ovHdr.Call("appendChild", ovHdrLeft)
	overviewSection.Call("appendChild", ovHdr)

	// Metric rows
	type metricRow struct {
		label string
		value string
		delta string
	}
	metrics := []metricRow{
		{"Customers", formatNumber(a.Stats.TotalCustomers), ""},
		{"Active Accounts", formatNumber(a.Stats.TotalAccounts), ""},
		{"Portfolio Balance", FormatAmount(a.Stats.TotalBalance, "USD"), ""},
		{"Transactions Today", formatNumber(a.Stats.TodayTxns), ""},
	}

	for _, m := range metrics {
		row := doc.Call("createElement", "div")
		row.Set("className", "metric-row")

		lbl := doc.Call("createElement", "div")
		lbl.Set("className", "metric-label")
		lbl.Set("textContent", m.label)
		row.Call("appendChild", lbl)

		valGroup := doc.Call("createElement", "div")
		valGroup.Set("className", "metric-value-group")

		val := doc.Call("createElement", "div")
		val.Set("className", "metric-value")
		val.Set("textContent", m.value)
		valGroup.Call("appendChild", val)

		if m.delta != "" {
			delta := doc.Call("createElement", "div")
			delta.Set("className", "metric-delta positive")
			delta.Set("textContent", m.delta)
			valGroup.Call("appendChild", delta)
		}

		row.Call("appendChild", valGroup)
		overviewSection.Call("appendChild", row)
	}

	// Navigate shortcuts
	navHdr := doc.Call("createElement", "div")
	navHdr.Set("style", "margin-top: 16px; padding-top: 14px; border-top: 1px solid var(--color-border-light);")
	navLabel := doc.Call("createElement", "div")
	navLabel.Set("style", "font-size: 0.72rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: var(--color-text-muted); margin-bottom: 10px;")
	navLabel.Set("textContent", "Quick Navigate")
	navHdr.Call("appendChild", navLabel)

	shortcuts := []struct {
		label string
		view  string
		icon  string
	}{
		{"Customers", "customers", "group"},
		{"Accounts", "accounts", "account_balance"},
		{"Products", "products", "inventory_2"},
		{"Loans", "loans", "request_quote"},
	}

	shortcutGrid := doc.Call("createElement", "div")
	shortcutGrid.Set("style", "display: grid; grid-template-columns: 1fr 1fr; gap: 6px;")

	for _, sc := range shortcuts {
		scBtn := doc.Call("createElement", "button")
		scBtn.Set("style", "display: flex; align-items: center; gap: 6px; padding: 8px 10px; background: var(--color-border-light); border: 1px solid var(--color-border); border-radius: 8px; font-size: 0.82rem; font-weight: 500; color: var(--color-text-secondary); cursor: pointer; transition: all 120ms;")
		scBtn.Set("onmouseover", "this.style.borderColor='var(--color-primary)'; this.style.color='var(--color-primary)';")
		scBtn.Set("onmouseout", "this.style.borderColor='var(--color-border)'; this.style.color='var(--color-text-secondary)';")

		scBtn.Call("appendChild", createMaterialIcon(doc, sc.icon, ""))
		scBtn.Get("firstChild").Set("style", "font-size: 15px;")

		scLabel := doc.Call("createElement", "span")
		scLabel.Set("textContent", sc.label)
		scBtn.Call("appendChild", scLabel)

		viewName := sc.view
		scBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.CurrentView = viewName
			a.Error = ""
			a.Success = ""
			if viewName == "customers" {
				a.ListParties(js.Value{}, nil)
			} else if viewName == "accounts" {
				a.ListParties(js.Value{}, nil)
				a.ListAllAccounts(js.Value{}, nil)
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
		shortcutGrid.Call("appendChild", scBtn)
	}

	navHdr.Call("appendChild", shortcutGrid)
	overviewSection.Call("appendChild", navHdr)

	grid.Call("appendChild", overviewSection)
	container.Call("appendChild", grid)

	return container
}

// renderCustomersView renders the customers list view with search
func (a *App) renderCustomersView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "customers-view")

	// ── Search & Filter Panel ─────────────────────────────────────────
	filterPanel := doc.Call("createElement", "div")
	filterPanel.Set("className", "customers-filter-panel")

	filterPanelHeader := doc.Call("createElement", "div")
	filterPanelHeader.Set("className", "customers-filter-header")

	filterTitle := doc.Call("createElement", "div")
	filterTitle.Set("className", "customers-filter-title")
	filterTitle.Call("appendChild", createMaterialIcon(doc, "search", ""))
	filterTitle.Get("lastChild").Set("style", "font-size: 16px; color: var(--color-text-muted);")
	filterTitleText := doc.Call("createElement", "span")
	filterTitleText.Set("textContent", "Search & Filter")
	filterTitle.Call("appendChild", filterTitleText)
	filterPanelHeader.Call("appendChild", filterTitle)

	addBtn := doc.Call("createElement", "button")
	addBtn.Set("className", "btn btn-primary")
	addBtnIcon := createMaterialIcon(doc, "person_add", "")
	addBtnIcon.Set("style", "font-size: 16px; margin-right: 6px;")
	addBtn.Call("appendChild", addBtnIcon)
	addBtnLabel := doc.Call("createElement", "span")
	addBtnLabel.Set("textContent", "New Customer")
	addBtn.Call("appendChild", addBtnLabel)
	addBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.ShowNewCustomerForm = !a.ShowNewCustomerForm
		a.Render()
		return nil
	}))
	filterPanelHeader.Call("appendChild", addBtn)
	filterPanel.Call("appendChild", filterPanelHeader)

	// Search row
	filterRow := doc.Call("createElement", "div")
	filterRow.Set("className", "customers-filter-row")

	// Search input
	searchWrapper := doc.Call("createElement", "div")
	searchWrapper.Set("className", "search-wrapper customers-search")
	searchIcon := createMaterialIcon(doc, "search", "search-icon")
	searchWrapper.Call("appendChild", searchIcon)
	searchInput := doc.Call("createElement", "input")
	searchInput.Set("type", "text")
	searchInput.Set("className", "search-input")
	searchInput.Set("placeholder", "Search by name or email…")
	searchInput.Set("value", a.SearchQuery)
	searchInput.Call("addEventListener", "input", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.SearchQuery = this.Get("value").String()
		a.Render()
		return nil
	}))
	searchWrapper.Call("appendChild", searchInput)
	filterRow.Call("appendChild", searchWrapper)

	// Status filter chips
	chipGroup := doc.Call("createElement", "div")
	chipGroup.Set("className", "filter-chip-group")

	statuses := []struct{ label, value string }{
		{"All", ""},
		{"Active", "active"},
		{"Suspended", "suspended"},
		{"Closed", "closed"},
	}
	for _, s := range statuses {
		chip := doc.Call("createElement", "button")
		cls := "filter-chip"
		if a.FilterStatus == s.value {
			cls += " active"
		}
		chip.Set("className", cls)
		chip.Set("textContent", s.label)
		val := s.value
		chip.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.FilterStatus = val
			a.Render()
			return nil
		}))
		chipGroup.Call("appendChild", chip)
	}
	filterRow.Call("appendChild", chipGroup)
	filterPanel.Call("appendChild", filterRow)

	// Inline new customer form (shown when toggled)
	if a.ShowNewCustomerForm {
		formRow := doc.Call("createElement", "div")
		formRow.Set("className", "customers-inline-form")

		formLabel := doc.Call("createElement", "div")
		formLabel.Set("className", "customers-inline-form-label")
		formLabel.Set("textContent", "New Customer")
		formRow.Call("appendChild", formLabel)

		formFields := doc.Call("createElement", "div")
		formFields.Set("className", "customers-inline-form-fields")

		nameInput := doc.Call("createElement", "input")
		nameInput.Set("type", "text")
		nameInput.Set("id", "customer-name")
		nameInput.Set("placeholder", "Full Name")
		nameInput.Set("className", "form-input")
		formFields.Call("appendChild", nameInput)

		emailInput := doc.Call("createElement", "input")
		emailInput.Set("type", "email")
		emailInput.Set("id", "customer-email")
		emailInput.Set("placeholder", "Email Address")
		emailInput.Set("className", "form-input")
		formFields.Call("appendChild", emailInput)

		saveBtn := doc.Call("createElement", "button")
		saveBtn.Set("id", "create-customer-button")
		saveBtn.Set("className", "btn btn-primary")
		saveBtn.Set("textContent", "Create")
		saveBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			name := doc.Call("getElementById", "customer-name").Get("value").String()
			email := doc.Call("getElementById", "customer-email").Get("value").String()
			if name == "" || email == "" {
				a.Error = "Name and email are required"
				a.Render()
				return nil
			}
			a.ShowNewCustomerForm = false
			a.CreateParty(js.Value{}, []js.Value{js.ValueOf(name), js.ValueOf(email)})
			return nil
		}))
		formFields.Call("appendChild", saveBtn)

		cancelBtn := doc.Call("createElement", "button")
		cancelBtn.Set("className", "btn btn-ghost")
		cancelBtn.Set("textContent", "Cancel")
		cancelBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
			a.ShowNewCustomerForm = false
			a.Render()
			return nil
		}))
		formFields.Call("appendChild", cancelBtn)

		formRow.Call("appendChild", formFields)
		filterPanel.Call("appendChild", formRow)
	}

	container.Call("appendChild", filterPanel)

	// ── Results Panel ─────────────────────────────────────────────────
	resultsPanel := doc.Call("createElement", "div")
	resultsPanel.Set("className", "customers-results-panel")

	// Apply both search and status filter
	filteredParties := a.filterPartiesWithStatus(a.SearchQuery, a.FilterStatus)

	// Results header
	resultsHeader := doc.Call("createElement", "div")
	resultsHeader.Set("className", "customers-results-header")

	countLabel := doc.Call("createElement", "div")
	countLabel.Set("className", "customers-results-count")
	countText := "All customers"
	if a.SearchQuery != "" || a.FilterStatus != "" {
		countText = formatNumber(len(filteredParties)) + " result"
		if len(filteredParties) != 1 {
			countText += "s"
		}
	} else {
		countText = formatNumber(len(filteredParties)) + " customer"
		if len(filteredParties) != 1 {
			countText += "s"
		}
	}
	countLabel.Set("textContent", countText)
	resultsHeader.Call("appendChild", countLabel)
	resultsPanel.Call("appendChild", resultsHeader)

	if len(filteredParties) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state-large")
		emptyIcon := createMaterialIcon(doc, "person_search", "")
		emptyIcon.Set("style", "font-size: 36px; color: var(--color-text-muted); display: block; margin-bottom: 8px;")
		empty.Call("appendChild", emptyIcon)
		emptyMsg := doc.Call("createElement", "div")
		if a.SearchQuery != "" || a.FilterStatus != "" {
			emptyMsg.Set("textContent", "No customers match your search")
		} else {
			emptyMsg.Set("textContent", "No customers yet — add your first customer above")
		}
		empty.Call("appendChild", emptyMsg)
		resultsPanel.Call("appendChild", empty)
	} else {
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
		resultsPanel.Call("appendChild", table)
	}

	container.Call("appendChild", resultsPanel)
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

	formCard := doc.Call("createElement", "div")
	formCard.Set("className", "form-card")
	formCard.Call("setAttribute", "data-testid", "create-account-form")

	formTitle := doc.Call("createElement", "h3")
	formTitle.Set("textContent", "Open New Account")
	formCard.Call("appendChild", formTitle)

	form := doc.Call("createElement", "div")
	form.Set("className", "form-stack")

	partySelect := doc.Call("createElement", "select")
	partySelect.Set("id", "account-party-select")
	partySelect.Set("className", "form-select")
	emptyParty := doc.Call("createElement", "option")
	emptyParty.Set("value", "")
	emptyParty.Set("textContent", "Select customer")
	partySelect.Call("appendChild", emptyParty)
	for _, party := range a.Parties {
		option := doc.Call("createElement", "option")
		option.Set("value", party.PartyID)
		option.Set("textContent", party.FullName+" ("+party.Email+")")
		if a.SelectedParty != nil && a.SelectedParty.PartyID == party.PartyID {
			option.Set("selected", true)
		}
		partySelect.Call("appendChild", option)
	}
	form.Call("appendChild", labeledNode(doc, "Customer", partySelect))

	accountNameInput := doc.Call("createElement", "input")
	accountNameInput.Set("id", "account-name")
	accountNameInput.Set("type", "text")
	accountNameInput.Set("className", "form-input")
	accountNameInput.Set("placeholder", "Main Checking")
	form.Call("appendChild", labeledNode(doc, "Account Name", accountNameInput))

	currencySelect := doc.Call("createElement", "select")
	currencySelect.Set("id", "account-currency")
	currencySelect.Set("className", "form-select")
	appendOptions(doc, currencySelect, []string{"USD", "EUR", "GBP", "JPY"})
	form.Call("appendChild", labeledNode(doc, "Currency", currencySelect))

	createBtn := doc.Call("createElement", "button")
	createBtn.Set("id", "create-account-button")
	createBtn.Set("className", "btn btn-primary")
	createBtn.Set("textContent", "Create Account")
	createBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		partyID := doc.Call("getElementById", "account-party-select").Get("value").String()
		accountName := doc.Call("getElementById", "account-name").Get("value").String()
		if partyID == "" {
			a.Error = "Select a customer first"
			a.Success = ""
			a.Render()
			return nil
		}
		if accountName == "" {
			a.Error = "Account name is required"
			a.Success = ""
			a.Render()
			return nil
		}
		for _, party := range a.Parties {
			if party.PartyID == partyID {
				chosen := party
				a.SelectedParty = &chosen
				break
			}
		}
		a.CreateAccount(js.Value{}, []js.Value{
			js.ValueOf(partyID),
			js.ValueOf(accountName),
			js.ValueOf(doc.Call("getElementById", "account-currency").Get("value").String()),
		})
		return nil
	}))
	form.Call("appendChild", createBtn)
	formCard.Call("appendChild", form)
	container.Call("appendChild", formCard)

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

	container.Call("appendChild", headerCard)

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

	// Holds Panel
	holdsSection := doc.Call("createElement", "div")
	holdsSection.Set("className", "detail-section")

	holdsTitleRow := doc.Call("createElement", "div")
	holdsTitleRow.Set("className", "card-header-row")
	holdsTitle := doc.Call("createElement", "h3")
	holdsTitle.Set("textContent", "Funds Holds")
	holdsTitleRow.Call("appendChild", holdsTitle)

	// Available balance indicator
	availBadge := doc.Call("createElement", "span")
	availBadge.Set("className", "stat-label")
	holdsHeldAmt := int64(0)
	for _, h := range a.Holds {
		if h.Status == "active" {
			holdsHeldAmt += h.Amount
		}
	}
	availBal := account.Balance - holdsHeldAmt
	availBadge.Set("textContent", "Available: "+FormatAmount(availBal, account.Currency))
	holdsTitleRow.Call("appendChild", availBadge)
	holdsSection.Call("appendChild", holdsTitleRow)

	// Place hold form
	holdForm := doc.Call("createElement", "div")
	holdForm.Set("className", "form-card")
	holdFormTitle := doc.Call("createElement", "h4")
	holdFormTitle.Set("textContent", "Place New Hold")
	holdForm.Call("appendChild", holdFormTitle)

	holdFormGrid := doc.Call("createElement", "div")
	holdFormGrid.Set("className", "form-grid")

	holdAmountInput := doc.Call("createElement", "input")
	holdAmountInput.Set("type", "number")
	holdAmountInput.Set("id", "hold-amount-input")
	holdAmountInput.Set("placeholder", "Amount (minor units)")
	holdAmountInput.Set("className", "form-input")
	holdFormGrid.Call("appendChild", holdAmountInput)

	holdReasonInput := doc.Call("createElement", "input")
	holdReasonInput.Set("type", "text")
	holdReasonInput.Set("id", "hold-reason-input")
	holdReasonInput.Set("placeholder", "Reason")
	holdReasonInput.Set("className", "form-input")
	holdFormGrid.Call("appendChild", holdReasonInput)

	holdForm.Call("appendChild", holdFormGrid)

	placeHoldBtn := doc.Call("createElement", "button")
	placeHoldBtn.Set("className", "btn btn-warning")
	placeHoldBtn.Set("textContent", "Place Hold")
	accIDForHold := account.AccountID
	placeHoldBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		amtStr := doc.Call("getElementById", "hold-amount-input").Get("value").String()
		reason := doc.Call("getElementById", "hold-reason-input").Get("value").String()
		if amtStr != "" && reason != "" {
			amt := 0
			fmt.Sscanf(amtStr, "%d", &amt)
			a.PlaceAccountHold(js.Value{}, []js.Value{
				js.ValueOf(accIDForHold),
				js.ValueOf(amt),
				js.ValueOf(reason),
			})
		}
		return nil
	}))
	holdForm.Call("appendChild", placeHoldBtn)
	holdsSection.Call("appendChild", holdForm)

	// Existing holds table
	if len(a.Holds) == 0 {
		holdsEmpty := doc.Call("createElement", "div")
		holdsEmpty.Set("className", "empty-state")
		holdsEmpty.Set("textContent", "No holds on this account")
		holdsSection.Call("appendChild", holdsEmpty)
	} else {
		holdsTable := doc.Call("createElement", "table")
		holdsTable.Set("className", "data-table")

		holdsThead := doc.Call("createElement", "thead")
		holdsTheadRow := doc.Call("createElement", "tr")
		for _, h := range []string{"Amount", "Reason", "Status", "Placed", "Actions"} {
			th := doc.Call("createElement", "th")
			th.Set("textContent", h)
			holdsTheadRow.Call("appendChild", th)
		}
		holdsThead.Call("appendChild", holdsTheadRow)
		holdsTable.Call("appendChild", holdsThead)

		holdsTbody := doc.Call("createElement", "tbody")
		for _, hold := range a.Holds {
			holdRow := doc.Call("createElement", "tr")

			amtCell := doc.Call("createElement", "td")
			amtCell.Set("className", "cell-balance")
			amtCell.Set("textContent", FormatAmount(hold.Amount, account.Currency))
			holdRow.Call("appendChild", amtCell)

			reasonCell := doc.Call("createElement", "td")
			reasonCell.Set("textContent", hold.Reason)
			holdRow.Call("appendChild", reasonCell)

			statusCell := doc.Call("createElement", "td")
			statusBadge := doc.Call("createElement", "span")
			statusBadge.Set("className", "status-badge "+hold.Status)
			statusBadge.Set("textContent", capitalize(hold.Status))
			statusCell.Call("appendChild", statusBadge)
			holdRow.Call("appendChild", statusCell)

			placedCell := doc.Call("createElement", "td")
			placedCell.Set("textContent", formatTimestamp(hold.PlacedAt))
			holdRow.Call("appendChild", placedCell)

			actCell := doc.Call("createElement", "td")
			if hold.Status == "active" {
				releaseBtn := doc.Call("createElement", "button")
				releaseBtn.Set("className", "btn btn-sm btn-ghost")
				releaseBtn.Set("textContent", "Release")
				holdID := hold.HoldID
				releaseBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
					a.ReleaseAccountHold(js.Value{}, []js.Value{
						js.ValueOf(accIDForHold),
						js.ValueOf(holdID),
					})
					return nil
				}))
				actCell.Call("appendChild", releaseBtn)
			}
			holdRow.Call("appendChild", actCell)

			holdsTbody.Call("appendChild", holdRow)
		}
		holdsTable.Call("appendChild", holdsTbody)
		holdsSection.Call("appendChild", holdsTable)
	}

	container.Call("appendChild", holdsSection)

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

func (a *App) renderProductsView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "products-view")

	toolbar := doc.Call("createElement", "div")
	toolbar.Set("className", "view-toolbar")

	title := doc.Call("createElement", "h3")
	title.Set("textContent", "Product Management")
	toolbar.Call("appendChild", title)

	refreshBtn := doc.Call("createElement", "button")
	refreshBtn.Set("className", "btn btn-secondary")
	refreshBtn.Set("textContent", "Refresh Products")
	refreshBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.ListSavingsProducts(js.Value{}, nil)
		a.ListLoanProducts(js.Value{}, nil)
		return nil
	}))
	toolbar.Call("appendChild", refreshBtn)
	container.Call("appendChild", toolbar)

	forms := doc.Call("createElement", "div")
	forms.Set("className", "two-col-forms")

	savingsCard := doc.Call("createElement", "div")
	savingsCard.Set("className", "form-card")
	savingsTitle := doc.Call("createElement", "h3")
	savingsTitle.Set("textContent", "Create Savings Product")
	savingsCard.Call("appendChild", savingsTitle)
	savingsForm := doc.Call("createElement", "div")
	savingsForm.Set("className", "form-stack")

	for _, field := range []struct {
		label       string
		id          string
		placeholder string
		inputType   string
	}{
		{"Name", "savings-name", "High Yield Savings", "text"},
		{"Description", "savings-description", "Product description", "text"},
		{"Interest Rate (bps)", "savings-rate-bps", "450", "number"},
		{"Minimum Balance", "savings-minimum-balance", "100.00", "text"},
	} {
		label := doc.Call("createElement", "label")
		label.Set("textContent", field.label)
		savingsForm.Call("appendChild", label)
		input := doc.Call("createElement", "input")
		input.Set("id", field.id)
		input.Set("type", field.inputType)
		input.Set("className", "form-input")
		input.Set("placeholder", field.placeholder)
		savingsForm.Call("appendChild", input)
	}

	savingsCurrency := doc.Call("createElement", "select")
	savingsCurrency.Set("id", "savings-currency")
	savingsCurrency.Set("className", "form-select")
	appendOptions(doc, savingsCurrency, []string{"USD", "EUR", "GBP", "JPY"})
	savingsForm.Call("appendChild", labeledNode(doc, "Currency", savingsCurrency))

	savingsInterestType := doc.Call("createElement", "select")
	savingsInterestType.Set("id", "savings-interest-type")
	savingsInterestType.Set("className", "form-select")
	appendOptions(doc, savingsInterestType, []string{"simple", "compound"})
	savingsForm.Call("appendChild", labeledNode(doc, "Interest Type", savingsInterestType))

	savingsCompounding := doc.Call("createElement", "select")
	savingsCompounding.Set("id", "savings-compounding-period")
	savingsCompounding.Set("className", "form-select")
	appendOptions(doc, savingsCompounding, []string{"daily", "monthly", "quarterly", "annually"})
	savingsForm.Call("appendChild", labeledNode(doc, "Compounding Period", savingsCompounding))

	savingsBtn := doc.Call("createElement", "button")
	savingsBtn.Set("id", "create-savings-product-button")
	savingsBtn.Set("className", "btn btn-primary")
	savingsBtn.Set("textContent", "Create Savings Product")
	savingsBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		rateBps, err := strconv.ParseInt(doc.Call("getElementById", "savings-rate-bps").Get("value").String(), 10, 64)
		if err != nil {
			a.Error = "Invalid interest rate"
			a.Success = ""
			a.Render()
			return nil
		}
		minimumBalance, err := ParseAmount(doc.Call("getElementById", "savings-minimum-balance").Get("value").String())
		if err != nil {
			a.Error = "Invalid minimum balance"
			a.Success = ""
			a.Render()
			return nil
		}
		a.CreateSavingsProduct(js.Value{}, []js.Value{
			js.ValueOf(doc.Call("getElementById", "savings-name").Get("value").String()),
			js.ValueOf(doc.Call("getElementById", "savings-description").Get("value").String()),
			js.ValueOf(doc.Call("getElementById", "savings-currency").Get("value").String()),
			js.ValueOf(int(rateBps)),
			js.ValueOf(doc.Call("getElementById", "savings-interest-type").Get("value").String()),
			js.ValueOf(doc.Call("getElementById", "savings-compounding-period").Get("value").String()),
			js.ValueOf(minimumBalance),
		})
		return nil
	}))
	savingsForm.Call("appendChild", savingsBtn)
	savingsCard.Call("appendChild", savingsForm)
	forms.Call("appendChild", savingsCard)

	loanCard := doc.Call("createElement", "div")
	loanCard.Set("className", "form-card")
	loanTitle := doc.Call("createElement", "h3")
	loanTitle.Set("textContent", "Create Loan Product")
	loanCard.Call("appendChild", loanTitle)
	loanForm := doc.Call("createElement", "div")
	loanForm.Set("className", "form-stack")

	for _, field := range []struct {
		label       string
		id          string
		placeholder string
		inputType   string
	}{
		{"Name", "loan-product-name", "Starter Loan", "text"},
		{"Description", "loan-product-description", "Loan product description", "text"},
		{"Min Amount", "loan-product-min-amount", "100.00", "text"},
		{"Max Amount", "loan-product-max-amount", "5000.00", "text"},
		{"Min Term (months)", "loan-product-min-term", "6", "number"},
		{"Max Term (months)", "loan-product-max-term", "24", "number"},
		{"Interest Rate (bps)", "loan-product-rate-bps", "1200", "number"},
	} {
		label := doc.Call("createElement", "label")
		label.Set("textContent", field.label)
		loanForm.Call("appendChild", label)
		input := doc.Call("createElement", "input")
		input.Set("id", field.id)
		input.Set("type", field.inputType)
		input.Set("className", "form-input")
		input.Set("placeholder", field.placeholder)
		loanForm.Call("appendChild", input)
	}

	loanCurrency := doc.Call("createElement", "select")
	loanCurrency.Set("id", "loan-product-currency")
	loanCurrency.Set("className", "form-select")
	appendOptions(doc, loanCurrency, []string{"USD", "EUR", "GBP", "JPY"})
	loanForm.Call("appendChild", labeledNode(doc, "Currency", loanCurrency))

	loanInterestType := doc.Call("createElement", "select")
	loanInterestType.Set("id", "loan-product-interest-type")
	loanInterestType.Set("className", "form-select")
	appendOptions(doc, loanInterestType, []string{"flat", "declining"})
	loanForm.Call("appendChild", labeledNode(doc, "Interest Type", loanInterestType))

	loanBtn := doc.Call("createElement", "button")
	loanBtn.Set("id", "create-loan-product-button")
	loanBtn.Set("className", "btn btn-primary")
	loanBtn.Set("textContent", "Create Loan Product")
	loanBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		minTerm, minTermErr := strconv.ParseInt(doc.Call("getElementById", "loan-product-min-term").Get("value").String(), 10, 64)
		maxTerm, maxTermErr := strconv.ParseInt(doc.Call("getElementById", "loan-product-max-term").Get("value").String(), 10, 64)
		rateBps, rateErr := strconv.ParseInt(doc.Call("getElementById", "loan-product-rate-bps").Get("value").String(), 10, 64)
		minAmount, minErr := ParseAmount(doc.Call("getElementById", "loan-product-min-amount").Get("value").String())
		maxAmount, maxErr := ParseAmount(doc.Call("getElementById", "loan-product-max-amount").Get("value").String())
		if minErr != nil || maxErr != nil {
			a.Error = "Invalid loan product amounts"
			a.Success = ""
			a.Render()
			return nil
		}
		if minTermErr != nil || maxTermErr != nil {
			a.Error = "Invalid loan product term"
			a.Success = ""
			a.Render()
			return nil
		}
		if rateErr != nil {
			a.Error = "Invalid loan product rate"
			a.Success = ""
			a.Render()
			return nil
		}
		a.CreateLoanProduct(js.Value{}, []js.Value{
			js.ValueOf(doc.Call("getElementById", "loan-product-name").Get("value").String()),
			js.ValueOf(doc.Call("getElementById", "loan-product-description").Get("value").String()),
			js.ValueOf(doc.Call("getElementById", "loan-product-currency").Get("value").String()),
			js.ValueOf(minAmount),
			js.ValueOf(maxAmount),
			js.ValueOf(int(minTerm)),
			js.ValueOf(int(maxTerm)),
			js.ValueOf(int(rateBps)),
			js.ValueOf(doc.Call("getElementById", "loan-product-interest-type").Get("value").String()),
		})
		return nil
	}))
	loanForm.Call("appendChild", loanBtn)
	loanCard.Call("appendChild", loanForm)
	forms.Call("appendChild", loanCard)

	container.Call("appendChild", forms)

	container.Call("appendChild", a.renderSavingsProductsTable())
	container.Call("appendChild", a.renderLoanProductsTable())
	return container
}

func (a *App) renderSavingsProductsTable() js.Value {
	doc := js.Global().Get("document")
	card := doc.Call("createElement", "div")
	card.Set("className", "dashboard-card")
	title := doc.Call("createElement", "h3")
	title.Set("textContent", "Savings Products")
	card.Call("appendChild", title)

	if len(a.SavingsProducts) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state")
		empty.Set("textContent", "No savings products yet")
		card.Call("appendChild", empty)
		return card
	}

	table := doc.Call("createElement", "table")
	table.Set("className", "data-table")
	thead := doc.Call("createElement", "thead")
	headRow := doc.Call("createElement", "tr")
	for _, header := range []string{"Name", "Currency", "Rate", "Type", "Minimum Balance", "Status"} {
		th := doc.Call("createElement", "th")
		th.Set("textContent", header)
		headRow.Call("appendChild", th)
	}
	thead.Call("appendChild", headRow)
	table.Call("appendChild", thead)
	tbody := doc.Call("createElement", "tbody")
	for _, product := range a.SavingsProducts {
		row := doc.Call("createElement", "tr")
		appendCell(doc, row, product.Name)
		appendCell(doc, row, product.Currency)
		appendCell(doc, row, strconv.FormatInt(product.InterestRateBps, 10)+" bps")
		appendCell(doc, row, capitalize(product.InterestType)+" / "+capitalize(product.CompoundingPeriod))
		appendCell(doc, row, FormatAmount(product.MinimumBalance, product.Currency))
		appendCell(doc, row, capitalize(product.Status))
		tbody.Call("appendChild", row)
	}
	table.Call("appendChild", tbody)
	card.Call("appendChild", table)
	return card
}

func (a *App) renderLoanProductsTable() js.Value {
	doc := js.Global().Get("document")
	card := doc.Call("createElement", "div")
	card.Set("className", "dashboard-card")
	title := doc.Call("createElement", "h3")
	title.Set("textContent", "Loan Products")
	card.Call("appendChild", title)

	if len(a.LoanProducts) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state")
		empty.Set("textContent", "No loan products yet")
		card.Call("appendChild", empty)
		return card
	}

	table := doc.Call("createElement", "table")
	table.Set("className", "data-table")
	thead := doc.Call("createElement", "thead")
	headRow := doc.Call("createElement", "tr")
	for _, header := range []string{"Name", "Currency", "Amount Range", "Term Range", "Rate", "Status"} {
		th := doc.Call("createElement", "th")
		th.Set("textContent", header)
		headRow.Call("appendChild", th)
	}
	thead.Call("appendChild", headRow)
	table.Call("appendChild", thead)
	tbody := doc.Call("createElement", "tbody")
	for _, product := range a.LoanProducts {
		row := doc.Call("createElement", "tr")
		appendCell(doc, row, product.Name)
		appendCell(doc, row, product.Currency)
		appendCell(doc, row, FormatAmount(product.MinAmount, product.Currency)+" - "+FormatAmount(product.MaxAmount, product.Currency))
		appendCell(doc, row, strconv.FormatInt(product.MinTermMonths, 10)+"-"+strconv.FormatInt(product.MaxTermMonths, 10)+" mo")
		appendCell(doc, row, strconv.FormatInt(product.InterestRateBps, 10)+" bps "+capitalize(product.InterestType))
		appendCell(doc, row, capitalize(product.Status))
		tbody.Call("appendChild", row)
	}
	table.Call("appendChild", tbody)
	card.Call("appendChild", table)
	return card
}

func (a *App) renderLoansView() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "loans-view")

	toolbar := doc.Call("createElement", "div")
	toolbar.Set("className", "view-toolbar")

	partySelect := doc.Call("createElement", "select")
	partySelect.Set("id", "loan-party-select")
	partySelect.Set("className", "form-select")
	emptyParty := doc.Call("createElement", "option")
	emptyParty.Set("value", "")
	emptyParty.Set("textContent", "Select customer")
	partySelect.Call("appendChild", emptyParty)
	for _, party := range a.Parties {
		option := doc.Call("createElement", "option")
		option.Set("value", party.PartyID)
		option.Set("textContent", party.FullName+" ("+party.Email+")")
		if a.SelectedParty != nil && a.SelectedParty.PartyID == party.PartyID {
			option.Set("selected", true)
		}
		partySelect.Call("appendChild", option)
	}
	partySelect.Call("addEventListener", "change", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		selectedID := this.Get("value").String()
		a.SelectedParty = nil
		for _, party := range a.Parties {
			if party.PartyID == selectedID {
				chosen := party
				a.SelectedParty = &chosen
				break
			}
		}
		a.SelectedLoan = nil
		a.LoanRepayments = nil
		a.ListLoansForSelectedParty()
		a.Render()
		return nil
	}))
	toolbar.Call("appendChild", labeledNode(doc, "Customer", partySelect))

	refreshBtn := doc.Call("createElement", "button")
	refreshBtn.Set("className", "btn btn-secondary")
	refreshBtn.Set("textContent", "Refresh Loans")
	refreshBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		a.ListParties(js.Value{}, nil)
		a.ListAllAccounts(js.Value{}, nil)
		a.ListLoanProducts(js.Value{}, nil)
		a.ListLoansForSelectedParty()
		return nil
	}))
	toolbar.Call("appendChild", refreshBtn)
	container.Call("appendChild", toolbar)

	formCard := doc.Call("createElement", "div")
	formCard.Set("className", "form-card")
	formTitle := doc.Call("createElement", "h3")
	formTitle.Set("textContent", "Create Loan")
	formCard.Call("appendChild", formTitle)
	form := doc.Call("createElement", "div")
	form.Set("className", "form-stack")

	productSelect := doc.Call("createElement", "select")
	productSelect.Set("id", "loan-create-product")
	productSelect.Set("className", "form-select")
	for _, product := range a.LoanProducts {
		option := doc.Call("createElement", "option")
		option.Set("value", product.ProductID)
		option.Set("textContent", product.Name+" ("+product.Currency+")")
		productSelect.Call("appendChild", option)
	}
	form.Call("appendChild", labeledNode(doc, "Loan Product", productSelect))

	accountSelect := doc.Call("createElement", "select")
	accountSelect.Set("id", "loan-create-account")
	accountSelect.Set("className", "form-select")
	for _, account := range a.selectedPartyAccounts() {
		option := doc.Call("createElement", "option")
		option.Set("value", account.AccountID)
		option.Set("textContent", account.Name+" ("+account.Currency+")")
		accountSelect.Call("appendChild", option)
	}
	form.Call("appendChild", labeledNode(doc, "Disbursement Account", accountSelect))

	principalInput := doc.Call("createElement", "input")
	principalInput.Set("id", "loan-create-principal")
	principalInput.Set("type", "text")
	principalInput.Set("className", "form-input")
	principalInput.Set("placeholder", "1000.00")
	form.Call("appendChild", labeledNode(doc, "Principal", principalInput))

	termInput := doc.Call("createElement", "input")
	termInput.Set("id", "loan-create-term")
	termInput.Set("type", "number")
	termInput.Set("className", "form-input")
	termInput.Set("placeholder", "12")
	form.Call("appendChild", labeledNode(doc, "Term (months)", termInput))

	createBtn := doc.Call("createElement", "button")
	createBtn.Set("id", "create-loan-button")
	createBtn.Set("className", "btn btn-primary")
	createBtn.Set("textContent", "Create Loan")
	createBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		if a.SelectedParty == nil {
			a.Error = "Select a customer first"
			a.Success = ""
			a.Render()
			return nil
		}
		principal, err := ParseAmount(doc.Call("getElementById", "loan-create-principal").Get("value").String())
		if err != nil {
			a.Error = "Invalid principal amount"
			a.Success = ""
			a.Render()
			return nil
		}
		termMonths, termErr := strconv.ParseInt(doc.Call("getElementById", "loan-create-term").Get("value").String(), 10, 64)
		if termErr != nil {
			a.Error = "Invalid loan term"
			a.Success = ""
			a.Render()
			return nil
		}
		a.CreateLoan(js.Value{}, []js.Value{
			js.ValueOf(a.SelectedParty.PartyID),
			js.ValueOf(doc.Call("getElementById", "loan-create-product").Get("value").String()),
			js.ValueOf(doc.Call("getElementById", "loan-create-account").Get("value").String()),
			js.ValueOf(principal),
			js.ValueOf(int(termMonths)),
		})
		return nil
	}))
	form.Call("appendChild", createBtn)
	formCard.Call("appendChild", form)
	container.Call("appendChild", formCard)

	container.Call("appendChild", a.renderLoansTable())
	if a.SelectedLoan != nil {
		container.Call("appendChild", a.renderLoanRepaymentsPanel())
	}
	return container
}

func (a *App) renderLoansTable() js.Value {
	doc := js.Global().Get("document")
	card := doc.Call("createElement", "div")
	card.Set("className", "dashboard-card")
	title := doc.Call("createElement", "h3")
	title.Set("textContent", "Loans")
	card.Call("appendChild", title)

	if len(a.Loans) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state")
		if a.SelectedParty == nil {
			empty.Set("textContent", "Select a customer to view loans")
		} else {
			empty.Set("textContent", "No loans for the selected customer")
		}
		card.Call("appendChild", empty)
		return card
	}

	table := doc.Call("createElement", "table")
	table.Set("className", "data-table")
	thead := doc.Call("createElement", "thead")
	headRow := doc.Call("createElement", "tr")
	for _, header := range []string{"Loan", "Product", "Principal", "Outstanding", "Monthly Payment", "Status", "Actions"} {
		th := doc.Call("createElement", "th")
		th.Set("textContent", header)
		headRow.Call("appendChild", th)
	}
	thead.Call("appendChild", headRow)
	table.Call("appendChild", thead)
	tbody := doc.Call("createElement", "tbody")

	for _, loan := range a.Loans {
		row := doc.Call("createElement", "tr")
		appendCell(doc, row, truncateID(loan.LoanID))
		appendCell(doc, row, a.loanProductName(loan.ProductID))
		appendCell(doc, row, FormatAmount(loan.Principal, loan.Currency))
		appendCell(doc, row, FormatAmount(loan.OutstandingBalance, loan.Currency))
		appendCell(doc, row, FormatAmount(loan.MonthlyPayment, loan.Currency))
		appendCell(doc, row, capitalize(loan.Status))

		actions := doc.Call("createElement", "td")
		viewLoan := loan
		viewBtn := a.createActionButton("View", "primary", func() {
			a.GetLoan(js.Value{}, []js.Value{js.ValueOf(viewLoan.LoanID)})
		})
		actions.Call("appendChild", viewBtn)
		if loan.Status == "pending" {
			approveLoan := loan
			actions.Call("appendChild", a.createActionButton("Approve", "success", func() {
				a.ApproveLoan(js.Value{}, []js.Value{js.ValueOf(approveLoan.LoanID)})
			}))
		}
		if loan.Status == "approved" {
			disburseLoan := loan
			actions.Call("appendChild", a.createActionButton("Disburse", "warning", func() {
				a.DisburseLoan(js.Value{}, []js.Value{js.ValueOf(disburseLoan.LoanID)})
			}))
		}
		row.Call("appendChild", actions)
		tbody.Call("appendChild", row)
	}

	table.Call("appendChild", tbody)
	card.Call("appendChild", table)
	return card
}

func (a *App) renderLoanRepaymentsPanel() js.Value {
	doc := js.Global().Get("document")
	container := doc.Call("createElement", "div")
	container.Set("className", "dashboard-card")

	title := doc.Call("createElement", "h3")
	title.Set("textContent", "Loan Details and Repayments")
	container.Call("appendChild", title)

	summary := doc.Call("createElement", "div")
	summary.Set("className", "detail-stats")
	appendStat(summary, "Loan ID", truncateID(a.SelectedLoan.LoanID))
	appendStat(summary, "Outstanding", FormatAmount(a.SelectedLoan.OutstandingBalance, a.SelectedLoan.Currency))
	appendStat(summary, "Status", capitalize(a.SelectedLoan.Status))
	container.Call("appendChild", summary)

	form := doc.Call("createElement", "div")
	form.Set("className", "form-stack")
	repaymentAmount := doc.Call("createElement", "input")
	repaymentAmount.Set("id", "loan-repayment-amount")
	repaymentAmount.Set("type", "text")
	repaymentAmount.Set("className", "form-input")
	repaymentAmount.Set("placeholder", "50.00")
	form.Call("appendChild", labeledNode(doc, "Repayment Amount", repaymentAmount))

	paymentType := doc.Call("createElement", "select")
	paymentType.Set("id", "loan-repayment-type")
	paymentType.Set("className", "form-select")
	appendOptions(doc, paymentType, []string{"partial", "full"})
	form.Call("appendChild", labeledNode(doc, "Payment Type", paymentType))

	repaymentBtn := doc.Call("createElement", "button")
	repaymentBtn.Set("id", "record-loan-repayment-button")
	repaymentBtn.Set("className", "btn btn-primary")
	repaymentBtn.Set("textContent", "Record Repayment")
	selectedLoanID := a.SelectedLoan.LoanID
	repaymentBtn.Call("addEventListener", "click", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		amount, err := ParseAmount(doc.Call("getElementById", "loan-repayment-amount").Get("value").String())
		if err != nil {
			a.Error = "Invalid repayment amount"
			a.Render()
			return nil
		}
		a.RecordLoanRepayment(js.Value{}, []js.Value{
			js.ValueOf(selectedLoanID),
			js.ValueOf(amount),
			js.ValueOf(doc.Call("getElementById", "loan-repayment-type").Get("value").String()),
		})
		return nil
	}))
	form.Call("appendChild", repaymentBtn)
	container.Call("appendChild", form)

	if len(a.LoanRepayments) == 0 {
		empty := doc.Call("createElement", "div")
		empty.Set("className", "empty-state")
		empty.Set("textContent", "No repayments recorded yet")
		container.Call("appendChild", empty)
		return container
	}

	table := doc.Call("createElement", "table")
	table.Set("className", "data-table")
	thead := doc.Call("createElement", "thead")
	headRow := doc.Call("createElement", "tr")
	for _, header := range []string{"Amount", "Principal", "Interest", "Status", "Paid At"} {
		th := doc.Call("createElement", "th")
		th.Set("textContent", header)
		headRow.Call("appendChild", th)
	}
	thead.Call("appendChild", headRow)
	table.Call("appendChild", thead)
	tbody := doc.Call("createElement", "tbody")
	for _, repayment := range a.LoanRepayments {
		row := doc.Call("createElement", "tr")
		appendCell(doc, row, FormatAmount(repayment.Amount, a.SelectedLoan.Currency))
		appendCell(doc, row, FormatAmount(repayment.PrincipalPortion, a.SelectedLoan.Currency))
		appendCell(doc, row, FormatAmount(repayment.InterestPortion, a.SelectedLoan.Currency))
		appendCell(doc, row, capitalize(repayment.Status))
		appendCell(doc, row, formatTimestamp(repayment.PaidAt))
		tbody.Call("appendChild", row)
	}
	table.Call("appendChild", tbody)
	container.Call("appendChild", table)
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

func (a *App) filterPartiesWithStatus(query string, status string) []Party {
	var filtered []Party
	lowerQuery := toLower(query)
	for _, p := range a.Parties {
		if status != "" && p.Status != status {
			continue
		}
		if query == "" || contains(toLower(p.FullName), lowerQuery) || contains(toLower(p.Email), lowerQuery) {
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

func appendOptions(doc js.Value, selectEl js.Value, options []string) {
	for _, value := range options {
		option := doc.Call("createElement", "option")
		option.Set("value", value)
		option.Set("textContent", value)
		selectEl.Call("appendChild", option)
	}
}

func labeledNode(doc js.Value, labelText string, node js.Value) js.Value {
	wrapper := doc.Call("createElement", "div")
	label := doc.Call("createElement", "label")
	label.Set("textContent", labelText)
	wrapper.Call("appendChild", label)
	wrapper.Call("appendChild", node)
	return wrapper
}

func appendCell(doc js.Value, row js.Value, value string) {
	cell := doc.Call("createElement", "td")
	cell.Set("textContent", value)
	row.Call("appendChild", cell)
}

func appendStat(container js.Value, labelText string, value string) {
	doc := js.Global().Get("document")
	stat := doc.Call("createElement", "div")
	stat.Set("className", "detail-stat")
	label := doc.Call("createElement", "div")
	label.Set("className", "stat-label")
	label.Set("textContent", labelText)
	stat.Call("appendChild", label)
	content := doc.Call("createElement", "div")
	content.Set("className", "stat-value")
	content.Set("textContent", value)
	stat.Call("appendChild", content)
	container.Call("appendChild", stat)
}

func (a *App) selectedPartyAccounts() []Account {
	if a.SelectedParty == nil {
		return a.Accounts
	}

	var filtered []Account
	for _, account := range a.Accounts {
		if account.PartyID == a.SelectedParty.PartyID {
			filtered = append(filtered, account)
		}
	}
	return filtered
}

func (a *App) loanProductName(productID string) string {
	for _, product := range a.LoanProducts {
		if product.ProductID == productID {
			return product.Name
		}
	}
	return truncateID(productID)
}

func formatNumber(n int) string {
	return strconv.Itoa(n)
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
