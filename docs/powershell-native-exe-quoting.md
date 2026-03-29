# PowerShell Native Executable Quoting Issues

PowerShell re-parses and re-quotes arguments before passing them to native
executables. This mangles nested JSON strings and other complex arguments.

## Symptom

Commands that work in Bash produce blank output or errors in PowerShell:

```powershell
# BROKEN — PowerShell mangles the JSON
echo 'hello' | claude -p --json-schema '{"type":"object","properties":{"echo_result":{"type":"string"}},"required":["echo_result"]}'
```

## Fix: Stop-Parsing Token (`--%`)

The `--%` token tells PowerShell to pass everything after it as raw text,
bypassing argument re-parsing. Inner quotes must use `\"`:

```powershell
# WORKS
echo 'hello' | claude --% -p --model haiku --output-format json --json-schema "{\"type\":\"object\",\"properties\":{\"echo_result\":{\"type\":\"string\"}},\"required\":[\"echo_result\"]}"
```

## Limitations of `--%`

- No variable expansion after `--%` (everything is literal)
- Must use `\"` for inner quotes, not `'`
- The token applies to the rest of the line

## Alternative: PowerShell 7.3+

PowerShell 7.3 added `$PSNativeCommandArgumentPassing = 'Standard'` which
fixes this behavior. Not available in PowerShell 5.1 (ships with Windows).

```powershell
# PowerShell 7.3+ only
$PSNativeCommandArgumentPassing = 'Standard'
echo 'hello' | claude -p --json-schema '{"type":"object",...}'
```

## Scope

This affects ALL native executables called from PowerShell with complex
arguments, not just `claude`. Common victims: `curl`, `jq`, `docker`,
anything that takes JSON on the command line.
