package main

import (
	"fmt"
	"syscall/js"
)

func main() {
	fmt.Println("IronLedger Dashboard starting...")

	// Initialize the app
	app := NewApp()

	// Set up global functions for JavaScript to call
	js.Global().Set("ironledger", js.ValueOf(map[string]interface{}{
		"navigate":             js.FuncOf(app.Navigate),
		"createParty":          js.FuncOf(app.CreateParty),
		"listParties":          js.FuncOf(app.ListParties),
		"suspendParty":         js.FuncOf(app.SuspendParty),
		"closeParty":           js.FuncOf(app.CloseParty),
		"createAccount":        js.FuncOf(app.CreateAccount),
		"listAccounts":         js.FuncOf(app.ListAccounts),
		"listAllAccounts":      js.FuncOf(app.ListAllAccounts),
		"freezeAccount":        js.FuncOf(app.FreezeAccount),
		"unfreezeAccount":      js.FuncOf(app.UnfreezeAccount),
		"closeAccount":         js.FuncOf(app.CloseAccount),
		"getBalance":           js.FuncOf(app.GetBalance),
		"getAccountDetails":    js.FuncOf(app.GetAccountDetails),
		"transfer":             js.FuncOf(app.Transfer),
		"deposit":              js.FuncOf(app.Deposit),
		"withdraw":             js.FuncOf(app.Withdraw),
		"getTransaction":       js.FuncOf(app.GetTransaction),
		"listTransactions":     js.FuncOf(app.ListTransactions),
		"listAllTransactions":  js.FuncOf(app.ListAllTransactions),
		"reverseTransaction":   js.FuncOf(app.ReverseTransaction),
		"getLedgerEntries":     js.FuncOf(app.GetLedgerEntries),
		"fetchDashboardStats":  js.FuncOf(app.FetchDashboardStats),
		"listSavingsProducts":  js.FuncOf(app.ListSavingsProducts),
		"createSavingsProduct": js.FuncOf(app.CreateSavingsProduct),
		"listLoanProducts":     js.FuncOf(app.ListLoanProducts),
		"createLoanProduct":    js.FuncOf(app.CreateLoanProduct),
		"listLoans":            js.FuncOf(app.ListLoans),
		"createLoan":           js.FuncOf(app.CreateLoan),
		"getLoan":              js.FuncOf(app.GetLoan),
		"approveLoan":          js.FuncOf(app.ApproveLoan),
		"disburseLoan":         js.FuncOf(app.DisburseLoan),
		"listLoanRepayments":   js.FuncOf(app.ListLoanRepayments),
		"recordLoanRepayment":  js.FuncOf(app.RecordLoanRepayment),
		"logout":               js.FuncOf(app.Logout),
	}))

	app.Render()
	app.BootstrapSession()

	// Keep the program running
	select {}
}
