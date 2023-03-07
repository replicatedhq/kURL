package cli

var Reset = "\033[0m"
var Red = "\033[31m"
var Green = "\033[32m"
var Yellow = "\033[33m"
var Blue = "\033[34m"

// OutputPassGreen return [PASS] to be outputted in green
func OutputPassGreen() string {
	return Green + "[PASS]" + Reset
}

// OutputWarnYellow return [Warn] to be outputted in yellow
func OutputWarnYellow() string {
	return Yellow + "[WARN]" + Reset
}

// OutputFailRed return [Fail] to be outputted in red
func OutputFailRed() string {
	return Red + "[FAIL]" + Reset
}

// OutputInfoBlue return [Info] to be outputted in blue
func OutputInfoBlue() string {
	return Blue + "[INFO]" + Reset
}
