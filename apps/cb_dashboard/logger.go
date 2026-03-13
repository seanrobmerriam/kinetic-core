package main

import (
	"fmt"
	"syscall/js"
	"time"
)

type LogLevel string

const (
	DEBUG LogLevel = "DEBUG"
	INFO  LogLevel = "INFO"
	WARN  LogLevel = "WARN"
	ERROR LogLevel = "ERROR"
)

func logMsg(level LogLevel, msg string, fields map[string]interface{}) {
	timestamp := time.Now().Format("15:04:05.000")
	prefix := fmt.Sprintf("[IronLedger %s %s]", timestamp, level)

	fieldStr := ""
	for k, v := range fields {
		fieldStr += fmt.Sprintf(" %s=%v", k, v)
	}

	full := prefix + " " + msg + fieldStr

	switch level {
	case ERROR:
		js.Global().Get("console").Call("error", full)
	case WARN:
		js.Global().Get("console").Call("warn", full)
	case DEBUG:
		js.Global().Get("console").Call("debug", full)
	default:
		js.Global().Get("console").Call("log", full)
	}
}
