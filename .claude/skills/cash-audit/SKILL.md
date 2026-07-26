---
name: cash-audit
description: "Audit changed code for security sharp edges — dangerous defaults, type confusion, and silent failures"
context: fork
agent: Explore
disallowedTools: [Edit, Write]
license: MIT
metadata:
  author: cash
  version: "1.0"
---

## Project-local Cash CLI bootstrap

執行任何 Cash artifact command 前，MUST 先從目前目錄解析並驗證 Git root，再使用該 root 下的 absolute launcher；不得依賴 PATH 或外部 runtime：

```shell
cash_root="$(git rev-parse --show-toplevel)" || exit 1
cash_cli="$cash_root/.cash-skills/bin/cash"
test -x "$cash_cli" || exit 1
```

同一段 workflow 後續每個 artifact command MUST 使用 `"$cash_cli"`。

Audit changed code for security sharp edges in a Claude Code fork. This generated skill is report-only: it SHALL NOT edit files and SHALL NOT apply fixes directly inside the fork.

## Claude fork context

Run `git diff HEAD` to gather the current changes. If there are no changes, report that no security sharp edges were found and stop.

Analyze the diff through the Scoundrel, Lazy Developer, and Confused Developer lenses. Return a consolidated report with findings grouped by severity, affected files, and recommended fixes. The main thread decides whether to apply any fixes.

---

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

## Core Framework

### Three Adversaries

| Role                   | Mindset                                   | Key Questions                                                                     |
| ---------------------- | ----------------------------------------- | --------------------------------------------------------------------------------- |
| **Scoundrel**          | Malicious, deliberate exploitation        | Can I disable security via config? Downgrade algorithms? Inject values?           |
| **Lazy Developer**     | Copy-paste, skips docs, deadline pressure | Is the first example safe? Is the default secure? Do errors guide me right?       |
| **Confused Developer** | Misunderstands usage                      | Can I swap params silently? Will mistakes fail loudly? Are types distinguishable? |

### Six Trap Categories

#### 1. Algorithm Choice Traps

Letting developers choose algorithms = inviting them to choose wrong.

```ruby
# Dangerous: accepts arbitrary algorithm
OpenSSL::Digest.new(algorithm).hexdigest(password)  # algorithm = "md5"?

# Safe: no choice
BCrypt::Password.create(password)  # can't pick wrong
```

#### 2. Dangerous Defaults

Defaults that are insecure, or zero/empty values that disable security.
Insecure defaults cannot be grandfathered for backwards compatibility; deprecate them loudly and require migration.

```ruby
# What does timeout=0 mean? Never expire? Expire immediately?
def verify_token(token, timeout: 300)
  return true if timeout == 0  # 0 = skip verification?!
end
```

**Key question:** What do `timeout=0`, `max_attempts=0`, `key=""`, `nil` each mean?

#### 3. Raw Primitives vs Semantic Types

Using raw bytes/strings instead of meaningful types invites type confusion.

```ruby
# Dangerous: both params are strings, swappable
encrypt(message, key, nonce)

# Safe: types protect against swapping
encrypt(message, Key.new(k), Nonce.new(n))
```

#### 4. Configuration Cliffs

One wrong config value = disaster, with no warning.

```yaml
# A typo = security mechanism disappears
verify_ssl: fasle # not "false", might be treated as truthy?

# Dangerous combination
auth_required: true
bypass_auth_for_health: true
health_check_path: "/" # oops, entire site bypasses auth
```

#### 5. Silent Failures

Security errors that don't surface, or "success" masking failure.

```ruby
# Silent bypass
def verify_signature(sig, data, key)
  return true if key.nil?  # no key = skip verification?!
end

# Return value ignored
result = crypto.verify(data, sig)  # returns false but nobody checks
```

#### 6. Stringly-Typed Security

Security-critical values as plain strings = open door for injection and confusion.

```ruby
# Dangerous: string concatenation
permissions = "read,write"
permissions += ",admin"   # too easy to escalate

# Safe: use enums
permissions = Set[Permission::READ, Permission::WRITE]
```

### Severity Classification

| Severity | Condition                                 | Example                                             |
| -------- | ----------------------------------------- | --------------------------------------------------- |
| Critical | Default or most obvious usage is insecure | `verify: false` is default, empty password accepted |
| High     | Easy misconfiguration breaks security     | Algorithm param accepts `"none"`                    |
| Medium   | Uncommon but possible misconfiguration    | Negative timeout has unexpected behavior            |
| Low      | Requires deliberate misuse                | Obscure parameter combination                       |
