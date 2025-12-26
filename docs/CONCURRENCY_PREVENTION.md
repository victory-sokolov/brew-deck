# Preventing Swift 6 Concurrency Issues

This document outlines strategies to catch and prevent Swift 6 concurrency issues early in development.

## Quick Reference

**Run all checks locally:**
```bash
# Quick pattern check
./scripts/check-concurrency.sh

# Full check including Static Analyzer
./scripts/check-concurrency.sh --analyzer

# Just run Static Analyzer
./scripts/run-analyzer.sh
```

## 1. Xcode Static Analyzer

The Static Analyzer performs deep code analysis to find:
- Memory leaks and retain cycles
- Null pointer dereferences  
- Uninitialized variables
- Dead code and unreachable conditions
- **Concurrency and data race issues**
- API misuse

### Running Locally

**Option 1: Dedicated script (recommended)**
```bash
./scripts/run-analyzer.sh
```

**Option 2: With concurrency checks**
```bash
./scripts/check-concurrency.sh --analyzer
```

**Option 3: Direct xcodebuild**
```bash
xcodebuild analyze \
  -project BrewDeck.xcodeproj \
  -scheme BrewDeck \
  -configuration Debug \
  OTHER_SWIFT_FLAGS="-Xfrontend -strict-concurrency=complete"
```

### Viewing Results

The analyzer generates HTML reports in `build/analyzer-results/`:
```bash
# Open all HTML reports
open build/analyzer-results/*.html
```

### In Xcode

1. **Product** → **Analyze** (⇧⌘B)
2. Issues appear in the Issue Navigator
3. Click on issues to see detailed explanations

## 2. Xcode Build Settings (Already Configured ✅)

Your project has these enabled:
- `SWIFT_VERSION = 6.2.3`
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

### Additional Recommended Settings

Add to Build Settings → "Other Swift Flags":
```
-Xfrontend -warn-concurrency
-Xfrontend -enable-actor-data-race-checks
```

## 3. SwiftLint Custom Rules (Configured ✅)

The `.swiftlint.yml` includes custom rules for:
- `NSMutableData` usage detection
- Old-style `DispatchQueue` detection
- Deprecated `NSHomeDirectory()` usage
- Foundation vs native string methods

**Run manually:**
```bash
swiftlint --strict
```

**Auto-fix:**
```bash
swiftlint --fix
```

## 4. ast-grep Pattern Detection (Configured ✅)

The `check-concurrency.sh` script uses ast-grep to find:
- NSMutableData in concurrent code
- Mutable variable captures in closures
- @Sendable closure issues
- MainActor isolation violations
- Old-style GCD usage

## 5. Continuous Integration (CI/CD) ✅

Your `.github/workflows/CI.yml` now includes:
- SwiftLint strict checking
- swift-format linting
- **Concurrency pattern detection**
- **Static Analyzer** 
- Strict concurrency compilation
- Test execution

## 6. Pre-commit Hook (Optional)

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
echo "🔍 Running pre-commit checks..."

# SwiftLint
if which swiftlint >/dev/null; then
    swiftlint --strict
    if [ $? -ne 0 ]; then
        echo "❌ SwiftLint failed"
        exit 1
    fi
fi

# Concurrency patterns
./scripts/check-concurrency.sh

echo "✅ Pre-commit checks passed!"
```

Make executable:
```bash
chmod +x .git/hooks/pre-commit
```

## 7. Common Patterns to Watch For

### ❌ Anti-patterns (Static Analyzer catches these)

```swift
// NSMutableData in concurrent code
let data = NSMutableData()
handler = { data.append(...) } // ❌ Not Sendable, data race

// Mutable var capture  
var finished = false
handler = { finished = true } // ❌ Concurrent mutation

// Memory leak - retain cycle
class MyClass {
    var closure: (() -> Void)?
    func setup() {
        closure = {
            self.doWork() // ❌ Retain cycle
        }
    }
}

// Null dereference
let value: String? = nil
let length = value!.count // ❌ Force unwrap of nil

// Uninitialized variable
var name: String
print(name) // ❌ Used before initialization
```

### ✅ Correct patterns

```swift
// Thread-safe data wrapper
nonisolated class DataWrapper: @unchecked Sendable {
    private let lock = NSLock()
    private let data: NSMutableData
    
    init(data: NSMutableData) {
        self.data = data
    }
    
    nonisolated func append(_ d: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(d)
    }
}

// Thread-safe flag
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var value = false
    
    nonisolated func checkAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !value else { return true }
        value = true
        return false
    }
}

// Weak capture to avoid retain cycle
class MyClass {
    var closure: (() -> Void)?
    func setup() {
        closure = { [weak self] in
            self?.doWork() // ✅ No retain cycle
        }
    }
}

// Safe optional handling
if let value = value {
    let length = value.count // ✅ Safe
}

// Initialization
var name: String = "default"
print(name) // ✅ Initialized
```

## 8. Development Workflow

**Before committing:**
```bash
# 1. Auto-fix formatting
swiftlint --fix
xcrun swift-format format --in-place --recursive BrewDeck/

# 2. Run all checks
./scripts/check-concurrency.sh

# 3. Run Static Analyzer (thorough check)
./scripts/run-analyzer.sh

# 4. Build
xcodebuild -scheme BrewDeck build
```

**During development:**
- Run Static Analyzer: **Product** → **Analyze** (⇧⌘B)
- Check Issues Navigator for warnings
- Fix issues as they appear

## 9. What Each Tool Catches

| Tool | Catches | Speed |
|------|---------|-------|
| **SwiftLint** | Code style, simple patterns | ⚡️ Fast |
| **ast-grep** | Code structure patterns | ⚡️ Fast |
| **Swift Compiler** | Type errors, concurrency violations | ⚡️ Fast |
| **Static Analyzer** | Deep logic issues, memory leaks, data races | 🐌 Slow but thorough |

**Recommended workflow:**
1. Development: SwiftLint + ast-grep (fast feedback)
2. Before commit: Add Static Analyzer (thorough)
3. CI/CD: All tools (gate for merging)

## 10. Static Analyzer Configuration

### Enable in Xcode

Build Settings → Analysis → Search for:
- **"Analyze During 'Build'"** → NO (manual only)
- **"Warning Policies"** → Set to "Treat Warnings as Errors" (optional)

### Additional Analyzer Settings

```bash
# In Build Settings, add:
CLANG_ANALYZER_DEADCODE_DEADSTORES = YES
CLANG_ANALYZER_MEMORY_MANAGEMENT = YES
CLANG_ANALYZER_SECURITY_FLOATLOOPCOUNTER = YES
CLANG_ANALYZER_SECURITY_INSECUREAPI_RAND = YES
```

## Summary

You now have **4 layers of protection**:

1. **SwiftLint** - Style and simple patterns ✅
2. **ast-grep** - Structural patterns ✅  
3. **Swift Compiler** - Type safety and concurrency ✅
4. **Static Analyzer** - Deep logic and memory issues ✅

All integrated into:
- Local development scripts
- Pre-commit hooks (optional)
- CI/CD pipeline

**The issues you fixed were:**
- NSMutableData not Sendable → Thread-safe wrapper
- Mutable var in closures → Thread-safe Flag class  
- MainActor violations → `nonisolated` annotation

These tools will catch similar issues before they reach production! 🎯
